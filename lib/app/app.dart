import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/push/push_controller.dart';
import '../data/push/push_deep_links.dart';
import '../features/auth/auth_controller.dart';
import '../features/settings/biometric_enrolment_sheet.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'locale_controller.dart';
import 'router.dart';

class BuffetApp extends ConsumerStatefulWidget {
  const BuffetApp({super.key});

  @override
  ConsumerState<BuffetApp> createState() => _BuffetAppState();
}

class _BuffetAppState extends ConsumerState<BuffetApp> {
  final _deepLinks = PushDeepLinks();
  bool _listeningForTaps = false;

  /// Follows a held notification link, if the session is open enough to.
  ///
  /// Called both when a tap arrives and on every transition into `signedIn`,
  /// because a tap that lands at the lock screen has to wait for the unlock.
  void _drainDeepLink() {
    final route = _deepLinks.takeIf(
      sessionIsOpen: ref.read(authStageProvider) == AuthStage.signedIn,
    );
    if (route == null) return;

    // push, not go: the user came from somewhere and should be able to get back.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The Future is the popped result, which nothing here waits for.
      unawaited(ref.read(routerProvider).push<void>(route));
    });
  }

  Future<void> _onSignedIn() async {
    await ref.read(pushControllerProvider).register();

    if (!_listeningForTaps && PushController.isSupported) {
      _listeningForTaps = true;
      await _deepLinks.listen(onLink: _drainDeepLink);
    }

    // A tap may already be waiting — either from a cold start via
    // getInitialMessage, or from one that arrived while the app was locked.
    _drainDeepLink();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeControllerProvider);
    final router = ref.watch(routerProvider);

    // Installed once, and before any sign-out can happen: unregistering has to
    // run while the bearer token is still valid.
    ref.read(authControllerProvider.notifier).onBeforeSignOut ??= () async =>
        ref.read(pushControllerProvider).unregister();

    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next.stage == AuthStage.signedIn &&
          previous?.stage != AuthStage.signedIn) {
        unawaited(_onSignedIn());
      }
    });

    // The enrolment offer follows the user to whichever screen they land on,
    // so it lives here rather than being repeated in the catalogue and the
    // queue. Listening on the flag rather than on the sign-in event means the
    // sheet cannot appear twice: accepting or declining clears it.
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next.offerBiometricEnrolment &&
          previous?.offerBiometricEnrolment != true) {
        // The navigator context is resolved INSIDE the callback: at listen
        // time the router has not yet rebuilt for the new stage, so the
        // context captured here would belong to the login screen that is
        // about to be replaced.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final context = router.routerDelegate.navigatorKey.currentContext;
          if (context != null && context.mounted) {
            unawaited(BiometricEnrolmentSheet.show(context));
          }
        });
      }
    });

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,

      theme: AppTheme.light,

      // Arabic first (§2.4). Flutter flips the whole layout from the locale's
      // direction, which is why every widget uses start/end rather than
      // left/right — an LTR-shaped layout ships backwards the moment someone
      // switches to English, and vice versa.
      locale: locale,
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      routerConfig: router,
    );
  }
}
