import 'package:buffet_app/data/local/preferences_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('the remembered delivery location goes with the account', () async {
    const prefs = PreferencesStore(FlutterSecureStorage());
    await prefs.writeLocationId(41);
    expect(await prefs.readLocationId(), 41);

    // The next user of this device does not inherit the previous one's desk.
    await prefs.clearAccountPreferences();
    expect(await prefs.readLocationId(), isNull);
  });

  test('choosing no location forgets the stored one', () async {
    const prefs = PreferencesStore(FlutterSecureStorage());
    await prefs.writeLocationId(41);
    await prefs.writeLocationId(null);
    expect(await prefs.readLocationId(), isNull);
  });
}
