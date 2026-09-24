import 'package:flutter/material.dart';

import '../../theme/brand_colors.dart';

/// The pale-blue page with the design's soft glow at the top: the backdrop of
/// the screens that stand outside the app — splash, first-launch, sign-in and
/// lock.
///
/// The glow is decorative (see [BrandColors.glow]); content laid over it keeps
/// its text below the glow's peak.
class BrandBackdrop extends StatelessWidget {
  const BrandBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: BrandColors.page,
      gradient: RadialGradient(
        // Just above the top edge, so the brightest part is the top of the
        // screen and it has faded out by roughly a quarter of the way down.
        center: Alignment(0, -1.2),
        radius: 0.9,
        colors: [BrandColors.glow, BrandColors.page],
      ),
    ),
    child: child,
  );
}
