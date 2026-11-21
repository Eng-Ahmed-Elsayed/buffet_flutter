import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import '../shared/widgets/banners.dart';
import 'routes.dart';

/// Where an address the app does not have lands: a stale notification link,
/// a mistyped deep link.
///
/// The router's `errorPageBuilder`. Without it go_router 14, not finding
/// `package:flutter`'s `MaterialApp` since the move to `material_ui`, showed
/// its bare English error text with no Material around it.
///
/// Reached with `go`, so there is nothing beneath it: back, like the button,
/// goes to Home, which the redirect turns into the queue for staff.
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go(Routes.home);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.pageNotFoundTitle)),
        body: EmptyState(
          icon: Icons.link_off_outlined,
          title: l10n.pageNotFoundTitle,
          body: l10n.pageNotFoundBody,
          action: FilledButton(
            onPressed: () => context.go(Routes.home),
            child: Text(l10n.backToStart),
          ),
        ),
      ),
    );
  }
}
