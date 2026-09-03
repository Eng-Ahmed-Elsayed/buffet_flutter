import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/data/models/favourite_models.dart';
import 'package:buffet_app/features/order/widgets/favourites_strip.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

FavouriteDto _favourite({
  int id = 1,
  String name = 'قهوة الصبح',
  int drink = 4,
  DateTime? lastUsed,
}) => FavouriteDto(
  favouriteId: id,
  name: name,
  // Ascending with the id, so "newest saved" and "lowest id" differ.
  createdAtUtc: DateTime.utc(2026, 8, id),
  lastUsedAtUtc: lastUsed,
  lines: [
    OrderLineDto(
      drinkItemId: drink,
      drinkNameAr: 'قهوة',
      sugarSpoons: 0,
      variantId: null,
      sugarItemId: null,
      extraItemIds: const <int>[],
      lineNote: null,
      drinkFromOwn: false,
      sugarFromOwn: false,
      ownExtraItemIds: const <int>[],
    ),
  ],
);

Widget _wrap(Widget child) => MaterialApp(
  locale: const Locale('ar'),
  supportedLocales: const [Locale('ar'), Locale('en')],
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  group('the strip defers a long list rather than filling the screen', () {
    testWidgets('shows every favourite when there are few', (tester) async {
      await tester.pumpWidget(
        _wrap(
          FavouritesStrip(
            favourites: [
              _favourite(id: 1, name: 'أ'),
              _favourite(id: 2, name: 'ب'),
            ],
            onReplay: (_) {},
            onDelete: (_) {},
            onShowAll: () {},
          ),
        ),
      );

      expect(find.byType(FavouriteCard), findsNWidgets(2));
      // Nothing hidden, so nothing to offer.
      expect(find.textContaining('عرض الكل'), findsNothing);
    });

    testWidgets('caps the cards and offers the rest behind a link', (
      tester,
    ) async {
      // The cap is 20 per user; twenty cards would push "New order" off the
      // screen this strip sits on.
      await tester.pumpWidget(
        _wrap(
          FavouritesStrip(
            favourites: [
              for (var i = 1; i <= 9; i++) _favourite(id: i, name: 'طلب $i'),
            ],
            onReplay: (_) {},
            onDelete: (_) {},
            onShowAll: () {},
          ),
        ),
      );

      expect(find.byType(FavouriteCard), findsNWidgets(4));
      // The count is on the label, so the user knows what the tap is worth.
      expect(find.text('عرض الكل (9)'), findsOneWidget);
    });

    testWidgets('shows ALL of them when there is nowhere to send the user', (
      tester,
    ) async {
      // Truncating with no "show all" link would lose favourites exactly as
      // silently as filtering a retired one out — the thing this feature
      // refuses to do. Better a long strip than a vanished order.
      await tester.pumpWidget(
        _wrap(
          FavouritesStrip(
            favourites: [
              for (var i = 1; i <= 9; i++) _favourite(id: i, name: 'طلب $i'),
            ],
            onReplay: (_) {},
            onDelete: (_) {},
          ),
        ),
      );

      expect(find.byType(FavouriteCard), findsNWidgets(9));
      expect(find.textContaining('عرض الكل'), findsNothing);
    });

    testWidgets('leads with the most recently USED, not the newest saved', (
      tester,
    ) async {
      // lastUsedAtUtc exists so a client can lead with what is actually in
      // use. Truncating is only honest if the ones cut are the least wanted.
      await tester.pumpWidget(
        _wrap(
          FavouritesStrip(
            maxVisible: 1,
            favourites: [
              // Newest saved, never ordered.
              _favourite(id: 9, name: 'جديد'),
              _favourite(
                id: 1,
                name: 'المعتاد',
                lastUsed: DateTime.utc(2026, 9, 1),
              ),
            ],
            onReplay: (_) {},
            onDelete: (_) {},
            onShowAll: () {},
          ),
        ),
      );

      expect(find.textContaining('المعتاد'), findsOneWidget);
      expect(find.textContaining('جديد'), findsNothing);
    });
  });

  group('a favourite whose item an admin retired', () {
    testWidgets('is shown and marked, never hidden', (tester) async {
      // The server deliberately does not filter these out (§7.6): one that
      // vanished silently would leave the user nothing to act on, and no way
      // to delete what they cannot see.
      await tester.pumpWidget(
        _wrap(
          FavouritesStrip(
            favourites: [_favourite(drink: 99)],
            availableItemIds: const {4},
            onReplay: (_) {},
            onDelete: (_) {},
          ),
        ),
      );

      expect(find.byType(FavouriteCard), findsOneWidget);
      // Said in words, not by colour alone (§2.5).
      expect(find.text('غير متاح حاليًا'), findsOneWidget);
    });

    testWidgets('it still taps, so the user can see what is wrong', (
      tester,
    ) async {
      FavouriteDto? replayed;
      await tester.pumpWidget(
        _wrap(
          FavouritesStrip(
            favourites: [_favourite(drink: 99)],
            availableItemIds: const {4},
            onReplay: (f) => replayed = f,
            onDelete: (_) {},
          ),
        ),
      );

      await tester.tap(find.byType(FavouriteCard));
      await tester.pump();

      // Not disabled: tapping seeds the composer, where the missing drink is a
      // line they can look at rather than an opaque refusal.
      expect(replayed?.favouriteId, 1);
    });

    testWidgets('an available favourite carries no mark', (tester) async {
      await tester.pumpWidget(
        _wrap(
          FavouritesStrip(
            favourites: [_favourite(drink: 4)],
            availableItemIds: const {4},
            onReplay: (_) {},
            onDelete: (_) {},
          ),
        ),
      );

      expect(find.byType(FavouriteCard), findsOneWidget);
      expect(find.text('غير متاح حاليًا'), findsNothing);
    });

    testWidgets('nothing is marked while the catalogue is still loading', (
      tester,
    ) async {
      // Null means "not known yet". Flashing "unavailable" over a request that
      // has merely not come back would be a lie with a scary tone.
      await tester.pumpWidget(
        _wrap(
          FavouritesStrip(
            favourites: [_favourite(drink: 99)],
            onReplay: (_) {},
            onDelete: (_) {},
          ),
        ),
      );

      expect(find.byType(FavouriteCard), findsOneWidget);
      expect(find.text('غير متاح حاليًا'), findsNothing);
    });
  });
}
