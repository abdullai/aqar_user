import '../../models/market_property_request_priority.dart';
import '../../models/market_property_request_row.dart';
import '../utils/geo_helper.dart';

/// ترتيب ظهور الطلبات المدفوعة/المستعجلة في الخلاصات.
///
/// - الطلبات **المدفوعة** (فوري / مستعجل / أولوية) تبقى دائماً فوق غير المدفوعة
///   والإعلانات في الخليط، حتى لو تاريخ إنشائها أحدث أو أقدم.
/// - داخل نافذة التعزيز الجغرافي: شارة ومدة متبقية (Chrome).
/// - عند إتمام الصفقة يُخفى من الرئيسية وينتقل لتبويب الصفقات (عبر صلاحيات العرض).
class InstantMarketRequestFeed {
  InstantMarketRequestFeed._();

  /// طلب فوري مدفوع داخل منطقة المعلن.
  static const int sameRegionBoostMs = 86400000 * 7; // 1 week

  /// طلب فوري مدفوع خارج المنطقة.
  static const int crossRegionBoostMs = 86400000 * 3; // 72h

  /// مستعجل داخل منطقة المعلن.
  static const int urgentSameRegionBoostMs = 86400000 * 7; // 1 week

  /// أولوية داخل منطقة المعلن.
  static const int prioritySameRegionBoostMs = 86400000 * 3; // 72h

  /// إزاحة ثابتة تضمن بقاء المدفوع فوق أي إعلان/طلب عادي زمنياً.
  static const int _paidPinFloorMs = 50 * 365 * 86400000; // ~50 سنة

  /// درجات مدفوعة (فوري / مستعجل / أولوية) — تُثبَّت أعلى الخلاصة دائماً.
  static bool isPaidPriorityPin(MarketPropertyRequestRow row) {
    switch (row.requestPriority) {
      case MarketPropertyRequestPriority.immediate:
      case MarketPropertyRequestPriority.urgent:
      case MarketPropertyRequestPriority.priority:
        return true;
      case MarketPropertyRequestPriority.standard:
      case MarketPropertyRequestPriority.flexible:
        return false;
    }
  }

  static Duration get sameRegionBoostDuration =>
      Duration(milliseconds: sameRegionBoostMs);

  static Duration get crossRegionBoostDuration =>
      Duration(milliseconds: crossRegionBoostMs);

  static Duration boostWindowFor(
    MarketPropertyRequestRow row, {
    required bool inRequestRegion,
  }) {
    switch (row.requestPriority) {
      case MarketPropertyRequestPriority.immediate:
        return inRequestRegion
            ? sameRegionBoostDuration
            : crossRegionBoostDuration;
      case MarketPropertyRequestPriority.urgent:
        return inRequestRegion
            ? const Duration(milliseconds: urgentSameRegionBoostMs)
            : Duration.zero;
      case MarketPropertyRequestPriority.priority:
        return inRequestRegion
            ? const Duration(milliseconds: prioritySameRegionBoostMs)
            : Duration.zero;
      case MarketPropertyRequestPriority.standard:
      case MarketPropertyRequestPriority.flexible:
        return Duration.zero;
    }
  }

  static bool isInAdvertiserRegion(
    MarketPropertyRequestRow row, {
    String? viewerRegion,
  }) {
    final viewer = (viewerRegion ?? '').trim();
    if (viewer.isEmpty) return false;
    final requestRegion = row.regionLabel;
    if (requestRegion.isNotEmpty && regionsMatch(viewer, requestRegion)) {
      return true;
    }
    return regionsMatch(viewer, row.city);
  }

  /// هل الطلب يظهر كـ «مدفوع / أولوية» بإطار مميز؟
  /// المدفوع (فوري/مستعجل/أولوية) يبقى مميزاً دائماً في الخلاصات.
  static bool showsPaidPriorityChrome(
    MarketPropertyRequestRow row, {
    String? viewerRegion,
    DateTime? now,
  }) {
    return isPaidPriorityPin(row);
  }

  static bool isBoostActive(
    MarketPropertyRequestRow row, {
    String? viewerRegion,
    DateTime? now,
  }) {
    final hasViewer = (viewerRegion ?? '').trim().isNotEmpty;
    // بدون منطقة مشاهِد (شارة البطاقة): نفترض منطقة المعلن حتى تظهر الشارة طوال المدة.
    final inRegion = !hasViewer ||
        isInAdvertiserRegion(row, viewerRegion: viewerRegion);
    final window = boostWindowFor(row, inRequestRegion: inRegion);
    if (window <= Duration.zero) return false;
    final clock = now ?? DateTime.now();
    final age = clock.difference(row.sortTime);
    if (age.isNegative) return true;
    return age <= window;
  }

  /// المدة المتبقية للتعزيز (للشارة).
  static Duration? boostRemaining(
    MarketPropertyRequestRow row, {
    String? viewerRegion,
    DateTime? now,
  }) {
    final hasViewer = (viewerRegion ?? '').trim().isNotEmpty;
    final inRegion = !hasViewer ||
        isInAdvertiserRegion(row, viewerRegion: viewerRegion);
    final window = boostWindowFor(row, inRequestRegion: inRegion);
    if (window <= Duration.zero) return null;
    final clock = now ?? DateTime.now();
    final left = window - clock.difference(row.sortTime);
    if (left.isNegative) return null;
    return left;
  }

  static String normalizeLocationToken(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static bool regionsMatch(String a, String b) {
    final na = normalizeLocationToken(a);
    final nb = normalizeLocationToken(b);
    if (na.isEmpty || nb.isEmpty) return false;
    if (na == nb) return true;
    if (na.contains(nb) || nb.contains(na)) return true;
    for (final part in na.split(' ')) {
      if (part.length >= 3 && nb.contains(part)) return true;
    }
    for (final part in nb.split(' ')) {
      if (part.length >= 3 && na.contains(part)) return true;
    }
    return false;
  }

  /// كلما كان الرقم أعلى ظهر الطلب أبكر في القائمة.
  static int sortEpochMs(
    MarketPropertyRequestRow row, {
    String? viewerRegion,
    DateTime? now,
  }) {
    final base = row.sortTime.millisecondsSinceEpoch;
    // المدفوع دائماً فوق غير المدفوع والإعلانات — بغض النظر عن تاريخ الطرح.
    if (isPaidPriorityPin(row)) {
      return _paidPinFloorMs +
          (row.requestPriority.feedRank * 86400000 * 30) +
          base;
    }
    final inRegion =
        isInAdvertiserRegion(row, viewerRegion: viewerRegion);
    final window = boostWindowFor(row, inRequestRegion: inRegion);
    if (window <= Duration.zero) {
      // مرن: تأخير خفيف؛ الباقي زمني عادي.
      if (row.requestPriority == MarketPropertyRequestPriority.flexible) {
        return base - (86400000 * 2);
      }
      return base;
    }

    final clock = now ?? DateTime.now();
    final ageMs = clock.difference(row.sortTime).inMilliseconds;
    if (ageMs < 0) return base + window.inMilliseconds;
    if (ageMs <= window.inMilliseconds) {
      return base + window.inMilliseconds;
    }
    return base;
  }

  static double? distanceKmTo(
    MarketPropertyRequestRow row, {
    double? viewerLat,
    double? viewerLng,
  }) {
    final lat = row.latitude;
    final lng = row.longitude;
    if (viewerLat == null ||
        viewerLng == null ||
        lat == null ||
        lng == null) {
      return null;
    }
    return GeoHelper.distanceKm(
      lat1: viewerLat,
      lon1: viewerLng,
      lat2: lat,
      lon2: lng,
    );
  }

  static int compare(
    MarketPropertyRequestRow a,
    MarketPropertyRequestRow b, {
    String? viewerRegion,
    DateTime? now,
    double? viewerLat,
    double? viewerLng,
  }) {
    final aPaid = isPaidPriorityPin(a);
    final bPaid = isPaidPriorityPin(b);
    if (aPaid != bPaid) return aPaid ? -1 : 1;

    final byRank =
        b.requestPriority.feedRank.compareTo(a.requestPriority.feedRank);
    if (byRank != 0) return byRank;

    final sa = sortEpochMs(a, viewerRegion: viewerRegion, now: now);
    final sb = sortEpochMs(b, viewerRegion: viewerRegion, now: now);
    final byBoost = sb.compareTo(sa);
    if (byBoost != 0) return byBoost;

    // نفس المدينة أولاً ثم الأقرب مسافةً.
    final viewer = (viewerRegion ?? '').trim();
    if (viewer.isNotEmpty) {
      final aSame = regionsMatch(a.regionLabel, viewer) ||
          regionsMatch(a.city, viewer);
      final bSame = regionsMatch(b.regionLabel, viewer) ||
          regionsMatch(b.city, viewer);
      if (aSame != bSame) return aSame ? -1 : 1;
    }

    final da = distanceKmTo(a, viewerLat: viewerLat, viewerLng: viewerLng);
    final db = distanceKmTo(b, viewerLat: viewerLat, viewerLng: viewerLng);
    if (da != null && db != null) {
      final byDist = da.compareTo(db);
      if (byDist != 0) return byDist;
    } else if (da != null) {
      return -1;
    } else if (db != null) {
      return 1;
    }

    return b.sortTime.compareTo(a.sortTime);
  }
}
