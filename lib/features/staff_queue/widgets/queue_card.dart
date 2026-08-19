import 'package:flutter/material.dart';

import '../../../data/models/staff_models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/formatters.dart';
import '../../../shared/widgets/banners.dart';
import '../../../shared/widgets/source_chip.dart';
import '../../../theme/brand_colors.dart';
import '../../../theme/dimens.dart';

/// One order in the staff queue.
///
/// The card's whole job is saying **which jar to reach for**: every line names
/// its source owner, in violet when it is someone's personal stock. There is no
/// sugar *name* to show — `sugarNameAr` is always null — so the card shows the
/// spoon count and the source instead (§8.1).
class QueueCard extends StatelessWidget {
  const QueueCard({
    required this.order,
    required this.warnings,
    required this.onMarkReady,
    required this.onComplete,
    super.key,
  });

  final StaffOrderDto order;

  /// Warnings from a recent serve. A populated list is **not** a failure — the
  /// drink was made and the shortfall is for an admin to reconcile.
  final List<StockWarningDto>? warnings;

  final Future<void> Function(StaffOrderDto, {required bool deliverNow})?
  onMarkReady;
  final Future<void> Function(StaffOrderDto)? onComplete;

  @override
  Widget build(BuildContext context) {
    final minutes = Formatters.minutesFromSeconds(order.waitingSeconds);
    final isAgeing = minutes >= 5;
    final hasWarnings = warnings != null && warnings!.isNotEmpty;

    return Container(
      padding: const EdgeInsetsDirectional.all(Dimens.space4),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        border: Border.all(
          color: hasWarnings ? BrandColors.warning : BrandColors.brandLight,
        ),
        borderRadius: BorderRadius.circular(Dimens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.requesterDisplayName,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      '${order.department} · ${order.locationText}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              _AgeingBadge(minutes: minutes, isAgeing: isAgeing),
            ],
          ),

          const SizedBox(height: Dimens.space3),
          const Divider(),
          const SizedBox(height: Dimens.space3),

          for (final line in order.lines) ...[
            _LineDetails(line: line),
            if (line != order.lines.last) const SizedBox(height: Dimens.space4),
          ],

          if (order.notes.isNotEmpty) ...[
            const SizedBox(height: Dimens.space3),
            _NoteBlock(note: order.notes),
          ],

          if (hasWarnings) ...[
            const SizedBox(height: Dimens.space3),
            _ShortageWarnings(warnings: warnings!),
          ],

          const SizedBox(height: Dimens.space4),
          _Actions(
            order: order,
            onMarkReady: onMarkReady,
            onComplete: onComplete,
          ),
        ],
      ),
    );
  }
}

class _AgeingBadge extends StatelessWidget {
  const _AgeingBadge({required this.minutes, required this.isAgeing});

  final int minutes;
  final bool isAgeing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Dimens.space2,
        vertical: Dimens.space1,
      ),
      decoration: BoxDecoration(
        color: isAgeing ? BrandColors.warningSurface : BrandColors.page,
        borderRadius: BorderRadius.circular(Dimens.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule,
            size: 13,
            color: isAgeing ? BrandColors.warning : BrandColors.muted,
          ),
          const SizedBox(width: Dimens.space1),
          Text(
            l10n.waitingMinutes(minutes),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isAgeing ? BrandColors.warning : BrandColors.muted,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _LineDetails extends StatelessWidget {
  const _LineDetails({required this.line});

  final StaffOrderLineDto line;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              // Arabic by contract: StaffOrderLineDto carries only *NameAr —
              // there are no English fields on the staff wire, unlike
              // CatalogueItemDto. Deliberately NOT joined against /catalogue
              // to translate: staff work in Arabic, and fetching the whole
              // employee catalogue on every queue render for a cosmetic name
              // swap is the wrong trade. Revisit if the staff DTO gains
              // NameEn.
              line.drinkNameAr,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (line.variantNameAr != null) ...[
              const SizedBox(width: Dimens.space2),
              Text(
                line.variantNameAr!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        const SizedBox(height: Dimens.space2),

        Wrap(
          spacing: Dimens.space2,
          runSpacing: Dimens.space2,
          children: [
            // Which jar the drink itself comes from — the most important line
            // on the card.
            SourceChip(label: l10n.drink, ownerName: line.drinkSourceOwnerName),

            // sugarNameAr is always null, so this is the spoon count plus its
            // source — never a sugar name.
            SourceChip(
              label: l10n.spoons(line.sugarSpoons),
              ownerName: line.sugarSourceOwnerName,
            ),

            for (final extra in line.extraSources)
              SourceChip(label: extra.nameAr, ownerName: extra.sourceOwnerName),

            // An extra with no matching source entry still gets shown.
            for (final name in line.extraNamesAr)
              if (!line.extraSources.any((s) => s.nameAr == name))
                DetailChip(label: name),
          ],
        ),

        if (line.lineNote != null && line.lineNote!.isNotEmpty) ...[
          const SizedBox(height: Dimens.space2),
          _NoteBlock(note: line.lineNote!),
        ],
      ],
    );
  }
}

class _NoteBlock extends StatelessWidget {
  const _NoteBlock({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Dimens.space3,
        vertical: Dimens.space2,
      ),
      decoration: BoxDecoration(
        color: BrandColors.page,
        borderRadius: BorderRadius.circular(Dimens.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.sticky_note_2_outlined,
            size: 15,
            color: BrandColors.muted,
          ),
          const SizedBox(width: Dimens.space2),
          Expanded(
            child: Text(
              note,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: BrandColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shortages that came back on a **`200`** after serving.
///
/// Presented as information, not failure: the drink was made and handed over.
class _ShortageWarnings extends StatelessWidget {
  const _ShortageWarnings({required this.warnings});

  final List<StockWarningDto> warnings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        for (final warning in warnings)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: Dimens.space2),
            child: InlineBanner(
              tone: BannerTone.warning,
              title: l10n.shortageTitle,
              body: [
                warning.nameAr,
                if (warning.ownerDisplayName.isNotEmpty)
                  l10n.fromJarOf(Formatters.isolate(warning.ownerDisplayName)),
                // Quantity and unit isolated — the unit is admin-entered.
                l10n.shortfallAmount(
                  Formatters.quantity(warning.shortfall, warning.unit),
                ),
                l10n.shortageBody,
              ].join('\n'),
            ),
          ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.order,
    required this.onMarkReady,
    required this.onComplete,
  });

  final StaffOrderDto order;
  final Future<void> Function(StaffOrderDto, {required bool deliverNow})?
  onMarkReady;
  final Future<void> Function(StaffOrderDto)? onComplete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // The handover list: the drink is already made and stock already deducted,
    // so the only action left is stamping it as collected.
    if (onComplete != null) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () => onComplete!(order),
          child: Text(l10n.markDelivered),
        ),
      );
    }

    if (onMarkReady == null) return const SizedBox.shrink();

    return Row(
      children: [
        // deliverNow is the common case at the counter — ready and handed over
        // in one motion — so it is the primary action and the largest target.
        //
        // NEITHER button is ever disabled on a stock reading: /ready returns
        // 200 with warnings, never 400 (§8.1).
        Expanded(
          child: FilledButton(
            onPressed: () => onMarkReady!(order, deliverNow: true),
            child: Text(
              l10n.readyAndDelivered,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: Dimens.space2),
        OutlinedButton(
          onPressed: () => onMarkReady!(order, deliverNow: false),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: BrandColors.brand),
            minimumSize: const Size(Dimens.minTarget, Dimens.controlHeight),
          ),
          child: Text(l10n.markReady),
        ),
      ],
    );
  }
}
