import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/locale_controller.dart';
import '../../app/routes.dart';
import '../../data/models/order_models.dart';
import '../../data/repositories/notifications_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/error_text.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/banners.dart';
import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';
import '../auth/auth_controller.dart';

/// Everything the server has told this user, newest first.
final notificationsProvider = FutureProvider.autoDispose<List<NotificationDto>>((
  ref,
) async {
  final locale = ref.watch(localeControllerProvider);
  return ref
      .watch(notificationsRepositoryProvider)
      .fetch(
        languageCode: locale.languageCode,
        // Never shown: screens render a network failure through describeError.
        networkErrorFallback: '',
      );
});

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
  /// The rows that were new when the screen opened. Marking read reloads the
  /// list with every row read, so without this the rows the user came for
  /// lost their mark while being read.
  Set<int> _unreadOnOpen = const {};

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
      // Loaded before marking, so the snapshot is of what was new, and a
      // list that never loaded is never marked read unseen.
      final items = await ref.read(notificationsProvider.future);
      if (!mounted) return;
      setState(
        () => _unreadOnOpen = {
          for (final n in items)
            if (!n.isRead) n.notificationId,
        },
      );
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
    final isStaff = ref.watch(startsOnQueueProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.notifications)),
      // skipError: Home and the queue refresh this list in the background, and
      // a failed refresh must not swap the list being read for an error
      // screen. Only a first load with nothing to show falls to the error.
      body: notifications.when(
        skipError: true,
        loading: () => const Center(child: CircularProgressIndicator()),

        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: l10n.genericError,
          // The server's reason when it gave one (§4), not always "network".
          body: describeError(error, l10n),
          action: OutlinedButton.icon(
            onPressed: () => ref.invalidate(notificationsProvider),
            icon: const Icon(Icons.refresh),
            label: Text(l10n.retry),
          ),
        ),

        data: (items) {
          final stale = notifications.hasError;
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
              itemCount: items.length + (stale ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(height: Dimens.space2),
              itemBuilder: (context, index) {
                if (stale && index == 0) {
                  return InlineBanner(
                    tone: BannerTone.warning,
                    title: l10n.couldNotRefreshTitle,
                    body: describeError(notifications.error!, l10n),
                    action: TextButton(
                      onPressed: () => ref.invalidate(notificationsProvider),
                      child: Text(l10n.retry),
                    ),
                  );
                }
                final notification = items[index - (stale ? 1 : 0)];
                return _NotificationRow(
                  notification: notification,
                  locale: locale,
                  unread:
                      !notification.isRead ||
                      _unreadOnOpen.contains(notification.notificationId),
                  onTap: _destination(notification, isStaff: isStaff),
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// Where a row leads, if anywhere. An order opens its tracking screen. A
  /// declaration's outcome opens My materials, where the balance it changed
  /// is shown — for employees only, since staff have no materials screen.
  /// `LowStock` goes only to admins and is about buffet stock, which nothing
  /// in the app shows, so it leads nowhere.
  VoidCallback? _destination(
    NotificationDto notification, {
    required bool isStaff,
  }) {
    final orderId = notification.orderId;
    if (orderId != null) {
      return () => context.push(Routes.orderStatusFor(orderId));
    }
    final declaration =
        notification.kind == 'DeclarationConfirmed' ||
        notification.kind == 'DeclarationRejected';
    if (declaration && !isStaff) return () => context.push(Routes.materials);
    return null;
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.notification,
    required this.locale,
    required this.unread,
    required this.onTap,
  });

  final NotificationDto notification;
  final String locale;

  /// Unread on the server, or when the screen opened.
  final bool unread;

  /// Null when the row leads nowhere; it then does not invite the tap.
  final VoidCallback? onTap;

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
    final l10n = AppLocalizations.of(context);
    final (icon, tint) = _glyph;
    final text = Theme.of(context).textTheme;

    // Unread is said three ways, never by the fill alone (1.35:1 against the
    // page): a dot named for screen readers, and the message in bold.
    return Material(
      color: unread ? BrandColors.brandLight : BrandColors.surface,
      borderRadius: BorderRadius.circular(Dimens.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(Dimens.radius),
        // A row that leads nowhere does not invite the tap: one that did,
        // then did nothing, is worse.
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.all(Dimens.space3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: Dimens.iconSm, color: tint),
              const SizedBox(width: Dimens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // Already localised server-side; rendered as-is.
                      notification.message,
                      style: text.bodyMedium?.copyWith(
                        fontWeight: unread ? FontWeight.w600 : null,
                      ),
                    ),
                    const SizedBox(height: Dimens.space1),
                    Row(
                      children: [
                        if (unread) ...[
                          Semantics(
                            label: l10n.unread,
                            child: Container(
                              width: Dimens.unreadDot,
                              height: Dimens.unreadDot,
                              decoration: const BoxDecoration(
                                color: BrandColors.brand,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          const SizedBox(width: Dimens.space1),
                        ],
                        Flexible(
                          child: Text(
                            Formatters.dateTime(
                              notification.createdAtUtc,
                              locale,
                            ),
                            // Muted fails on the unread row's blue (4.19:1);
                            // the brand blue holds 6.07:1 there.
                            style: text.labelSmall?.copyWith(
                              color: unread ? BrandColors.brand : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                // Points "onward": left in Arabic, right in English. The icon
                // mirrors with the ambient direction on its own; forcing RTL
                // here made it point backwards in English.
                const Icon(
                  Icons.chevron_right,
                  size: Dimens.iconXs,
                  color: BrandColors.muted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
