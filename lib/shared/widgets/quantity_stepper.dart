import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';

/// The design's "− n +" pill: how many cups of one drink.
///
/// Both buttons keep the 44dp minimum target. At [max] the `+` stops and
/// [atMaxReason] is shown beneath it, so the stopped control is never a dead
/// end with nothing to explain it. [max] must come from a structural limit,
/// never from a stock reading.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    required this.value,
    required this.max,
    required this.onChanged,
    required this.moreTooltip,
    required this.fewerTooltip,
    required this.atMaxReason,
    super.key,
  });

  final int value;
  final int max;
  final ValueChanged<int> onChanged;
  final String moreTooltip;
  final String fewerTooltip;
  final String atMaxReason;

  @override
  Widget build(BuildContext context) {
    final atMax = value >= max;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: const ShapeDecoration(
            color: BrandColors.surface,
            shape: StadiumBorder(side: BorderSide(color: BrandColors.outline)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.remove),
                color: BrandColors.brand,
                tooltip: fewerTooltip,
                constraints: const BoxConstraints(
                  minWidth: Dimens.minTarget,
                  minHeight: Dimens.minTarget,
                ),
                onPressed: value > 1 ? () => onChanged(value - 1) : null,
              ),
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: Dimens.space2,
                  ),
                  child: Text(
                    '$value',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.merge(AppTheme.tabularFigures)
                        .copyWith(color: BrandColors.ink),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                color: BrandColors.brand,
                tooltip: moreTooltip,
                constraints: const BoxConstraints(
                  minWidth: Dimens.minTarget,
                  minHeight: Dimens.minTarget,
                ),
                onPressed: atMax ? null : () => onChanged(value + 1),
              ),
            ],
          ),
        ),
        if (atMax) ...[
          const SizedBox(height: Dimens.space1),
          Text(
            atMaxReason,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: BrandColors.muted),
          ),
        ],
      ],
    );
  }
}
