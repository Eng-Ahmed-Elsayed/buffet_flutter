import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/locale_controller.dart';
import '../../data/api/api_exception.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/banners.dart';
import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';
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

  /// §5.1: hiding a shared seeded password typed on a phone keyboard helps
  /// nobody. Starts revealed on the first sign-in, hidden once we know the
  /// user has their own password.
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final remembered = ref.read(authControllerProvider).rememberedEmail;
    if (remembered != null) _emailController.text = remembered;
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
            username: _emailController.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: BrandColors.surface,
      body: SafeArea(
        child: AutofillGroup(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: Dimens.space5,
                vertical: Dimens.space6,
              ),
              children: [
                // The lockup is Latin-only and reads left-to-right. It stays
                // LTR inside the RTL layout rather than being mirrored (§2.1).
                Center(
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Image.asset(
                      'assets/images/logo-defi.png',
                      width: 208,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: Dimens.space7),

                Text(
                  l10n.signInTitle,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text(
                  l10n.appTitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: Dimens.space6),

                if (_errorMessage != null) ...[
                  InlineBanner(tone: BannerTone.danger, title: _errorMessage!),
                  const SizedBox(height: Dimens.space4),
                ],

                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(labelText: l10n.email),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  autocorrect: false,
                  enabled: !_submitting,
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? '' : null,
                ),
                const SizedBox(height: Dimens.space4),

                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: l10n.password,
                    hintText: l10n.passwordHint,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      tooltip: _obscurePassword
                          ? l10n.showPassword
                          : l10n.hidePassword,
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  obscureText: _obscurePassword,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  enabled: !_submitting,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (value) =>
                      (value == null || value.isEmpty) ? '' : null,
                ),
                const SizedBox(height: Dimens.space6),

                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: BrandColors.surface,
                          ),
                        )
                      : Text(l10n.signIn),
                ),

                const SizedBox(height: Dimens.space7),
                Center(
                  child: Text(
                    l10n.adminWorkOnWeb,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
