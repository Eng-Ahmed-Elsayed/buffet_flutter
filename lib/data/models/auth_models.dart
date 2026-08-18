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
  /// `/auth/change-password` returns `204` (§5).
  final bool mustChangePassword;
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
