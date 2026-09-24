import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/widgets/brand_backdrop.dart';
import '../../shared/widgets/brand_lockup.dart';

/// Shown while the stored token is read.
///
/// Exists so a signed-in user never sees the login screen flash past on a cold
/// start — the router holds here until the auth stage resolves.
///
/// The design's splash: the lockup alone on the glowing page. No spinner — the
/// wait is a fraction of a second, and a spinner that flashes for 200ms reads
/// as a stutter. Screen readers are still told it is loading.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: BrandBackdrop(
        child: Center(
          child: Semantics(
            liveRegion: true,
            label: l10n.loading,
            child: const BrandLockup(width: 250),
          ),
        ),
      ),
    );
  }
}
