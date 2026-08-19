import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/locale_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';
import '../auth/auth_controller.dart';
import 'biometric_tile.dart';

/// Settings: the language switch and sign-out.
///
/// The language choice drives both the UI strings and the `Accept-Language`
/// header, so switching it also changes the language of server-side error
/// messages (§4).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(localeControllerProvider);
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        padding: const EdgeInsetsDirectional.all(Dimens.space4),
        children: [
          if (auth.session != null) ...[
            _AccountCard(
              displayName: auth.session!.displayName,
              department: auth.session!.department,
            ),
            const SizedBox(height: Dimens.space5),
          ],

          Text(l10n.language, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: Dimens.space2),

          // Each option is labelled in its OWN language, in both locales —
          // someone who has accidentally switched to a language they cannot
          // read still needs to find their way back.
          RadioGroup<Locale>(
            groupValue: locale,
            onChanged: (value) {
              if (value != null) {
                unawaited(
                  ref.read(localeControllerProvider.notifier).setLocale(value),
                );
              }
            },
            child: Column(
              children: [
                for (final option in LocaleController.supported)
                  RadioListTile<Locale>(
                    value: option,
                    title: Text(
                      option.languageCode == 'ar'
                          ? l10n.languageArabic
                          : l10n.languageEnglish,
                    ),
                    activeColor: BrandColors.brand,
                    contentPadding: EdgeInsetsDirectional.zero,
                  ),
              ],
            ),
          ),

          const SizedBox(height: Dimens.space5),
          const Divider(),
          const SizedBox(height: Dimens.space2),

          // Offered here as well as once after sign-in, so a user who declined
          // the first time can still find it (§6).
          const BiometricTile(),

          const SizedBox(height: Dimens.space5),
          const Divider(),
          const SizedBox(height: Dimens.space4),

          OutlinedButton.icon(
            // The router redirects to login as soon as the stage changes, so
            // there is nothing here to await.
            onPressed: () =>
                unawaited(ref.read(authControllerProvider.notifier).signOut()),
            style: OutlinedButton.styleFrom(
              foregroundColor: BrandColors.danger,
              side: const BorderSide(color: BrandColors.danger),
            ),
            icon: const Icon(Icons.logout),
            label: Text(l10n.signOut),
          ),

          const SizedBox(height: Dimens.space5),
          Center(
            child: Text(
              l10n.adminWorkOnWeb,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.displayName, required this.department});

  final String displayName;
  final String department;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.all(Dimens.space4),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        border: Border.all(color: BrandColors.brandLight),
        borderRadius: BorderRadius.circular(Dimens.radiusLg),
      ),
      child: Row(
        children: [
          // The mark alone: direction-neutral, unlike the Latin lockup.
          Image.asset(
            'assets/images/logo-defi-mark.png',
            width: 40,
            height: 40,
          ),
          const SizedBox(width: Dimens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(department, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
