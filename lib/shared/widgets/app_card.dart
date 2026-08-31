import 'package:flutter/material.dart';

import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';

/// What a card's surface is saying.
///
/// The tints are the ones already defined in the palette; this enum exists so a
/// caller names the *meaning* rather than reaching for a colour, which is how
/// the violet rule gets broken by accident.
enum CardTone {
  /// The ordinary card. White on the page ground.
  neutral,

  /// Drawn from the user's **own jar**. The one place violet is permitted.
  own,

  /// A shortage or a cap. Warns; never means failure.
  warning,

  /// Ready, healthy stock, handover.
  ok,
}

/// The app's one card.
///
/// The same white-surface, hairline-bordered, `radiusLg` container had been
/// hand-rolled in six screens. They agreed by coincidence rather than by
/// construction, which meant a palette edit had to find all six — and the
/// moment one drifted, the app stopped looking like one product.
///
/// Pass [onTap] to make it tappable; it gets an ink response and a
/// [Dimens.minTarget] floor rather than each caller remembering both.
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.onTap,
    this.tone = CardTone.neutral,
    this.padding,
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final CardTone tone;

  /// Defaults to [Dimens.space4] — the spacing every existing card used.
  final EdgeInsetsDirectional? padding;

  /// Set when the card is tappable and its contents do not already read as a
  /// label.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final (background, border) = switch (tone) {
      CardTone.neutral => (BrandColors.surface, BrandColors.brandLight),
      CardTone.own => (BrandColors.accentSurface, BrandColors.accent),
      CardTone.warning => (BrandColors.warningSurface, BrandColors.warning),
      CardTone.ok => (BrandColors.okSurface, BrandColors.ok),
    };

    final body = Padding(
      padding: padding ?? const EdgeInsetsDirectional.all(Dimens.space4),
      child: child,
    );

    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(Dimens.radiusLg),
      ),
      child: onTap == null
          ? body
          : ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Dimens.minTarget),
              child: body,
            ),
    );

    if (onTap == null) return decorated;

    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Dimens.radiusLg),
          child: decorated,
        ),
      ),
    );
  }
}
