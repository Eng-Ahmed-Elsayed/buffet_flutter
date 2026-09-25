import 'package:flutter/material.dart';

import '../../../theme/brand_colors.dart';
import '../../../theme/dimens.dart';

/// The fixed bar under an ordering step that holds its primary action.
///
/// Clears the system navigation bar: with Android's three-button navigation a
/// ~48dp strip is drawn over the bottom of the screen, on top of whatever
/// button sits there. `paddingOf`, not `viewPaddingOf`: inside a Scaffold the
/// padding a parent already consumed is subtracted, so this is what is really
/// left to clear. Added to the design padding, so a gesture-navigation device
/// (inset ~0) keeps the spacing it was designed with.
class StepFooter extends StatelessWidget {
  const StepFooter({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      width: double.infinity,
      padding: EdgeInsetsDirectional.only(
        start: Dimens.gutter,
        end: Dimens.gutter,
        top: Dimens.space3,
        bottom: Dimens.space5 + bottomInset,
      ),
      decoration: const BoxDecoration(
        color: BrandColors.surface,
        border: BorderDirectional(
          top: BorderSide(color: BrandColors.brandLight),
        ),
      ),
      child: child,
    );
  }
}
