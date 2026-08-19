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
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final item = _selectedItem;
    if (item == null) return;

    final l10n = AppLocalizations.of(context);
    final locale = ref.read(localeControllerProvider);
    final quantity = num.tryParse(_quantityController.text.trim());
    if (quantity == null) return;

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(materialsRepositoryProvider)
          .declare(
            request: DeclareMaterialRequest(
              itemId: item.itemId,
              quantity: quantity,
              note: _noteController.text.trim().isEmpty
                  ? null
                  : _noteController.text.trim(),
            ),
            languageCode: locale.languageCode,
            networkErrorFallback: l10n.networkError,
          );

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
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: Dimens.space4,
            end: Dimens.space4,
            top: Dimens.space3,
            bottom: Dimens.space5,
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
                DropdownButtonFormField<DeclarableItem>(
                  initialValue: _selectedItem,
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
                  ],
                  onChanged: _submitting || items.isEmpty
                      ? null
                      : (value) => setState(() => _selectedItem = value),
                  validator: (value) => value == null ? '' : null,
                ),
                const SizedBox(height: Dimens.space4),

                TextFormField(
                  controller: _quantityController,
                  decoration: InputDecoration(
                    labelText: l10n.quantity,
                    // Isolated: the unit is admin-entered and keeps whatever
                    // language it was typed in, so it sits beside a Latin-digit
                    // quantity in either locale. Without the isolate the bidi
                    // algorithm reorders the pair (§2.4).
                    suffixText: _selectedItem == null
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
