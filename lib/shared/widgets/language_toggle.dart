import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/locale_controller.dart';
import '../../l10n/app_localizations.dart';

/// The language choice, on the screens that sit in front of settings: sign-in
/// and the first-launch explainer.
///
/// A compact segmented control rather than the radio list settings uses: this
/// is a secondary affordance under a sign-in form, and a two-row radio group
/// would carry more visual weight than the password field above it.
///
/// Each option is labelled in **its own language** in both locales, exactly as
/// in settings — somebody who has landed in a language they cannot read still
/// has to be able to find their way out.
class LanguageToggle extends ConsumerWidget {
  const LanguageToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeControllerProvider);
    final l10n = AppLocalizations.of(context);

    return Center(
      child: SegmentedButton<Locale>(
        segments: [
          for (final option in LocaleController.supported)
            ButtonSegment<Locale>(
              value: option,
              label: Text(
                option.languageCode == 'ar'
                    ? l10n.languageArabic
                    : l10n.languageEnglish,
              ),
            ),
        ],
        selected: {locale},
        showSelectedIcon: false,
        onSelectionChanged: (selected) => unawaited(
          ref.read(localeControllerProvider.notifier).setLocale(selected.first),
        ),
      ),
    );
  }
}
