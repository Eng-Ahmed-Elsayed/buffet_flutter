import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/brand_colors.dart';
import '../../../theme/dimens.dart';

/// The sugar stepper.
///
/// **Zero is valid and explicit** — it renders as "no sugar", not as a blank
/// field. The server distinguishes "zero spoons" from "unspecified", so the
/// user must be able to say zero deliberately (§7.1).
class SugarStepper extends StatelessWidget {
  const SugarStepper({
    required this.spoons,
    required this.onChanged,
    this.max = 10,
    super.key,
  });

  final int spoons;
  final ValueChanged<int> onChanged;
  final int max;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Dimens.space3,
        vertical: Dimens.space2,
      ),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        border: Border.all(color: BrandColors.brandLight),
        borderRadius: BorderRadius.circular(Dimens.radius),
      ),
      child: Row(
        children: [
          _StepperButton(
            icon: Icons.remove,
            tooltip: l10n.removeSpoon,
            // Disabled only at the floor — a bound of the control itself,
            // never a stock reading.
            onPressed: spoons > 0 ? () => onChanged(spoons - 1) : null,
          ),
          Expanded(
            child: Semantics(
              // The label already says "no sugar" at zero, so a screen reader
              // hears the meaning rather than a bare number.
              label: l10n.sugar,
              value: l10n.spoons(spoons),
              liveRegion: true,
              child: Column(
                children: [
                  Text(
                    '$spoons',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    l10n.spoons(spoons),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
          _StepperButton(
            icon: Icons.add,
            tooltip: l10n.addSpoon,
            onPressed: spoons < max ? () => onChanged(spoons + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(Dimens.radius),
        child: Container(
          // §2.5: never below 44px.
          width: Dimens.minTarget,
          height: Dimens.minTarget,
          decoration: BoxDecoration(
            color: onPressed == null
                ? BrandColors.page
                : BrandColors.brandLight,
            borderRadius: BorderRadius.circular(Dimens.radius),
          ),
          child: Icon(
            icon,
            size: 18,
            color: onPressed == null ? BrandColors.muted : BrandColors.brand,
          ),
        ),
      ),
    );
  }
}
