// Generated from android/app/google-services.json.
//
// Committed on purpose: these are public project identifiers, not credentials —
// the same values ship inside every APK. The service-account key, which IS a
// credential, lives only on the server and never reaches this repository.
//
// **Android only.** iOS push needs a paid Apple Developer account for APNs and
// there is no budget for one, so no iOS app is registered in Firebase yet
// (§7.4). `Firebase.initializeApp` is therefore only called on Android — see
// main.dart — and an iPhone runs the whole app without it, falling back to the
// local alerts and the notification list.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('This app does not run on the web.');
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => android,
      // Deliberate: registering an iOS app in Firebase without an APNs key
      // would look configured while delivering nothing. Better to say so.
      TargetPlatform.iOS => throw UnsupportedError(
        'iOS push is not configured — it needs an Apple Developer account. '
        'The app falls back to local alerts and the notification list.',
      ),
      _ => throw UnsupportedError(
        'Firebase is not configured for $defaultTargetPlatform.',
      ),
    };
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAW8Zn-fjtOiEfljiBfXDHCAg4Bnik2H3o',
    appId: '1:144808458172:android:39fef57451ec08bffd5db9',
    messagingSenderId: '144808458172',
    projectId: 'digital-buffet-846f0',
    storageBucket: 'digital-buffet-846f0.firebasestorage.app',
  );
}
