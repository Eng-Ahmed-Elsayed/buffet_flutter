import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/biometric_service.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/banners.dart';
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
    final email = ref.watch(authControllerProvider).rememberedEmail;

    return ExitConfirmation(
      // The lock has no route beneath it. Back must not quietly close the
      // app: the way past is the explicit "use password instead" button,
      // not a gesture that looks like it dismissed the lock.
      child: Scaffold(
        backgroundColor: BrandColors.surface,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.all(Dimens.space5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Direction-neutral: the mark alone, never the Latin lockup.
                  Image.asset(
                    'assets/images/logo-defi-mark.png',
                    width: 72,
                    height: 72,
                  ),
                  const SizedBox(height: Dimens.space6),

                  Text(
                    l10n.lockedTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  if (email != null) ...[
                    const SizedBox(height: Dimens.space2),
                    Text(
                      email,
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: Dimens.space5),

                  // Locked out is not the same as cancelled: retrying the prompt
                  // cannot clear it, so the message says so rather than inviting
                  // a tap that will fail again.
                  if (_failure != null) ...[
                    InlineBanner(
                      tone: BannerTone.danger,
                      title: _failure == BiometricFailure.lockedOut
                          ? l10n.biometricLockedOut
                          : l10n.biometricFailed,
                    ),
                    const SizedBox(height: Dimens.space5),
                  ],

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed:
                          _prompting || _failure == BiometricFailure.lockedOut
                          ? null
                          : _prompt,
                      icon: const Icon(Icons.fingerprint),
                      label: Text(l10n.unlock),
                    ),
                  ),
                  const SizedBox(height: Dimens.space3),

                  // The way past. Always present, never disabled.
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => ref
                          .read(authControllerProvider.notifier)
                          .signOutFromLock(),
                      child: Text(l10n.usePasswordInstead),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
