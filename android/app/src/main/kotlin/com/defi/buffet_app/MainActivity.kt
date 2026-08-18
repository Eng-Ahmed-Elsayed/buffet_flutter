package com.defi.buffet_app

import io.flutter.embedding.android.FlutterFragmentActivity

/**
 * Must extend FlutterFragmentActivity, not FlutterActivity (§11).
 *
 * local_auth shows its prompt through the AndroidX BiometricPrompt, which needs
 * a FragmentActivity host. With a plain FlutterActivity the prompt crashes at
 * the moment it is shown — which is to say, on the unlock path, in the user's
 * hands, not in a test.
 */
class MainActivity : FlutterFragmentActivity()
