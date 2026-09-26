import 'package:flutter/material.dart';

import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';

/// What a button shows in place of its label while its request is in flight.
///
/// Brand blue, never white: the button is disabled meanwhile, and white on the
/// disabled fill measured 1.43:1 — a spinner nobody could see, on the one
/// control saying "wait". Brand on that fill is about 5.8:1. Named, so a screen
/// reader hears [label] rather than an unnamed, dimmed button.
class ButtonSpinner extends StatelessWidget {
  const ButtonSpinner({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: Dimens.spinnerSize,
    child: CircularProgressIndicator(
      strokeWidth: Dimens.spinnerStroke,
      color: BrandColors.brand,
      semanticsLabel: label,
    ),
  );
}
