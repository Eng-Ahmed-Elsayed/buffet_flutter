import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/locale_controller.dart';
import '../../app/routes.dart';
import '../../data/models/order_models.dart';
import '../../data/repositories/notifications_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/banners.dart';
import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';

/// Everything the server has told this user, newest first.
final notificationsProvider = FutureProvider.autoDispose<List<NotificationDto>>(
  (ref) async {
    final locale = ref.watch(localeControllerProvider);
    return ref
        .watch(notificationsRepositoryProvider)
        .fetch(
          languageCode: locale.languageCode,
          networkErrorFallback: 'network',
        );
  },
);

/// How many are unread, for the bell badge on the home screens.
///
/// Derived rather than fetched: the list is already loaded on any screen that
/// cares, and a second round trip to count what we are holding is waste. Reads
/// as zero while loading or on error, so a badge never claims a number it
/// cannot stand behind.
final unreadNotificationCountProvider = Provider.autoDispose<int>((ref) {
  final notifications =
      ref.watch(notificationsProvider).valueOrNull ?? const [];
  return notifications.where((n) => !n.isRead).length;
});

/// The in-app notification list.
///
/// This is the **reliable half** of §7.4. A push can be throttled by iOS,
/// deferred by Doze, refused at the permission prompt, or simply arrive on a
/// phone that was reinstalled — and in every one of those cases the row is
/// still here. It is also the only place `LowStock`, `DeclarationConfirmed`
/// and `DeclarationRejected` ever appear, since those deliberately get no push.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // After the first frame: this reads providers and localisations, and an
    // inherited widget cannot be looked up before initState returns.
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
  }

  /// Marks everything read on open.
  ///
  /// On open rather than on close, because that is what the endpoint actually
  /// does — it marks *all*, with no per-row granularity — so pretending to
  /// track what scrolled past the fold would be a fiction. Failures are
  /// swallowed: the badge being briefly wrong is not worth an error banner over
  /// a list the user is already reading.
  Future<void> _markRead() async {
    if (!mounted) return;
    final locale = ref.read(localeControllerProvider);

    try {
      await ref
          .read(notificationsRepositoryProvider)
          .markAllRead(
            languageCode: locale.languageCode,
            networkErrorFallback: '',
          );
      if (mounted) ref.invalidate(notificationsProvider);
    } on Object {
      // Deliberately ignored — see above.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final notifications = ref.watch(notificationsProvider);
    final locale = ref.watch(localeControllerProvider).languageCode;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.notifications)),
      body: notifications.when(
        loading: () => const Center(child: CircularProgressIndicator()),

        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: l10n.genericError,
          body: l10n.networkError,
          action: OutlinedButton.icon(
            onPressed: () => ref.invalidate(notificationsProvider),
            icon: const Icon(Icons.refresh),
            label: Text(l10n.retry),
          ),
        ),

        data: (items) {
          if (items.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(notificationsProvider),
              child: Stack(
                children: [
                  ListView(),
                  EmptyState(
                    icon: Icons.notifications_none_outlined,
                    title: l10n.noNotifications,
                    body: l10n.noNotificationsBody,
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(notificationsProvider),
            child: ListView.separated(
              padding: const EdgeInsetsDirectional.all(Dimens.space4),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: Dimens.space2),
              itemBuilder: (context, index) =>
                  _NotificationRow(notification: items[index], locale: locale),
            ),
          );
        },
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.notification, required this.locale});

  final NotificationDto notification;
  final String locale;

  /// The glyph for a kind, compared by **name** — the wire carries a string and
  /// the enum's ordinals are not in workflow order.
  (IconData, Color) get _glyph => switch (notification.kind) {
    'OrderReady' => (Icons.local_cafe_outlined, BrandColors.ok),
    'OrderCancelled' => (Icons.cancel_outlined, BrandColors.danger),
    'LowStock' => (Icons.inventory_2_outlined, BrandColors.warning),
    'DeclarationConfirmed' => (Icons.check_circle_outline, BrandColors.ok),
    'DeclarationRejected' => (Icons.highlight_off, BrandColors.danger),
    // An unknown kind is still worth showing: the server may have added one,
    // and a message the user cannot see is worse than a generic bell.
    _ => (Icons.notifications_none_outlined, BrandColors.muted),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, tint) = _glyph;
    final orderId = notification.orderId;

    return Material(
      color: notification.isRead ? BrandColors.surface : BrandColors.brandLight,
      borderRadius: BorderRadius.circular(Dimens.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(Dimens.radius),
        // Only rows that name an order lead anywhere. A low-stock notice has
        // nothing to open, and a tappable row that does nothing is worse than
        // one that plainly does not invite the tap.
        onTap: orderId == null
            ? null
            : () => context.push(Routes.orderStatusFor(orderId)),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(Dimens.space3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: tint),
              const SizedBox(width: Dimens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // Already localised server-side; rendered as-is.
                      notification.message,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: Dimens.space1),
                    Text(
                      Formatters.dateTime(notification.createdAtUtc, locale),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              if (orderId != null)
                // Directional: this points "onward", which is left in Arabic
                // and right in English.
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: BrandColors.muted,
                  textDirection: TextDirection.rtl,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
