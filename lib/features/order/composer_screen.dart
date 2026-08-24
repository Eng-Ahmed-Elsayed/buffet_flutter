import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/locale_controller.dart';
import '../../app/routes.dart';
import '../../data/api/api_exception.dart';
import '../../data/models/catalogue_models.dart';
import '../../data/repositories/catalogue_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/exit_confirmation.dart';
import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';
import '../../theme/motion.dart';
import '../auth/auth_controller.dart';
import 'composer_controller.dart';
import 'my_orders_screen.dart';
import 'self_order_outcome.dart';
import 'widgets/drink_tile.dart';
import 'widgets/outstanding_order_card.dart';
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

class _ComposerScreenState extends ConsumerState<ComposerScreen>
    with WidgetsBindingObserver {
  bool _placing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A drink can turn Ready while the app is in the background. Re-reading
    // on resume is what makes the card honest for the user who closed the app
    // to wait — the case this whole card is for.
    if (state == AppLifecycleState.resumed) ref.invalidate(myOrdersProvider);
  }

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
      // The new order belongs in the outstanding list the moment it exists,
      // so the card is already there when the user comes back here.
      ref.invalidate(myOrdersProvider);

      // A staff member's own order is already made and handed over — they were
      // standing at the machine. Opening a status screen would poll an order
      // that will never move, so the confirmation goes back to the queue with
      // them instead.
      if (result.autoServed) {
        final outcome = SelfOrderOutcome(
          orderId: result.orderId,
          shortageNames: result.shortageNames,
        );
        if (context.canPop()) {
          context.pop(outcome);
        } else {
          context.go(Routes.queue);
        }
        return;
      }

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

    return ExitConfirmation(
      // A landing screen: nothing sits beneath it in the stack, so back
      // would otherwise close the app outright.
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.orderTitle),
          actions: [
            // The way back to a live order. Without this the tracking screen
            // was reachable only by placing an order — leave it and a drink
            // still being made became untraceable.
            IconButton(
              icon: const Icon(Icons.receipt_long_outlined),
              tooltip: l10n.myOrdersTitle,
              onPressed: () => context.push(Routes.myOrders),
            ),
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

            // The caps live on the server and are published with the
            // catalogue, so the limit is not duplicated as a magic number
            // here. Applied in a post-frame callback: this runs during build,
            // and mutating a provider mid-build would be a write during a
            // read.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              ref.read(composerControllerProvider.notifier)
                ..applyLimits(
                  maxLines: data.maxLines,
                  maxBuffetDrinks: data.maxBuffetDrinks,
                )
                // The cap rule needs both the name and the privilege, so the
                // model carries both rather than half the rule living in the
                // guest field's `if`.
                ..setCanOrderForGuests(ref.read(canOrderForGuestsProvider));
            });

            return _ComposerBody(
              catalogue: data,
              composer: composer,
              placing: _placing,
              onPlaceOrder: _placeOrder,
            );
          },
        ),
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
    final outstanding = ref.watch(outstandingOrdersProvider);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsetsDirectional.all(Dimens.space4),
            children: [
              // Above even the usual order: a drink already owed to the user
              // outranks placing another. This is the whole reason the card
              // exists — closing the app while waiting is normal, and on the
              // next launch this screen is where they land.
              if (outstanding.isNotEmpty) ...[
                OutstandingOrderCard(
                  order: outstanding.first,
                  othersCount: outstanding.length - 1,
                  onTap: () => context.push(
                    Routes.orderStatusFor(outstanding.first.orderId),
                  ),
                ),
                const SizedBox(height: Dimens.space4),
              ],

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

              // The shortage warning fades in rather than snapping: it appears
              // as a consequence of selecting a drink, and an element that
              // materialises instantly reads as an error the user caused.
              // Collapses to no animation under reduced motion (§2.3).
              AnimatedSwitcher(
                duration: Motion.of(context, Motion.base),
                switchInCurve: Motion.easeOut,
                // Exits are always faster than entrances (§2.3).
                switchOutCurve: Motion.easeSoft,
                child: composer.ownStockIsShort
                    ? Padding(
                        key: const ValueKey('own-stock-short'),
                        padding: const EdgeInsetsDirectional.only(
                          bottom: Dimens.space4,
                        ),
                        child: InlineBanner(
                          tone: BannerTone.warning,
                          title: l10n.ownStockShortTitle,
                          body: l10n.ownStockShortBody,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              // Drinks already added. Absent for the ordinary one-drink
              // order, which is unchanged.
              if (composer.lines.isNotEmpty) ...[
                _AddedLines(
                  lines: composer.lines,
                  onRemove: controller.removeLine,
                ),
                const SizedBox(height: Dimens.space4),
              ],

              // The buffet cap, explained where the user can act on it rather
              // than as a 400 after the whole order is composed.
              //
              // A structural limit, not a stock reading: the server rejects
              // the order outright past it. It still does not disable the
              // order button — the user fixes it by switching a drink to
              // their own jar or removing it.
              // The password change worked but the token refresh did not.
              // Shown here because this is where the user lands afterwards,
              // and dismissed once seen.
              if (ref.watch(sessionNotRefreshedProvider)) ...[
                InlineBanner(
                  tone: BannerTone.warning,
                  title: l10n.sessionNotRefreshed,
                ),
                const SizedBox(height: Dimens.space4),
              ],

              // Shown for the order as it stands AND for a draft that cannot
              // be added — the add button is disabled in the second case, and
              // a disabled control with no reason beside it is a dead end.
              if (composer.exceedsBuffetCap ||
                  composer.draftWouldExceedBuffetCap) ...[
                InlineBanner(
                  tone: BannerTone.warning,
                  title: l10n.buffetCapTitle,
                  body: l10n.buffetCapBody,
                ),
                const SizedBox(height: Dimens.space4),
              ],

              if (!composer.canAddAnotherLine) ...[
                InlineBanner(
                  tone: BannerTone.warning,
                  title: l10n.maxLinesReachedTitle,
                  body: l10n.maxLinesReachedBody(composer.maxLines),
                ),
                const SizedBox(height: Dimens.space4),
              ],

              Text(l10n.drink, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: Dimens.space3),

              // Split into "my materials" and "the buffet" so the buffet cap
              // is legible: the user can see which drinks count against it.
              //
              // Grouped on `hasOwnStock`, which means the user owns *some* —
              // it says nothing about how much. An owned item with nothing
              // left still belongs here, with the shortage shown on the tile
              // and NEVER hidden or disabled (§3).
              ..._groupedDrinks(
                context: context,
                drinks: catalogue.drinks,
                composer: composer,
                controller: controller,
              ),

              // Shown ONLY when the selected drink has more than one way of
              // being made. `variants` is empty for drinks made one way, so a
              // selector with a single option would be a decision the user
              // does not actually have.
              if ((composer.drink?.variants.length ?? 0) > 1) ...[
                const SizedBox(height: Dimens.space5),
                Text(
                  l10n.preparation,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: Dimens.space2),
                Wrap(
                  spacing: Dimens.space2,
                  runSpacing: Dimens.space2,
                  children: [
                    for (final variant in composer.drink!.variants)
                      ChoiceChip(
                        label: Text(
                          variant.localisedName(
                            Localizations.localeOf(context).languageCode,
                          ),
                        ),
                        selected: composer.variantId == variant.variantId,
                        onSelected: (_) =>
                            controller.selectVariant(variant.variantId),
                        // Brand, not accent: this is a preparation choice,
                        // not a statement about whose jar it comes from.
                        selectedColor: BrandColors.brandLight,
                      ),
                  ],
                ),
              ],

              const SizedBox(height: Dimens.space5),
              Text(l10n.sugar, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: Dimens.space2),
              SugarStepper(
                spoons: composer.sugarSpoons,
                onChanged: controller.setSugarSpoons,
              ),

              // Filtered by the selected drink. A drink with no configured
              // restriction permits everything (null); one configured to take
              // none has an empty list and hides the row entirely rather than
              // showing an empty section (§6).
              //
              // Not cosmetic: an extra the drink does not permit is dropped
              // server-side while the order still SUCCEEDS, so offering one
              // produces a drink that arrives wrong rather than an error.
              if (_visibleExtras(catalogue.extras, composer.drink)
                  case final List<CatalogueItemDto> extras
                  when extras.isNotEmpty) ...[
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
                    for (final extra in extras)
                      _ExtraChip(
                        extra: extra,
                        selected: composer.extraItemIds.contains(extra.itemId),
                        // Follows the PREPARATION, not the drink: milk is in a
                        // فرنساوي and not in a غامق, so the mark moves when the
                        // user switches between them.
                        doublesUp: composer.extraDoublesUp(extra.itemId),
                        onTap: () => controller.toggleExtra(extra.itemId),
                      ),
                  ],
                ),

                // Shown only once such an extra is actually ticked. The
                // doubling is correct — two pours, two deductions — but it is
                // the kind of correct that looks like a bug on the stock
                // report if nobody says so first.
                //
                // A warning, never a block: a double portion is a legitimate
                // thing to order and the user may well mean it.
                if (composer.doubledExtraItemIds.isNotEmpty) ...[
                  const SizedBox(height: Dimens.space3),
                  InlineBanner(
                    tone: BannerTone.warning,
                    title: l10n.extraDoublesHint,
                  ),
                ],
              ],

              // Commits the drink being composed and clears the controls
              // for the next one — one screen, never a wizard (§7.1).
              // Hidden until a drink is chosen: there is nothing to add.
              if (composer.drink != null) ...[
                const SizedBox(height: Dimens.space5),
                OutlinedButton.icon(
                  // Disabled on a structural limit the server enforces, never
                  // on a stock reading alone: the cap counts resolved sources,
                  // and the banner above says how to satisfy it.
                  onPressed:
                      composer.canAddAnotherLine &&
                          !composer.draftWouldExceedBuffetCap
                      ? controller.addLine
                      : null,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(l10n.addAnotherDrink),
                ),
              ],

              const SizedBox(height: Dimens.space5),
            ],
          ),
        ),

        _ComposerFooter(
          composer: composer,
          placing: placing,
          onPlaceOrder: onPlaceOrder,
        ),
      ],
    );
  }
}

/// The extras this drink permits, in catalogue order.
///
/// A null [CatalogueItemDto.allowedExtraItemIds] means unrestricted, so every
/// extra shows; an empty list means none, and the caller hides the row. With no
/// drink chosen yet the full list shows — there is no restriction to apply.
List<CatalogueItemDto> _visibleExtras(
  List<CatalogueItemDto> extras,
  CatalogueItemDto? drink,
) => drink == null
    ? extras
    : [
        for (final e in extras)
          if (drink.permitsExtra(e.itemId)) e,
      ];

/// The drink grid, split into "my materials" and "the buffet".
///
/// Owned items come first. An item can be in both — [CatalogueItemDto.hasOwnStock]
/// means the user owns *some*, and the buffet may stock it too — so this groups
/// by which jar is available to draw on, and the per-drink "from my jar" toggle
/// stays the thing that actually decides.
/// The drink grid, split into "my materials" and "the buffet".
///
/// **A drink the user owns appears in BOTH sections** — the same coffee
/// available from two jars is two tiles, one per jar. Partitioning instead
/// would take away the choice to draw an owned drink from the buffet, which is
/// a real one: someone saving their own beans for later still wants a coffee.
///
/// The tile carries the source, so there is no separate "from my materials"
/// toggle. The question is answered by which group was tapped, before the drink
/// is chosen rather than after.
List<Widget> _groupedDrinks({
  required BuildContext context,
  required List<CatalogueItemDto> drinks,
  required ComposerState composer,
  required ComposerController controller,
}) {
  final l10n = AppLocalizations.of(context);
  final mine = [
    for (final d in drinks)
      if (d.hasOwnStock) d,
  ];

  Widget grid(List<CatalogueItemDto> items, {required bool fromOwn}) =>
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: Dimens.space3,
          crossAxisSpacing: Dimens.space3,
          childAspectRatio: 0.82,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final drink = items[index];
          return DrinkTile(
            item: drink,
            // Both the drink AND the jar must match: the same drink is on
            // screen twice, and lighting up both tiles would say the user had
            // chosen two things.
            selected:
                composer.drink?.itemId == drink.itemId &&
                composer.drinkFromOwn == fromOwn,
            showOwnStock: fromOwn,
            onTap: () => controller.selectDrink(drink, fromOwn: fromOwn),
          );
        },
      );

  // One flat grid when the user owns nothing — headings over a single section
  // are noise for the majority.
  if (mine.isEmpty) return [grid(drinks, fromOwn: false)];

  return [
    _PickerSectionHeading(
      label: l10n.sectionMyMaterials,
      // Violet, because this section genuinely IS the user's own jar.
      color: BrandColors.accent,
    ),
    const SizedBox(height: Dimens.space2),
    grid(mine, fromOwn: true),
    const SizedBox(height: Dimens.space4),
    _PickerSectionHeading(label: l10n.sectionBuffet, color: BrandColors.muted),
    const SizedBox(height: Dimens.space2),
    // The whole catalogue, including drinks the user also owns.
    grid(drinks, fromOwn: false),
  ];
}

/// An extras chip.
///
/// Carries two independent markings that must not be confused:
///
/// - **Violet** means the extra comes from the user's own jar. Never a generic
///   selected state (rule 3).
/// - **A warning mark** means the chosen preparation already pours this, so
///   ticking it is a second portion. It **annotates, never filters**: an
///   ingredient is part of the recipe and cannot be declined, which is exactly
///   what separates it from `allowedExtraItemIds`.
class _ExtraChip extends StatelessWidget {
  const _ExtraChip({
    required this.extra,
    required this.selected,
    required this.doublesUp,
    required this.onTap,
  });

  final CatalogueItemDto extra;
  final bool selected;
  final bool doublesUp;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = extra.localisedName(
      Localizations.localeOf(context).languageCode,
    );

    return Tooltip(
      message: doublesUp ? l10n.extraAlreadyInPreparation : name,
      child: FilterChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name),
            if (doublesUp) ...[
              const SizedBox(width: Dimens.space1),
              const Icon(
                Icons.add_circle_outline,
                size: 14,
                color: BrandColors.warning,
              ),
            ],
          ],
        ),
        selected: selected,
        onSelected: (_) => onTap(),
        // Violet only when it is genuinely the user's own stock — never as a
        // generic selected state.
        selectedColor: extra.hasOwnStock
            ? BrandColors.accentSurface
            : BrandColors.brandLight,
        checkmarkColor: extra.hasOwnStock
            ? BrandColors.accent
            : BrandColors.brand,
      ),
    );
  }
}

class _PickerSectionHeading extends StatelessWidget {
  const _PickerSectionHeading({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: Dimens.space1,
        height: Dimens.space4,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(Dimens.radiusSm),
        ),
      ),
      const SizedBox(width: Dimens.space2),
      Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
      ),
    ],
  );
}

/// The drinks already added to this order, each removable.
class _AddedLines extends StatelessWidget {
  const _AddedLines({required this.lines, required this.onRemove});

  final List<ComposerLine> lines;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;

    return Container(
      padding: const EdgeInsetsDirectional.all(Dimens.space3),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        border: Border.all(color: BrandColors.brandLight),
        borderRadius: BorderRadius.circular(Dimens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.drinksInOrder(lines.length),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: Dimens.space2),
          for (final (index, line) in lines.indexed)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: Dimens.space1),
              child: Row(
                children: [
                  // Violet only when the drink genuinely resolves to the
                  // user's own jar — a line that falls back to buffet stock
                  // is not "from my jar" however it was requested.
                  Icon(
                    Icons.local_cafe_outlined,
                    size: 18,
                    color: line.resolvesToBuffet
                        ? BrandColors.muted
                        : BrandColors.accent,
                  ),
                  const SizedBox(width: Dimens.space2),
                  Expanded(
                    child: Text(
                      line.drink.localisedName(language),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  // The shortage is shown, never used to block or remove.
                  if (line.ownStockIsShort)
                    const Padding(
                      padding: EdgeInsetsDirectional.only(end: Dimens.space2),
                      child: Icon(
                        Icons.warning_amber_outlined,
                        size: 18,
                        color: BrandColors.warning,
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: l10n.removeDrink,
                    onPressed: () => onRemove(index),
                  ),
                ],
              ),
            ),
        ],
      ),
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
          // Server-composed and rendered as-is per §4 — but ISOLATED: the
          // server builds this from the item's English name and an Arabic
          // parenthetical regardless of Accept-Language, so it is reliably
          // mixed-script ("Coffee (بدون سكر)"). Without the isolate the bidi
          // algorithm reorders the parentheses around the Latin run.
          Text(
            Formatters.isolate(usual.summary),
            style: Theme.of(context).textTheme.bodySmall,
          ),
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
class _ComposerFooter extends ConsumerWidget {
  const _ComposerFooter({
    required this.composer,
    required this.placing,
    required this.onPlaceOrder,
  });

  final ComposerState composer;
  final bool placing;
  final Future<void> Function() onPlaceOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(composerControllerProvider.notifier);

    // The system navigation bar draws OVER this footer. With Android's
    // three-button navigation that is a ~48dp strip sitting on top of the
    // order button — reachable only by the part of it still showing, and on
    // some devices not at all.
    //
    // `paddingOf`, not `viewPaddingOf`: inside a Scaffold the padding a parent
    // has already consumed is subtracted, so this is what is genuinely left to
    // clear. viewPadding reports the raw system value and double-counts.
    //
    // Added to the design padding rather than replacing it, so a gesture-
    // navigation device (inset ~0) keeps the spacing it was designed with and
    // a three-button device gets clearance on top of it.
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      padding: EdgeInsetsDirectional.only(
        start: Dimens.space4,
        end: Dimens.space4,
        top: Dimens.space3,
        bottom: Dimens.space5 + bottomInset,
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
          // Plain text, deliberately — no suggestion list for now.
          //
          // The managed list was only ever a *suggestion*, and free text is the
          // safer half of that: it always sends `locationText`, which the
          // server accepts for any place at all. An unlisted spot could never
          // block an order, and now nothing has to be matched against a list
          // to get there.
          TextField(
            decoration: InputDecoration(
              labelText: l10n.deliveryLocation,
              hintText: l10n.locationHint,
              prefixIcon: const Icon(Icons.place_outlined, size: 18),
            ),
            textInputAction: TextInputAction.next,
            onChanged: (text) => controller.setLocation(locationText: text),
          ),
          const SizedBox(height: Dimens.space3),

          // Free-text notes for the whole order. The controller and the wire
          // contract both carried this from the start; without a field the
          // user had no way to say "no milk" and the staff queue card that
          // renders notes could never have anything to show.
          TextField(
            decoration: InputDecoration(
              labelText: l10n.orderNotes,
              hintText: l10n.orderNotesHint,
              prefixIcon: const Icon(Icons.notes_outlined, size: 18),
            ),
            maxLines: 2,
            textInputAction: TextInputAction.done,
            onChanged: (text) =>
                controller.setNotes(text.trim().isEmpty ? null : text.trim()),
          ),
          const SizedBox(height: Dimens.space3),

          // Shown only when the token carries the privilege. The server reads
          // it from the token's claims, not the body — a client cannot grant
          // itself this, and offering the field to someone without it would
          // produce an unexplained rejection.
          //
          // Naming a guest also lifts the one-buffet-drink cap server-side:
          // an order for three visitors that had to draw two drinks from the
          // employee's own jar would be useless for its one purpose.
          if (ref.watch(canOrderForGuestsProvider)) ...[
            TextField(
              decoration: InputDecoration(
                labelText: l10n.guestOrderLabel,
                hintText: l10n.guestOrderHint,
                helperText: l10n.guestOrderNote,
                prefixIcon: const Icon(Icons.person_outline, size: 18),
              ),
              textInputAction: TextInputAction.done,
              onChanged: controller.setOnBehalfOfName,
            ),
            const SizedBox(height: Dimens.space3),
          ],

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
