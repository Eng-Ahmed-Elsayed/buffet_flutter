import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// What the user chose when asked to name a favourite.
///
/// Distinguishes "they dismissed the dialog" from "they accepted it without
/// typing a name" — the second is an ordinary choice, not a cancellation, and
/// collapsing both to a null string would make an unnamed save impossible.
class FavouriteNameChoice {
  const FavouriteNameChoice(this.name);

  /// Null means "name it after the drinks", which the server does — including
  /// the preparation, so "قهوة غامق" and "قهوة فرنساوي" stay distinguishable.
  final String? name;
}

/// Asks what to call a favourite, offering to name it after the drinks.
///
/// Returns null when the user backed out, and a [FavouriteNameChoice] when they
/// went ahead — whose [FavouriteNameChoice.name] is null for the blank case.
///
/// **The name is genuinely optional**, so the primary action stays enabled with
/// the field empty. A dialog that demanded a name before it would save would
/// turn a one-tap action into a typing task, and the server already writes a
/// better name than most people would.
Future<FavouriteNameChoice?> showFavouriteNameDialog(BuildContext context) =>
    showDialog<FavouriteNameChoice>(
      context: context,
      builder: (context) => const _FavouriteNameDialog(),
    );

class _FavouriteNameDialog extends StatefulWidget {
  const _FavouriteNameDialog();

  @override
  State<_FavouriteNameDialog> createState() => _FavouriteNameDialogState();
}

class _FavouriteNameDialogState extends State<_FavouriteNameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _accept() {
    final typed = _controller.text.trim();
    Navigator.of(context)
        .pop(FavouriteNameChoice(typed.isEmpty ? null : typed));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l10n.favouriteNameDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              labelText: l10n.favouriteNameOptional,
              hintText: l10n.favouriteNameHint,
            ),
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _accept(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        // Never disabled on an empty field: blank is a valid, ordinary choice.
        TextButton(onPressed: _accept, child: Text(l10n.save)),
      ],
    );
  }
}
