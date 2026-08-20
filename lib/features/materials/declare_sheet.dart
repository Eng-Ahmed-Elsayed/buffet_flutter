import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/locale_controller.dart';
import '../../data/api/api_exception.dart';
import '../../data/models/catalogue_models.dart';
import '../../data/models/material_models.dart';
import '../../data/repositories/materials_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/banners.dart';
import '../../theme/dimens.dart';
import '../order/composer_screen.dart';
import 'my_materials_screen.dart';

/// One item a user may declare, with the balance they already hold of it.
///
/// The list comes from the **catalogue**, not from `/materials/mine`. Sourcing
/// it from the balances would let a user top up only what they already own —
/// a material they have never brought in before could never be declared at
/// all, which is the common case this sheet exists for. The server agrees:
/// `POST /materials/declare` returns `202` for any catalogue item, owned or
/// not.
class DeclarableItem {
  const DeclarableItem({required this.item, this.balance});

  final CatalogueItemDto item;

  /// The caller's confirmed balance, when they already hold some. Null for an
  /// item they have never declared — which is not an error, just the first
  /// time.
  final MyMaterialDto? balance;

  int get itemId => item.itemId;
  String get unit => item.unit;

  /// Falls back to Arabic when the admin left `nameEn` empty, which is the
  /// common case on the live server.
  String localisedName(String languageCode) => item.localisedName(languageCode);
}

/// Every catalogue item, joined to the caller's balances.
///
/// Drinks, sugars and extras all appear: a user brings in their own milk or
/// sugar as readily as their own coffee, and the API draws no distinction.
/// Watches [catalogueProvider] as a future rather than reading it: the sheet
/// can be opened without ever visiting the composer, in which case the
/// catalogue has never been fetched and reading it would sit at null forever.
final declarableItemsProvider =
    FutureProvider.autoDispose<List<DeclarableItem>>((ref) async {
      final catalogue = await ref.watch(catalogueProvider.future);
      final balances = {
        for (final m in await ref.watch(myMaterialsProvider.future))
          m.itemId: m,
      };

      return [
        for (final item in [
          ...catalogue.drinks,
          ...catalogue.sugars,
          ...catalogue.extras,
        ])
          DeclarableItem(item: item, balance: balances[item.itemId]),
      ];
    });

/// Declares materials handed to staff.
///
/// `POST /materials/declare` returns **`202 Accepted`, not `201`** — and the
/// wording here reflects that. A declaration creates nothing until an admin
/// confirms receipt, so this says "awaiting confirmation", never "added". A
/// user who believes they have stock they do not have will be surprised by the
/// first order that draws on it (§7.5).
class DeclareSheet extends ConsumerStatefulWidget {
  const DeclareSheet({super.key});

  @override
  ConsumerState<DeclareSheet> createState() => _DeclareSheetState();
}

class _DeclareSheetState extends ConsumerState<DeclareSheet> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _noteController = TextEditingController();

  DeclarableItem? _selectedItem;

  /// True once «الصنف غير مدرج» is chosen. The picker holds no value in this
  /// mode — there is no catalogue row to point at yet.
  bool _newItem = false;

  final _nameController = TextEditingController();
  final _unitController = TextEditingController();
  final _perPackageController = TextEditingController();
  final _perServingController = TextEditingController();
  String _category = 'Drink';

  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _quantityController.dispose();
    _noteController.dispose();
    _nameController.dispose();
    _unitController.dispose();
    _perPackageController.dispose();
    _perServingController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_newItem && _selectedItem == null) return;

    final l10n = AppLocalizations.of(context);
    final locale = ref.read(localeControllerProvider);
    final quantity = num.tryParse(_quantityController.text.trim());
    if (quantity == null) return;

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final repository = ref.read(materialsRepositoryProvider);
      final note = _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim();

      if (_newItem) {
        // A different endpoint, and a different meaning for `quantity`: here
        // it is PACKAGES, and the server multiplies by unitsPerPackage. The
        // field is labelled accordingly — sending grams would silently declare
        // a fraction of what the user brought.
        final unit = _unitController.text.trim();
        await repository.declareNew(
          request: DeclareNewMaterialRequest(
            nameAr: _nameController.text.trim(),
            category: _category,
            unit: unit.isEmpty ? null : unit,
            unitsPerPackage:
                num.tryParse(_perPackageController.text.trim()) ?? 0,
            unitsPerServing:
                num.tryParse(_perServingController.text.trim()) ?? 0,
            quantity: quantity,
            note: note,
          ),
          languageCode: locale.languageCode,
          networkErrorFallback: l10n.networkError,
        );
      } else {
        await repository.declare(
          request: DeclareMaterialRequest(
            itemId: _selectedItem!.itemId,
            quantity: quantity,
            note: note,
          ),
          languageCode: locale.languageCode,
          networkErrorFallback: l10n.networkError,
        );
      }

      if (!mounted) return;
      ref.invalidate(myMaterialsProvider);
      Navigator.of(context).pop();

      // "Sent — awaiting confirmation", never "added". The 202 is the whole
      // reason this wording matters.
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.declarationSentBody)));
    } on ApiException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(localeControllerProvider);
    final itemsAsync = ref.watch(declarableItemsProvider);
    final items = itemsAsync.valueOrNull ?? const <DeclarableItem>[];

    return Padding(
      // viewInsets is the KEYBOARD; padding is what is left of the system
      // navigation bar after ancestors took their share. Two different things,
      // and the sheet needs clearance from both — the submit button sits at
      // the bottom edge, where three-button navigation draws over it.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: Dimens.space4,
            end: Dimens.space4,
            top: Dimens.space3,
            bottom: Dimens.space5 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: Dimens.handleWidth,
                    height: Dimens.handleHeight,
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(Dimens.handleRadius),
                    ),
                  ),
                ),
                const SizedBox(height: Dimens.space5),

                Text(
                  l10n.declareMaterials,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  l10n.declareBody,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: Dimens.space5),

                if (_errorMessage != null) ...[
                  InlineBanner(tone: BannerTone.danger, title: _errorMessage!),
                  const SizedBox(height: Dimens.space4),
                ],

                // A failed catalogue fetch left the dropdown permanently
                // disabled under a "loading" hint with no way to retry —
                // indistinguishable from a server with no items.
                if (itemsAsync.hasError) ...[
                  InlineBanner(
                    tone: BannerTone.danger,
                    title: itemsAsync.error is ApiException
                        ? (itemsAsync.error! as ApiException).message
                        : l10n.genericError,
                    trailing: TextButton(
                      onPressed: () => ref.invalidate(declarableItemsProvider),
                      child: Text(l10n.retry),
                    ),
                  ),
                  const SizedBox(height: Dimens.space4),
                ],

                // Every catalogue item, not only the ones already owned —
                // otherwise a first-time declaration is impossible to make.
                // Nullable value, with null meaning «الصنف غير مدرج» — the
                // last entry, so the common case (topping up something known)
                // stays the default. Mirrors the web's `value="0"` sentinel
                // without borrowing an id that means "rejected" on the wire.
                DropdownButtonFormField<DeclarableItem?>(
                  initialValue: _newItem ? null : _selectedItem,
                  decoration: InputDecoration(
                    labelText: l10n.item,
                    helperText: switch (itemsAsync) {
                      AsyncValue(hasError: true) => null,
                      AsyncValue(isLoading: true) => l10n.loading,
                      _ when items.isEmpty => l10n.emptyCatalogueTitle,
                      _ => null,
                    },
                  ),
                  isExpanded: true,
                  items: [
                    for (final item in items)
                      DropdownMenuItem(
                        value: item,
                        child: _ItemLabel(item: item, locale: locale),
                      ),
                    DropdownMenuItem(
                      value: null,
                      child: Text(l10n.itemNotListed),
                    ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() {
                          _selectedItem = value;
                          _newItem = value == null;
                        }),
                  // Null is a legitimate choice here, so the picker cannot
                  // validate on it — the new-item fields carry their own.
                  validator: (value) => value == null && !_newItem ? '' : null,
                ),

                // Revealed only for «الصنف غير مدرج». Built rather than merely
                // hidden, so a stale value from a previous mode can never be
                // submitted.
                if (_newItem) ...[
                  const SizedBox(height: Dimens.space4),
                  _NewItemFields(
                    nameController: _nameController,
                    unitController: _unitController,
                    perPackageController: _perPackageController,
                    perServingController: _perServingController,
                    category: _category,
                    enabled: !_submitting,
                    onCategoryChanged: (value) =>
                        setState(() => _category = value),
                  ),
                ],
                const SizedBox(height: Dimens.space4),

                // The SAME field means two different things, so it is
                // labelled two different ways. On an existing item it is base
                // units; on a new one it is PACKAGES, which the server
                // multiplies by unitsPerPackage. Sending grams into the second
                // is silent — it would declare 2g of a 200g jar.
                TextFormField(
                  controller: _quantityController,
                  decoration: InputDecoration(
                    labelText: _newItem ? l10n.packageCount : l10n.quantity,
                    helperText: _newItem ? l10n.packageCountHint : null,
                    // Isolated: the unit is admin-entered and keeps whatever
                    // language it was typed in, so it sits beside a Latin-digit
                    // quantity in either locale. Without the isolate the bidi
                    // algorithm reorders the pair (§2.4).
                    suffixText: _newItem || _selectedItem == null
                        ? null
                        : Formatters.isolate(_selectedItem!.unit),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  enabled: !_submitting,
                  validator: (value) {
                    final parsed = num.tryParse(value?.trim() ?? '');
                    return (parsed == null || parsed <= 0) ? '' : null;
                  },
                ),
                const SizedBox(height: Dimens.space4),

                TextFormField(
                  controller: _noteController,
                  decoration: InputDecoration(labelText: l10n.noteOptional),
                  maxLines: 3,
                  enabled: !_submitting,
                ),
                const SizedBox(height: Dimens.space5),

                // States the 202 rule in the user's own words, before they
                // commit — not only in the confirmation afterwards.
                InlineBanner(
                  tone: BannerTone.own,
                  title: l10n.awaitingConfirmation,
                  body: l10n.declareNotCredited,
                ),
                const SizedBox(height: Dimens.space5),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : Text(l10n.sendDeclaration),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One row in the item dropdown.
///
/// Names the item, and — only when the user already holds some — the balance
/// they are adding to. An item with no balance simply shows its name: a first
/// declaration is the normal case, not a gap.
/// The details for an item the buffet does not carry.
///
/// Shown only for «الصنف غير مدرج». Every field the server validates has a
/// local validator too, so the common mistakes cost no round trip — but the
/// server's `400` message still wins, since it is already localised.
class _NewItemFields extends StatelessWidget {
  const _NewItemFields({
    required this.nameController,
    required this.unitController,
    required this.perPackageController,
    required this.perServingController,
    required this.category,
    required this.enabled,
    required this.onCategoryChanged,
  });

  final TextEditingController nameController;
  final TextEditingController unitController;
  final TextEditingController perPackageController;
  final TextEditingController perServingController;
  final String category;
  final bool enabled;
  final ValueChanged<String> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    String? positive(String? value) {
      final parsed = num.tryParse(value?.trim() ?? '');
      return (parsed == null || parsed <= 0) ? l10n.mustBePositive : null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.newItemDetails,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: Dimens.space3),

        TextFormField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: l10n.itemName,
            hintText: l10n.itemNamePlaceholder,
          ),
          maxLength: 200,
          enabled: enabled,
          validator: (value) => (value?.trim().isEmpty ?? true) ? '' : null,
        ),
        const SizedBox(height: Dimens.space3),

        // Sent by NAME, never the ordinal: an ordinal 0 is indistinguishable
        // from an unset field and the server answers 400.
        DropdownButtonFormField<String>(
          initialValue: category,
          decoration: InputDecoration(labelText: l10n.itemType),
          items: [
            DropdownMenuItem(value: 'Drink', child: Text(l10n.categoryDrink)),
            DropdownMenuItem(value: 'Sugar', child: Text(l10n.categorySugar)),
            DropdownMenuItem(value: 'Extra', child: Text(l10n.categoryExtra)),
          ],
          onChanged: enabled
              ? (value) => onCategoryChanged(value ?? 'Drink')
              : null,
        ),
        const SizedBox(height: Dimens.space3),

        // Optional — the server defaults it to وحدة.
        TextFormField(
          controller: unitController,
          decoration: InputDecoration(labelText: l10n.unitOfMeasure),
          maxLength: 50,
          enabled: enabled,
        ),
        const SizedBox(height: Dimens.space3),

        TextFormField(
          controller: perPackageController,
          decoration: InputDecoration(
            labelText: l10n.packageContents,
            helperText: l10n.packageContentsHint,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          enabled: enabled,
          validator: positive,
        ),
        const SizedBox(height: Dimens.space3),

        TextFormField(
          controller: perServingController,
          decoration: InputDecoration(
            labelText: l10n.amountPerCup,
            helperText: l10n.amountPerCupHint,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          enabled: enabled,
          validator: positive,
        ),
      ],
    );
  }
}

class _ItemLabel extends StatelessWidget {
  const _ItemLabel({required this.item, required this.locale});

  final DeclarableItem item;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final balance = item.balance;
    return Row(
      children: [
        Expanded(
          child: Text(
            item.localisedName(locale.languageCode),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (balance != null) ...[
          const SizedBox(width: Dimens.space2),
          Text(
            // Bidi-isolated: the unit is admin-entered and keeps whatever
            // language it was typed in (§2.4).
            Formatters.quantity(balance.quantity, balance.unit),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
