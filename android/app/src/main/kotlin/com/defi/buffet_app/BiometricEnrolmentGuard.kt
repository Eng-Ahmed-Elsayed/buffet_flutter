package com.defi.buffet_app

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

/**
 * Detects that the device's biometric enrolment has changed.
 *
 * `local_auth` cannot report this: it authenticates without a CryptoObject, so
 * the Keystore key Android would invalidate is never involved. This guard
 * creates such a key deliberately — `setInvalidatedByBiometricEnrollment(true)`
 * tells Android to destroy it the moment a fingerprint or face is enrolled or
 * removed. Initialising a Cipher with the dead key then throws
 * KeyPermanentlyInvalidatedException, which is the signal we cannot otherwise
 * get.
 *
 * The key encrypts nothing. Its only job is to stop existing when enrolment
 * changes, so §6 can be honoured: a changed biometric means an untrusted
 * device, and the stored token must go.
 */
object BiometricEnrolmentGuard {

    private const val KEY_NAME = "buffet_biometric_enrolment_sentinel"
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"

    /** Result of checking the sentinel. */
    enum class State {
        /** Enrolment is unchanged since the key was created. */
        VALID,

        /** Biometrics were added or removed — the caller must clear the token. */
        CHANGED,

        /** No sentinel yet, or the platform cannot provide one. */
        UNAVAILABLE,
    }

    /**
     * Creates the sentinel key, replacing any existing one.
     *
     * Called when the user turns biometric unlock ON: the key's lifetime is
     * the enrolment state we are pinning to.
     */
    fun arm(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        return try {
            val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
            if (keyStore.containsAlias(KEY_NAME)) keyStore.deleteEntry(KEY_NAME)

            val generator = KeyGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_AES,
                ANDROID_KEYSTORE,
            )
            val spec = KeyGenParameterSpec.Builder(
                KEY_NAME,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_CBC)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_PKCS7)
                // Bind the key to biometric auth...
                .setUserAuthenticationRequired(true)
                // ...and, the whole point, have Android destroy it when the
                // set of enrolled biometrics changes.
                .setInvalidatedByBiometricEnrollment(true)
                .build()

            generator.init(spec)
            generator.generateKey()
            true
        } catch (e: Exception) {
            // A device with no secure lock screen cannot hold such a key. That
            // is not an error — it means this protection is unavailable, and
            // the caller falls back to the password path.
            false
        }
    }

    /**
     * Reports whether enrolment has changed since [arm].
     *
     * Initialising the Cipher is what surfaces the invalidation; the operation
     * is never completed and nothing is encrypted.
     */
    fun check(): State {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return State.UNAVAILABLE
        return try {
            val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
            val key = keyStore.getKey(KEY_NAME, null) as? SecretKey
                ?: return State.UNAVAILABLE

            val cipher = Cipher.getInstance(
                KeyProperties.KEY_ALGORITHM_AES + "/" +
                    KeyProperties.BLOCK_MODE_CBC + "/" +
                    KeyProperties.ENCRYPTION_PADDING_PKCS7,
            )
            cipher.init(Cipher.ENCRYPT_MODE, key)
            State.VALID
        } catch (e: KeyPermanentlyInvalidatedException) {
            // The signal we came for: biometrics were added or removed.
            State.CHANGED
        } catch (e: Exception) {
            // Anything else — no key, no keystore, an OEM quirk — is "cannot
            // tell". Treating an unknown as CHANGED would sign users out for
            // no reason on devices that simply behave differently.
            State.UNAVAILABLE
        }
    }

    /** Removes the sentinel. Called when biometric unlock is turned off. */
    fun disarm() {
        try {
            KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
                .deleteEntry(KEY_NAME)
        } catch (e: Exception) {
            // Nothing to clean up.
        }
    }
}
