/// Behaviour §12 of the guide requires that no other test exercised, found by
/// the milestone's definition-of-done check.
library;

import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/data/models/favourite_models.dart';
import 'package:buffet_app/data/models/material_models.dart';
import 'package:buffet_app/data/repositories/favourites_repository.dart';
import 'package:buffet_app/data/repositories/materials_repository.dart';
import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:buffet_app/features/auth/lock_screen.dart';
import 'package:buffet_app/features/materials/declare_sheet.dart';
import 'package:buffet_app/features/materials/my_materials_screen.dart';
import 'package:buffet_app/features/order/composer_screen.dart';
import 'package:buffet_app/features/order/favourites_controller.dart';
import 'package:buffet_app/features/order/favourites_screen.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_harness.dart';
import '../helpers/fake_auth_controller.dart';

final _ar = lookupAppLocalizations(const Locale('ar'));

class _Lock extends FakeAuthController {
  _Lock()
    : super(
        const AuthState(
          stage: AuthStage.locked,
          rememberedEmail: 'sara@company.com',
        ),
        pinned: true,
      );

  int toPassword = 0;

  @override
  Future<void> signOutFromLock() async => toPassword++;
}

class _Favourites extends FavouritesRepository {
  _Favourites() : super(Dio());

  final deleted = <int>[];

  @override
  Future<void> deleteFavourite({
    required int favouriteId,
    required String languageCode,
    required String networkErrorFallback,
  }) async => deleted.add(favouriteId);
}

class _Materials extends MaterialsRepository {
  _Materials() : super(Dio());

  DeclareMaterialRequest? declared;

  @override
  Future<void> declare({
    required DeclareMaterialRequest request,
    required String languageCode,
    required String networkErrorFallback,
  }) async => declared = request;
}

CatalogueItemDto _item(int id, String name) => CatalogueItemDto(
  itemId: id,
  nameAr: name,
  nameEn: name,
  category: 'Drink',
  unit: 'جرام',
  imageUrl: null,
  inStock: true,
  hasOwnStock: false,
  ownServingsLeft: 0,
  variants: const [],
  allowedExtraItemIds: null,
);

void main() {
  setUpAll(loadAppFonts);

  Future<void> tall(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('the lock always offers the password, even after a failed '
      'prompt', (tester) async {
    await tall(tester);
    final auth = _Lock();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWith((r) => auth)],
        child: testApp(home: const LockScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // The fake's prompt was cancelled: the failure banner is up, and the way
    // past is still there and still works — a lock with no key is worse than
    // no lock (§6).
    expect(find.text(_ar.biometricFailed), findsOneWidget);
    await tester.tap(find.text(_ar.usePasswordInstead));
    await tester.pumpAndSettle();
    expect(auth.toPassword, 1);
  });

  testWidgets('a long press deletes a favourite, after asking', (tester) async {
    await tall(tester);
    final repository = _Favourites();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          favouritesRepositoryProvider.overrideWithValue(repository),
          favouritesProvider.overrideWith(
            (r) async => FavouritesResponse(
              favourites: [
                FavouriteDto(
                  favouriteId: 4,
                  name: 'قهوة الصباح',
                  createdAtUtc: DateTime.utc(2026, 9, 1),
                  lastUsedAtUtc: null,
                  lines: const <OrderLineDto>[],
                ),
              ],
            ),
          ),
          catalogueProvider.overrideWith(
            (r) async => const CatalogueResponse(
              drinks: [],
              sugars: [],
              extras: [],
              locations: [],
            ),
          ),
        ],
        child: testApp(home: const FavouritesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.textContaining('قهوة الصباح'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(repository.deleted, isEmpty);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(_ar.delete),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.deleted, [4]);
  });

  testWidgets('a declaration says it awaits confirmation, never "added"', (
    tester,
  ) async {
    await tall(tester);
    final repository = _Materials();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          materialsRepositoryProvider.overrideWithValue(repository),
          myMaterialsProvider.overrideWith(
            (r) async => const <MyMaterialDto>[],
          ),
          catalogueProvider.overrideWith(
            (r) async => CatalogueResponse(
              drinks: [_item(7, 'قهوة تركية')],
              sugars: const [],
              extras: const [],
              locations: const [],
            ),
          ),
        ],
        child: testApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const DeclareSheet(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<Object>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('قهوة تركية').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '250');
    await tester.ensureVisible(find.text(_ar.sendDeclaration));
    await tester.tap(find.text(_ar.sendDeclaration));
    await tester.pumpAndSettle();

    expect(repository.declared?.itemId, 7);
    // A 202 creates nothing until an admin confirms receipt (rule 4).
    expect(find.text(_ar.declarationSentBody), findsOneWidget);
    expect(_ar.declarationSentBody, contains('التأكيد'));
  });
}
