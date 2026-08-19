import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/biometric_service.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';
import '../auth/auth_controller.dart';

/// The one-time offer, shown immediately after a password sign-in.
///
/// §6: **never enable biometrics silently.** It is offered once at the moment
/// the token is fresh, and again in settings for anyone who declines here.
///
/// Declining is a real choice, not a delay — the sheet does not reappear on
/// the next launch.
class BiometricEnrolmentSheet extends ConsumerStatefulWidget {
  const BiometricEnrolmentSheet({super.key});

  /// Shows the sheet, resolving once the user has chosen either way.
  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // Dismissing by tapping away is the same choice as "not now": the offer
    // is a convenience, and nothing should be enabled by walking away from it.
    builder: (_) => const BiometricEnrolmentSheet(),
  );

  @override
  ConsumerState<BiometricEnrolmentSheet> createState() =>
      _BiometricEnrolmentSheetState();
}

class _BiometricEnrolmentSheetState
    extends ConsumerState<BiometricEnrolmentSheet> {
  bool _busy = false;
  String? _message;

  Future<void> _enable() async {
    setState(() {
      _busy = true;
      _message = null;
    });

    final l10n = AppLocalizations.of(context);
    final failure = await ref
        .read(authControllerProvider.notifier)
        .enableBiometrics(reason: l10n.biometricReason);

    if (!mounted) return;

    if (failure == null) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _busy = false;
      _message = switch (failure) {
        BiometricFailure.unavailable => l10n.biometricsUnavailable,
        BiometricFailure.lockedOut => l10n.biometricLockedOut,
        BiometricFailure.cancelled => l10n.biometricFailed,
      };
    });
  }

  void _decline() {
    ref.read(authControllerProvider.notifier).declineBiometricEnrolment();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: Dimens.space4,
        end: Dimens.space4,
        top: Dimens.space3,
        bottom: Dimens.space5,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: Dimens.space5),

          const Icon(Icons.fingerprint, size: 40, color: BrandColors.brand),
          const SizedBox(height: Dimens.space3),

          Text(
            l10n.enableBiometricsTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: Dimens.space2),

          // Says plainly that this unlocks a stored session. Biometrics are
          // not a second factor and the copy must not imply they are (§6).
          Text(
            _message ?? l10n.enableBiometricsBody,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: Dimens.space5),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : () => unawaited(_enable()),
              child: Text(l10n.enableBiometricsAction),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _busy ? null : _decline,
              child: Text(l10n.notNow),
            ),
          ),
        ],
      ),
    );
  }
}
