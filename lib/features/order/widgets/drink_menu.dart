import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/models/catalogue_models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/search_text.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../theme/brand_colors.dart';
import '../../../theme/dimens.dart';
import '../../../theme/motion.dart';
import 'menu_item_row.dart';

/// Every drink, grouped by the jar it would be made from — «من موادي» first,
/// then «من البوفيه» (guide §7.1) — and filtered by [query].
///
/// Shared by Home and the composer's first step, so the two can never list
/// drinks differently. An owned drink appears under both jars; the row tapped
/// is the jar ordered from, reported through [onSelect].
///
/// **Must sit in a scroll view that builds all its children** (a `Column`, not
/// a lazy list): the jump chips scroll to a section heading, and a lazy list
/// never builds a heading that is off screen.
class DrinkMenu extends StatefulWidget {
  const DrinkMenu({
    required this.drinks,
    required this.query,
    required this.onSelect,
    super.key,
  });

  final List<CatalogueItemDto> drinks;
  final String query;
  final void Function(CatalogueItemDto drink, {required bool fromOwn}) onSelect;

  @override
  State<DrinkMenu> createState() => _DrinkMenuState();
}

class _DrinkMenuState extends State<DrinkMenu> {
  final _mineKey = GlobalKey();
  final _buffetKey = GlobalKey();

  Future<void> _jumpTo(GlobalKey key) async {
    final target = key.currentContext;
    if (target == null) return;
    await Scrollable.ensureVisible(
      target,
      duration: Motion.of(context, Motion.slow),
      curve: Motion.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    bool matches(CatalogueItemDto d) =>
        matchesSearch(widget.query, [d.nameAr, d.nameEn]);

    final mine = widget.drinks
        .where((d) => d.hasOwnStock && matches(d))
        .toList();
    final buffet = widget.drinks.where(matches).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(label: l10n.menuTitle),
        const SizedBox(height: Dimens.space3),

        // Jump links to the two jars — the design's category chips, until the
        // backend has menu groups. Only when there is more than one section.
        if (mine.isNotEmpty && buffet.isNotEmpty) ...[
          Wrap(
            spacing: Dimens.space2,
            runSpacing: Dimens.space2,
            children: [
              ActionChip(
                avatar: const Icon(
                  Icons.inventory_2_outlined,
                  color: BrandColors.accent,
                ),
                label: Text(l10n.sectionMyMaterials),
                // The one violet chip: it IS "my own jar".
                side: const BorderSide(color: BrandColors.accent),
                onPressed: () => unawaited(_jumpTo(_mineKey)),
              ),
              ActionChip(
                avatar: const Icon(
                  Icons.local_cafe_outlined,
                  color: BrandColors.brand,
                ),
                label: Text(l10n.sectionBuffet),
                onPressed: () => unawaited(_jumpTo(_buffetKey)),
              ),
            ],
          ),
          const SizedBox(height: Dimens.space4),
        ],

        if (mine.isEmpty && buffet.isEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              vertical: Dimens.space5,
            ),
            child: Text(
              l10n.noDrinkMatches,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: BrandColors.muted),
            ),
          ),

        if (mine.isNotEmpty) ...[
          SectionHeader(
            key: _mineKey,
            label: l10n.sectionMyMaterials,
            accent: BrandColors.accent,
          ),
          const SizedBox(height: Dimens.space2),
          for (final drink in mine) ...[
            MenuItemRow(
              drink: drink,
              fromOwn: true,
              onTap: () => widget.onSelect(drink, fromOwn: true),
            ),
            const SizedBox(height: Dimens.space3),
          ],
          const SizedBox(height: Dimens.space3),
        ],

        if (buffet.isNotEmpty) ...[
          // Named only when there is a «من موادي» section to tell it apart
          // from; otherwise the menu heading says enough.
          if (mine.isNotEmpty) ...[
            SectionHeader(
              key: _buffetKey,
              label: l10n.sectionBuffet,
              accent: BrandColors.muted,
            ),
            const SizedBox(height: Dimens.space2),
          ],
          for (final drink in buffet) ...[
            MenuItemRow(
              drink: drink,
              fromOwn: false,
              onTap: () => widget.onSelect(drink, fromOwn: false),
            ),
            const SizedBox(height: Dimens.space3),
          ],
        ],
      ],
    );
  }
}
