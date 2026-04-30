part of 'user_dashboard.dart';

// =========================
// STATE EXTENSIONS
// =========================

extension UserDashboardStateHelpers on _UserDashboardState {
  bool get isLoggedIn => _uid.isNotEmpty;

  bool get isGuestUser => _uid.isEmpty;

  bool get hasFavorites => _favoriteIds.isNotEmpty;

  bool get hasCart => _cart.isNotEmpty;

  bool get hasOffers => _offers.isNotEmpty;
}
