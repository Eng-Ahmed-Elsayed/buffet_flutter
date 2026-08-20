import 'package:json_annotation/json_annotation.dart';

part 'auth_models.g.dart';

/// Mirrors `LoginRequest` in ApiContracts.cs.
@JsonSerializable(createFactory: false)
class LoginRequest {
  const LoginRequest({required this.username, required this.password});

  final String username;
  final String password;

  Map<String, dynamic> toJson() => _$LoginRequestToJson(this);
}

/// Mirrors `LoginResponse` in ApiContracts.cs.
///
/// The role is read from **this response**, not by decoding the JWT
/// client-side (§4.2).
@JsonSerializable(createToJson: false)
class LoginResponse {
  const LoginResponse({
    required this.token,
    required this.expiresUtc,
    required this.username,
    required this.displayName,
    required this.role,
    required this.department,
    required this.mustChangePassword,
    this.canOrderForGuests = false,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) =>
      _$LoginResponseFromJson(json);

  final String token;

  /// Tokens last 30 days and **there is no refresh endpoint** — when this
  /// passes, the user signs in again.
  final DateTime expiresUtc;

  final String username;
  final String displayName;

  /// `"Employee" | "Staff" | "Admin"`. Compared by name, as with order status.
  final String role;

  final String department;

  /// The token works even when this is true, so a careless client could skip
  /// the change screen and order anyway. Navigation must stay blocked until
  /// the password is changed (§5).
  final bool mustChangePassword;

  /// Whether this user may attach a guest's name to an order.
  ///
  /// **Authoritative only as of sign-in.** The server reads the privilege from
  /// the token's claims and the token lasts 30 days, so a grant or revocation
  /// made today does not reach an already-signed-in client until it gets a new
  /// token.
  ///
  /// Defaults to false so a server predating the field withholds the guest
  /// field rather than offering one every order would be rejected for.
  final bool canOrderForGuests;
}

/// Mirrors `SetInitialPasswordRequest` in ApiContracts.cs.
///
/// **Carries no current password on purpose.** The endpoint is reachable only
/// with a token whose `must_change_password` claim is set, minted by signing in
/// with the current password moments earlier — asking for it again is friction
/// with no security value.
///
/// Kept separate from [ChangePasswordRequest] rather than making that type's
/// current password optional, so a fault in the claim check cannot quietly turn
/// every password change into an unauthenticated one.
@JsonSerializable(createFactory: false)
class SetInitialPasswordRequest {
  const SetInitialPasswordRequest({required this.newPassword});

  final String newPassword;

  Map<String, dynamic> toJson() => _$SetInitialPasswordRequestToJson(this);
}

/// Mirrors `ChangePasswordRequest` in ApiContracts.cs.
@JsonSerializable(createFactory: false)
class ChangePasswordRequest {
  const ChangePasswordRequest({
    required this.currentPassword,
    required this.newPassword,
  });

  final String currentPassword;

  /// Server minimum is 8 characters. Validated locally for instant feedback,
  /// but the server's `400` message is what gets shown — it is already
  /// localised (§5.2).
  final String newPassword;

  Map<String, dynamic> toJson() => _$ChangePasswordRequestToJson(this);
}

/// The three roles the API issues. Parsed from [LoginResponse.role] by name.
enum UserRole {
  employee,
  staff,
  admin;

  /// Maps the wire value to the enum. Unknown roles fall back to [employee] —
  /// the least-privileged view — rather than throwing, so a new server-side
  /// role cannot lock a user out of the app entirely.
  static UserRole fromWire(String value) => switch (value) {
    'Staff' => UserRole.staff,
    'Admin' => UserRole.admin,
    _ => UserRole.employee,
  };

  /// `Staff` lands on the queue; everyone else lands on the catalogue.
  ///
  /// An `Admin` signing in gets the catalogue with a quiet note that admin work
  /// is on the web — there are deliberately no admin screens here (§5).
  bool get startsOnQueue => this == UserRole.staff;
}
