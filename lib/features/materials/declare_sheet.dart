import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/locale_controller.dart';
import '../../data/api/api_exception.dart';
import '../../data/models/material_models.dart';
import '../../data/repositories/materials_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/banners.dart';
import '../../theme/dimens.dart';
import 'my_materials_screen.dart';

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

  MyMaterialDto? _selectedItem;
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
    final materials = ref.watch(myMaterialsProvider).valueOrNull ?? [];

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
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(2),
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

                DropdownButtonFormField<MyMaterialDto>(
                  initialValue: _selectedItem,
                  decoration: InputDecoration(labelText: l10n.item),
                  items: [
                    for (final item in materials)
                      DropdownMenuItem(value: item, child: Text(item.nameAr)),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _selectedItem = value),
                  validator: (value) => value == null ? '' : null,
                ),
                const SizedBox(height: Dimens.space4),

                TextFormField(
                  controller: _quantityController,
                  decoration: InputDecoration(
                    labelText: l10n.quantity,
                    // The unit is admin-entered and keeps its own language.
                    suffixText: _selectedItem?.unit,
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
