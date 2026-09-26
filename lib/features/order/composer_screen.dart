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
import '../../shared/error_text.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/banners.dart';
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
import 'steps/choose_drink_step.dart';
import 'steps/drink_details_step.dart';
import 'steps/review_order_step.dart';

/// Fetches the catalogue in one round trip.
final catalogueProvider = FutureProvider.autoDispose<CatalogueResponse>((
  ref,
) async {
  final locale = ref.watch(localeControllerProvider);
  return ref
      .watch(catalogueRepositoryProvider)
      .fetchCatalogue(
        languageCode: locale.languageCode,
        // Never shown: screens render a network failure through describeError.
        networkErrorFallback: '',
      );
});

/// The three steps of ordering, as the design draws them.
enum ComposerStep { chooseDrink, drinkDetails, review }

/// The order composer: **Choose a drink → Drink Details → Review**, the
/// design's three screens (D2 in `docs/figma-redesign.md`).
///
/// One route hosting three steps rather than three routes, on purpose: the
/// whole flow is one order — one draft, one guest name, one idempotency key —
/// and one screen owning it means none of that can be dropped between routes.
/// The steps navigate among themselves, and system back steps back through
/// them before it leaves the flow.
///
/// Always a **pushed** screen: from Home for an employee, from the queue for a
/// staff member ordering their own drink. Where it starts depends on the
/// [seed]: a favourite opens straight on Review, a drink tapped on Home opens
/// on Drink Details, and everything else — staff, a guest order — starts at
/// Choose a drink.
///
/// In [OrderMode.guest] the guest name is asked for first and required; in
/// [OrderMode.self] there is no guest field at all.
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

  /// The steps the user has walked through, newest last. Empty until the
  /// catalogue has arrived and the seed has decided where to start.
  final List<ComposerStep> _steps = [];

  /// The guest name needs a controller where most fields do not: it can be
  /// cleared from outside (a revoked privilege) and the field has to show it.
  final _guestNameController = TextEditingController();

  /// Whether the guest field has been interacted with yet. The error appears
  /// once they have left it, or once they try to go on without it — not before
  /// they have had a chance to type.
  bool _guestNameTouched = false;

  /// Guards [_applySeed] so a rebuild cannot refill a draft the user has since
  /// changed or deliberately cleared.
  bool _seedApplied = false;

  final _favouriteNameController = TextEditingController();

  // Review's fields keep their text while the user walks back to add another
  // drink — a field rebuilt empty over a location still in the state would
  // show nothing while the order carries something.
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();

  final _searchController = TextEditingController();
  String _query = '';

  /// Focused and scrolled to whenever a way on finds the guest name missing.
  final _guestNameFocus = FocusNode();

  /// What the last favourite replayed could not add, said on screen rather
  /// than dropped: drinks no longer on the menu, and any past the line cap.
  List<OrderLineDto> _favouriteRetired = const [];
  List<OrderLineDto> _favouriteOverCap = const [];
  List<OrderLineDto> _favouriteOverBuffetCap = const [];

  /// The step the favourite notice belongs to. It is cleared as soon as the
  /// user moves on, rather than following them through the flow.
  ComposerStep? _favouriteNoticeStep;

  /// The last placement's failure was uncertain (no response, or a server
  /// error): the order may have been created. A definite refusal is not.
  bool _placeUncertain = false;

  /// On the failure notice, so it can be brought into view: it heads Review's
  /// scroll view, and after a failure from further down (or with the keyboard
  /// up) it would otherwise sit off screen while the button just stops
  /// spinning.
  final _placeErrorKey = GlobalKey();

  /// The last placement's failure, shown on Review until the next attempt —
  /// not a SnackBar that floats over the very button that retries it and is
  /// gone in four seconds.
  String? _placeError;

  /// Whether any placement has failed. Sticky: a request that failed on the
  /// way back may still have created the order, so leaving says so (rule 11).
  bool _placeFailed = false;

  @override
  void dispose() {
    _guestNameFocus.dispose();
    _guestNameController.dispose();
    _favouriteNameController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// The mode this session is really in.
  ///
  /// A guest seed whose privilege has since gone away degrades to a self order
  /// rather than offering a field every order would be rejected for.
  OrderMode _effectiveMode(bool canOrderForGuests) =>
      canOrderForGuests ? widget.seed.mode : OrderMode.self;

  ComposerStep get _step =>
      _steps.isEmpty ? ComposerStep.chooseDrink : _steps.last;

  void _go(ComposerStep step) => setState(() {
    _favouriteNoticeStep = null;
    _steps.add(step);
  });

  /// To Review — back to the one already in the flow when there is one, so the
  /// steps never pile up a second Review and back always unwinds sensibly.
  void _goToReview() {
    final at = _steps.lastIndexOf(ComposerStep.review);
    setState(() {
      if (at == -1) {
        _steps.add(ComposerStep.review);
      } else {
        _steps.removeRange(at + 1, _steps.length);
      }
    });
  }

  /// Review's "remove" on the drink still being composed. The Drink Details
  /// step that edited it goes too: back must never land on a step with no
  /// drink to show.
  void _clearDraft() {
    ref.read(composerControllerProvider.notifier).clearDraft();
    setState(() {
      _steps.removeWhere((s) => s == ComposerStep.drinkDetails);
      if (_steps.isEmpty) _steps.add(ComposerStep.review);
    });
  }

  /// Whether leaving the composer now would throw work away: an order
  /// assembled on Review, drinks already added, or a placement that failed
  /// and may yet have reached the buffet. Backing out of a single drink's
  /// details, opened from Home, costs nothing and is not asked about.
  bool _leavingDiscards(ComposerState composer) =>
      _placeFailed ||
      composer.lines.isNotEmpty ||
      (_step == ComposerStep.review && composer.allLines.isNotEmpty);

  /// One step back; out of the flow from its first step — after asking, when
  /// leaving would discard the order.
  Future<void> _back() async {
    if (_placing) return;
    if (_steps.length > 1) {
      setState(_steps.removeLast);
      return;
    }
    if (_leavingDiscards(ref.read(composerControllerProvider)) &&
        !await _confirmDiscard()) {
      return;
    }
    if (mounted && context.canPop()) context.pop();
  }

  /// Lowers the keyboard and scrolls the failure notice into view.
  void _showPlaceError() {
    FocusScope.of(context).unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notice = _placeErrorKey.currentContext;
      if (!mounted || notice == null || !notice.mounted) return;
      unawaited(
        Scrollable.ensureVisible(
          notice,
          duration: Motion.of(context, Motion.base),
          curve: Motion.easeOut,
        ),
      );
    });
  }

  Future<bool> _confirmDiscard() async {
    final l10n = AppLocalizations.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.discardOrderTitle),
        content: Text(
          !_placeFailed
              ? l10n.discardOrderBody
              // Staff have no My orders to check.
              : ref.read(authControllerProvider).role.startsOnQueue
              ? l10n.discardAfterFailureBodyStaff
              : l10n.discardAfterFailureBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.keepOrdering),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: BrandColors.danger),
            child: Text(l10n.discardOrder),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  /// In guest mode nothing moves on without the guest's name: it is what lifts
  /// the buffet cap. Reveals the error on the field instead of disabling
  /// anything, so the user is told what is missing.
  bool _guestNamePresent() {
    if (!ref.read(composerControllerProvider).guestNameMissing) return true;
    setState(() => _guestNameTouched = true);
    _focusGuestName();
    return false;
  }

  /// Takes the user to the name field. It sits above the menu, often far out
  /// of view from the drink that was tapped, so an error there alone read as
  /// a tap that did nothing.
  void _focusGuestName() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _guestNameFocus.requestFocus();
      final field = _guestNameFocus.context;
      if (field != null && field.mounted) {
        unawaited(
          Scrollable.ensureVisible(
            field,
            duration: Motion.of(context, Motion.base),
            curve: Motion.easeOut,
          ),
        );
      }
    });
  }

  void _selectDrink(CatalogueItemDto drink, {required bool fromOwn}) {
    if (!_guestNamePresent()) return;
    final controller = ref.read(composerControllerProvider.notifier)
      ..selectDrink(drink, fromOwn: fromOwn);
    // selectDrink refuses a new drink when the order is already full; the
    // step does not move on over a choice that was not taken.
    if (ref.read(composerControllerProvider).drink?.itemId != drink.itemId) {
      return;
    }
    controller.setDraftQuantity(1);
    _go(ComposerStep.drinkDetails);
  }

  void _replayFavourite(FavouriteDto favourite, CatalogueResponse data) {
    if (!_guestNamePresent()) return;
    if (_takeFavourite(favourite, data)) _goToReview();
  }

  /// Replays [favourite] and records what could not be added, for the banner.
  /// Returns whether anything was added.
  bool _takeFavourite(FavouriteDto favourite, CatalogueResponse data) {
    final result = ref
        .read(composerControllerProvider.notifier)
        .applyFavourite(favourite, data.drinks);
    final skipped =
        result.retired.length +
        result.overCap.length +
        result.overBuffetCap.length;
    final applied = skipped < favourite.lines.length;
    setState(() {
      _favouriteRetired = result.retired;
      _favouriteOverCap = result.overCap;
      _favouriteOverBuffetCap = result.overBuffetCap;
      _favouriteNoticeStep = skipped == 0
          ? null
          : (applied ? ComposerStep.review : ComposerStep.chooseDrink);
    });
    return applied;
  }

  /// Commits the drink being composed and goes back to choose the next one.
  /// When the cap refuses the commit, the user stays where the banner says
  /// why.
  void _addAnother() {
    final controller = ref.read(composerControllerProvider.notifier);
    if (ref.read(composerControllerProvider).drink != null) {
      controller.addLine();
      if (ref.read(composerControllerProvider).drink != null) return;
    }
    _query = '';
    _searchController.clear();
    // On top of Review, not in place of it: back returns to the order so far
    // rather than out of the composer with every drink in it.
    setState(() {
      _favouriteNoticeStep = null;
      _steps
        ..removeWhere((s) => s == ComposerStep.drinkDetails)
        ..add(ComposerStep.chooseDrink);
    });
  }

  Future<void> _placeOrder() async {
    final l10n = AppLocalizations.of(context);
    final locale = ref.read(localeControllerProvider);
    final composer = ref.read(composerControllerProvider);

    // A guest order without a name goes back to the field that asks for it,
    // with the error showing, rather than leaving a dead button.
    if (composer.guestNameMissing) {
      // On top of Review, so back returns to the order once the name is in.
      setState(() {
        _guestNameTouched = true;
        _steps.add(ComposerStep.chooseDrink);
      });
      _focusGuestName();
      return;
    }
    if (!composer.canPlaceOrder) return;

    setState(() {
      _placing = true;
      _placeError = null;
    });

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
      // `favouriteId` null is NOT an error: saving is best-effort.
      if (result.favouriteId != null) ref.invalidate(favouritesProvider);
      ref.read(composerControllerProvider.notifier).resetAfterConfirmedOrder();
      // The new order belongs in the outstanding list the moment it exists.
      ref.invalidate(myOrdersProvider);

      // A staff member's own order is already made and handed over — they
      // were standing at the machine. The confirmation goes back to the queue
      // with them instead of opening a status screen that will never move.
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

      // pushReplacement, not go: this swaps the composer for the status
      // screen and leaves Home underneath, so back lands where the
      // outstanding card is already showing this very order.
      context.pushReplacement(Routes.orderStatusFor(result.orderId));
    } on ApiException catch (error) {
      if (!mounted) return;
      // The composer keeps its contents and its idempotency key, so the retry
      // is the *same* order. Nothing is queued for later (§9).
      // Only an uncertain failure — nothing came back, or the server itself
      // failed — may have created the order. A 4xx is a definite refusal and
      // its message says why; retrying unchanged would fail the same way.
      final uncertain =
          error.isNetworkFailure ||
          error.statusCode == null ||
          error.statusCode! >= 500;
      setState(() {
        _placeError = error.message;
        _placeUncertain = uncertain;
        if (uncertain) _placeFailed = true;
      });
      _showPlaceError();
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
    // valueOrNull, never `when`: ordering must not wait on this list. A
    // failure leaves the strip absent, the same state as having saved none.
    final favourites = ref.watch(favouritesProvider).valueOrNull;

    // Where the flow starts, decided once from the seed, before anything that
    // depends on the step (the title) is built. Set during build without
    // setState: it is the first frame's own state.
    final loadedDrinks = catalogue.valueOrNull?.drinks;
    if (_steps.isEmpty && loadedDrinks != null && loadedDrinks.isNotEmpty) {
      _steps.add(_firstStep(catalogue.requireValue));
    }

    final title = switch (_step) {
      ComposerStep.chooseDrink =>
        mode == OrderMode.guest ? l10n.guestOrderTitle : l10n.orderTitle,
      ComposerStep.drinkDetails =>
        composer.drink?.localisedName(
              Localizations.localeOf(context).languageCode,
            ) ??
            l10n.orderTitle,
      ComposerStep.review => l10n.reviewOrderTitle,
    };

    return PopScope(
      // Back steps back through the flow first; it leaves only from the step
      // the flow started on, never mid-placement, and only after asking when
      // leaving would discard the order.
      canPop: _steps.length <= 1 && !_placing && !_leavingDiscards(composer),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_back());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          leading: _steps.length > 1 ? BackButton(onPressed: _back) : null,
        ),
        body: catalogue.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => EmptyState(
            icon: Icons.cloud_off_outlined,
            title: l10n.genericError,
            body: describeError(error, l10n),
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
            // catalogue. Applied after the frame: mutating a provider
            // mid-build would be a write during a read.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              ref.read(composerControllerProvider.notifier)
                ..applyLimits(
                  maxLines: data.maxLines,
                  maxBuffetDrinks: data.maxBuffetDrinks,
                )
                // The cap rule needs both the name and the privilege.
                ..setCanOrderForGuests(ref.read(canOrderForGuestsProvider))
                // AFTER the privilege: setCanOrderForGuests(false) nulls any
                // guest name, and the other order would leave guest mode with
                // the name wiped.
                ..setMode(mode);
              _applySeed(data);
            });

            // The field is the only visible part of the guest name, so it
            // must agree with the state it stands for.
            _syncGuestNameField(composer.onBehalfOfName);

            final header = _notices(l10n, composer);
            final step = switch (_step) {
              ComposerStep.chooseDrink => ChooseDrinkStep(
                catalogue: data,
                composer: composer,
                mode: mode,
                guestNameController: _guestNameController,
                guestNameFocusNode: _guestNameFocus,
                guestNameError: _guestNameTouched && composer.guestNameMissing,
                onGuestNameChanged: ref
                    .read(composerControllerProvider.notifier)
                    .setOnBehalfOfName,
                onGuestNameBlurred: () {
                  if (!_guestNameTouched) {
                    setState(() => _guestNameTouched = true);
                  }
                },
                favourites: favourites?.favourites ?? const [],
                onReplayFavourite: (f) => _replayFavourite(f, data),
                onDeleteFavourite: (f) =>
                    unawaited(confirmDeleteFavourite(context, ref, f)),
                header: _step == _favouriteNoticeStep ? header : null,
                onShowAllFavourites: () async {
                  final picked = await context.push<FavouriteDto>(
                    Routes.favouritesList,
                  );
                  if (picked != null && mounted) {
                    _replayFavourite(picked, data);
                  }
                },
                searchController: _searchController,
                query: _query,
                onQueryChanged: (value) => setState(() => _query = value),
                onSelectDrink: _selectDrink,
                // Guest-checked like every other way off this step.
                onReview: () {
                  if (_guestNamePresent()) _goToReview();
                },
              ),
              ComposerStep.drinkDetails => DrinkDetailsStep(
                catalogue: data,
                composer: composer,
                onContinue: _goToReview,
              ),
              ComposerStep.review => ReviewOrderStep(
                catalogue: data,
                composer: composer,
                mode: mode,
                placing: _placing,
                favourites: favourites?.favourites ?? const [],
                // Unknown while loading, and read as "not full" until it
                // arrives: a control disabled on a request that has not come
                // back would be a dead end with nothing to explain it.
                favouritesFull: favourites?.canSaveAnother == false,
                maxFavourites: favourites?.maxFavourites ?? 20,
                locationController: _locationController,
                notesController: _notesController,
                favouriteNameController: _favouriteNameController,
                onEditDraft: () => _go(ComposerStep.drinkDetails),
                onClearDraft: _clearDraft,
                onChooseDrink: () => _go(ComposerStep.chooseDrink),
                onAddAnother: _addAnother,
                onPlaceOrder: _placeOrder,
                header: header,
              ),
            };

            return step;
          },
        ),
      ),
    );
  }

  /// The composer's own notices for the current step: a favourite that could
  /// not be replayed in full (on the step it was raised on), and on Review a
  /// placement that failed. Null when there is nothing to say.
  Widget? _notices(AppLocalizations l10n, ComposerState composer) {
    final notices = [
      if (_step == _favouriteNoticeStep)
        InlineBanner(
          tone: BannerTone.warning,
          title: l10n.favouriteNotAllAddedTitle,
          body: [
            if (_favouriteRetired.isNotEmpty)
              l10n.favouriteNotOnMenu(
                _favouriteRetired
                    // The only name the saved line carries; isolated, since
                    // it may sit inside English text.
                    .map((l) => Formatters.isolate(l.drinkNameAr))
                    .toSet()
                    .join(l10n.listSeparator),
              ),
            if (_favouriteOverCap.isNotEmpty)
              l10n.favouriteOverCap(composer.maxLines),
            if (_favouriteOverBuffetCap.isNotEmpty)
              l10n.favouriteOverBuffetCap(composer.maxBuffetDrinks),
          ].join('\n'),
        ),
      if (_step == ComposerStep.review && _placeError != null)
        // Announced as it appears: a danger banner is a live region.
        InlineBanner(
          key: _placeErrorKey,
          tone: BannerTone.danger,
          title: _placeUncertain
              ? l10n.placeFailedTitle
              : l10n.placeRejectedTitle,
          body: _placeUncertain
              ? '${_placeError!}\n${l10n.placeFailedRetry}'
              : _placeError,
        ),
    ];
    if (notices.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, notice) in notices.indexed) ...[
          if (i > 0) const SizedBox(height: Dimens.space3),
          notice,
        ],
      ],
    );
  }

  /// Where the flow opens, from how it was opened.
  ComposerStep _firstStep(CatalogueResponse data) {
    if (widget.seed.favourite case final FavouriteDto favourite) {
      // Review when any of its drinks is still on the menu; otherwise Choose,
      // where the banner says which were not.
      final known = favourite.lines.any(
        (l) => data.drinks.any((d) => d.itemId == l.drinkItemId),
      );
      return known ? ComposerStep.review : ComposerStep.chooseDrink;
    }
    if (widget.seed.drinkItemId case final int id
        when data.drinks.any((d) => d.itemId == id)) {
      return ComposerStep.drinkDetails;
    }
    return ComposerStep.chooseDrink;
  }

  /// Keeps the guest-name field showing whatever the state actually holds.
  ///
  /// Only ever writes when the two have genuinely diverged, so it cannot fight
  /// the user mid-keystroke or move their cursor while they type. Compared on
  /// the TRIMMED text, because the state is trimmed and the field is not.
  void _syncGuestNameField(String? name) {
    final text = name ?? '';
    if (_guestNameController.text.trim() == text) return;

    _guestNameController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    // A field cleared from underneath the user has not been "touched" by them.
    if (text.isEmpty) _guestNameTouched = false;
  }

  /// Fills the draft from the seed this session was opened with, once.
  ///
  /// Guarded rather than idempotent-by-luck: this runs from a post-frame
  /// callback that fires on every rebuild, and refilling a draft the user has
  /// since edited or cleared would silently undo their work.
  void _applySeed(CatalogueResponse data) {
    if (_seedApplied) return;
    final controller = ref.read(composerControllerProvider.notifier);

    final favourite = widget.seed.favourite;
    if (favourite != null) {
      _seedApplied = true;
      _takeFavourite(favourite, data);
      return;
    }

    // A drink tapped on Home's menu opens already chosen, from the jar its row
    // stood for. One no longer in the catalogue is left unchosen.
    final drinkId = widget.seed.drinkItemId;
    if (drinkId != null) {
      _seedApplied = true;
      final drink = data.drinks.where((d) => d.itemId == drinkId).firstOrNull;
      if (drink != null) {
        controller.selectDrink(drink, fromOwn: widget.seed.drinkFromOwn);
      }
    }
  }
}
