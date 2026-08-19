import 'package:buffet_app/data/api/api_config.dart';
import 'package:buffet_app/data/models/material_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StockLevel — values observed from the running server', () {
    test('parses the two bands the API actually returns', () {
      // Confirmed against /materials/mine: a healthy balance is "Ok" and a
      // depleted one is "Out". These are NOT High/Medium/Low/Empty, which an
      // earlier version of this enum guessed at.
      expect(StockLevel.fromWire('Ok'), StockLevel.ok);
      expect(StockLevel.fromWire('Out'), StockLevel.out);
    });

    test('matching is case-insensitive', () {
      expect(StockLevel.fromWire('ok'), StockLevel.ok);
      expect(StockLevel.fromWire('OUT'), StockLevel.out);
    });

    test('an unrecognised band falls back to ok, not to empty', () {
      // A material with an unknown band still has a quantity. Showing a false
      // "empty" would be worse than a neutral reading — the number beside it
      // is the real signal.
      expect(StockLevel.fromWire('Something'), StockLevel.ok);
      expect(StockLevel.fromWire(''), StockLevel.ok);
    });
  });

  group('MyMaterialDto', () {
    // A real response body, captured from the running server.
    MyMaterialDto parse({num quantity = 138, String level = 'Ok'}) =>
        MyMaterialDto.fromJson({
          'itemId': 7,
          'nameAr': 'قهوة تركية بالهيل',
          'unit': 'جرام',
          'quantity': quantity,
          'servingsLeft': 11,
          'level': level,
          'imageUrl': '/uploads/items/item-7-914ab363.png',
        });

    test('parses the imageUrl the API now returns', () {
      expect(parse().imageUrl, '/uploads/items/item-7-914ab363.png');
    });

    test('a relative imageUrl resolves against the API host', () {
      final resolved = ApiConfig.imageUrl(parse().imageUrl);
      expect(resolved, isNotNull);
      expect(resolved, contains('/uploads/items/item-7-914ab363.png'));
      expect(resolved, startsWith('http'));
    });

    test('an absolute imageUrl is passed through unchanged', () {
      // /catalogue returns ABSOLUTE urls while /materials/mine returns
      // relative ones — both must work through the same code path.
      const absolute =
          'http://digitalbuffet.runasp.net/uploads/items/item-7-914ab363.png';
      expect(ApiConfig.imageUrl(absolute), absolute);
    });

    test('a null imageUrl resolves to null so the caller falls back', () {
      expect(ApiConfig.imageUrl(null), isNull);
      expect(ApiConfig.imageUrl(''), isNull);
    });

    test('a decimal quantity does not truncate', () {
      expect(parse(quantity: 138.5).quantity, 138.5);
    });

    test(
      'a NEGATIVE quantity parses — balances legitimately go below zero',
      () {
        // Observed live: serving past an empty jar leaves -6.0000 with
        // level "Out". Shortages never block, so the ledger records the
        // overdraw rather than refusing the drink.
        final material = parse(quantity: -6, level: 'Out');
        expect(material.quantity, -6);
        expect(material.stockLevel, StockLevel.out);
      },
    );
  });
}
