/// Route paths, in one place so a typo cannot become a silent redirect loop.
abstract final class Routes {
  static const splash = '/';
  static const login = '/login';
  static const changePassword = '/change-password';
  static const lock = '/lock';

  // Employee
  static const catalogue = '/order';
  static const orderStatus = '/order/:orderId';
  static const myOrders = '/orders';
  static const materials = '/materials';
  static const notifications = '/notifications';
  static const settings = '/settings';

  // Staff
  static const queue = '/queue';

  static String orderStatusFor(int orderId) => '/order/$orderId';
}
