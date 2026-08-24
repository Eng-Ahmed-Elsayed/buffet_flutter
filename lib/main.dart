import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';
import 'data/push/push_background.dart';
import 'data/push/push_controller.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Loads the locale data `DateFormat` needs. Without it, formatting a
  // timestamp for a named locale throws LocaleDataException at runtime — and
  // every screen in this app renders a converted UTC time.
  await initializeDateFormatting();

  // Before runApp, because onBackgroundMessage must be registered before the
  // engine can be handed a message, and initializeApp is its precondition.
  //
  // Android only: no iOS app is registered in Firebase, because APNs needs a
  // paid Apple Developer account and there is no budget for one (§7.4). An
  // iPhone runs the whole app without this and falls back to the local alerts
  // and the notification list.
  //
  // Failure here is survivable and must be: push is an enhancement, and an app
  // that will not start because Firebase is unhappy is far worse than one that
  // cannot notify.
  if (PushController.isSupported) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseMessaging.onBackgroundMessage(handleBackgroundMessage);
    } on Object catch (error) {
      debugPrint('Firebase could not start; push is off: $error');
    }
  }

  runApp(const ProviderScope(child: BuffetApp()));
}
