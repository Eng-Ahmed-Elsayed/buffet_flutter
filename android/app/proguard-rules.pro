# R8 rules for the release build.
#
# Flutter contributes its own rules through the Gradle plugin; these cover the
# native entry points this app adds, which R8 cannot see are used because they
# are reached reflectively or from platform code.

# The biometric enrolment guard is invoked from Dart over a method channel, so
# nothing in Kotlin references it and R8 would otherwise strip it. Losing it
# would silently disable the §6 check rather than fail the build.
-keep class com.defi.buffet_app.BiometricEnrolmentGuard { *; }
-keep class com.defi.buffet_app.MainActivity { *; }

# AndroidX BiometricPrompt, used by local_auth. Keeping the callbacks named is
# what lets the prompt deliver its result.
-keep class androidx.biometric.** { *; }

# The security-crypto stack behind flutter_secure_storage's
# EncryptedSharedPreferences. Tink resolves primitives by class name.
-keep class androidx.security.crypto.** { *; }
-keep class com.google.crypto.tink.** { *; }

# Suppress warnings for the optional Tink dependencies that are never on the
# runtime path for this app.
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
