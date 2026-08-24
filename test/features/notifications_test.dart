import 'package:buffet_app/data/models/order_models.dart';
import 'package:buffet_app/data/repositories/notifications_repository.dart';
import 'package:buffet_app/features/notifications/notifications_screen.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

NotificationDto _notification({
  required int id,
  required String kind,
  String message = 'طلبك جاهز',
  int? orderId,
  bool isRead = false,
}) => NotificationDto(
  notificationId: id,
  kind: kind,
  message: message,
  orderId: orderId,
  createdAtUtc: DateTime.utc(2026, 8, 24, 7),
  isRead: isRead,
);

class _FakeNotificationsRepository extends NotificationsRepository {
  _FakeNotificationsRepository(this.items) : super(Dio());

  final List<NotificationDto> items;
  int markReadCalls = 0;

  @override
  Future<List<NotificationDto>> fetch({
    required String languageCode,
    required String networkErrorFallback,
    bool unreadOnly = false,
  }) async => items;

  @override
  Future<void> markAllRead({
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    markReadCalls++;
  }
}

Widget _app(_FakeNotificationsRepository repository) => ProviderScope(
  overrides: [notificationsRepositoryProvider.overrideWithValue(repository)],
  child: const MaterialApp(
    locale: Locale('ar'),
    localizationsDelegates: [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: [Locale('ar'), Locale('en')],
    home: NotificationsScreen(),
  ),
);

void main() {
  group('the notification list', () {
    testWidgets('renders the server message verbatim', (tester) async {
      // Messages arrive already localised. The client never maps a kind to a
      // sentence of its own.
      final repository = _FakeNotificationsRepository([
        _notification(id: 1, kind: 'OrderReady', message: 'طلبك رقم ٤١٢ جاهز'),
      ]);

      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();

      expect(find.text('طلبك رقم ٤١٢ جاهز'), findsOneWidget);
    });

    testWidgets('shows an empty state when there is nothing', (tester) async {
      final repository = _FakeNotificationsRepository([]);

      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('ar'));
      expect(find.text(l10n.noNotifications), findsOneWidget);
    });

    testWidgets('marks everything read on open', (tester) async {
      // On open, because the endpoint marks all — there is no per-row call to
      // make, so tracking what scrolled past would be a fiction.
      final repository = _FakeNotificationsRepository([
        _notification(id: 1, kind: 'OrderReady'),
      ]);

      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();

      expect(repository.markReadCalls, 1);
    });

    testWidgets('carries the kinds that never get a push', (tester) async {
      // This screen is the only place these three ever surface. If it stops
      // rendering them the user has no way to learn about them at all.
      final repository = _FakeNotificationsRepository([
        _notification(id: 1, kind: 'LowStock', message: 'الشاي أوشك'),
        _notification(
          id: 2,
          kind: 'DeclarationConfirmed',
          message: 'تم التأكيد',
        ),
        _notification(id: 3, kind: 'DeclarationRejected', message: 'تم الرفض'),
      ]);

      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();

      expect(find.text('الشاي أوشك'), findsOneWidget);
      expect(find.text('تم التأكيد'), findsOneWidget);
      expect(find.text('تم الرفض'), findsOneWidget);
    });

    testWidgets('an unrecognised kind still renders', (tester) async {
      // A server that adds a kind must not produce a blank row: a message the
      // user cannot see is worse than a generic bell.
      final repository = _FakeNotificationsRepository([
        _notification(id: 1, kind: 'SomethingNew', message: 'رسالة جديدة'),
      ]);

      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();

      expect(find.text('رسالة جديدة'), findsOneWidget);
    });

    testWidgets('only a row naming an order is tappable', (tester) async {
      final repository = _FakeNotificationsRepository([
        _notification(id: 1, kind: 'OrderReady', orderId: 412),
        _notification(id: 2, kind: 'LowStock', message: 'الشاي أوشك'),
      ]);

      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();

      final inkWells = tester.widgetList<InkWell>(find.byType(InkWell));
      final tappable = inkWells.where((w) => w.onTap != null);

      // The low-stock row has nothing to open, and a row that invites a tap
      // then does nothing is worse than one that plainly does not.
      expect(tappable, hasLength(1));
    });
  });

  group('the unread badge', () {
    testWidgets('counts only what is unread', (tester) async {
      final repository = _FakeNotificationsRepository([
        _notification(id: 1, kind: 'OrderReady'),
        _notification(id: 2, kind: 'OrderReady', isRead: true),
        _notification(id: 3, kind: 'OrderCancelled'),
      ]);

      late int unread;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationsRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            locale: const Locale('ar'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                ref.watch(notificationsProvider);
                unread = ref.watch(unreadNotificationCountProvider);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(unread, 2);
    });
  });
}
