import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/locale_controller.dart';
import '../../data/api/api_config.dart';
import '../../data/api/api_exception.dart';
import '../../data/models/material_models.dart';
import '../../data/repositories/materials_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/banners.dart';
import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';
import '../order/widgets/item_image.dart';
import 'declare_sheet.dart';

final myMaterialsProvider = FutureProvider.autoDispose<List<MyMaterialDto>>((
  ref,
) async {
  final locale = ref.watch(localeControllerProvider);
  return ref
      .watch(materialsRepositoryProvider)
      .fetchMine(
        languageCode: locale.languageCode,
        networkErrorFallback: 'network',
      );
});

/// The employee's own material balances.
///
/// **Employee declares, staff confirms.** Stock only exists once staff confirm
/// the jar physically arrived, so a declaration shows as "awaiting
/// confirmation" and is kept visually separate from the confirmed balance
/// (§7.5).
class MyMaterialsScreen extends ConsumerWidget {
  const MyMaterialsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final materials = ref.watch(myMaterialsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.myMaterialsTitle)),
      body: materials.when(
        loading: () => const Center(child: CircularProgressIndicator()),

        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: l10n.genericError,
          body: error is ApiException ? error.message : l10n.networkError,
          action: OutlinedButton.icon(
            onPressed: () => ref.invalidate(myMaterialsProvider),
            icon: const Icon(Icons.refresh),
            label: Text(l10n.retry),
          ),
        ),

        data: (items) => items.isEmpty
            ? EmptyState(
                icon: Icons.inventory_2_outlined,
                title: l10n.noMaterialsTitle,
                body: l10n.noMaterialsBody,
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(myMaterialsProvider),
                child: ListView.separated(
                  padding: const EdgeInsetsDirectional.all(Dimens.space4),
                  itemCount: items.length + 1,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: Dimens.space3),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsetsDirectional.only(
                          bottom: Dimens.space1,
                        ),
                        child: Text(
                          l10n.confirmedBalance,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      );
                    }
                    return _MaterialCard(material: items[index - 1]);
                  },
                ),
              ),
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => const DeclareSheet(),
        ),
        backgroundColor: BrandColors.brand,
        foregroundColor: BrandColors.surface,
        icon: const Icon(Icons.add),
        label: Text(l10n.declareMaterials),
      ),
    );
  }
}

class _MaterialCard extends StatelessWidget {
  const _MaterialCard({required this.material});

  final MyMaterialDto material;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final (levelColour, levelLabel, fraction) = switch (material.stockLevel) {
      StockLevel.high => (BrandColors.ok, l10n.levelHigh, 0.85),
      StockLevel.medium => (BrandColors.brand, l10n.levelMedium, 0.5),
      StockLevel.low => (BrandColors.warning, l10n.levelLow, 0.22),
      StockLevel.empty => (BrandColors.danger, l10n.levelEmpty, 0.03),
    };

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
              // The real uploaded photograph, resolved against the API host.
              // Falls back to a category glyph while imageUrl is absent — see
              // docs/backend-request-material-image.md.
              ItemImage(
                imageUrl: ApiConfig.imageUrl(material.imageUrl),
                category: material.nameAr,
                size: 44,
              ),
              const SizedBox(width: Dimens.space3),
              Expanded(
                child: Text(
                  material.nameAr,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              // Quantity and unit are bidi-isolated: the unit is admin-entered
              // and keeps whatever language it was typed in (§2.4).
              Text(
                Formatters.quantity(material.quantity, material.unit),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: Dimens.space3),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 6,
                    backgroundColor: BrandColors.brandLight,
                    valueColor: AlwaysStoppedAnimation(levelColour),
                  ),
                ),
              ),
              const SizedBox(width: Dimens.space3),
              // The band is never colour alone — the word is always there.
              Text(
                levelLabel,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: levelColour, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: Dimens.space1),
          Text(
            material.stockLevel == StockLevel.empty
                ? l10n.willUseBuffetStock
                : l10n.servingsLeft(material.servingsLeft),
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}
