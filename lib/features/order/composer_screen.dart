import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/locale_controller.dart';
import '../../app/routes.dart';
import '../../data/api/api_exception.dart';
import '../../data/models/catalogue_models.dart';
import '../../data/repositories/catalogue_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/banners.dart';
import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';
import 'composer_controller.dart';
import 'widgets/drink_tile.dart';
import 'widgets/sugar_stepper.dart';

/// Fetches the catalogue in one round trip.
final catalogueProvider = FutureProvider.autoDispose<CatalogueResponse>((
  ref,
) async {
  final locale = ref.watch(localeControllerProvider);
  return ref
      .watch(catalogueRepositoryProvider)
      .fetchCatalogue(
        languageCode: locale.languageCode,
        // The repository only uses this when there was no response at all.
        networkErrorFallback: 'network',
      );
});

/// The order composer — one screen, not a wizard. A wizard on a phone for a cup
/// of coffee is worse, not better (§7.1).
class ComposerScreen extends ConsumerStatefulWidget {
  const ComposerScreen({super.key});

  @override
  ConsumerState<ComposerScreen> createState() => _ComposerScreenState();
}

class _ComposerScreenState extends ConsumerState<ComposerScreen> {
  bool _placing = false;

  Future<void> _placeOrder() async {
    final l10n = AppLocalizations.of(context);
    final locale = ref.read(localeControllerProvider);
    final composer = ref.read(composerControllerProvider);
    if (!composer.canPlaceOrder) return;

    setState(() => _placing = true);

    try {
      final result = await ref
          .read(catalogueRepositoryProvider)
          .placeOrder(
            request: composer.toRequest(),
            languageCode: locale.languageCode,
            networkErrorFallback: l10n.networkError,
          );

      if (!mounted) return;

      // 201 duplicate:false and 200 duplicate:true are both success — the
      // second means a retry matched an existing order. Same confirmation.
      ref.read(composerControllerProvider.notifier).resetAfterConfirmedOrder();
      context.go(Routes.orderStatusFor(result.orderId));
    } on ApiException catch (error) {
      if (!mounted) return;
      // The composer keeps its contents and its idempotency key, so the retry
      // is the *same* order. Nothing is queued for later (§9).
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final catalogue = ref.watch(catalogueProvider);
    final composer = ref.watch(composerControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.orderTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: l10n.myMaterialsTitle,
            onPressed: () => context.push(Routes.materials),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.settings,
            onPressed: () => context.push(Routes.settings),
          ),
        ],
      ),
      body: catalogue.when(
        loading: () => const Center(child: CircularProgressIndicator()),

        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: l10n.genericError,
          body: error is ApiException ? error.message : l10n.networkError,
          action: OutlinedButton.icon(
            onPressed: () => ref.invalidate(catalogueProvider),
            icon: const Icon(Icons.refresh),
            label: Text(l10n.retry),
          ),
        ),

        data: (data) {
          if (data.drinks.isEmpty) {
            return EmptyState(
              icon: Icons.no_drinks_outlined,
              title: l10n.emptyCatalogueTitle,
              body: l10n.emptyCatalogueBody,
              action: OutlinedButton.icon(
                onPressed: () => ref.invalidate(catalogueProvider),
                icon: const Icon(Icons.refresh),
                label: Text(l10n.refresh),
              ),
            );
          }

          return _ComposerBody(
            catalogue: data,
            composer: composer,
            placing: _placing,
            onPlaceOrder: _placeOrder,
          );
        },
      ),
    );
  }
}

class _ComposerBody extends ConsumerWidget {
  const _ComposerBody({
    required this.catalogue,
    required this.composer,
    required this.placing,
    required this.onPlaceOrder,
  });

  final CatalogueResponse catalogue;
  final ComposerState composer;
  final bool placing;
  final Future<void> Function() onPlaceOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(composerControllerProvider.notifier);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsetsDirectional.all(Dimens.space4),
            children: [
              // The usual order is the single highest-value feature in the
              // app — one tap, at the top (§7.1).
              if (catalogue.usual != null) ...[
                _UsualOrderCard(
                  usual: catalogue.usual!,
                  onApply: () =>
                      controller.applyUsual(catalogue.usual!, catalogue.drinks),
                ),
                const SizedBox(height: Dimens.space4),
              ],

              if (composer.ownStockIsShort) ...[
                InlineBanner(
                  tone: BannerTone.warning,
                  title: l10n.ownStockShortTitle,
                  body: l10n.ownStockShortBody,
                ),
                const SizedBox(height: Dimens.space4),
              ],

              Text(l10n.drink, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: Dimens.space3),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: Dimens.space3,
                  crossAxisSpacing: Dimens.space3,
                  childAspectRatio: 0.82,
                ),
                itemCount: catalogue.drinks.length,
                itemBuilder: (context, index) {
                  final drink = catalogue.drinks[index];
                  return DrinkTile(
                    item: drink,
                    selected: composer.drink?.itemId == drink.itemId,
                    onTap: () => controller.selectDrink(drink),
                  );
                },
              ),

              // Appears only once a drink the user owns is selected — showing
              // it always is noise for the majority who own nothing (§7.1).
              if (composer.canUseOwnMaterials) ...[
                const SizedBox(height: Dimens.space4),
                _FromMyMaterialsToggle(
                  servingsLeft: composer.drink?.ownServingsLeft ?? 0,
                  value: composer.drinkFromOwn,
                  onChanged: controller.setDrinkFromOwn,
                ),
              ],

              const SizedBox(height: Dimens.space5),
              Text(l10n.sugar, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: Dimens.space2),
              SugarStepper(
                spoons: composer.sugarSpoons,
                onChanged: controller.setSugarSpoons,
              ),

              if (catalogue.extras.isNotEmpty) ...[
                const SizedBox(height: Dimens.space5),
                Text(
                  l10n.extras,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: Dimens.space2),
                Wrap(
                  spacing: Dimens.space2,
                  runSpacing: Dimens.space2,
                  children: [
                    for (final extra in catalogue.extras)
                      FilterChip(
                        label: Text(extra.nameAr),
                        selected: composer.extraItemIds.contains(extra.itemId),
                        onSelected: (_) => controller.toggleExtra(extra.itemId),
                        // Violet only when it is genuinely the user's own
                        // stock — never as a generic selected state.
                        selectedColor: extra.hasOwnStock
                            ? BrandColors.accentSurface
                            : BrandColors.brandLight,
                        checkmarkColor: extra.hasOwnStock
                            ? BrandColors.accent
                            : BrandColors.brand,
                      ),
                  ],
                ),
              ],

              const SizedBox(height: Dimens.space5),
            ],
          ),
        ),

        _ComposerFooter(
          locations: catalogue.locations,
          composer: composer,
          placing: placing,
          onPlaceOrder: onPlaceOrder,
        ),
      ],
    );
  }
}

class _UsualOrderCard extends StatelessWidget {
  const _UsualOrderCard({required this.usual, required this.onApply});

  final UsualOrderDto usual;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsetsDirectional.all(Dimens.space4),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        border: Border.all(color: BrandColors.brandLight),
        borderRadius: BorderRadius.circular(Dimens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.refresh, size: 18, color: BrandColors.brand),
              const SizedBox(width: Dimens.space2),
              Text(
                l10n.usualOrder,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: Dimens.space2),
          // Server-composed and human-readable; rendered as-is.
          Text(usual.summary, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: Dimens.space3),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onApply,
              child: Text(l10n.orderTheUsual),
            ),
          ),
        ],
      ),
    );
  }
}

/// The violet toggle. Violet means "from my own jar" — nowhere else.
class _FromMyMaterialsToggle extends StatelessWidget {
  const _FromMyMaterialsToggle({
    required this.servingsLeft,
    required this.value,
    required this.onChanged,
  });

  final int servingsLeft;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEmpty = servingsLeft <= 0;

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Dimens.space4,
        vertical: Dimens.space2,
      ),
      decoration: BoxDecoration(
        color: BrandColors.accentSurface,
        border: Border.all(color: BrandColors.accent),
        borderRadius: BorderRadius.circular(Dimens.radius),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.inventory_2_outlined,
            size: 20,
            color: BrandColors.accent,
          ),
          const SizedBox(width: Dimens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.fromMyMaterials,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: BrandColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  l10n.servingsLeft(servingsLeft),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isEmpty ? BrandColors.warning : BrandColors.muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          // Deliberately still switchable at zero: the order goes through and
          // staff see the shortage. Never disabled on a stock reading.
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: BrandColors.surface,
            activeTrackColor: BrandColors.accent,
          ),
        ],
      ),
    );
  }
}

class _ComposerFooter extends ConsumerWidget {
  const _ComposerFooter({
    required this.locations,
    required this.composer,
    required this.placing,
    required this.onPlaceOrder,
  });

  final List<LocationDto> locations;
  final ComposerState composer;
  final bool placing;
  final Future<void> Function() onPlaceOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(composerControllerProvider.notifier);

    return Container(
      padding: const EdgeInsetsDirectional.only(
        start: Dimens.space4,
        end: Dimens.space4,
        top: Dimens.space3,
        bottom: Dimens.space5,
      ),
      decoration: const BoxDecoration(
        color: BrandColors.surface,
        border: BorderDirectional(
          top: BorderSide(color: BrandColors.brandLight),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A combo, not a dropdown: the managed list is a *suggestion* and an
          // unlisted place must never block an order (§7.1).
          Autocomplete<LocationDto>(
            optionsBuilder: (value) => value.text.isEmpty
                ? locations
                : locations.where((l) => l.nameAr.contains(value.text)),
            displayStringForOption: (option) => option.nameAr,
            onSelected: (option) =>
                controller.setLocation(locationId: option.locationId),
            fieldViewBuilder:
                (context, textController, focusNode, onFieldSubmitted) {
                  return TextField(
                    controller: textController,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      labelText: l10n.deliveryLocation,
                      hintText: l10n.locationHint,
                      prefixIcon: const Icon(Icons.place_outlined, size: 18),
                    ),
                    // Free text is sent as locationText — the order stands
                    // even when the place is not on the managed list.
                    onChanged: (text) =>
                        controller.setLocation(locationText: text),
                  );
                },
          ),
          const SizedBox(height: Dimens.space3),
          FilledButton(
            // Disabled only when there is genuinely nothing to order.
            // NEVER disabled on a stock reading — see ownStockIsShort, which
            // drives a warning and nothing else.
            onPressed: composer.canPlaceOrder && !placing
                ? () => onPlaceOrder()
                : null,
            child: placing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: BrandColors.surface,
                    ),
                  )
                : Text(l10n.placeOrder),
          ),
        ],
      ),
    );
  }
}
