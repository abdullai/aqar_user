// lib/routes.dart
class AppRoutes {
  // ✅ Marketing Flow
  static const String ownerRequests = '/ownerRequests';
  static const String marketerDashboard = '/marketerDashboard';

  static const String createListingRequest = '/createListingRequest';
  static const String listingRequestStatus = '/listingRequestStatus';

  static const String ownerOffers = '/ownerOffers';
  static const String submitOffer = '/submitOffer';
  static const String submitPermits = '/submitPermits';

  /// التحقق من عقد (روابط مسماة / إشعارات / عميق).
  static const String contractVerify = '/contractVerify';

  // ✅ NEW: In-app notifications
  static const String inAppNotifications = '/inAppNotifications';

  /// مؤسسة: فريق + مراقبة (صاحب مكتب/مؤسسة/شركة)
  static const String orgTeamManagement = '/orgTeamManagement';
  static const String orgMonitoring = '/orgMonitoring';

  /// تحليل السوق (لقطة موحّدة من الخادم)
  static const String marketInsights = '/marketInsights';

  /// إدارة الأجهزة (حدّ جهازين).
  static const String deviceManagement = '/deviceManagement';

  /// محادثة عقد تسويق داخل لوحة المستخدم (عنوان الشريط الخارجي).
  static const String listingContractChat = '/dashboard/listing-contract-chat';
}