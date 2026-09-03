import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';
import '../formatters.dart';

/// A chip naming where one component of a drink comes from.
///
/// **Violet means "from someone's own jar"** — the single most important
/// signal on the staff queue, and the reason staff get a DTO that names owners
/// rather than the employee's caller-relative booleans.
///
/// Company stock arrives as an *empty* owner name, which renders neutral.
class SourceChip extends StatelessWidget {
  const SourceChip({required this.label, required this.ownerName, super.key});

  /// What the source is for — the drink, the sugar, a named extra.
  final String label;

  /// Empty string for company stock; otherwise the owner's display name.
  final String ownerName;

  bool get _isPersonal => ownerName.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // The owner's name is user data in an unknown language sitting next to
    // Arabic label text — isolate it so the bidi algorithm cannot reorder the
    // run around it.
    //
    // Buffet stock is the unremarkable case: the chip says only what the
    // component is. The colon-plus-source form is reserved for a personal
    // jar, so the punctuation itself carries the "from my own materials"
    // signal alongside the violet.
    final text = _isPersonal
        ? '$label: ${l10n.fromJarOf(Formatters.isolate(ownerName))}'
        : label;

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Dimens.space3,
        vertical: Dimens.space1,
      ),
      constraints: const BoxConstraints(minHeight: 30),
      decoration: BoxDecoration(
        color: _isPersonal ? BrandColors.accentSurface : BrandColors.page,
        border: Border.all(
          color: _isPersonal ? BrandColors.accent : BrandColors.brandLight,
        ),
        borderRadius: BorderRadius.circular(Dimens.radiusLg),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: _isPersonal ? BrandColors.accent : BrandColors.ink,
          fontWeight: _isPersonal ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
  }
}

/// A neutral chip for a value that has no source — a spoon count, an extra
/// whose owner is the buffet.
class DetailChip extends StatelessWidget {
  const DetailChip({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Dimens.space3,
        vertical: Dimens.space1,
      ),
      constraints: const BoxConstraints(minHeight: 30),
      decoration: BoxDecoration(
        color: BrandColors.page,
        borderRadius: BorderRadius.circular(Dimens.radiusLg),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: BrandColors.ink,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
