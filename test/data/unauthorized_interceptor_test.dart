import 'package:buffet_app/data/api/api_client.dart';
import 'package:buffet_app/data/local/secure_token_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers every request with a 401. [whileInFlight] runs before the answer
/// comes back — standing in for whatever else the app did meanwhile.
class _Unauthorized implements HttpClientAdapter {
  _Unauthorized({this.whileInFlight});

  final Future<void> Function()? whileInFlight;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await whileInFlight?.call();
    return ResponseBody.fromString('', 401);
  }

  @override
  void close({bool force = false}) {}
}

const _store = SecureTokenStore(FlutterSecureStorage());

Future<void> _storeToken(String token) => _store.write(
  token: token,
  expiresUtc: DateTime.now().toUtc().add(const Duration(days: 30)),
);

/// Sends one request through the app's real Dio, returning how many times the
/// session was ended.
Future<int> _send(HttpClientAdapter adapter) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final dio = container.read(dioProvider)..httpClientAdapter = adapter;
  var ended = 0;
  final sub = container
      .read(authEventsProvider)
      .onUnauthorized
      .listen((_) => ended++);
  addTearDown(sub.cancel);

  await expectLater(dio.get<void>('/orders'), throwsA(isA<DioException>()));
  await pumpEventQueue();
  return ended;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('§4.4 — a 401 ends the session it belongs to, and only that one', () {
    test('a 401 for the token held now clears it and signals', () async {
      await _storeToken('current');

      final ended = await _send(_Unauthorized());

      expect(ended, 1);
      expect(await _store.readToken(), isNull);
    });

    test('a 401 for a token already replaced leaves the new session', () async {
      await _storeToken('old');

      // The request goes out on the old token; before it returns, the user has
      // signed in again. Acting on this 401 used to wipe the NEW session.
      final ended = await _send(
        _Unauthorized(whileInFlight: () => _storeToken('new')),
      );

      expect(ended, 0);
      expect(await _store.readToken(), 'new');
    });

    test('a 401 when no token is held signals nothing twice', () async {
      // Already signed out by an earlier 401 in the same burst.
      final ended = await _send(_Unauthorized());

      expect(ended, 0);
    });
  });
}
