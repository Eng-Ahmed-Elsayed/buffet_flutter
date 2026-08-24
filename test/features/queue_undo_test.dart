import 'package:buffet_app/data/api/api_config.dart';
import 'package:buffet_app/data/models/staff_models.dart';
import 'package:buffet_app/data/repositories/queue_repository.dart';
import 'package:buffet_app/features/staff_queue/queue_screen.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

StaffOrderDto _order(int id, {String? onBehalfOfName}) => StaffOrderDto(
  orderId: id,
  status: 'Pending',
  createdAtUtc: DateTime.utc(2026, 8, 24, 7),
  readyAtUtc: null,
  requesterDisplayName: 'سارة العتيبي',
  department: 'المالية',
  locationText: 'الدور الثالث',
  onBehalfOfName: onBehalfOfName,
  notes: '',
  waitingSeconds: 30,
  lines: const [
    StaffOrderLineDto(
      drinkItemId: 1,
      drinkNameAr: 'شاي',
      variantNameAr: null,
      sugarSpoons: 1,
      sugarNameAr: null,
      extraNamesAr: [],
      lineNote: null,
      drinkSourceOwnerName: '',
      sugarSourceOwnerName: '',
      extraSources: [],
    ),
  ],
);

/// Records what actually reached the wire.
///
/// The whole point of the undo window is that nothing is sent until it closes,
/// so the assertions here are mostly about calls that must *not* have happened.
class _FakeQueueRepository extends QueueRepository {
  _FakeQueueRepository(this.queue) : super(Dio());

  List<StaffOrderDto> queue;
  final List<int> readyCalls = [];
  final List<int> completeCalls = [];

  @override
  Future<List<StaffOrderDto>> fetchQueue({
    required String languageCode,
    required String networkErrorFallback,
  }) async => queue;

  @override
  Future<List<StaffOrderDto>> fetchReadyForHandover({
    required String languageCode,
    required String networkErrorFallback,
  }) async => const [];

  @override
  Future<ServeResultDto> markReady({
    required int orderId,
    required bool deliverNow,
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    readyCalls.add(orderId);
    queue = queue.where((o) => o.orderId != orderId).toList();
    return ServeResultDto(
      orderId: orderId,
      status: 'Ready',
      warnings: const [],
    );
  }

  @override
  Future<void> complete({
    required int orderId,
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    completeCalls.add(orderId);
  }
}

Widget _app(_FakeQueueRepository repository) => ProviderScope(
  overrides: [queueRepositoryProvider.overrideWithValue(repository)],
  child: const MaterialApp(
    locale: Locale('ar'),
    localizationsDelegates: [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: [Locale('ar'), Locale('en')],
    home: QueueScreen(),
  ),
);

void main() {
  group('the undo window closes', () {
    testWidgets('no undo affordance survives the window — the reported bug', (
      tester,
    ) async {
      // Two, not more: the default test surface only renders two of these
      // cards, and a ListView will not build the third. Two concurrent
      // windows is already the case the old snackbar could not handle.
      final repository = _FakeQueueRepository([_order(1), _order(2)]);
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('ar'));

      // Three orders bumped in quick succession — the rush case that used to
      // queue three snackbars, each outliving its own timer. Always the
      // first remaining button: each tap swaps that card into its pending
      // state, so the next untapped card moves to the front.
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text(l10n.readyAndDelivered).first);
        // Settle the action/pending cross-fade, which otherwise leaves both
        // children mounted and the next tap landing on a stale button.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }

      // Each card carries its own countdown, both at once — where the old
      // snackbar could only ever show one, queueing the rest behind it.
      expect(find.textContaining(l10n.undo), findsNWidgets(2));

      await tester.pump(ApiConfig.undoWindow + const Duration(seconds: 1));
      await tester.pumpAndSettle();

      // Both windows have closed. Nothing may still offer to undo an order
      // that has already been served — which is exactly what the queued
      // snackbars did, for as long as five seconds per order behind them.
      expect(find.textContaining(l10n.undo), findsNothing);
      expect(repository.readyCalls, hasLength(2));
    });

    testWidgets('undo before the window closes sends nothing', (tester) async {
      final repository = _FakeQueueRepository([_order(1)]);
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('ar'));

      await tester.tap(find.text(l10n.readyAndDelivered));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.textContaining(l10n.undo));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.pump(ApiConfig.undoWindow + const Duration(seconds: 1));
      await tester.pumpAndSettle();

      // A deferred send, not a compensating one: the API was never called, so
      // there is nothing to reverse.
      expect(repository.readyCalls, isEmpty);
      expect(find.text(l10n.readyAndDelivered), findsOneWidget);
    });

    testWidgets('undoing one order leaves the others pending', (tester) async {
      final repository = _FakeQueueRepository([_order(1), _order(2)]);
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('ar'));

      await tester.tap(find.text(l10n.readyAndDelivered).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text(l10n.readyAndDelivered).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Undo only the first. The second must be untouched — under the old
      // snackbar this was the tap that hit the wrong order.
      await tester.tap(find.textContaining(l10n.undo).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.pump(ApiConfig.undoWindow + const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(repository.readyCalls, hasLength(1));
    });
  });

  group('the pending card', () {
    testWidgets('stays in the list rather than vanishing', (tester) async {
      final repository = _FakeQueueRepository([_order(1)]);
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('ar'));

      await tester.tap(find.text(l10n.readyAndDelivered));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // The requester is still on screen: the undo lives on the card it acts
      // on, so the card has to still be there.
      expect(find.textContaining('سارة'), findsOneWidget);
      expect(find.text(l10n.servingOrder), findsOneWidget);

      // ...and its actions are gone, so the same cup cannot be served twice.
      expect(find.text(l10n.readyAndDelivered), findsNothing);

      await tester.pump(ApiConfig.undoWindow + const Duration(seconds: 1));
      await tester.pumpAndSettle();
    });
  });

  group('a guest order', () {
    testWidgets('names the guest first and the orderer second', (tester) async {
      final repository = _FakeQueueRepository([
        _order(1, onBehalfOfName: 'ضيف الإدارة'),
      ]);
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('ar'));

      // The drink is for the guest; the colleague who ordered it stays visible
      // underneath, because accountability does not move.
      expect(find.textContaining('ضيف الإدارة'), findsOneWidget);
      expect(find.text(l10n.guestOrder), findsOneWidget);
      expect(find.textContaining('سارة'), findsOneWidget);
    });

    testWidgets('an ordinary order carries no guest chip', (tester) async {
      final repository = _FakeQueueRepository([_order(1)]);
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('ar'));
      expect(find.text(l10n.guestOrder), findsNothing);
    });
  });
}
