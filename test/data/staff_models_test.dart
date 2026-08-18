import 'package:buffet_app/data/models/staff_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServeResultDto — shortages warn, never block', () {
    test('an empty warnings array is the normal success case', () {
      final result = ServeResultDto.fromJson({
        'orderId': 12,
        'status': 'Ready',
        'warnings': <Map<String, dynamic>>[],
      });

      expect(result.hasWarnings, isFalse);
      expect(result.status, 'Ready');
    });

    test(
      'a populated warnings array is still SUCCESS — the drink was made',
      () {
        // /ready returns 200 with warnings, never 400. Anything treating this
        // as a failure would tell staff the drink was not made when it was.
        final result = ServeResultDto.fromJson({
          'orderId': 12,
          'status': 'Ready',
          'warnings': [
            {
              'itemId': 3,
              'nameAr': 'بن تركي',
              'ownerDisplayName': 'أحمد حسن',
              'shortfall': 12,
              'unit': 'جرام',
            },
          ],
        });

        expect(result.hasWarnings, isTrue);
        // The status still advanced — that is the whole point.
        expect(result.status, 'Ready');
        expect(result.warnings.single.shortfall, 12);
      },
    );

    test('shortfall parses as a decimal without truncating', () {
      final result = ServeResultDto.fromJson({
        'orderId': 1,
        'status': 'Ready',
        'warnings': [
          {
            'itemId': 3,
            'nameAr': 'حليب',
            'ownerDisplayName': '',
            'shortfall': 2.5,
            'unit': 'لتر',
          },
        ],
      });

      expect(result.warnings.single.shortfall, 2.5);
    });
  });

  group('StaffOrderLineDto — sources are named, not caller-relative', () {
    StaffOrderLineDto parse({
      required String drinkOwner,
      required String sugarOwner,
    }) => StaffOrderLineDto.fromJson({
      'drinkItemId': 1,
      'drinkNameAr': 'قهوة تركي',
      'variantNameAr': 'وسط',
      'sugarSpoons': 2,
      // Always null — a documented deviation.
      'sugarNameAr': null,
      'extraNamesAr': ['حليب'],
      'lineNote': null,
      'drinkSourceOwnerName': drinkOwner,
      'sugarSourceOwnerName': sugarOwner,
      'extraSources': [
        {'itemId': 9, 'nameAr': 'حليب', 'sourceOwnerName': 'أحمد حسن'},
      ],
    });

    test('an empty owner name means company stock', () {
      final line = parse(drinkOwner: '', sugarOwner: '');
      expect(line.drinkSourceOwnerName, isEmpty);
      expect(line.sugarSourceOwnerName, isEmpty);
    });

    test('a named owner means that person\'s own jar', () {
      final line = parse(drinkOwner: 'أحمد حسن', sugarOwner: '');
      expect(line.drinkSourceOwnerName, 'أحمد حسن');
      // Mixed sources on one line are normal: the coffee is his, the sugar is
      // the buffet's.
      expect(line.sugarSourceOwnerName, isEmpty);
    });

    test('sugarNameAr is always null — the card shows spoons instead', () {
      final line = parse(drinkOwner: '', sugarOwner: '');
      expect(line.sugarNameAr, isNull);
      expect(line.sugarSpoons, 2);
    });

    test('extra sources name their own owner', () {
      final line = parse(drinkOwner: '', sugarOwner: '');
      expect(line.extraSources.single.sourceOwnerName, 'أحمد حسن');
    });
  });

  group('StaffOrderDto', () {
    test('carries waitingSeconds for the ageing indicator', () {
      final order = StaffOrderDto.fromJson({
        'orderId': 7,
        'status': 'Pending',
        'createdAtUtc': '2026-08-18T09:00:00Z',
        'readyAtUtc': null,
        'requesterDisplayName': 'أحمد حسن',
        'department': 'الشؤون المالية',
        'locationText': 'الدور الثالث',
        'onBehalfOfName': null,
        'notes': '',
        'waitingSeconds': 480,
        'lines': <Map<String, dynamic>>[],
      });

      expect(order.waitingSeconds, 480);
      expect(order.createdAtUtc.isUtc, isTrue);
      expect(order.requesterDisplayName, 'أحمد حسن');
    });
  });
}
