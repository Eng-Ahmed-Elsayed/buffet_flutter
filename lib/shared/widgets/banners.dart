import 'package:flutter/material.dart';

import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';

/// The tone of an inline message. Each pairs a colour with an icon and a
/// heading, so **status is never carried by colour alone** (§2.5).
enum BannerTone { info, warning, danger, own }

/// An inline message block: shortage warnings, the forced-password notice, the
/// awaiting-confirmation card.
///
/// Deliberately not a snackbar for anything that must stay on screen — a
/// shortage warning the user scrolls back to is more useful than one that
/// vanished after four seconds.
class InlineBanner extends StatelessWidget {
  const InlineBanner({
    required this.tone,
    required this.title,
    this.body,
    this.trailing,
    super.key,
  });

  final BannerTone tone;
  final String title;
  final String? body;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final (background, border, foreground, icon) = switch (tone) {
      BannerTone.info => (
        BrandColors.page,
        BrandColors.brandLight,
        BrandColors.ink,
        Icons.info_outline,
      ),
      BannerTone.warning => (
        BrandColors.warningSurface,
        BrandColors.warning,
        BrandColors.warning,
        Icons.warning_amber_rounded,
      ),
      BannerTone.danger => (
        BrandColors.surface,
        BrandColors.danger,
        BrandColors.danger,
        Icons.error_outline,
      ),
      // Violet: "from my own jar". Never a generic selection state.
      BannerTone.own => (
        BrandColors.accentSurface,
        BrandColors.accent,
        BrandColors.accent,
        Icons.inventory_2_outlined,
      ),
    };

    return Container(
      padding: const EdgeInsetsDirectional.all(Dimens.space4),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(Dimens.radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: foreground),
          const SizedBox(width: Dimens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (body != null) ...[
                  const SizedBox(height: Dimens.space1),
                  Text(
                    body!,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: BrandColors.ink),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: Dimens.space3),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// A full-screen empty or error state.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(Dimens.space7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: BrandColors.muted),
            const SizedBox(height: Dimens.space5),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: Dimens.space2),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (action != null) ...[
              const SizedBox(height: Dimens.space5),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
