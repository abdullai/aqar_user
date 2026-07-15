/// نماذج باقات الاشتراك وحالة اشتراك المستخدم.
enum SubscriptionPlanId { free, basic, pro, business }

enum SubscriptionStatus { none, active, pending, expired, cancelled }

class SubscriptionPlan {
  final SubscriptionPlanId id;
  final String nameAr;
  final String nameEn;
  final String descriptionAr;
  final String descriptionEn;
  final double priceSar;
  final int durationDays;

  /// أقصى عدد إعلانات نشطة. null = غير محدود.
  final int? maxActiveListings;
  final bool featuredListings;
  final bool prioritySupport;
  final List<String> featuresAr;
  final List<String> featuresEn;
  final bool isPopular;

  const SubscriptionPlan({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.descriptionAr,
    required this.descriptionEn,
    required this.priceSar,
    required this.durationDays,
    required this.maxActiveListings,
    required this.featuredListings,
    required this.prioritySupport,
    required this.featuresAr,
    required this.featuresEn,
    this.isPopular = false,
  });

  String name(bool isAr) => isAr ? nameAr : nameEn;
  String description(bool isAr) => isAr ? descriptionAr : descriptionEn;
  List<String> features(bool isAr) => isAr ? featuresAr : featuresEn;

  bool get isFree => id == SubscriptionPlanId.free || priceSar <= 0;

  String priceLabel(bool isAr) {
    if (isFree) return isAr ? 'مجاني' : 'Free';
    final n = priceSar == priceSar.roundToDouble()
        ? priceSar.toInt().toString()
        : priceSar.toStringAsFixed(2);
    return isAr ? '$n ر.س / شهر' : 'SAR $n / month';
  }

  String limitLabel(bool isAr) {
    if (maxActiveListings == null) {
      return isAr ? 'إعلانات غير محدودة' : 'Unlimited listings';
    }
    return isAr
        ? 'حتى $maxActiveListings إعلانات نشطة'
        : 'Up to $maxActiveListings active listings';
  }

  static SubscriptionPlanId idFromString(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'basic':
        return SubscriptionPlanId.basic;
      case 'pro':
        return SubscriptionPlanId.pro;
      case 'business':
        return SubscriptionPlanId.business;
      case 'free':
      default:
        return SubscriptionPlanId.free;
    }
  }

  static String idToDb(SubscriptionPlanId id) {
    switch (id) {
      case SubscriptionPlanId.basic:
        return 'basic';
      case SubscriptionPlanId.pro:
        return 'pro';
      case SubscriptionPlanId.business:
        return 'business';
      case SubscriptionPlanId.free:
        return 'free';
    }
  }
}

class UserSubscription {
  final String userId;
  final SubscriptionPlanId planId;
  final SubscriptionStatus status;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final DateTime? requestedAt;

  const UserSubscription({
    required this.userId,
    required this.planId,
    required this.status,
    this.startedAt,
    this.expiresAt,
    this.requestedAt,
  });

  bool get isActive {
    if (status != SubscriptionStatus.active) return false;
    if (expiresAt == null) return true;
    return expiresAt!.isAfter(DateTime.now());
  }

  bool get isPending => status == SubscriptionStatus.pending;

  static SubscriptionStatus statusFromString(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'active':
        return SubscriptionStatus.active;
      case 'pending':
        return SubscriptionStatus.pending;
      case 'expired':
        return SubscriptionStatus.expired;
      case 'cancelled':
        return SubscriptionStatus.cancelled;
      default:
        return SubscriptionStatus.none;
    }
  }

  static String statusToDb(SubscriptionStatus s) {
    switch (s) {
      case SubscriptionStatus.active:
        return 'active';
      case SubscriptionStatus.pending:
        return 'pending';
      case SubscriptionStatus.expired:
        return 'expired';
      case SubscriptionStatus.cancelled:
        return 'cancelled';
      case SubscriptionStatus.none:
        return 'none';
    }
  }

  factory UserSubscription.free(String userId) => UserSubscription(
        userId: userId,
        planId: SubscriptionPlanId.free,
        status: SubscriptionStatus.active,
        startedAt: DateTime.now(),
      );
}
