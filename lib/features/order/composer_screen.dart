import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/locale_controller.dart';
import '../../app/routes.dart';
import '../../data/api/api_exception.dart';
import '../../data/models/catalogue_models.dart';
import '../../data/models/favourite_models.dart';
import '../../data/repositories/catalogue_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/section_header.dart';
import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';
import '../../theme/motion.dart';
import '../auth/auth_controller.dart';
import 'composer_controller.dart';
import 'favourites_controller.dart';
import 'favourites_screen.dart';
import 'my_orders_screen.dart';
import 'order_mode.dart';
import 'self_order_outcome.dart';
import 'widgets/drink_tile.dart';
import 'widgets/favourites_strip.dart';
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
///
/// Always a **pushed** screen: from the home hub for an employee, from the queue
/// for a staff member ordering their own drink. It used to be the employee
/// landing screen, which is why so much that had nothing to do with composing a
/// drink had accumulated on it.
///
/// The [seed] says how it was opened. In [OrderMode.guest] the guest name is
/// asked for first and required; in [OrderMode.self] there is no guest field at
/// all — not an empty one. Which of the two the user is doing is settled before
/// they choose a drink, rather than inferred afterwards from whether they
/// happened to type into an optional box.
class ComposerScreen extends ConsumerStatefulWidget {
  const ComposerScreen({this.seed = const ComposerSeed(), super.key});

  /// How this session was opened. Defaults to an ordinary self order, which is
  /// what the staff "order for myself" push and any deep link both mean.
  final ComposerSeed seed;

  @override
  ConsumerState<ComposerScreen> createState() => _ComposerScreenState();
}

class _ComposerScreenState extends ConsumerState<ComposerScreen> {
  bool _placing = false;

  /// The guest name needs a controller where the other fields do not: it can be
  /// cleared from outside (a revoked privilege) and the screen has to be able
  /// to show that.
  final _guestNameController = TextEditingController();

  /// Whether the guest field has been interacted with yet.
  ///
  /// The field is required, but a required field that turns red before the user
  /// has had a chance to type is scolding them for not having done something
  /// yet. The error appears once they have left it, or once they try to order.
  bool _guestNameTouched = false;

  /// Guards [_applySeedFavourite] so a rebuild cannot refill a draft the user
  /// has since changed or deliberately cleared.
  bool _seedFavouriteApplied = false;

  /// The optional name for a favourite saved with this order.
  ///
  /// A controller rather than a plain `onChanged`, for the same reason as the
  /// guest name: it is cleared from outside — switching the toggle off drops
  /// the name — and the field has to be able to show that.
  final _favouriteNameController = TextEditingController();

  @override
  void dispose() {
    _guestNameController.dispose();
    _favouriteNameController.dispose();
    super.dispose();
  }

  /// The mode this session is really in.
  ///
  /// A guest seed whose privilege has since gone away degrades to a self order
  /// rather than offering a field every order would be rejected for. Computed
  /// in `build` rather than stored, so there is no frame in which the wrong
  /// mode is on screen.
  OrderMode _effectiveMode(bool canOrderForGuests) =>
      canOrderForGuests ? widget.seed.mode : OrderMode.self;

  Future<void> _placeOrder() async {
    final l10n = AppLocalizations.of(context);
    final locale = ref.read(localeControllerProvider);
    final composer = ref.read(composerControllerProvider);

    // Reveal the reason before refusing. Without this the button is simply
    // dead for a guest order with no name, which is the dead end that
    // disabling a control always risks.
    if (composer.guestNameMissing) {
      setState(() => _guestNameTouched = true);
      return;
    }
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
      // The list has a new row when this order asked to save one. Invalidated
      // before the reset so the strip is already correct on the way back.
      //
      // `favouriteId` null is NOT an error — saving is best-effort and the
      // drink is already made — so nothing is said about it either way, and
      // the refetch is harmless when nothing was saved.
      if (result.favouriteId != null) ref.invalidate(favouritesProvider);
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

      // pushReplacement, not go: `go` is a location change that clears the
      // stack, which would leave the status screen with nothing beneath it and
      // send back to a composer the user has finished with. This swaps the
      // composer for the status screen and leaves the hub underneath, so back
      // lands on the hub — where the outstanding card is already showing this
      // very order.
      context.pushReplacement(Routes.orderStatusFor(result.orderId));
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
    final mode = _effectiveMode(ref.watch(canOrderForGuestsProvider));
    // valueOrNull, never `when`: the composer must not wait on this list to
    // draw a drink grid. A failure here leaves the strip absent, which is the
    // same state as having saved none — and ordering still works.
    final favourites = ref.watch(favouritesProvider).valueOrNull;

    // No ExitConfirmation and no action cluster: this is a pushed screen now,
    // with a back arrow and somewhere to go back to. Pushing settings on top of
    // a half-composed order was never a good offer anyway.
    return Scaffold(
      appBar: AppBar(
        title: Text(
          mode == OrderMode.guest ? l10n.guestOrderTitle : l10n.orderTitle,
        ),
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
              ..setCanOrderForGuests(ref.read(canOrderForGuestsProvider))
              // Ordered AFTER the privilege: setCanOrderForGuests(false)
              // nulls any guest name, and doing it the other way round would
              // leave the session in guest mode with the name wiped.
              ..setMode(mode);

            _applySeedFavourite(data);
          });

          // The field is the only part of the guest name the user can see, so
          // it must agree with the state it stands for. The state can be
          // cleared from underneath it — a confirmed order resets it, and a
          // revoked privilege nulls it — and a field still showing a name the
          // order will not carry is worse than an empty one: the button goes
          // dead with an error asking for a name that is visibly already
          // there.
          _syncGuestNameField(composer.onBehalfOfName);

          return _ComposerBody(
            catalogue: data,
            composer: composer,
            mode: mode,
            placing: _placing,
            favourites: favourites?.favourites ?? const [],
            // Unknown while the list is loading, and read as "not full" until
            // it arrives: a save control disabled because a request has not
            // come back yet would be a dead end with nothing to explain it.
            favouritesFull: favourites?.canSaveAnother == false,
            maxFavourites: favourites?.maxFavourites ?? 20,
            favouriteNameController: _favouriteNameController,
            onDeleteFavourite: (favourite) =>
                unawaited(confirmDeleteFavourite(context, ref, favourite)),
            guestNameController: _guestNameController,
            guestNameError: _guestNameTouched && composer.guestNameMissing,
            onGuestNameBlurred: () {
              if (!_guestNameTouched) {
                setState(() => _guestNameTouched = true);
              }
            },
            onPlaceOrder: _placeOrder,
          );
        },
      ),
    );
  }

  /// Keeps the guest-name field showing whatever the state actually holds.
  ///
  /// Only ever writes when the two have genuinely diverged, so it cannot fight
  /// the user mid-keystroke or move their cursor while they type.
  void _syncGuestNameField(String? name) {
    final text = name ?? '';

    // Compared on the TRIMMED text, because the state is trimmed and the field
    // is not. Comparing raw would make every trailing space a divergence: the
    // user types "أحمد " on the way to "أحمد محمد", the state trims it back to
    // "أحمد", and the sync would snatch the space away as they typed it.
    if (_guestNameController.text.trim() == text) return;

    _guestNameController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    // A field cleared from underneath the user has not been "touched" by them,
    // so it must not carry a validation error into its next use.
    if (text.isEmpty) _guestNameTouched = false;
  }

  /// Fills the draft from the favourite this session was opened with, once.
  ///
  /// Guarded rather than idempotent-by-luck: this runs from a post-frame
  /// callback that fires on every rebuild, and refilling a draft the user has
  /// since edited or cleared would silently undo their work.
  void _applySeedFavourite(CatalogueResponse data) {
    final favourite = widget.seed.favourite;
    if (favourite == null || _seedFavouriteApplied) return;

    _seedFavouriteApplied = true;
    ref
        .read(composerControllerProvider.notifier)
        .applyFavourite(favourite, data.drinks);
  }
}

class _ComposerBody extends ConsumerWidget {
  const _ComposerBody({
    required this.catalogue,
    required this.composer,
    required this.mode,
    required this.placing,
    required this.guestNameController,
    required this.guestNameError,
    required this.onGuestNameBlurred,
    required this.onPlaceOrder,
    required this.favourites,
    required this.favouritesFull,
    required this.maxFavourites,
    required this.favouriteNameController,
    required this.onDeleteFavourite,
  });

  final CatalogueResponse catalogue;
  final ComposerState composer;
  final OrderMode mode;
  final bool placing;
  final TextEditingController guestNameController;
  final bool guestNameError;
  final VoidCallback onGuestNameBlurred;
  final Future<void> Function() onPlaceOrder;

  /// The caller's saved orders, or empty while the list is still loading. An
  /// empty strip and an unloaded one are the same shape, so the composer never
  /// waits on this to draw the drink grid.
  final List<FavouriteDto> favourites;

  /// Whether the per-user cap is reached, from `maxFavourites`.
  final bool favouritesFull;
  final int maxFavourites;

  final TextEditingController favouriteNameController;
  final void Function(FavouriteDto favourite) onDeleteFavourite;

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
              // Who this is for comes FIRST, and only in guest mode. It is the
              // one thing that makes this order different from an ordinary
              // one, it changes which rules apply, and it is required — so it
              // is asked before the drink rather than discovered in a footer
              // after the order has been composed.
              if (mode == OrderMode.guest) ...[
                InlineBanner(
                  tone: BannerTone.info,
                  title: l10n.guestOrderTitle,
                  // States the cap-lifting up front, where it explains why this
                  // order may take more than one buffet drink.
                  body: l10n.guestOrderNote,
                ),
                const SizedBox(height: Dimens.space3),
                Focus(
                  onFocusChange: (hasFocus) {
                    if (!hasFocus) onGuestNameBlurred();
                  },
                  child: TextField(
                    controller: guestNameController,
                    decoration: InputDecoration(
                      labelText: l10n.guestOrderLabel,
                      hintText: l10n.guestOrderHint,
                      prefixIcon: const Icon(Icons.person_outline, size: 18),
                      errorText: guestNameError ? l10n.guestNameRequired : null,
                    ),
                    textInputAction: TextInputAction.next,
                    onChanged: controller.setOnBehalfOfName,
                  ),
                ),
                const SizedBox(height: Dimens.space4),
              ],

              // The strip stays HERE as well as on the hub, and not as a
              // duplicate: staff reach this screen by pushing it from the
              // queue and never see the hub at all, so having it only there
              // would take the one-tap repeat away from them entirely. It is
              // one tap from the ordering screen for both roles (§12).
              //
              // Hidden once anything has been composed — replacing a drink
              // the user has already chosen is not a "repeat".
              if (favourites.isNotEmpty && composer.allLines.isEmpty) ...[
                FavouritesStrip(
                  favourites: favourites,
                  // Already on the composer, so this fills the draft in place
                  // rather than pushing a second one.
                  onReplay: (favourite) =>
                      controller.applyFavourite(favourite, catalogue.drinks),
                  onDelete: onDeleteFavourite,
                  availableItemIds: {
                    for (final d in catalogue.drinks) d.itemId,
                  },
                  onShowAll: () => context.push(Routes.favourites),
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
              //
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

              // Save this order for next time — in the same round trip, since
              // POST /orders carries it. Offered only once there is something
              // to save, and never in guest mode: a visitor's order is not a
              // habit of the user's, and the server drops `onBehalfOfName`
              // from a favourite anyway.
              if (composer.allLines.isNotEmpty && mode == OrderMode.self) ...[
                const SizedBox(height: Dimens.space5),
                _SaveFavouriteControl(
                  composer: composer,
                  full: favouritesFull,
                  maxFavourites: maxFavourites,
                  nameController: favouriteNameController,
                  // Replaying a favourite and then toggling "save" would write
                  // a second identical copy — the server does not dedupe — so
                  // the control says "already saved" instead of offering it.
                  alreadySaved: favourites.any(
                    (f) => f.orders([
                      for (final line in composer.allLines) line.toDto(),
                    ]),
                  ),
                ),
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

/// The "save this for next time" toggle, with its optional name.
///
/// **The cap is the one limit this app does disable a control on.** It is
/// structural — the server refuses past it — not a stock reading, and the
/// disabled switch is never a dead end: the banner beside it says what the
/// limit is and that deleting one makes room.
class _SaveFavouriteControl extends ConsumerWidget {
  const _SaveFavouriteControl({
    required this.composer,
    required this.full,
    required this.maxFavourites,
    required this.nameController,
    this.alreadySaved = false,
  });

  final ComposerState composer;
  final bool full;
  final int maxFavourites;
  final TextEditingController nameController;

  /// Whether what is on screen is already in the user's favourites.
  final bool alreadySaved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(composerControllerProvider.notifier);

    // The field is the only visible part of the name, so it must agree with
    // the state: switching the toggle off drops the name, and a field still
    // showing one would name the next saved favourite after this order.
    final name = composer.favouriteName ?? '';
    if (nameController.text.trim() != name) {
      nameController.value = TextEditingValue(
        text: name,
        selection: TextSelection.collapsed(offset: name.length),
      );
    }

    // Said plainly and the control withdrawn, rather than a toggle that would
    // silently write a duplicate. Matches the order-history row exactly.
    if (alreadySaved) {
      return Row(
        children: [
          const Icon(Icons.star, size: 16, color: BrandColors.brand),
          const SizedBox(width: Dimens.space2),
          Flexible(
            child: Text(
              l10n.favouriteAlreadySaved,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: BrandColors.muted),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (full) ...[
          InlineBanner(
            tone: BannerTone.warning,
            title: l10n.favouritesFullTitle,
            body: l10n.favouritesFullBody(maxFavourites),
          ),
          const SizedBox(height: Dimens.space3),
        ],
        SwitchListTile.adaptive(
          value: composer.saveAsFavourite,
          // Disabled only at the cap, and only with the banner above saying
          // so. Never on a stock reading.
          onChanged: full ? null : controller.setSaveAsFavourite,
          title: Text(l10n.saveAsFavourite),
          contentPadding: EdgeInsetsDirectional.zero,
          activeThumbColor: BrandColors.brand,
        ),
        // The name is genuinely optional — blank means "name it after the
        // drinks", which the server does including the preparation — so the
        // field appears only once saving is asked for, rather than sitting
        // there as a question nobody has to answer.
        if (composer.saveAsFavourite) ...[
          const SizedBox(height: Dimens.space2),
          TextField(
            controller: nameController,
            decoration: InputDecoration(
              labelText: l10n.favouriteNameLabel,
              hintText: l10n.favouriteNameHint,
              prefixIcon: const Icon(Icons.star_outline, size: 18),
            ),
            textInputAction: TextInputAction.done,
            onChanged: controller.setFavouriteName,
          ),
        ],
      ],
    );
  }
}

/// How tall a drink tile has to be for its text to fit at the current scale.
///
/// The image and the paddings are fixed; the name (up to two lines) and the
/// servings label are not, and both grow with the platform text scale. Measured
/// rather than guessed, so a large-text user gets a taller tile instead of a
/// clipped name.
double _drinkTileHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  final text = Theme.of(context).textTheme;

  final nameLine =
      scaler.scale(text.labelSmall?.fontSize ?? 12) * Dimens.lineHeight;

  // padding + image + gap + two lines of name + gap + one line of servings.
  return Dimens.space3 * 2 +
      40 +
      Dimens.space2 +
      nameLine * 2 +
      Dimens.space1 +
      nameLine;
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
        // maxCrossAxisExtent, not a fixed count with a fixed ratio: the ratio
        // dictated the tile HEIGHT, so a two-line drink name overflowed it —
        // on a 320dp phone at the DEFAULT text scale, and worse at the
        // accessibility scales. An extent keeps three columns on an ordinary
        // phone and adds more on a tablet.
        //
        // The height scales with the text rather than being fixed, because a
        // fixed one merely converts the overflow into a silent clip: at 2x the
        // name had room for one line of the two it is allowed, so a drink
        // whose name needs both became unreadable with nothing to show for it.
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 128,
          mainAxisSpacing: Dimens.space3,
          crossAxisSpacing: Dimens.space3,
          mainAxisExtent: _drinkTileHeight(context),
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
    SectionHeader(
      label: l10n.sectionMyMaterials,
      // Violet, because this section genuinely IS the user's own jar.
      accent: BrandColors.accent,
    ),
    const SizedBox(height: Dimens.space2),
    grid(mine, fromOwn: true),
    const SizedBox(height: Dimens.space4),
    SectionHeader(label: l10n.sectionBuffet, accent: BrandColors.muted),
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

/// The drinks already added to this order, each removable.
class _AddedLines extends StatelessWidget {
  const _AddedLines({required this.lines, required this.onRemove});

  final List<ComposerLine> lines;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;

    return AppCard(
      padding: const EdgeInsetsDirectional.all(Dimens.space3),
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

          // The guest name is NOT here. It moved to the top of the screen and
          // only exists in guest mode — asking "who is this for?" underneath a
          // composed order was asking it far too late, and asking it of
          // everyone made the two kinds of order look identical.
          FilledButton(
            // Disabled only when there is genuinely nothing to order.
            // NEVER disabled on a stock reading — see ownStockIsShort, which
            // drives a warning and nothing else.
            //
            // A missing guest name deliberately does NOT disable it: the
            // handler reveals the error on the field instead, so the user is
            // told what is wrong rather than left with a dead button.
            onPressed: composer.allLines.isNotEmpty && !placing
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
