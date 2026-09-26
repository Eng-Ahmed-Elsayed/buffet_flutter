import 'package:buffet_app/data/api/api_config.dart';
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
  _Repository repository, {
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

    final announced = find.bySemanticsLabel(
      RegExp(RegExp.escape(_ar.undoWindowSemantics(2, 3))),
    );
    expect(announced, findsOneWidget);

    // The bar reads the real clock, so let real time pass, then the tick.
    // The digit on the button moves on; the live region's words do not — a
    // label that changed every second was re-read every second.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(_ar.undoCountdown(2)), findsOneWidget);
    expect(announced, findsOneWidget);
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
}
