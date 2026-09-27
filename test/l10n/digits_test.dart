import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Latin digits throughout, decided 2026-09-27. Counts, order numbers and
/// dates all come out Latin; a digit typed into a translation is the one
/// place an Arabic-Indic numeral can still slip in beside them.
void main() {
  test('no translation writes Arabic-Indic digits', () {
    final arabicIndic = RegExp('[\u{0660}-\u{0669}\u{06F0}-\u{06F9}]');
    for (final path in ['lib/l10n/app_ar.arb', 'lib/l10n/app_en.arb']) {
      final entries =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      final offending = [
        for (final MapEntry(:key, :value) in entries.entries)
          if (!key.startsWith('@') &&
              value is String &&
              arabicIndic.hasMatch(value))
            key,
      ];
      expect(offending, isEmpty, reason: path);
    }
  });
}
