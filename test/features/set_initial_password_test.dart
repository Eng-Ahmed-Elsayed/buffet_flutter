import 'package:buffet_app/data/api/api_config.dart';
import 'package:buffet_app/data/local/preferences_store.dart';
import 'package:buffet_app/data/local/secure_token_store.dart';
import 'package:buffet_app/data/repositories/auth_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what was sent and answers with a canned response, so the real
/// repository — URL, body and all — is the thing under test.
class _RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString('', 204);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _RecordingAdapter adapter;
  late AuthRepository repository;

  setUp(() {
    adapter = _RecordingAdapter();
    repository = AuthRepository(
      dio: Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'))
        ..httpClientAdapter = adapter,
      tokenStore: _NullTokenStore(),
      preferences: _NullPreferences(),
    );
  });

  group('§5.2 — the forced path uses its own endpoint', () {
    test('posts to /auth/set-initial-password', () async {
      await repository.setInitialPassword(
        newPassword: 'a-new-password',
        languageCode: 'ar',
        networkErrorFallback: 'network',
      );

      expect(adapter.requests.single.path, ApiConfig.setInitialPassword);
    });

    test('sends ONLY the new password — never the current one', () async {
      await repository.setInitialPassword(
        newPassword: 'a-new-password',
        languageCode: 'ar',
        networkErrorFallback: 'network',
      );

      final body = adapter.requests.single.data as Map<String, dynamic>;
      // The whole point of the endpoint: the user proved the current password
      // by signing in seconds ago, so it is neither asked for nor sent.
      expect(body.keys, ['newPassword']);
      expect(body['newPassword'], 'a-new-password');
    });

    test('the voluntary path still sends both', () async {
      await repository.changePassword(
        currentPassword: 'old',
        newPassword: 'a-new-password',
        languageCode: 'ar',
        networkErrorFallback: 'network',
      );

      final request = adapter.requests.single;
      expect(request.path, ApiConfig.changePassword);
      final body = request.data as Map<String, dynamic>;
      expect(body['currentPassword'], 'old');
      expect(body['newPassword'], 'a-new-password');
    });

    test('carries Accept-Language so the 400 message is localised', () async {
      await repository.setInitialPassword(
        newPassword: 'a-new-password',
        languageCode: 'en',
        networkErrorFallback: 'network',
      );

      expect(adapter.requests.single.extra[ApiConfig.languageFlag], 'en');
    });
  });
}

/// The repository's collaborators are irrelevant to these assertions — this
/// endpoint touches neither the token nor any preference.
class _NullTokenStore implements SecureTokenStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NullPreferences implements PreferencesStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
