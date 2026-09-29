import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether this app may show notifications, and the way to the system screen
/// that changes it.
///
/// A declined permission used to leave the app silent with nothing saying so:
/// the user saw push arrive on a colleague's phone and not on theirs, and had
/// no way to tell why. Android 13 stops asking after a second refusal, so the
/// system settings screen is the only way back.
///
/// **Android only**, like push. Elsewhere [enabled] answers null and the
/// screen shows nothing.
class NotificationSettings {
  NotificationSettings(this._plugin);

  static const _channel = MethodChannel('buffet/notification_settings');

  final FlutterLocalNotificationsPlugin _plugin;

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// True or false on Android; null where it cannot be known.
  Future<bool?> enabled() async {
    if (!_isAndroid) return null;
    try {
      return await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.areNotificationsEnabled();
    } on Object catch (error) {
      debugPrint('Could not read the notification setting: $error');
      return null;
    }
  }

  /// Opens this app's notification settings.
  Future<void> open() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('open');
    } on Object catch (error) {
      debugPrint('Could not open notification settings: $error');
    }
  }
}

final notificationSettingsProvider = Provider<NotificationSettings>(
  (ref) => NotificationSettings(FlutterLocalNotificationsPlugin()),
);

/// Re-read when the app resumes, since the user changes it in system settings.
final notificationsEnabledProvider = FutureProvider.autoDispose<bool?>(
  (ref) => ref.watch(notificationSettingsProvider).enabled(),
);
