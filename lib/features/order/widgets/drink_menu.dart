import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/models/catalogue_models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/formatters.dart';
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
///
/// **With menu groups** (§7.9) the chips filter instead: All, each group in
/// the server's order, and Other for drinks with none. The two jar sections
/// stay, so a group still lists «من موادي» first. Without groups, which is
/// the server until an admin creates some, the chips jump to the two jars.
///
/// **[ownOnly]** lists «من موادي» alone: the composer sets it once the order
/// has used its buffet allowance, so no row offers a drink the server would
/// refuse.
class DrinkMenu extends StatefulWidget {
  const DrinkMenu({
    required this.drinks,
    required this.query,
    required this.onSelect,
    this.groups = const [],
    this.ownOnly = false,
    super.key,
  });

  final List<CatalogueItemDto> drinks;
  final String query;

  /// `CatalogueResponse.drinkGroups`, already in display order.
  final List<DrinkGroupDto> groups;

  /// Leaves out the buffet section.
  final bool ownOnly;
  final void Function(CatalogueItemDto drink, {required bool fromOwn}) onSelect;

  @override
  State<DrinkMenu> createState() => _DrinkMenuState();
}

/// The chip that stands for drinks with no group: ungrouped, or filed under a
/// group since retired (the server sends null for both).
const _otherGroup = -1;

class _DrinkMenuState extends State<DrinkMenu> {
  final _mineKey = GlobalKey();
  final _buffetKey = GlobalKey();

  /// The chosen group: null for All, [_otherGroup] for Other.
  int? _group;

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
    final language = Localizations.localeOf(context).languageCode;
    final groupIds = {for (final g in widget.groups) g.drinkGroupId};
    // A group that names nothing in the list counts as none, so no drink can
    // fall between the chips.
    int? groupOf(CatalogueItemDto d) =>
        groupIds.contains(d.drinkGroupId) ? d.drinkGroupId : null;
    final grouped = widget.groups.isNotEmpty;
    // The drinks this menu can list at all.
    final listable = widget.ownOnly
        ? widget.drinks.where((d) => d.hasOwnStock).toList()
        : widget.drinks;
    final hasOther = grouped && listable.any((d) => groupOf(d) == null);
    // A choice that no longer exists (the catalogue reloaded) is All again.
    final group = _group == _otherGroup && hasOther || groupIds.contains(_group)
        ? _group
        : null;
    bool inGroup(CatalogueItemDto d) => switch (group) {
      null => true,
      _otherGroup => groupOf(d) == null,
      final id => groupOf(d) == id,
    };
    bool searched(CatalogueItemDto d) =>
        matchesSearch(widget.query, [d.nameAr, d.nameEn]);
    bool matches(CatalogueItemDto d) => inGroup(d) && searched(d);
    String groupLabel(int id) => id == _otherGroup
        ? l10n.menuGroupOther
        : widget.groups
              .firstWhere((g) => g.drinkGroupId == id)
              .localisedName(language);

    final mine = widget.drinks
        .where((d) => d.hasOwnStock && matches(d))
        .toList();
    final buffet = widget.ownOnly
        ? const <CatalogueItemDto>[]
        : widget.drinks.where(matches).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(label: l10n.menuTitle),
        const SizedBox(height: Dimens.space3),

        if (grouped) ...[
          Wrap(
            spacing: Dimens.space2,
            runSpacing: Dimens.space2,
            children: [
              for (final (id, label) in [
                (null, l10n.menuGroupAll),
                for (final g in widget.groups)
                  // Only groups with something this menu can list.
                  if (!widget.ownOnly ||
                      listable.any((d) => groupOf(d) == g.drinkGroupId))
                    (g.drinkGroupId, g.localisedName(language)),
                if (hasOther) (_otherGroup, l10n.menuGroupOther),
              ])
                ChoiceChip(
                  // Admin-entered, in either script.
                  label: Text(Formatters.isolate(label)),
                  selected: group == id,
                  onSelected: (_) => setState(() => _group = id),
                ),
            ],
          ),
          const SizedBox(height: Dimens.space4),
        ]
        // Jump links to the two jars, until an admin creates menu groups.
        // Only when there is more than one section.
        else if (mine.isNotEmpty && buffet.isNotEmpty) ...[
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
            // The chosen group, not the menu, may be what has none: saying
            // "no drink by that name" then denied one a chip away.
            child: group != null && listable.any(searched)
                ? Column(
                    children: [
                      Text(
                        l10n.noDrinkMatchesInGroup(
                          Formatters.isolate(groupLabel(group)),
                        ),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: BrandColors.muted),
                      ),
                      const SizedBox(height: Dimens.space2),
                      TextButton(
                        onPressed: () => setState(() => _group = null),
                        child: Text(l10n.searchAllGroups),
                      ),
                    ],
                  )
                : Text(
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
