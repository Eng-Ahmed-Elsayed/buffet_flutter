import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/data/models/favourite_models.dart';
import 'package:buffet_app/data/models/order_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// A response in the shape §7.6 documents.
Map<String, dynamic> body({
  List<Map<String, dynamic>>? favourites,
  int maxFavourites = 20,
}) => {
  'favourites':
      favourites ??
      [
        {
          'favouriteId': 12,
          'name': 'قهوتي',
          'createdAtUtc': '2026-08-24T09:12:00Z',
          'lastUsedAtUtc': null,
          'lines': [
            {
              'drinkItemId': 4,
              'drinkNameAr': 'قهوة تركي',
              'sugarSpoons': 2,
              'variantId': 7,
              'sugarItemId': 3,
              'extraItemIds': [9],
              'lineNote': null,
              'drinkFromOwn': true,
              'sugarFromOwn': false,
              'ownExtraItemIds': [9],
            },
          ],
        },
      ],
  'maxFavourites': maxFavourites,
};

void main() {
  group('FavouritesResponse', () {
    test('parses the documented shape', () {
      final parsed = FavouritesResponse.fromJson(body());
      final favourite = parsed.favourites.single;

      expect(favourite.favouriteId, 12);
      expect(favourite.name, 'قهوتي');
      expect(favourite.lastUsedAtUtc, isNull);
      expect(parsed.maxFavourites, 20);
    });

    test('lines parse as OrderLineDto — the same shape POST /orders takes', () {
      // This is the whole reason the endpoint returns lines rather than a
      // summary: replaying a favourite is a straight repost, no translation.
      final line = FavouritesResponse.fromJson(body())
          .favourites
          .single
          .lines
          .single;

      expect(line, isA<OrderLineDto>());
      expect(line.drinkItemId, 4);
      expect(line.sugarSpoons, 2);
      expect(line.variantId, 7);
      expect(line.extraItemIds, [9]);
      expect(line.drinkFromOwn, isTrue);
      expect(line.ownExtraItemIds, [9]);
    });

    test('lastUsedAtUtc is read when the favourite has been ordered', () {
      final parsed = FavouritesResponse.fromJson(
        body(
          favourites: [
            {
              'favouriteId': 1,
              'name': 'شاي',
              'createdAtUtc': '2026-08-24T09:12:00Z',
              'lastUsedAtUtc': '2026-09-01T06:30:00Z',
              'lines': <Map<String, dynamic>>[],
            },
          ],
        ),
      );

      expect(
        parsed.favourites.single.lastUsedAtUtc,
        DateTime.utc(2026, 9, 1, 6, 30),
      );
    });

    test('a server predating maxFavourites yields the limit it enforces', () {
      final parsed = FavouritesResponse.fromJson({
        'favourites': <Map<String, dynamic>>[],
      });

      expect(parsed.maxFavourites, 20);
    });

    test('canSaveAnother is false only at the cap', () {
      expect(FavouritesResponse.fromJson(body()).canSaveAnother, isTrue);
      expect(
        FavouritesResponse.fromJson(body(maxFavourites: 1)).canSaveAnother,
        isFalse,
      );
    });
  });

  group('SaveFavouriteRequest', () {
    const line = OrderLineDto(
      drinkItemId: 4,
      drinkNameAr: 'قهوة تركي',
      sugarSpoons: 0,
      variantId: null,
      sugarItemId: null,
      extraItemIds: [],
      lineNote: null,
      drinkFromOwn: false,
      sugarFromOwn: false,
      ownExtraItemIds: [],
    );

    test('a null name is omitted, meaning "name it after the drinks"', () {
      // includeIfNull: false — a `name: null` key on the wire would be a
      // different thing from an absent one to a stricter server, and the
      // absent form is what the contract documents.
      final json = const SaveFavouriteRequest(lines: [line]).toJson();

      expect(json.containsKey('name'), isFalse);
      expect(json['lines'], hasLength(1));
    });

    test('a name is sent when the user gave one', () {
      final json = const SaveFavouriteRequest(
        lines: [line],
        name: 'قهوة الصبح',
      ).toJson();

      expect(json['name'], 'قهوة الصبح');
    });
  });

  group('PlaceOrderResponse.favouriteId', () {
    PlaceOrderResponse parse(Map<String, dynamic> extra) =>
        PlaceOrderResponse.fromJson({
          'orderId': 5,
          'duplicate': false,
          ...extra,
        });

    test('is read when a favourite was saved with the order', () {
      expect(parse({'favouriteId': 12}).favouriteId, 12);
    });

    test('null is a normal outcome, not an error', () {
      // Saving is best-effort — the drink is already made — so a full list or
      // a since-retired item returns null rather than failing the order.
      expect(parse({'favouriteId': null}).favouriteId, isNull);
      expect(parse(const {}).favouriteId, isNull);
    });
  });

  group('FavouriteDto.orders — "you already saved this"', () {
    OrderLineDto line({
      int drink = 4,
      int? variant = 7,
      int spoons = 2,
      int? sugar = 3,
      List<int> extras = const [9],
      bool fromOwn = false,
      String? note,
    }) => OrderLineDto(
      drinkItemId: drink,
      drinkNameAr: 'قهوة تركي',
      sugarSpoons: spoons,
      variantId: variant,
      sugarItemId: sugar,
      extraItemIds: extras,
      lineNote: note,
      drinkFromOwn: fromOwn,
      sugarFromOwn: false,
      ownExtraItemIds: const [],
    );

    FavouriteDto saved(List<OrderLineDto> lines) => FavouriteDto(
      favouriteId: 1,
      name: 'قهوتي',
      createdAtUtc: DateTime.utc(2026, 8, 24),
      lastUsedAtUtc: null,
      lines: lines,
    );

    test('matches the same order', () {
      expect(saved([line()]).orders([line()]), isTrue);
    });

    test('a different drink, sugar count or preparation does not match', () {
      expect(saved([line()]).orders([line(drink: 5)]), isFalse);
      expect(saved([line()]).orders([line(spoons: 1)]), isFalse);
      expect(saved([line()]).orders([line(variant: 8)]), isFalse);
      expect(saved([line()]).orders([line(sugar: null)]), isFalse);
    });

    test('extras match regardless of the order they were ticked in', () {
      // The composer builds these from a Set, so two identical drinks can
      // differ only in tick order. Treating that as a different order would
      // offer to save a duplicate of something already saved.
      final a = saved([
        line(extras: const [9, 12]),
      ]);
      expect(
        a.orders([
          line(extras: const [12, 9]),
        ]),
        isTrue,
      );
      expect(
        a.orders([
          line(extras: const [9]),
        ]),
        isFalse,
      );
    });

    test('the display name and the jar are ignored', () {
      // Only what is ORDERED counts. Two saves of the same coffee are the same
      // favourite whether or not the user named them differently.
      expect(saved([line()]).orders([line(fromOwn: true, note: 'x')]), isTrue);
    });

    test('a different number of drinks does not match', () {
      expect(saved([line()]).orders([line(), line(drink: 5)]), isFalse);
      expect(saved([line(), line(drink: 5)]).orders([line()]), isFalse);
    });
  });

  group('FavouriteDto.isAvailable — an item retired since it was saved', () {
    FavouriteDto saved({
      int drink = 4,
      int? sugar = 3,
      List<int> extras = const [9],
    }) => FavouriteDto(
      favouriteId: 1,
      name: 'قهوتي',
      createdAtUtc: DateTime.utc(2026, 8, 24),
      lastUsedAtUtc: null,
      lines: [
        OrderLineDto(
          drinkItemId: drink,
          drinkNameAr: 'قهوة تركي',
          sugarSpoons: 2,
          variantId: null,
          sugarItemId: sugar,
          extraItemIds: extras,
          lineNote: null,
          drinkFromOwn: false,
          sugarFromOwn: false,
          ownExtraItemIds: const [],
        ),
      ],
    );

    test('available when every item is still in the catalogue', () {
      expect(saved().isAvailable({4, 3, 9}), isTrue);
    });

    test('unavailable when the drink is gone', () {
      // The server does NOT filter these out on the way back (§7.6), so this
      // is a state the client genuinely meets and must render.
      expect(saved().isAvailable({3, 9}), isFalse);
    });

    test('unavailable when a sugar or an extra is gone', () {
      expect(saved().isAvailable({4, 9}), isFalse);
      expect(saved().isAvailable({4, 3}), isFalse);
    });

    test('a line with no sugar is not made unavailable by its absence', () {
      expect(saved(sugar: null, extras: const []).isAvailable({4}), isTrue);
    });
  });
}
