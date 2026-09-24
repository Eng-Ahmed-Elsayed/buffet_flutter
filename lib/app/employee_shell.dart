import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../shared/widgets/exit_confirmation.dart';
import '../theme/brand_colors.dart';

/// The employee's bottom-nav shell: Home · Favourites · Orders · Account.
///
/// The four tabs are the destinations a user moves *between*. Everything that
/// is a step in a task — the composer, an order's status, notifications, my
/// materials — is pushed above the shell on the root navigator, so the bar
/// gets out of the way inside a flow.
///
/// **Back is handled here, not on the tabs.** A tab's root has nothing beneath
/// it in its own navigator, so go_router hands the gesture straight to this
/// page. From any tab but Home it returns to Home; on Home it asks before
/// closing the app. A guard on a tab's own screen would never be asked.
class EmployeeShell extends StatelessWidget {
  const EmployeeShell({required this.shell, this.onExit, super.key});

  final StatefulNavigationShell shell;

  /// Passed through to [ExitConfirmation]; overridden in tests.
  final Future<void> Function()? onExit;

  static const _homeIndex = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return ExitConfirmation(
      onExit: onExit,
      interceptBack: () {
        if (shell.currentIndex == _homeIndex) return false;
        shell.goBranch(_homeIndex);
        return true;
      },
      child: Scaffold(
        body: shell,
        bottomNavigationBar: DecoratedBox(
          // The design's bar is white with a hairline above it, the mirror of
          // the top bar's edge.
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: BrandColors.brandLight)),
          ),
          child: NavigationBar(
            selectedIndex: shell.currentIndex,
            // Tapping the tab you are on returns it to its root, as every
            // platform's tab bar does.
            onDestinationSelected: (index) => shell.goBranch(
              index,
              initialLocation: index == shell.currentIndex,
            ),
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: const Icon(Icons.home),
                label: l10n.navHome,
              ),
              NavigationDestination(
                icon: const Icon(Icons.favorite_border),
                selectedIcon: const Icon(Icons.favorite),
                label: l10n.navFavourites,
              ),
              NavigationDestination(
                icon: const Icon(Icons.receipt_long_outlined),
                selectedIcon: const Icon(Icons.receipt_long),
                label: l10n.navOrders,
              ),
              NavigationDestination(
                icon: const Icon(Icons.account_circle_outlined),
                selectedIcon: const Icon(Icons.account_circle),
                label: l10n.navAccount,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
