import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/locale_controller.dart';
import '../../data/api/api_exception.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/banners.dart';
import '../../theme/dimens.dart';
import 'auth_controller.dart';

/// Serves both the forced first-run case and the voluntary one from settings.
///
/// In the forced case this screen **cannot be dismissed**: no back arrow, no
/// skip, and `PopScope` blocks the system back gesture. The token already
/// works, so a client that let the user past would let them order on the
/// shared seeded password (§5, rule 10).
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscure = true;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
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
          .changePassword(
            currentPassword: _currentController.text,
            newPassword: _newController.text,
            languageCode: locale.languageCode,
            networkErrorFallback: l10n.networkError,
          );
      // Only a 204 advances the stage; the router then redirects by role.
    } on ApiException catch (error) {
      // The server's 400 message is already in the user's language.
      if (mounted) setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isForced =
        ref.watch(authControllerProvider).stage == AuthStage.mustChangePassword;

    return PopScope(
      // The whole point of the forced case: the system back gesture must not
      // escape it either.
      canPop: !isForced,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.changePasswordTitle),
          // No back arrow in the forced case — an affordance that cannot work
          // should not be drawn.
          automaticallyImplyLeading: !isForced,
        ),
        body: SafeArea(
          child: AutofillGroup(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsetsDirectional.all(Dimens.space5),
                children: [
                  if (isForced) ...[
                    InlineBanner(
                      tone: BannerTone.warning,
                      title: l10n.mustChangePasswordTitle,
                      body: l10n.mustChangePasswordBody,
                    ),
                    const SizedBox(height: Dimens.space6),
                  ],

                  if (_errorMessage != null) ...[
                    InlineBanner(
                      tone: BannerTone.danger,
                      title: _errorMessage!,
                    ),
                    const SizedBox(height: Dimens.space4),
                  ],

                  TextFormField(
                    controller: _currentController,
                    decoration: InputDecoration(
                      labelText: l10n.currentPassword,
                    ),
                    obscureText: _obscure,
                    textInputAction: TextInputAction.next,
                    enabled: !_submitting,
                    validator: (value) =>
                        (value == null || value.isEmpty) ? '' : null,
                  ),
                  const SizedBox(height: Dimens.space4),

                  TextFormField(
                    controller: _newController,
                    decoration: InputDecoration(
                      labelText: l10n.newPassword,
                      helperText: l10n.passwordMinLength,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        tooltip: _obscure
                            ? l10n.showPassword
                            : l10n.hidePassword,
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    obscureText: _obscure,
                    // So the OS password manager offers to save the *new*
                    // password rather than the seeded one (§5.1).
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.next,
                    enabled: !_submitting,
                    // Validated locally for instant feedback; the server
                    // enforces the same minimum and its message wins on a 400.
                    validator: (value) =>
                        (value == null || value.length < 8) ? '' : null,
                  ),
                  const SizedBox(height: Dimens.space4),

                  TextFormField(
                    controller: _confirmController,
                    decoration: InputDecoration(
                      labelText: l10n.confirmPassword,
                    ),
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    enabled: !_submitting,
                    onFieldSubmitted: (_) => _submit(),
                    validator: (value) => value != _newController.text
                        ? l10n.passwordsDoNotMatch
                        : null,
                  ),
                  const SizedBox(height: Dimens.space6),

                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : Text(l10n.saveAndContinue),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
