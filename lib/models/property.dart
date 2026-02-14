// lib/models/property.dart

enum PropertyType { villa, apartment, land }

class Property {
  final String id;
  final String ownerId;

  /// ✅ اسم المعلن (من users_profiles أو properties.username)
  final String? ownerUsername;

  final String title;
  final PropertyType type;
  final String description;

  /// ✅ city/merged location (لأن DB عندك لا يوجد location)
  final String location;

  final double area; // m2
  final double price; // SAR

  final bool isAuction;
  final double? currentBid;

  final List<String> images; // urls

  final int views;
  final DateTime createdAt;

  /// ✅ إحداثيات
  final double? latitude;
  final double? longitude;

  const Property({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.type,
    required this.description,
    required this.location,
    required this.area,
    required this.price,
    required this.isAuction,
    this.currentBid,
    required this.images,
    required this.views,
    required this.createdAt,
    this.ownerUsername,
    this.latitude,
    this.longitude,
  });

  // =========================
  // Helpers for filters UI
  // =========================

  /// نص موحّد للمدينة/الموقع (للـ search/filters)
  String get locationLower => location.trim().toLowerCase();

  /// سلاج بسيط للمدينة لاستخدامه في _cityFilter
  /// مثال: "الرياض" -> "riyadh" (إذا كانت DB بالعربي سيبقى عربي)
  /// المهم أن الفلتر يقارن بـ contains على النص.
  String get citySlug {
    final s = locationLower;
    if (s.isEmpty) return 'unknown';

    // تطبيع بسيط شائع
    if (s.contains('الرياض') || s.contains('riyadh')) return 'riyadh';
    if (s.contains('جدة') || s.contains('jeddah')) return 'jeddah';
    if (s.contains('مكة') || s.contains('makkah') || s.contains('mecca')) return 'makkah';
    if (s.contains('الدمام') || s.contains('dammam')) return 'dammam';
    if (s.contains('الخبر') || s.contains('khobar')) return 'khobar';
    if (s.contains('المدينة') || s.contains('madinah') || s.contains('medina')) return 'madinah';

    // fallback: أول كلمة
    final parts = s.split(RegExp(r'\s+')).where((e) => e.trim().isNotEmpty).toList();
    return parts.isEmpty ? 'unknown' : parts.first;
  }

  // =========================
  // Parsing helpers (optional)
  // =========================

  static PropertyType parseType(String? s) {
    final v = (s ?? '').trim().toLowerCase();
    switch (v) {
      case 'apartment':
        return PropertyType.apartment;
      case 'land':
        return PropertyType.land;
      case 'villa':
      default:
        return PropertyType.villa;
    }
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static double _toDouble0(dynamic v, [double fallback = 0.0]) {
    return _toDouble(v) ?? fallback;
  }

  static int _toInt0(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  static DateTime _parseDt(dynamic v) {
    if (v is DateTime) return v.toLocal();
    if (v is String) return DateTime.tryParse(v)?.toLocal() ?? DateTime.now();
    return DateTime.now();
  }

  /// إذا حبيت لاحقاً تبني Property مباشرة من صف Supabase
  static Property fromDbRow(
    Map row, {
    required List<String> imageUrls,
    String? ownerUsername,
  }) {
    final typeStr = (row['type'] as String?) ?? 'villa';

    return Property(
      id: (row['id'] as String?) ?? '',
      ownerId: (row['owner_id'] as String?) ?? '',
      ownerUsername: ownerUsername,
      title: (row['title'] as String?) ?? '',
      type: parseType(typeStr),
      description: (row['description'] as String?) ?? '',
      location: ((row['city'] as String?) ?? '').trim(),
      area: _toDouble0(row['area']),
      price: _toDouble0(row['price']),
      isAuction: (row['is_auction'] as bool?) ?? false,
      currentBid: _toDouble(row['current_bid']),
      images: imageUrls,
      views: _toInt0(row['views']),
      createdAt: _parseDt(row['created_at']),
      latitude: _toDouble(row['latitude']),
      longitude: _toDouble(row['longitude']),
    );
  }
}
