import 'dart:async';

import 'package:buffet_app/data/api/api_config.dart';
import 'package:buffet_app/data/models/staff_models.dart';
import 'package:buffet_app/data/repositories/queue_repository.dart';
import 'package:buffet_app/features/notifications/notifications_screen.dart';
import 'package:buffet_app/features/staff_queue/queue_screen.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final _l10n = lookupAppLocalizations(const Locale('ar'));

StaffOrderDto _order(int id, String status) => StaffOrderDto(
  orderId: id,
  status: status,
  createdAtUtc: DateTime.utc(2026, 8, 24, 7),
  readyAtUtc: null,
  requesterDisplayName: 'سارة العتيبي',
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

/// A repository whose next fetch can be held open, so a poll sent before a
/// serve or handover answered can be made to land after it.
class _Repository extends QueueRepository {
  _Repository({required this.queue, required this.handovers}) : super(Dio());

  List<StaffOrderDto> queue;
  List<StaffOrderDto> handovers;

  /// When set, the next fetch of each list waits on these instead.
  Completer<List<StaffOrderDto>>? heldQueue;
  Completer<List<StaffOrderDto>>? heldHandovers;

  final serveAnswer = Completer<ServeResultDto>();
  final startAnswer = Completer<void>();

  @override
  Future<void> start({
    required int orderId,
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    await startAnswer.future;
    queue = [
      for (final o in queue) o.orderId == orderId ? _order(orderId, 'InProgress') : o,
    ];
  }
  final completeAnswer = Completer<void>();

  @override
  Future<List<StaffOrderDto>> fetchQueue({
    required String languageCode,
    required String networkErrorFallback,
  }) {
    final held = heldQueue;
    heldQueue = null;
    return held?.future ?? Future.value(queue);
  }

  @override
  Future<List<StaffOrderDto>> fetchReadyForHandover({
    required String languageCode,
    required String networkErrorFallback,
  }) {
    final held = heldHandovers;
    heldHandovers = null;
    return held?.future ?? Future.value(handovers);
  }

  @override
  Future<ServeResultDto> markReady({
    required int orderId,
    required bool deliverNow,
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    final result = await serveAnswer.future;
    queue = queue.where((o) => o.orderId != orderId).toList();
    return result;
  }

  @override
  Future<void> complete({
    required int orderId,
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    await completeAnswer.future;
    handovers = handovers.where((o) => o.orderId != orderId).toList();
  }
}

Future<void> _pump(WidgetTester tester, _Repository repository) async {
  tester.view.physicalSize = const Size(1080, 3600);
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
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: [Locale('ar'), Locale('en')],
        home: QueueScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a poll sent before a serve answered never brings the card back', (
    tester,
  ) async {
    final repository = _Repository(
      queue: [_order(7, 'Pending')],
      handovers: const [],
    );
    await _pump(tester, repository);

    // The next poll will describe the world before the serve.
    final stalePoll = Completer<List<StaffOrderDto>>();
    repository.heldQueue = stalePoll;

    await tester.tap(find.text(_l10n.readyAndDelivered).first);
    await tester.pump();
    // The undo window commits; the serve is in flight.
    await tester.pump(ApiConfig.undoWindow + const Duration(milliseconds: 100));
    // The 10s poll goes out while /ready is still unanswered, and is held.
    await tester.pump(ApiConfig.queuePollInterval);

    // The serve answers, and its own refresh lands first.
    repository.serveAnswer.complete(
      const ServeResultDto(orderId: 7, status: 'Completed', warnings: []),
    );
    await tester.pumpAndSettle();
    expect(find.text(_l10n.readyAndDelivered), findsNothing);

    // Then the stale poll lands, still listing the order Pending.
    stalePoll.complete([_order(7, 'Pending')]);
    await tester.pumpAndSettle();
    expect(find.text(_l10n.readyAndDelivered), findsNothing);
    expect(find.textContaining('سارة العتيبي'), findsNothing);
  });

  testWidgets('a start answered shows "being made" at once, not a poll later', (
    tester,
  ) async {
    final repository = _Repository(
      queue: [_order(7, 'Pending')],
      handovers: const [],
    );
    await _pump(tester, repository);

    final stalePoll = Completer<List<StaffOrderDto>>();
    repository.heldQueue = stalePoll;
    await tester.pump(ApiConfig.queuePollInterval);

    await tester.tap(find.text(_l10n.startMaking));
    await tester.pump();
    repository.startAnswer.complete();
    await tester.pumpAndSettle();
    // The refresh after the start landed, without waiting for the next poll.
    expect(find.text(_l10n.beingMade), findsOneWidget);

    // The poll sent before the start lands last, still saying Pending.
    stalePoll.complete([_order(7, 'Pending')]);
    await tester.pumpAndSettle();
    expect(find.text(_l10n.beingMade), findsOneWidget);
    expect(find.text(_l10n.startMaking), findsNothing);
  });

  testWidgets('a poll sent before a handover answered never brings it back', (
    tester,
  ) async {
    final repository = _Repository(
      queue: const [],
      handovers: [_order(9, 'Ready')],
    );
    await _pump(tester, repository);
    await tester.tap(find.textContaining(_l10n.handoverTab));
    await tester.pumpAndSettle();
    expect(find.textContaining('سارة العتيبي'), findsOneWidget);

    final stalePoll = Completer<List<StaffOrderDto>>();
    repository.heldHandovers = stalePoll;
    // The poll goes out first and is held.
    await tester.pump(ApiConfig.queuePollInterval);

    final handOver = find.text(_l10n.markDelivered);
    expect(handOver, findsOneWidget);
    await tester.tap(handOver);
    await tester.pump();

    repository.completeAnswer.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('سارة العتيبي'), findsNothing);

    stalePoll.complete([_order(9, 'Ready')]);
    await tester.pumpAndSettle();
    expect(find.textContaining('سارة العتيبي'), findsNothing);
  });
}
