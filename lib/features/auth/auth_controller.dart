import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
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

  /// Signed in, but the account is still on the seeded password.
  ///
  /// **The token works in this state**, which is exactly why navigation must
  /// stay blocked: a careless client could skip the screen and order anyway.
  mustChangePassword,

  signedIn,
}

class AuthState {
  const AuthState({required this.stage, this.session, this.rememberedEmail});

  const AuthState.restoring()
    : stage = AuthStage.restoring,
      session = null,
      rememberedEmail = null;

  final AuthStage stage;
  final LoginResponse? session;
  final String? rememberedEmail;

  UserRole get role =>
      session == null ? UserRole.employee : UserRole.fromWire(session!.role);

  AuthState copyWith({
    AuthStage? stage,
    LoginResponse? session,
    String? rememberedEmail,
  }) => AuthState(
    stage: stage ?? this.stage,
    session: session ?? this.session,
    rememberedEmail: rememberedEmail ?? this.rememberedEmail,
  );
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repository, this._authEvents)
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
  StreamSubscription<void>? _unauthorizedSubscription;

  Future<void> _restore() async {
    final email = await _repository.rememberedEmail();
    final hasToken = await _repository.hasValidToken();

    if (!mounted) return;

    // A restored token cannot tell us whether mustChangePassword was set —
    // that only arrives with a login response. The first authenticated call
    // will 401 if the token is actually dead, and the interceptor handles it.
    state = AuthState(
      stage: hasToken ? AuthStage.signedIn : AuthStage.signedOut,
      rememberedEmail: email,
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

    if (!mounted) return;

    state = AuthState(
      stage: session.mustChangePassword
          ? AuthStage.mustChangePassword
          : AuthStage.signedIn,
      session: session,
      rememberedEmail: username,
    );
  }

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
  ),
);
