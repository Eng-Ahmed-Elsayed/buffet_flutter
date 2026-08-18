import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/preferences_store.dart';

/// The app's locale, Arabic by default.
///
/// Arabic is the primary locale — not merely the first supported one — so a
/// fresh install with no stored preference opens in Arabic regardless of the
/// device language. English is a deliberate choice the user makes, and it is
/// remembered.
///
/// The chosen locale is also what goes in the `Accept-Language` header, because
/// **error messages are localised server-side from that header**. Switching the
/// language in settings changes the language of server errors too.
class LocaleController extends StateNotifier<Locale> {
  LocaleController(this._prefs) : super(const Locale('ar')) {
    // Deliberately not awaited: the app starts in Arabic immediately and
    // switches only if a stored preference says otherwise. Blocking the first
    // frame on a keystore read to discover the default is already correct
    // would be a visible delay for no gain.
    unawaited(_restore());
  }

  final PreferencesStore _prefs;

  static const supported = [Locale('ar'), Locale('en')];

  Future<void> _restore() async {
    final code = await _prefs.readLanguageCode();
    if (code != null && supported.any((l) => l.languageCode == code)) {
      state = Locale(code);
    }
  }

  Future<void> setLocale(Locale locale) async {
    if (!supported.contains(locale)) return;
    state = locale;
    await _prefs.writeLanguageCode(locale.languageCode);
  }
}

final localeControllerProvider =
    StateNotifierProvider<LocaleController, Locale>(
      (ref) => LocaleController(ref.watch(preferencesStoreProvider)),
    );
