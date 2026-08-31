import 'package:flutter/material.dart';

import '../../../data/models/catalogue_models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/formatters.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../theme/brand_colors.dart';
import '../../../theme/dimens.dart';

/// The one-tap repeat of the caller's last order.
///
/// The single highest-value feature in the app (§7.1), which is why it sits on
/// the home screen above the action grid rather than inside the composer: for
/// the user who orders the same coffee every morning, the whole task is one tap
/// from launch, and they never see a drink picker at all.
class UsualOrderCard extends StatelessWidget {
  const UsualOrderCard({required this.usual, required this.onApply, super.key});

  final UsualOrderDto usual;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.refresh, size: 18, color: BrandColors.brand),
              const SizedBox(width: Dimens.space2),
              // Expanded so the heading wraps rather than pushing itself off
              // the edge: at a large text scale on a narrow phone the icon
              // plus this label was wider than the card.
              Expanded(
                child: Text(
                  l10n.usualOrder,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: Dimens.space2),
          // Server-composed and rendered as-is per §4 — but ISOLATED: the
          // server builds this from the item's English name and an Arabic
          // parenthetical regardless of Accept-Language, so it is reliably
          // mixed-script ("Coffee (بدون سكر)"). Without the isolate the bidi
          // algorithm reorders the parentheses around the Latin run.
          Text(
            Formatters.isolate(usual.summary),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: Dimens.space3),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onApply,
              child: Text(l10n.orderTheUsual),
            ),
          ),
        ],
      ),
    );
  }
}
