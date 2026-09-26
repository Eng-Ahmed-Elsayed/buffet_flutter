import 'package:flutter/material.dart';

import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';

/// The design's label above a field ("EMAIL ADDRESS", "PASSWORD"), with an
/// optional action at its end ("Forgot?").
///
/// Small caps in Latin; Arabic has no case, so the same string is shown as-is.
/// The text is hidden from screen readers: use it through [LabelledField],
/// which gives the field itself the label, as written rather than in capitals.
class FieldLabel extends StatelessWidget {
  const FieldLabel({required this.label, this.trailing, super.key});

  final String label;

  /// A small text button, aligned to the label's foot. Give it
  /// `alignment: AlignmentDirectional.bottomEnd` and no vertical padding, so
  /// its 44dp target reaches up into the gap above rather than pushing the
  /// field down — the label then sits as close to its field as one without.
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
        // Bottom, not baseline: the label then sits exactly as far above its
        // field with a trailing action as without one.
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: ExcludeSemantics(
              child: Text(latin ? label.toUpperCase() : label, style: style),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A field with the design's label above it, named by that label for screen
/// readers.
///
/// The label is put on the field's own node rather than merged with it. A
/// `MergeSemantics` around the pair also merged the field's own controls into
/// it: the eye toggle on a password field stopped being a button a screen
/// reader could reach.
class LabelledField extends StatelessWidget {
  const LabelledField({
    required this.label,
    required this.child,
    this.trailing,
    super.key,
  });

  final String label;
  final Widget child;

  /// An action at the label's end, such as "Forgot?". See [FieldLabel].
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      FieldLabel(label: label, trailing: trailing),
      Semantics(label: label, child: child),
    ],
  );
}
