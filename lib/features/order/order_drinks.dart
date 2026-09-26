import '../../data/models/catalogue_models.dart';
import '../../data/models/order_models.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/formatters.dart';

/// The drinks on [order], identical ones once with ×N — "Coffee ×2, Tea".
/// Null for an order that carries no lines.
///
/// Named from [catalogue] in the reader's language, as the status screen does,
/// so the row and the order it opens never name a drink differently. The
/// stored Arabic name is the floor, for a menu still loading or a drink since
/// retired. Each name is isolated: admin-entered, in whatever script it was
/// typed.
String? describeOrderDrinks(
  OrderSummaryDto order,
  CatalogueResponse? catalogue,
  AppLocalizations l10n,
  String languageCode,
) {
  if (order.lines.isEmpty) return null;
  final names = <int, String>{};
  final counts = <int, int>{};
  for (final line in order.lines) {
    names.putIfAbsent(line.drinkItemId, () {
      for (final item in catalogue?.drinks ?? const <CatalogueItemDto>[]) {
        if (item.itemId == line.drinkItemId) {
          return item.localisedName(languageCode);
        }
      }
      return line.drinkNameAr;
    });
    counts.update(line.drinkItemId, (n) => n + 1, ifAbsent: () => 1);
  }
  return [
    for (final MapEntry(key: id, value: n) in counts.entries)
      n > 1
          ? '${Formatters.isolate(names[id]!)} ×$n'
          : Formatters.isolate(names[id]!),
  ].join(l10n.listSeparator);
}
