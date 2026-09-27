import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/locale_controller.dart';
import '../../data/api/api_config.dart';
import '../../data/api/api_exception.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/brand_backdrop.dart';
import '../../shared/widgets/brand_lockup.dart';
import '../../shared/widgets/button_spinner.dart';
import '../../shared/widgets/exit_confirmation.dart';
import '../../shared/widgets/field_label.dart';
import '../../shared/widgets/language_toggle.dart';
import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';
import '../../theme/motion.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  /// Hidden to start, with a toggle beside it: §5.1, a shared seeded password
  /// typed on a phone keyboard is easier to get right when it can be seen.
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final remembered = ref.read(authControllerProvider).rememberedEmail;
    if (remembered != null) _emailController.text = remembered;
    _emailController.addListener(_onEmailChanged);
  }

  /// Whether the field holds only a name, so the domain is shown after it.
  bool get _nameOnly => !_emailController.text.contains('@');
  late bool _showsDomain = _nameOnly;

  /// Isolated, or an Arabic line would carry the `@` to the far side.
  static final _domain = Formatters.isolate('@${ApiConfig.emailDomain}');

  void _onEmailChanged() {
    if (_showsDomain != _nameOnly) setState(() => _showsDomain = _nameOnly);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final l10n = AppLocalizations.of(context);
    final locale = ref.read(localeControllerProvider);

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(authControllerProvider.notifier)
          .signIn(
            username: ApiConfig.username(_emailController.text),
            password: _passwordController.text,
            languageCode: locale.languageCode,
            networkErrorFallback: l10n.networkError,
          );
      // On success the router redirects; this screen is disposed.
    } on ApiException catch (error) {
      // The server's message is already localised — show it as-is. It is
      // deliberately identical for a wrong password and a disabled account so
      // the endpoint cannot enumerate users; do not try to be more specific.
      if (mounted) setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// There is no self-service reset: no endpoint, and deliberately no email.
  /// Say who can reset it rather than offering a flow that cannot exist.
  Future<void> _explainForgotPassword() {
    final l10n = AppLocalizations.of(context);
    return showModalBottomSheet<void>(
      sheetAnimationStyle: Motion.sheet(context),
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            Dimens.gutter,
            0,
            Dimens.gutter,
            Dimens.space5,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.forgotPasswordTitle,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: Dimens.space2),
              Text(
                l10n.forgotPasswordBody,
                style: Theme.of(sheetContext).textTheme.bodyLarge,
              ),
              const SizedBox(height: Dimens.space5),
              FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: Text(l10n.gotIt),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final rtl = Directionality.of(context) == TextDirection.rtl;

    // The server's error came in the language it was asked in; after a
    // switch it would sit there in the other one. Cleared, the next attempt
    // answers in the new language.
    ref.listen<Locale>(localeControllerProvider, (previous, next) {
      if (previous != next && _errorMessage != null) {
        setState(() => _errorMessage = null);
      }
    });

    return ExitConfirmation(
      // Nothing sits beneath the login screen, so back would close the app
      // mid-sign-in — including on a typo the user was about to fix.
      child: Scaffold(
        body: BrandBackdrop(
          child: SafeArea(
            child: AutofillGroup(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: Dimens.gutter,
                    vertical: Dimens.space5,
                  ),
                  children: [
                    const Center(child: BrandLockup(width: Dimens.lockupEntry)),
                    const SizedBox(height: Dimens.space7),

                    Text(
                      l10n.welcomeBackTitle,
                      textAlign: TextAlign.center,
                      style: text.headlineMedium?.copyWith(
                        color: BrandColors.brand,
                      ),
                    ),
                    const SizedBox(height: Dimens.space1),
                    Text(
                      l10n.welcomeBackSubtitle,
                      textAlign: TextAlign.center,
                      style: text.bodyLarge?.copyWith(color: BrandColors.brand),
                    ),
                    const SizedBox(height: Dimens.space6),

                    // The session was cleared because the device's biometric
                    // enrolment changed. Say so: being dropped at a sign-in
                    // screen with no explanation reads as a bug rather than as
                    // the safeguard it is (§6).
                    if (ref
                        .watch(authControllerProvider)
                        .signedOutByEnrolmentChange) ...[
                      InlineBanner(
                        tone: BannerTone.info,
                        title: l10n.biometricsChangedTitle,
                        body: l10n.biometricsChangedBody,
                      ),
                      const SizedBox(height: Dimens.space4),
                    ],

                    // The 30-day token ran out, or the server rejected it. Said
                    // for the same reason as the enrolment-change notice above:
                    // this lands on somebody who did nothing wrong and was in
                    // the middle of something.
                    //
                    // Suppressed once a sign-in attempt has failed, so the two
                    // banners never stack — the newer message is the one that
                    // describes what just happened.
                    if (_errorMessage == null &&
                        ref.watch(sessionExpiredProvider)) ...[
                      InlineBanner(
                        tone: BannerTone.info,
                        title: l10n.sessionExpiredTitle,
                        body: l10n.sessionExpiredBody,
                      ),
                      const SizedBox(height: Dimens.space4),
                    ],

                    if (_errorMessage != null) ...[
                      InlineBanner(
                        tone: BannerTone.danger,
                        title: _errorMessage!,
                      ),
                      const SizedBox(height: Dimens.space4),
                    ],

                    // Label above the field, as the design draws it, and the
                    // field named by it for screen readers.
                    LabelledField(
                      label: l10n.email,
                      child: TextFormField(
                        controller: _emailController,
                        // An address reads left to right in either language,
                        // and the domain sits on its right: at the end in
                        // English, at the start (beside the icon) in Arabic.
                        textDirection: TextDirection.ltr,
                        // Against the domain, so the two read as one address
                        // rather than with the field's width between them.
                        textAlign: rtl ? TextAlign.end : TextAlign.start,
                        decoration: InputDecoration(
                          hintText: l10n.emailHint,
                          prefixIcon: const Icon(Icons.mail_outline),
                          prefixText: _showsDomain && rtl ? _domain : null,
                          suffixText: _showsDomain && !rtl ? _domain : null,
                        ),
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        autocorrect: false,
                        enabled: !_submitting,
                        // Words, not a red border alone (§2.5).
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? l10n.emailRequired
                            : null,
                      ),
                    ),
                    // Short: the "Forgot?" target below reaches up into this
                    // gap, so the two labels start the same distance apart
                    // as the design draws them.
                    const SizedBox(height: Dimens.space1),

                    LabelledField(
                      label: l10n.password,
                      trailing: TextButton(
                        style: TextButton.styleFrom(
                          alignment: AlignmentDirectional.bottomEnd,
                          padding: const EdgeInsetsDirectional.symmetric(
                            horizontal: Dimens.space2,
                          ),
                          minimumSize: const Size(
                            Dimens.minTarget,
                            Dimens.minTarget,
                          ),
                        ),
                        onPressed: _explainForgotPassword,
                        child: Text(l10n.forgotPassword),
                      ),
                      child: TextFormField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          hintText: l10n.passwordHint,
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            tooltip: _obscurePassword
                                ? l10n.showPassword
                                : l10n.hidePassword,
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        obscureText: _obscurePassword,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        enabled: !_submitting,
                        onFieldSubmitted: (_) => _submit(),
                        validator: (value) => (value == null || value.isEmpty)
                            ? l10n.passwordRequired
                            : null,
                      ),
                    ),
                    const SizedBox(height: Dimens.space6),

                    // Disabled only while the request is in flight, and the
                    // spinner in its place says why.
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? ButtonSpinner(label: l10n.pleaseWait)
                          : Text(l10n.signIn),
                    ),

                    const SizedBox(height: Dimens.space6),

                    // The language switch belongs HERE as well as in settings,
                    // because settings is behind the sign-in this screen gates.
                    // The app opens in Arabic by default regardless of the
                    // device language (§2.4), so an English-speaking user with
                    // no session had no way to read the screen they were being
                    // asked to sign in on — the one screen where being unable
                    // to change the language is unrecoverable rather than
                    // annoying.
                    //
                    // It also sets `Accept-Language`, so it changes the
                    // language of the sign-in errors the server returns, which
                    // is the other half of why it has to be reachable before
                    // signing in.
                    const LanguageToggle(),

                    const SizedBox(height: Dimens.space5),
                    Center(
                      child: Text(
                        l10n.adminWorkOnWeb,
                        textAlign: TextAlign.center,
                        style: text.labelSmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
