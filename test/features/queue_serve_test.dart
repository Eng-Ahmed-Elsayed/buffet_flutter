import 'dart:async';

import 'package:buffet_app/data/api/api_config.dart';
import 'package:buffet_app/data/api/api_exception.dart';
import 'package:buffet_app/data/models/staff_models.dart';
import 'package:buffet_app/data/repositories/queue_repository.dart';
import 'package:buffet_app/features/notifications/notifications_screen.dart';
import 'package:buffet_app/features/staff_queue/queue_screen.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _l10n = lookupAppLocalizations(const Locale('ar'));

StaffOrderDto _order(int id, String requester) => StaffOrderDto(
  orderId: id,
  status: 'Pending',
  createdAtUtc: DateTime.utc(2026, 8, 24, 7),
  readyAtUtc: null,
  requesterDisplayName: requester,
  department: 'المالية',
  locationText: 'الدور الثالث',
  onBehalfOfName: null,
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

const _shortSugar = StockWarningDto(
  itemId: 3,
  nameAr: 'سكر أبيض',
  ownerDisplayName: '',
  shortfall: 12.5,
  unit: 'جرام',
);

/// Serves on request. [serve] decides how the `/ready` call answers, so a
/// test can hold it open, fail it, or return warnings.
class _Repository extends QueueRepository {
  _Repository(this.queue) : super(Dio());

  List<StaffOrderDto> queue;
  Future<ServeResultDto> Function(int orderId)? serve;

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
    final result = await serve!(orderId);
    queue = queue.where((o) => o.orderId != orderId).toList();
    return result;
  }
}

Future<void> _pump(WidgetTester tester, _Repository repository) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        queueRepositoryProvider.overrideWithValue(repository),
        notificationsProvider.overrideWith((ref) async => const []),
      ],
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
    ),
  );
  await tester.pumpAndSettle();
}

/// Taps "ready and handed over", then lets the undo window run out.
Future<void> _serveAndWait(WidgetTester tester) async {
  await tester.tap(find.text(_l10n.readyAndDelivered).first);
  await tester.pump();
  await tester.pump(ApiConfig.undoWindow + const Duration(milliseconds: 100));
}

void main() {
  group('a shortage on "ready and handed over" is seen', () {
    testWidgets('it stays above the tabs, named, until dismissed', (
      tester,
    ) async {
      final repository = _Repository([_order(7, 'سارة العتيبي')])
        ..serve = (id) async => ServeResultDto(
          orderId: id,
          status: 'Completed',
          warnings: [_shortSugar],
        );
      await _pump(tester, repository);

      await _serveAndWait(tester);
      await tester.pumpAndSettle();

      // The order has left both lists; the warning did not leave with it.
      expect(find.textContaining('سارة العتيبي'), findsOneWidget);
      expect(find.textContaining('سكر أبيض'), findsOneWidget);

      await tester.tap(find.byTooltip(_l10n.dismiss));
      await tester.pumpAndSettle();
      expect(find.textContaining('سكر أبيض'), findsNothing);
    });
  });

  group('the card goes as the undo window commits', () {
    testWidgets('no Ready buttons come back while the server answers', (
      tester,
    ) async {
      final answer = Completer<ServeResultDto>();
      final repository = _Repository([_order(7, 'سارة العتيبي')])
        ..serve = (id) => answer.future;
      await _pump(tester, repository);

      await _serveAndWait(tester);

      // The request is still in flight: the card is gone, not back to its
      // buttons (a worker read that as "undone" and served twice).
      expect(find.textContaining('سارة العتيبي'), findsNothing);
      expect(find.text(_l10n.readyAndDelivered), findsNothing);

      answer.complete(
        const ServeResultDto(orderId: 7, status: 'Completed', warnings: []),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('سارة العتيبي'), findsNothing);
    });

    testWidgets('a failed serve puts the order back, and says why', (
      tester,
    ) async {
      final repository = _Repository([_order(7, 'سارة العتيبي')])
        ..serve = (id) async => throw const ApiException(
          message: 'تعذّر الاتصال',
          statusCode: null,
          isNetworkFailure: true,
        );
      await _pump(tester, repository);

      await _serveAndWait(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('سارة العتيبي'), findsOneWidget);
      expect(find.text('تعذّر الاتصال'), findsOneWidget);
    });
  });

  group('a rush of serves never brings a committed card back', () {
    testWidgets('a refresh while a serve is in flight keeps its card away', (
      tester,
    ) async {
      final held = Completer<ServeResultDto>();
      final repository = _Repository([
        _order(7, 'سارة العتيبي'),
        _order(8, 'محمد الشريف'),
      ]);
      // The first answers at once; the second is held open.
      repository.serve = (id) async => id == 7
          ? const ServeResultDto(orderId: 7, status: 'Completed', warnings: [])
          : held.future;
      await _pump(tester, repository);

      // Both served back to back: the second commits while the first's
      // answer (and the refresh it triggers) comes back.
      await tester.tap(find.text(_l10n.readyAndDelivered).at(1));
      await tester.pump();
      await tester.tap(find.text(_l10n.readyAndDelivered).first);
      await tester.pump();
      await tester.pump(ApiConfig.undoWindow + const Duration(seconds: 1));
      await tester.pump();

      // The refresh after order 7 still lists 8 as Pending — its /ready is in
      // flight — and 8's card must not come back with live buttons.
      expect(find.textContaining('محمد الشريف'), findsNothing);
      expect(find.text(_l10n.readyAndDelivered), findsNothing);

      held.complete(
        const ServeResultDto(orderId: 8, status: 'Completed', warnings: []),
      );
      await tester.pumpAndSettle();
    });
  });
}
