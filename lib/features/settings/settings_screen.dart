import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/locale_controller.dart';
import '../../app/routes.dart';
import '../../data/local/app_version.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/section_header.dart';
import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';
import '../auth/auth_controller.dart';
import 'biometric_tile.dart';

/// The account: who is signed in, what they hold, and how the app behaves.
///
/// For an employee this is the **Account** tab of the shell (Figma
/// "Settings"), and it also carries the way into their own materials. Staff
/// reach the same screen pushed from the queue, without that row.
///
/// Laid out as the design's stacked rows. What the design had and we do not —
/// order history (the Orders tab), payment, help, share — is left out rather
/// than drawn as rows that lead nowhere (docs/figma-redesign.md).
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
    final isStaff = auth.role.startsOnQueue;

    return Scaffold(
      // The tab is "Account"; the same screen pushed from the queue is what
      // staff know as settings.
      appBar: AppBar(title: Text(isStaff ? l10n.settings : l10n.navAccount)),
      body: ListView(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: Dimens.gutter,
          vertical: Dimens.space5,
        ),
        children: [
          // Reads displayName/department rather than session, so the header
          // survives a relaunch: a session restored from storage has no login
          // response, and keying off `session != null` made the user's own
          // name disappear on every launch after the first.
          if (auth.displayName != null) ...[
            _AccountHeader(
              displayName: auth.displayName!,
              department: auth.department ?? '',
            ),
            const SizedBox(height: Dimens.space5),
          ],

          // My materials moved here from a home tile when the shell arrived:
          // it is part of what the account holds, and Home is for ordering.
          // Employees only — staff never had a materials screen in the app.
          if (!isStaff) ...[
            _AccountRow(
              icon: Icons.inventory_2_outlined,
              label: l10n.accountMyMaterials,
              onTap: () => context.push(Routes.materials),
            ),
            const SizedBox(height: Dimens.space3),
          ],

          _AccountRow(
            icon: Icons.password_outlined,
            label: l10n.changePasswordTitle,
            onTap: () => context.push(Routes.password),
          ),
          const SizedBox(height: Dimens.space3),

          // Offered here as well as once after sign-in, so a user who declined
          // the first time can still find it (§6). Draws its own card, and
          // nothing at all on a device that cannot use it.
          const BiometricTile(),

          const SizedBox(height: Dimens.space3),
          SectionHeader(label: l10n.language),
          const SizedBox(height: Dimens.space2),

          // Each option is labelled in its OWN language, in both locales —
          // someone who has accidentally switched to a language they cannot
          // read still needs to find their way back.
          AppCard(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Dimens.space2,
            ),
            // Its own ink layer: a ListTile paints its ripple on the nearest
            // Material, which the card's filled background would hide.
            child: Material(
              type: MaterialType.transparency,
              child: RadioGroup<Locale>(
                groupValue: locale,
                onChanged: (value) {
                  if (value != null) {
                    unawaited(
                      ref
                          .read(localeControllerProvider.notifier)
                          .setLocale(value),
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
            ),
          ),

          const SizedBox(height: Dimens.space5),

          // The design's Logout row, in danger red. It is a row like the
          // others, with no chevron: it goes nowhere, it ends the session.
          _AccountRow(
            icon: Icons.logout,
            label: l10n.signOut,
            tone: BrandColors.danger,
            onTap: () => unawaited(_confirmSignOut(context, ref)),
          ),

          const SizedBox(height: Dimens.space6),
          Center(
            child: Text(
              l10n.adminWorkOnWeb,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          // The design's version line, in `muted` (labelSmall) rather than
          // its 1.64:1 tint. Nothing at all until the platform answers.
          if (ref.watch(appVersionProvider).valueOrNull case final version?)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: Dimens.space2),
              child: Text(
                l10n.appVersion(Formatters.isolate(version)),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// The design's name block: the name large in the primary blue, and the
/// department beneath it where the design had "Member since", which the API
/// does not carry.
class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.displayName, required this.department});

  final String displayName;
  final String department;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          displayName,
          style: text.headlineSmall?.copyWith(color: BrandColors.brand),
        ),
        if (department.trim().isNotEmpty)
          Text(
            department,
            style: text.bodyMedium?.copyWith(color: BrandColors.ink),
          ),
      ],
    );
  }
}

/// One of the design's stacked rows: an icon, a label, and a chevron when it
/// leads somewhere. [tone] recolours icon and label together — only ever
/// danger, for sign-out.
class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tone,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final leadsSomewhere = tone == null;

    // AppCard with onTap already reads as a button.
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: tone ?? BrandColors.iconBlue),
          const SizedBox(width: Dimens.space3),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: tone ?? BrandColors.brandSecondary),
            ),
          ),
          if (leadsSomewhere)
            const Icon(Icons.chevron_right, color: BrandColors.brand),
        ],
      ),
    );
  }
}

/// Signing out costs the password to get back in, and the row sits at the
/// foot of a list a thumb scrolls through, so it asks first. The router
/// redirects to login as soon as the stage changes; nothing here waits on it.
Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.signOutConfirmTitle),
      content: Text(l10n.signOutConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: BrandColors.danger),
          child: Text(l10n.signOut),
        ),
      ],
    ),
  );
  if ((confirmed ?? false) && context.mounted) {
    unawaited(ref.read(authControllerProvider.notifier).signOut());
  }
}
