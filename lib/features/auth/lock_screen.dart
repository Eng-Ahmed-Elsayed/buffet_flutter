import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/biometric_service.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/brand_backdrop.dart';
import '../../shared/widgets/brand_lockup.dart';
import '../../shared/widgets/exit_confirmation.dart';
import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';
import 'auth_controller.dart';

/// The cold-start gate: a stored token exists and biometric unlock is on.
///
/// **There is always a way past.** A failed or cancelled prompt leaves the
/// user here with a "use password instead" button that discards the token and
/// routes to login — a lock with no key is worse than no lock (§6).
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  BiometricFailure? _failure;
  bool _prompting = false;

  @override
  void initState() {
    super.initState();
    // Prompt on arrival rather than making the user tap first — the whole
    // point is that unlocking is faster than signing in.
    WidgetsBinding.instance.addPostFrameCallback((_) => _prompt());
  }

  Future<void> _prompt() async {
    if (_prompting) return;
    setState(() => _prompting = true);

    final reason = AppLocalizations.of(context).biometricReason;
    final failure = await ref
        .read(authControllerProvider.notifier)
        .unlock(reason: reason);

    if (!mounted) return;
    setState(() {
      _prompting = false;
      _failure = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final auth = ref.watch(authControllerProvider);
    // Who is being let back in: the name if we have it, else the email.
    final who = auth.displayName ?? auth.rememberedEmail;

    return ExitConfirmation(
      // The lock has no route beneath it. Back must not quietly close the
      // app: the way past is the explicit "use password instead" button,
      // not a gesture that looks like it dismissed the lock.
      child: Scaffold(
        body: BrandBackdrop(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: Dimens.gutter,
                  vertical: Dimens.space5,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The sign-in screen's layout, so unlocking reads as the
                    // same door rather than a different app.
                    const Center(child: BrandLockup(width: Dimens.lockupEntry)),
                    const SizedBox(height: Dimens.space7),

                    Text(
                      l10n.welcomeBackTitle,
                      textAlign: TextAlign.center,
                      style: text.headlineMedium?.copyWith(
                        color: BrandColors.brand,
                      ),
                    ),
                    if (who != null) ...[
                      const SizedBox(height: Dimens.space1),
                      Text(
                        who,
                        textAlign: TextAlign.center,
                        style: text.bodyLarge?.copyWith(
                          color: BrandColors.brand,
                        ),
                      ),
                    ],
                    const SizedBox(height: Dimens.space6),

                    // Locked out is not the same as cancelled: retrying the
                    // prompt cannot clear it, so the message says so rather
                    // than inviting a tap that will fail again.
                    if (_failure != null) ...[
                      InlineBanner(
                        tone: BannerTone.danger,
                        title: _failure == BiometricFailure.lockedOut
                            ? l10n.biometricLockedOut
                            : l10n.biometricFailed,
                      ),
                      const SizedBox(height: Dimens.space5),
                    ],

                    // Disabled while a prompt is up, and when the hardware has
                    // locked out — the banner above says so.
                    FilledButton.icon(
                      onPressed:
                          _prompting || _failure == BiometricFailure.lockedOut
                          ? null
                          : _prompt,
                      // Named for what it does, not for a sensor: the prompt
                      // may be a face, a fingerprint or the device PIN.
                      icon: const Icon(Icons.lock_open_outlined),
                      label: Text(l10n.unlock),
                    ),
                    const SizedBox(height: Dimens.space3),

                    // The way past. Always present, never disabled.
                    OutlinedButton(
                      onPressed: () => ref
                          .read(authControllerProvider.notifier)
                          .signOutFromLock(),
                      child: Text(l10n.usePasswordInstead),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
