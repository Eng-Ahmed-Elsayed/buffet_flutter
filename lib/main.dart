import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Loads the locale data `DateFormat` needs. Without it, formatting a
  // timestamp for a named locale throws LocaleDataException at runtime — and
  // every screen in this app renders a converted UTC time.
  await initializeDateFormatting();

  runApp(const ProviderScope(child: BuffetApp()));
}
