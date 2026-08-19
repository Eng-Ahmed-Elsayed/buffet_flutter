import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_controller.dart';
import '../features/settings/biometric_enrolment_sheet.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'locale_controller.dart';
import 'router.dart';

class BuffetApp extends ConsumerWidget {
  const BuffetApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeControllerProvider);
    final router = ref.watch(routerProvider);

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
