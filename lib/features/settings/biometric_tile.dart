import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/biometric_service.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/brand_colors.dart';
import '../auth/auth_controller.dart';

/// The biometric unlock switch.
///
/// Turning it **on** prompts first and only writes the preference once the
/// prompt has actually succeeded — enabling on the user's word alone would set
/// a flag for hardware that cannot satisfy it, and strand them behind a lock
/// that never opens on the next cold start.
///
/// Turning it **off** does not prompt: the user is already past the gate, and
/// demanding a fingerprint to stop using fingerprints traps anyone whose
/// sensor has begun to fail.
class BiometricTile extends ConsumerStatefulWidget {
  const BiometricTile({super.key});

  @override
  ConsumerState<BiometricTile> createState() => _BiometricTileState();
}

class _BiometricTileState extends ConsumerState<BiometricTile> {
  bool _available = false;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    unawaited(_checkAvailability());
  }

  Future<void> _checkAvailability() async {
    final available = await ref.read(biometricServiceProvider).isAvailable();
    if (mounted) setState(() => _available = available);
  }

  Future<void> _toggle(bool enable) async {
    setState(() {
      _busy = true;
      _message = null;
    });

    final controller = ref.read(authControllerProvider.notifier);
    final l10n = AppLocalizations.of(context);

    if (!enable) {
      await controller.disableBiometrics();
      if (mounted) setState(() => _busy = false);
      return;
    }

    final failure = await controller.enableBiometrics(
      reason: l10n.biometricReason,
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = switch (failure) {
        null => null,
        BiometricFailure.unavailable => l10n.biometricsUnavailable,
        BiometricFailure.lockedOut => l10n.biometricLockedOut,
        BiometricFailure.cancelled => l10n.biometricFailed,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final enabled = ref.watch(authControllerProvider).biometricsEnabled;

    // A device with no sensor and no passcode gets no switch at all, rather
    // than a control that can only ever fail.
    if (!_available && !enabled) return const SizedBox.shrink();

    return SwitchListTile(
      value: enabled,
      onChanged: _busy ? null : (value) => unawaited(_toggle(value)),
      title: Text(l10n.enableBiometrics),
      subtitle: Text(_message ?? l10n.enableBiometricsBody),
      activeThumbColor: BrandColors.brand,
      contentPadding: EdgeInsetsDirectional.zero,
      secondary: const Icon(Icons.fingerprint),
    );
  }
}
