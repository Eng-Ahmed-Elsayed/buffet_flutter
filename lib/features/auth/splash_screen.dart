import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';

/// Shown while the stored token is read.
///
/// Exists so a signed-in user never sees the login screen flash past on a cold
/// start — the router holds here until the auth stage resolves.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: BrandColors.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Direction-neutral: the mark alone, never the Latin lockup, in a
            // context that may be RTL or LTR.
            Image.asset(
              'assets/images/logo-defi-mark.png',
              width: 72,
              height: 72,
            ),
            const SizedBox(height: Dimens.space6),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: Dimens.space4),
            Semantics(
              liveRegion: true,
              child: Text(
                l10n.loading,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
