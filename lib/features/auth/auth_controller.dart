import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import '../../data/local/biometric_service.dart';
import '../../data/models/auth_models.dart';
import '../../data/repositories/auth_repository.dart';

/// Where the user is in the auth state machine (§5).
///
/// The router reads this and nothing else to decide what to show, so the
/// machine lives in one place rather than being re-derived per screen.
enum AuthStage {
  /// Reading the stored token. The router shows a splash rather than flashing
  /// the login screen at someone who is already signed in.
  restoring,

  signedOut,

  /// A stored token exists and biometric unlock is switched on, so nothing is
  /// revealed until a prompt succeeds.
  ///
  /// **Never entered without a stored token** — prompting for a fingerprint
  /// when there is nothing to unlock teaches users the prompt is meaningless
  /// (§6).
  locked,

  /// Signed in, but the account is still on the seeded password.
  ///
  /// **The token works in this state**, which is exactly why navigation must
  /// stay blocked: a careless client could skip the screen and order anyway.
  mustChangePassword,

  signedIn,
}

class AuthState {
  const AuthState({
    required this.stage,
    this.session,
    this.rememberedEmail,
    this.biometricsEnabled = false,
    this.offerBiometricEnrolment = false,
  });

  const AuthState.restoring()
    : stage = AuthStage.restoring,
      session = null,
      rememberedEmail = null,
      biometricsEnabled = false,
      offerBiometricEnrolment = false;

  final AuthStage stage;
  final LoginResponse? session;
  final String? rememberedEmail;

  /// Whether biometric unlock is switched on for this device.
  final bool biometricsEnabled;

  /// Set once, immediately after a password sign-in on a capable device where
  /// the user has not already chosen. **Never enable it silently** — §6 wants
  /// it offered at the moment the token is fresh, and again in settings.
  final bool offerBiometricEnrolment;

  UserRole get role =>
      session == null ? UserRole.employee : UserRole.fromWire(session!.role);

  AuthState copyWith({
    AuthStage? stage,
    LoginResponse? session,
    String? rememberedEmail,
    bool? biometricsEnabled,
    bool? offerBiometricEnrolment,
  }) => AuthState(
    stage: stage ?? this.stage,
    session: session ?? this.session,
    rememberedEmail: rememberedEmail ?? this.rememberedEmail,
    biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
    offerBiometricEnrolment:
        offerBiometricEnrolment ?? this.offerBiometricEnrolment,
  );
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repository, this._authEvents, this._biometrics)
    : super(const AuthState.restoring()) {
    unawaited(_restore());

    // A 401 from anywhere in the app lands here: the interceptor has already
    // cleared the token, so all that remains is moving the machine to
    // signedOut and letting the router redirect.
    _unauthorizedSubscription = _authEvents.onUnauthorized.listen((_) {
      if (mounted) {
        state = AuthState(
          stage: AuthStage.signedOut,
          rememberedEmail: state.rememberedEmail,
        );
      }
    });
  }

  final AuthRepository _repository;
  final AuthEvents _authEvents;
  final BiometricService _biometrics;
  StreamSubscription<void>? _unauthorizedSubscription;

  Future<void> _restore() async {
    final email = await _repository.rememberedEmail();
    final hasToken = await _repository.hasValidToken();
    final enabled = hasToken && await _repository.biometricsEnabled();

    if (!mounted) return;

    // A restored token cannot tell us whether mustChangePassword was set —
    // that only arrives with a login response. The first authenticated call
    // will 401 if the token is actually dead, and the interceptor handles it.
    //
    // The lock is only ever reached WITH a token: there is otherwise nothing
    // to unlock, and a fingerprint prompt over a login screen teaches users
    // the prompt means nothing (§6).
    state = AuthState(
      stage: !hasToken
          ? AuthStage.signedOut
          : enabled
          ? AuthStage.locked
          : AuthStage.signedIn,
      rememberedEmail: email,
      biometricsEnabled: enabled,
    );
  }

  /// Signs in, then routes by `mustChangePassword` — not by role. Role only
  /// decides the landing screen once the password is the user's own.
  Future<void> signIn({
    required String username,
    required String password,
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    final session = await _repository.login(
      username: username,
      password: password,
      languageCode: languageCode,
      networkErrorFallback: networkErrorFallback,
    );

    // Offered at the moment the token is fresh, and only where the device can
    // actually satisfy a prompt — never enabled silently (§6). A user who has
    // already switched it on is not asked again.
    final alreadyEnabled = await _repository.biometricsEnabled();
    final offer =
        !alreadyEnabled &&
        !session.mustChangePassword &&
        await _biometrics.isAvailable();

    if (!mounted) return;

    state = AuthState(
      stage: session.mustChangePassword
          ? AuthStage.mustChangePassword
          : AuthStage.signedIn,
      session: session,
      rememberedEmail: username,
      biometricsEnabled: alreadyEnabled,
      offerBiometricEnrolment: offer,
    );
  }

  /// Prompts, and only switches the preference on once a prompt has actually
  /// succeeded.
  ///
  /// Enabling on the user's word alone would leave a flag set for hardware
  /// that cannot satisfy it — and the next cold start would strand them behind
  /// a lock that can never open. Returns the failure so the caller can say why.
  Future<BiometricFailure?> enableBiometrics({required String reason}) async {
    final result = await _biometrics.authenticate(reason: reason);
    if (!result.succeeded) return result.failure;

    await _repository.setBiometricsEnabled(true);
    if (!mounted) return null;
    state = state.copyWith(
      biometricsEnabled: true,
      offerBiometricEnrolment: false,
    );
    return null;
  }

  /// Switches biometric unlock off. No prompt: the user is already past the
  /// gate, and demanding a fingerprint to *stop* using fingerprints would be
  /// a trap for anyone whose sensor has started failing.
  Future<void> disableBiometrics() async {
    await _repository.setBiometricsEnabled(false);
    if (!mounted) return;
    state = state.copyWith(biometricsEnabled: false);
  }

  /// Dismisses the one-time enrolment offer without enabling anything.
  void declineBiometricEnrolment() {
    if (mounted) state = state.copyWith(offerBiometricEnrolment: false);
  }

  /// The cold-start gate. Reveals nothing until the prompt succeeds.
  ///
  /// Passing does **not** make a 30-day-old token valid — the first `401`
  /// still routes to login (§6).
  Future<BiometricFailure?> unlock({required String reason}) async {
    final result = await _biometrics.authenticate(reason: reason);

    if (result.succeeded) {
      if (mounted) state = state.copyWith(stage: AuthStage.signedIn);
      return null;
    }

    // Hardware that can no longer satisfy the prompt would strand the user
    // behind a lock with no key. Turn the preference off and let them through
    // to the token they already hold — the lock protects a stored credential,
    // it is not a second factor.
    if (result.failure == BiometricFailure.unavailable) {
      await _repository.setBiometricsEnabled(false);
      if (mounted) {
        state = state.copyWith(
          stage: AuthStage.signedIn,
          biometricsEnabled: false,
        );
      }
      return null;
    }

    // cancelled and lockedOut both hold on the lock screen, which always
    // carries a "use password instead" way past.
    return result.failure;
  }

  /// The way past the lock screen: discards the token and starts a full
  /// password sign-in. There must always be one (§6).
  Future<void> signOutFromLock() => signOut();

  /// Changes the password and, on success, releases the block.
  ///
  /// The state only advances after the call returns — a `400` leaves the user
  /// exactly where they were, which is the point of the block.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    await _repository.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
      languageCode: languageCode,
      networkErrorFallback: networkErrorFallback,
    );

    if (!mounted) return;
    state = state.copyWith(stage: AuthStage.signedIn);
  }

  Future<void> signOut() async {
    // clearAccountPreferences() drops the biometrics flag with the token: a
    // flag surviving the credential it unlocks would gate the next user of
    // this device on the previous one's fingerprint.
    await _repository.signOut();
    if (!mounted) return;
    state = AuthState(
      stage: AuthStage.signedOut,
      rememberedEmail: state.rememberedEmail,
    );
  }

  @override
  void dispose() {
    unawaited(_unauthorizedSubscription?.cancel());
    super.dispose();
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) => AuthController(
    ref.watch(authRepositoryProvider),
    ref.watch(authEventsProvider),
    ref.watch(biometricServiceProvider),
  ),
);
