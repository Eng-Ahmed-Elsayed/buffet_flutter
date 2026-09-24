import 'package:flutter/material.dart';

/// The full DEFI lockup — circuit mark plus the "DIGITAL EGYPT FOR
/// INVESTMENT" wordmark — as the design uses it on splash, first-launch,
/// sign-in and lock.
///
/// The wordmark is Latin and reads left-to-right, so it stays LTR inside an
/// RTL layout rather than being mirrored (§2.1). Never recoloured.
///
/// Decorative for screen readers: every screen that shows it also names the
/// app in text, and announcing the brand twice is noise.
class BrandLockup extends StatelessWidget {
  const BrandLockup({required this.width, super.key});

  final double width;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Image.asset(
        'assets/images/logo-defi.png',
        width: width,
        fit: BoxFit.contain,
      ),
    ),
  );
}
