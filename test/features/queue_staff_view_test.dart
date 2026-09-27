import 'dart:async';

import 'package:buffet_app/data/api/api_config.dart';
import 'package:buffet_app/data/api/api_exception.dart';
import 'package:buffet_app/data/models/staff_models.dart';
import 'package:buffet_app/data/repositories/queue_repository.dart';
import 'package:buffet_app/features/notifications/notifications_screen.dart';
import 'package:buffet_app/features/staff_queue/pending_action.dart';
import 'package:buffet_app/features/staff_queue/queue_screen.dart';
import 'package:buffet_app/features/staff_queue/widgets/queue_card.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_harness.dart';

final _ar = lookupAppLocalizations(const Locale('ar'));

StaffOrderLineDto _line({
  int drink = 1,
  String name = 'شاي',
  int spoons = 1,
  String owner = '',
}) => StaffOrderLineDto(
  drinkItemId: drink,
  drinkNameAr: name,
  variantNameAr: null,
  sugarSpoons: spoons,
  sugarNameAr: null,
  extraNamesAr: const [],
  lineNote: null,
  drinkSourceOwnerName: owner,
  sugarSourceOwnerName: '',
  extraSources: const [],
);

StaffOrderDto _order(
  int id, {
  String status = 'Pending',
  List<StaffOrderLineDto>? lines,
  String? fulfilment,
}) => StaffOrderDto(
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
  lines: lines ?? [_line()],
  fulfilment: fulfilment,
);

class _Repository extends QueueRepository {
  _Repository({this.queue = const [], this.ready = const []}) : super(Dio());

  final List<StaffOrderDto> queue;
  final List<StaffOrderDto> ready;

  @override
  Future<List<StaffOrderDto>> fetchQueue({
    required String languageCode,
    required String networkErrorFallback,
  }) async => queue;

  @override
  Future<List<StaffOrderDto>> fetchReadyForHandover({
    required String languageCode,
    required String networkErrorFallback,
  }) async => ready;
}

Widget _card(StaffOrderDto order, {PendingAction? pending}) => testApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: QueueCard(
        order: order,
        warnings: null,
        pending: pending,
        onUndo: () {},
        onMarkReady: (o, {required deliverNow}) async {},
        onComplete: null,
        onCancel: (o) async {},
      ),
    ),
  ),
);

Future<void> _queue(
  WidgetTester tester,
  QueueRepository repository, {
  Size size = const Size(400, 1200),
  double scale = 1,
  Locale locale = const Locale('ar'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        queueRepositoryProvider.overrideWithValue(repository),
        notificationsProvider.overrideWith((ref) async => const []),
      ],
      child: testApp(
        home: const QueueScreen(),
        locale: locale,
        textScale: scale,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('identical cups show once, with how many', (tester) async {
    await tester.pumpWidget(
      _card(
        _order(
          1,
          lines: [
            _line(),
            _line(),
            _line(),
            // One spoon different: its own line.
            _line(spoons: 2),
          ],
        ),
      ),
    );

    expect(find.text('×3'), findsOneWidget);
    expect(find.text('شاي'), findsNWidgets(2));
  });

  testWidgets('every drink chip names its source', (tester) async {
    await tester.pumpWidget(
      _card(
        _order(
          1,
          lines: [
            _line(),
            _line(drink: 2, name: 'قهوة', owner: 'سارة'),
          ],
        ),
      ),
    );

    // A chip reading just «المشروب» named no source at all.
    expect(find.text(_ar.drinkFromBuffet), findsOneWidget);
    expect(find.textContaining('من مواد'), findsOneWidget);
  });

  testWidgets('the pending bar says which action is waiting, and is announced '
      'once rather than every second', (tester) async {
    final handle = tester.ensureSemantics();
    PendingAction pending({required bool deliverNow}) => PendingAction(
      kind: PendingActionKind.ready,
      deliverNow: deliverNow,
      deadline: DateTime.now().add(ApiConfig.undoWindow),
    );

    await tester.pumpWidget(
      _card(_order(1), pending: pending(deliverNow: false)),
    );
    expect(find.text(_ar.markingReady), findsOneWidget);

    // A fresh tree, so the first card's bar is not still cross-fading out.
    // Mounted partway through its window, as a card scrolled back into view
    // is: the announcement says the time actually left.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      _card(
        _order(2),
        pending: PendingAction(
          kind: PendingActionKind.ready,
          deliverNow: true,
          deadline: DateTime.now().add(const Duration(seconds: 3)),
        ),
      ),
    );
    expect(find.text(_ar.servingOrder), findsOneWidget);

    // The seconds left are read from the real clock, so compare before and
    // after rather than expect exact figures: a loaded machine shifts them.
    final liveRegion = find.bySemanticsLabel(
      RegExp(RegExp.escape(_ar.undoWindowSemantics(2, 0).split('0').first)),
    );
    final announcedBefore = tester.getSemantics(liveRegion).label;
    String undoLabel() => tester
        .widget<Text>(
          find.descendant(
            of: find.byType(TextButton),
            matching: find.byType(Text),
          ),
        )
        .data!;
    final undoBefore = undoLabel();

    // Let real time pass, then the tick. The digit on the button moves on;
    // the live region's words do not — a label that changed every second
    // was re-read every second.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(undoLabel(), isNot(undoBefore));
    expect(tester.getSemantics(liveRegion).label, announcedBefore);
    handle.dispose();
  });

  testWidgets('a made drink can be cancelled from handover, and the dialog '
      'says it becomes waste', (tester) async {
    await _queue(tester, _Repository(ready: [_order(9, status: 'Ready')]));

    await tester.tap(find.text(_ar.tabWithCount(_ar.handoverTab, 1)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_ar.cancelWithReason));
    await tester.pumpAndSettle();

    expect(find.text(_ar.cancelOrderTitle(9)), findsOneWidget);
    expect(find.text(_ar.cancelReadyWaste), findsOneWidget);
    // The buttons say what they do: keep it, or cancel it.
    final dialog = find.byType(AlertDialog);
    expect(
      find.descendant(of: dialog, matching: find.text(_ar.keepOrder)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text(_ar.cancelWithReason)),
      findsOneWidget,
    );
  });

  for (final locale in const [Locale('ar'), Locale('en')]) {
    testWidgets('both tabs say their count in full at 320dp and 2x '
        '(${locale.languageCode})', (tester) async {
      final l10n = lookupAppLocalizations(locale);
      await _queue(
        tester,
        _Repository(
          queue: [for (var i = 1; i <= 12; i++) _order(i)],
          ready: [for (var i = 20; i <= 31; i++) _order(i, status: 'Ready')],
        ),
        size: const Size(320, 640),
        scale: 2,
        locale: locale,
      );

      for (final label in [
        l10n.tabWithCount(l10n.queueTab, 12),
        l10n.tabWithCount(l10n.handoverTab, 12),
      ]) {
        // A fixed bar faded a label that did not fit, cut mid-word.
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        expect(paragraph.debugHasOverflowShader, isFalse, reason: label);
      }
      expect(tester.takeException(), isNull);
    });
  }

  group('the card says how the drink leaves the counter (§8.1)', () {
    testWidgets('a delivery names where to carry it', (tester) async {
      await tester.pumpWidget(_card(_order(1, fulfilment: 'Delivery')));
      await tester.pump();
      expect(
        find.textContaining(_ar.queueDeliverTo('').trim()),
        findsOneWidget,
      );
      expect(find.textContaining('الدور الثالث'), findsOneWidget);
      expect(find.text(_ar.queuePickup), findsNothing);
    });

    testWidgets('a pickup says so, and still where the person sits', (
      tester,
    ) async {
      await tester.pumpWidget(_card(_order(1, fulfilment: 'Pickup')));
      await tester.pump();
      expect(find.text(_ar.queuePickup), findsOneWidget);
      expect(find.textContaining('الدور الثالث'), findsOneWidget);
    });

    testWidgets('an order from before the choice shows the place alone', (
      tester,
    ) async {
      await tester.pumpWidget(_card(_order(1)));
      await tester.pump();
      expect(find.text(_ar.queuePickup), findsNothing);
      expect(
        find.textContaining(_ar.queueDeliverTo('').trim()),
        findsNothing,
      );
      expect(find.textContaining('الدور الثالث'), findsOneWidget);
    });
  });

  group('Start making', () {
    testWidgets('a Pending order starts once, then says it is being made, '
        'and can still be served', (tester) async {
      final handle = tester.ensureSemantics();
      final announced = <String>[];
      tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<
        Object?
      >(SystemChannels.accessibility, (message) async {
        final data = (message! as Map)['data'] as Map;
        if (data['message'] case final String text) announced.add(text);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockDecodedMessageHandler<Object?>(
              SystemChannels.accessibility,
              null,
            ),
      );
      final repository = _Starting([_order(5)]);
      await _queue(tester, repository);

      expect(find.text(_ar.beingMade), findsNothing);
      await tester.tap(find.text(_ar.startMaking));
      await tester.pump();
      // In flight: a second tap cannot post again, and the button says why
      // it is not answering.
      await tester.tap(find.text(_ar.startMaking), warnIfMissed: false);
      await tester.pump();
      // Merged into the button's own name.
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(_ar.pleaseWait))),
        findsOneWidget,
      );

      repository.answer.complete();
      await tester.pumpAndSettle();
      expect(repository.started, [5]);
      expect(find.text(_ar.startMaking), findsNothing);
      expect(find.text(_ar.beingMade), findsOneWidget);
      expect(find.text(_ar.readyAndDelivered), findsOneWidget);
      expect(find.text(_ar.markReady), findsOneWidget);
      // The list changing is not narrated on its own.
      expect(announced, contains(_ar.orderStartedAnnouncement));
      handle.dispose();
    });

    testWidgets("a refused start shows the server's reason and keeps the "
        'button', (tester) async {
      final repository = _Starting([_order(5)], refusal: 'تم إلغاء الطلب');
      await _queue(tester, repository);

      await tester.tap(find.text(_ar.startMaking));
      repository.answer.complete();
      await tester.pumpAndSettle();
      expect(find.text('تم إلغاء الطلب'), findsOneWidget);
      expect(find.text(_ar.startMaking), findsOneWidget);
    });

    testWidgets('a made drink awaiting handover offers no start', (
      tester,
    ) async {
      await _queue(tester, _Repository(ready: [_order(9, status: 'Ready')]));
      await tester.tap(find.text(_ar.tabWithCount(_ar.handoverTab, 1)));
      await tester.pumpAndSettle();
      expect(find.text(_ar.markDelivered), findsOneWidget);
      expect(find.text(_ar.startMaking), findsNothing);
    });
  });
}

/// A queue whose `/start` waits for [answer], then moves the order to
/// InProgress, or refuses with [refusal] as a server would.
class _Starting extends QueueRepository {
  _Starting(this.queue, {this.refusal}) : super(Dio());

  List<StaffOrderDto> queue;
  final String? refusal;
  final started = <int>[];
  final answer = Completer<void>();

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
  Future<void> start({
    required int orderId,
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    started.add(orderId);
    await answer.future;
    if (refusal != null) {
      throw ApiException(message: refusal!, statusCode: 400);
    }
    queue = [
      for (final o in queue)
        o.orderId == orderId ? _order(orderId, status: 'InProgress') : o,
    ];
  }
}
