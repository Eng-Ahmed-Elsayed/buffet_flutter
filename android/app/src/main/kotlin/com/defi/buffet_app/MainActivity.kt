package com.defi.buffet_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Must extend FlutterFragmentActivity, not FlutterActivity (§11).
 *
 * local_auth shows its prompt through the AndroidX BiometricPrompt, which needs
 * a FragmentActivity host. With a plain FlutterActivity the prompt crashes at
 * the moment it is shown — which is to say, on the unlock path, in the user's
 * hands, not in a test.
 */
class MainActivity : FlutterFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Biometric-enrolment detection (§6, §12). local_auth cannot report a
        // changed enrolment, so this channel exposes a Keystore sentinel that
        // Android invalidates on our behalf. See BiometricEnrolmentGuard.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "arm" -> result.success(BiometricEnrolmentGuard.arm())
                "check" -> result.success(BiometricEnrolmentGuard.check().name)
                "disarm" -> {
                    BiometricEnrolmentGuard.disarm()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Opens this app's notification settings, so a user who declined the
        // permission (or silenced a channel) can turn it back on. Android 13
        // stops asking after a second refusal, and only settings can undo it.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NOTIFICATION_SETTINGS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "open" -> {
                    openNotificationSettings()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun openNotificationSettings() {
        val intent =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            } else {
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(Uri.fromParts("package", packageName, null))
            }
        try {
            startActivity(intent)
        } catch (e: android.content.ActivityNotFoundException) {
            // Some OEM builds drop the notification screen: the app's details
            // page still reaches it.
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(Uri.fromParts("package", packageName, null)),
            )
        }
    }

    private companion object {
        const val CHANNEL = "buffet/biometric_enrolment"
        const val NOTIFICATION_SETTINGS_CHANNEL = "buffet/notification_settings"
    }
}
