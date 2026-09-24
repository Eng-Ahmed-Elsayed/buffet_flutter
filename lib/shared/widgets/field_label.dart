import 'package:flutter/material.dart';

import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';

/// The design's label above a field ("EMAIL ADDRESS", "PASSWORD"), with an
/// optional action at its end ("Forgot?").
///
/// Small caps in Latin; Arabic has no case, so the same string is shown as-is.
/// Pair it with the field inside a [MergeSemantics] so a screen reader reads
/// the label as the field's name rather than as a separate line.
class FieldLabel extends StatelessWidget {
  const FieldLabel({required this.label, this.trailing, super.key});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final latin = Localizations.localeOf(context).languageCode != 'ar';
    final style = Theme.of(context).textTheme.labelMedium
        ?.copyWith(color: BrandColors.brand);

    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: Dimens.space1,
        bottom: Dimens.space1,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(latin ? label.toUpperCase() : label, style: style),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
