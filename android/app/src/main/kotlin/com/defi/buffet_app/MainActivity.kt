package com.defi.buffet_app

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
    }

    private companion object {
        const val CHANNEL = "buffet/biometric_enrolment"
    }
}
