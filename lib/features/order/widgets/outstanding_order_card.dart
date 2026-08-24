import 'package:flutter/material.dart';

import '../../../data/models/order_models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/brand_colors.dart';
import '../../../theme/dimens.dart';

/// The standing reminder that a drink is still owed to the user.
///
/// Placement matters more than the widget does: an order the user has not
/// collected must be visible on the screen they land on after a restart, not
/// one tap away behind the history icon. Closing the app is the normal way to
/// wait for a drink.
///
/// Tapping opens the tracking screen for [order].
class OutstandingOrderCard extends StatelessWidget {
  const OutstandingOrderCard({
    required this.order,
    required this.othersCount,
    required this.onTap,
    super.key,
  });

  /// The order to lead with — the most urgent one, chosen by the caller.
  final OrderSummaryDto order;

  /// How many *further* orders are still outstanding, summarised in one line
  /// rather than stacking a card each.
  final int othersCount;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Read by name through OrderStatus — never by ordinal (rule 5).
    final ready = order.orderStatus == OrderStatus.ready;

    // Green for a drink that exists and is waiting; the ordinary brand tint
    // while it is still being made. Never violet — that means "from my own
    // jar" and nothing else (rule 3).
    final (background, border, foreground, icon, title, body) = ready
        ? (
            BrandColors.okSurface,
            BrandColors.ok,
            BrandColors.ok,
            Icons.local_cafe_outlined,
            l10n.outstandingReadyTitle,
            l10n.outstandingReadyBody,
          )
        : (
            BrandColors.page,
            BrandColors.brandLight,
            BrandColors.ink,
            Icons.hourglass_bottom_outlined,
            l10n.outstandingLiveTitle,
            l10n.outstandingLiveBody,
          );

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(Dimens.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(Dimens.radius),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: Dimens.minTarget),
          padding: const EdgeInsetsDirectional.all(Dimens.space3),
          decoration: BoxDecoration(
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(Dimens.radius),
          ),
          child: Row(
            children: [
              Icon(icon, color: foreground),
              const SizedBox(width: Dimens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Colour is never the only signal — the state is spelled
                    // out in words (§2.5).
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(color: foreground),
                    ),
                    Text(body, style: Theme.of(context).textTheme.bodySmall),
                    if (othersCount > 0)
                      Text(
                        l10n.outstandingMore(othersCount),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: Dimens.space2),
              Icon(Icons.chevron_right, size: 18, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}
