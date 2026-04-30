import 'dart:convert';

import 'market_property_request_priority.dart';

/// صف عام من [market_property_requests] للعرض في الرئيسية (طلبات السوق).
class MarketPropertyRequestRow {
  final String id;
  final String? requestPublicCode;
  final String title;
  final String? description;

  /// قيم متوقعة: purchase | rent
  final String purpose;

  /// كود نوع عقار (مثل villa, apartment, land) يطابق كاتالوج التطبيق حيث أمكن.
  final String propertyType;
  final String city;
  final List<String> districts;
  final double? budgetMin;
  final double? budgetMax;
  final double? areaMinM2;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String requesterId;
  final bool showRequesterName;
  final String? requesterPublicName;

  /// مسار في `property-images` (اختياري) لغلاف الطلب.
  final String? coverImageStoragePath;

  /// درجة الإلحاح (مرن … طلب فوري).
  final MarketPropertyRequestPriority requestPriority;

  /// حالة دورة حياة الطلب في الخادم (قد تكون فارغة في صفوف قديمة).
  final String status;
  final int editCount;
  final int maxEdits;
  final DateTime? deletionRequestedAt;
  final DateTime? completedAt;
  final String? selectedOfferId;

  /// تفاصيل إضافية من العمود `details_json` (مدة الإيجار، غرف، مرافق…).
  final Map<String, dynamic> details;

  /// صورة الملف الشخصي للطالب (تُدمج من استعلام منفصل عند التحميل).
  final String? requesterAvatarUrl;

  const MarketPropertyRequestRow({
    required this.id,
    this.requestPublicCode,
    required this.title,
    required this.description,
    required this.purpose,
    required this.propertyType,
    required this.city,
    required this.districts,
    required this.budgetMin,
    required this.budgetMax,
    required this.areaMinM2,
    required this.createdAt,
    required this.updatedAt,
    required this.requesterId,
    required this.showRequesterName,
    required this.requesterPublicName,
    this.coverImageStoragePath,
    this.requestPriority = MarketPropertyRequestPriority.standard,
    this.status = '',
    this.editCount = 0,
    this.maxEdits = 3,
    this.deletionRequestedAt,
    this.completedAt,
    this.selectedOfferId,
    this.details = const {},
    this.requesterAvatarUrl,
  });

  /// تاريخ إنشاء الطلب للعرض في الرئيسية: الأحدث إنشاءً أولاً.
  DateTime get sortTime =>
      createdAt ?? updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// خليط الرئيسية يعتمد على الإنشاء فقط حتى لا تقفز الطلبات القديمة عند تعديلها.
  DateTime get homeFeedTimelineSortAt => sortTime;

  double? get latitude =>
      _coordinateFromDetails('lat') ??
      _coordinateFromDetails('latitude') ??
      _coordinateFromNestedLocation('lat') ??
      _coordinateFromNestedLocation('latitude');

  double? get longitude =>
      _coordinateFromDetails('lng') ??
      _coordinateFromDetails('longitude') ??
      _coordinateFromNestedLocation('lng') ??
      _coordinateFromNestedLocation('longitude');

  double? _coordinateFromDetails(String key) => _dbl(details[key]);

  double? _coordinateFromNestedLocation(String key) {
    final raw = details['location'];
    if (raw is Map) {
      return _dbl(raw[key]);
    }
    return null;
  }

  static List<String> _districtsFromJson(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final dec = jsonDecode(raw);
        if (dec is List) {
          return dec
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList();
        }
      } catch (_) {}
    }
    return const [];
  }

  static double? _dbl(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim());
  }

  static Map<String, dynamic> _detailsFrom(dynamic raw) {
    if (raw == null) return const {};
    if (raw is Map) {
      return Map<String, dynamic>.from(
        raw.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is Map) {
          return Map<String, dynamic>.from(
            d.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
      } catch (_) {}
    }
    return const {};
  }

  factory MarketPropertyRequestRow.fromMap(Map<String, dynamic> m) {
    final av = (m['requester_avatar_url'] ?? '').toString().trim();
    return MarketPropertyRequestRow(
      id: (m['id'] ?? '').toString(),
      requestPublicCode: (m['request_public_code'] as String?)?.trim(),
      title: (m['title'] ?? '').toString().trim(),
      description: (m['description'] as String?)?.trim(),
      purpose: (m['purpose'] ?? '').toString().trim().toLowerCase(),
      propertyType: (m['property_type'] ?? '').toString().trim().toLowerCase(),
      city: (m['city'] ?? '').toString().trim(),
      districts: _districtsFromJson(m['districts']),
      budgetMin: _dbl(m['budget_min']),
      budgetMax: _dbl(m['budget_max']),
      areaMinM2: _dbl(m['area_min_m2']),
      createdAt: m['created_at'] != null
          ? DateTime.tryParse(m['created_at'].toString())
          : null,
      updatedAt: m['updated_at'] != null
          ? DateTime.tryParse(m['updated_at'].toString())
          : null,
      requesterId: (m['requester_id'] ?? '').toString(),
      showRequesterName: m['show_requester_name'] == true,
      requesterPublicName: (m['requester_public_name'] as String?)?.trim(),
      coverImageStoragePath: (m['cover_image_storage_path'] as String?)?.trim(),
      requestPriority:
          MarketPropertyRequestPriority.parse(m['request_priority']),
      status: (m['status'] ?? '').toString().trim().toLowerCase(),
      editCount: int.tryParse('${m['edit_count'] ?? 0}') ?? 0,
      maxEdits: int.tryParse('${m['max_edits'] ?? 3}') ?? 3,
      deletionRequestedAt: m['deletion_requested_at'] != null
          ? DateTime.tryParse(m['deletion_requested_at'].toString())
          : null,
      completedAt: m['completed_at'] != null
          ? DateTime.tryParse(m['completed_at'].toString())
          : null,
      selectedOfferId: (m['selected_offer_id'] as String?)?.trim(),
      details: _detailsFrom(m['details_json']),
      requesterAvatarUrl: av.isEmpty ? null : av,
    );
  }
}
