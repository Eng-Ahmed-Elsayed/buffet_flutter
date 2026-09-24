/// Route paths, in one place so a typo cannot become a silent redirect loop.
abstract final class Routes {
  static const splash = '/';
  static const login = '/login';
  static const changePassword = '/change-password';
  static const lock = '/lock';

  /// The first-launch explainer, shown once per install before the first
  /// sign-in.
  static const onboarding = '/welcome';

  // Employee — the four tabs of the bottom-nav shell, in tab order.
  /// The employee landing tab: outstanding order, favourites, ordering.
  static const home = '/home';

  /// The full saved-orders list, as a tab. Home shows only the first few.
  static const favourites = '/favourites';
  static const myOrders = '/orders';

  /// Settings and account, as a tab. Staff reach the same screen at
  /// [settings], pushed from the queue.
  static const account = '/account';

  /// The shell's tabs. Employee-only: staff are bounced off every one.
  static const shellTabs = [home, favourites, myOrders, account];

  // Pushed above the shell (or the queue), reachable by both roles.
  static const catalogue = '/order';
  static const orderStatus = '/order/:orderId';

  /// The full saved-orders list when it is pushed — from the composer, which
  /// staff reach too and which has no tab bar to offer [favourites] from.
  static const favouritesList = '/favourites-list';
  static const materials = '/materials';
  static const notifications = '/notifications';
  static const settings = '/settings';

  // Staff
  static const queue = '/queue';

  static String orderStatusFor(int orderId) => '/order/$orderId';
}
