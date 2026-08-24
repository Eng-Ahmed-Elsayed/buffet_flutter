import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';

/// The way into the notification list, with an unread count.
///
/// Sits on both home screens. It matters more than it looks: it is the only
/// route to the three notification kinds that deliberately get no push, and the
/// recovery path for a push that never arrived (§7.4).
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final unread = ref.watch(unreadNotificationCountProvider);

    return IconButton(
      tooltip: l10n.notifications,
      onPressed: () => context.push(Routes.notifications),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_none_outlined),
          if (unread > 0)
            PositionedDirectional(
              top: -2,
              end: -2,
              child: Container(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: Dimens.space1,
                ),
                constraints: const BoxConstraints(minWidth: Dimens.space3),
                decoration: BoxDecoration(
                  color: BrandColors.danger,
                  borderRadius: BorderRadius.circular(Dimens.handleRadius * 3),
                ),
                child: Text(
                  // Capped: past a certain point the exact number stops being
                  // information and starts being a wide badge.
                  unread > 9 ? '9+' : '$unread',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: BrandColors.surface, fontSize: 10),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
