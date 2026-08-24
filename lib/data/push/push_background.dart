import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../firebase_options.dart';

/// Handles a push that arrives while the app is backgrounded or terminated.
///
/// Runs in a **separate isolate** with no access to the app's providers, router
/// or widget tree — touching UI from here is not possible, not merely
/// discouraged. Its only job is staying alive long enough for the system to draw
/// the notification, which firebase_messaging does from the `notification`
/// payload itself.
///
/// Must be top-level, non-anonymous and annotated: the annotation is what keeps
/// it from being tree-shaken out of a release build, where its absence shows up
/// as pushes that silently never appear.
@pragma('vm:entry-point')
Future<void> handleBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}
