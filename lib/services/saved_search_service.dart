import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/search/arabic_search_intent.dart';
import '../models/property.dart';

class SavedPropertySearch {
  const SavedPropertySearch({
    required this.id,
    required this.queryText,
    required this.intent,
    required this.notify,
    this.lastMatchedAt,
  });

  final String id;
  final String queryText;
  final ArabicSearchIntent intent;
  final bool notify;
  final DateTime? lastMatchedAt;

  factory SavedPropertySearch.fromRow(Map<String, dynamic> r) {
    PropertyType? type;
    for (final t in PropertyType.values) {
      if (t.name == r['property_type']) type = t;
    }
    final kw = r['keywords'];
    return SavedPropertySearch(
      id: r['id'].toString(),
      queryText: (r['query_text'] ?? '').toString(),
      notify: r['notify'] != false,
      lastMatchedAt: DateTime.tryParse((r['last_matched_at'] ?? '').toString()),
      intent: ArabicSearchIntent(
        type: type,
        purpose: r['purpose']?.toString(),
        priceMin: (r['price_min'] as num?)?.toDouble(),
        priceMax: (r['price_max'] as num?)?.toDouble(),
        bedroomsMin: (r['bedrooms_min'] as num?)?.toInt(),
        keywords: kw is List ? kw.map((e) => e.toString()).toList() : const [],
        rawQuery: (r['query_text'] ?? '').toString(),
        nearWork: r['work_lat'] != null,
        workRadiusKm: (r['work_radius_km'] as num?)?.toDouble(),
      ),
    );
  }
}

/// حفظ عمليات البحث؛ مطابقتها مع الإعلانات الجديدة تتم في الخادم (trigger) وتصل كإشعار داخلي.
class SavedSearchService {
  SavedSearchService._();

  static SupabaseClient get _sb => Supabase.instance.client;

  /// يعيد null عند النجاح، أو رمز الخطأ: not_signed_in | limit | empty | failed.
  /// [workLat]/[workLng] تُرسل فقط بعد موافقة المستخدم، وتُقرَّب في الخادم إلى ≈1 كم.
  static Future<String?> save(
    ArabicSearchIntent intent,
    String query, {
    double? workLat,
    double? workLng,
    double? workRadiusKm,
  }) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return 'not_signed_in';
    final q = query.trim();
    if (q.isEmpty && !intent.isStructured) return 'empty';
    final withWork = workLat != null && workLng != null;
    try {
      await _sb.from('saved_property_searches').insert({
        'user_id': uid,
        'query_text': q,
        'property_type': intent.type?.name,
        'purpose': intent.purpose,
        'price_min': intent.priceMin,
        'price_max': intent.priceMax,
        'bedrooms_min': intent.bedroomsMin,
        'keywords': intent.isStructured ? intent.keywords : [q],
        if (withWork) 'work_lat': workLat,
        if (withWork) 'work_lng': workLng,
        if (withWork) 'work_radius_km': (workRadiusKm ?? 10).clamp(1, 100),
      });
      return null;
    } on PostgrestException catch (e) {
      if (e.message.contains('saved_search_limit_reached')) return 'limit';
      return 'failed';
    } catch (_) {
      return 'failed';
    }
  }

  static Future<List<SavedPropertySearch>> list() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return const [];
    try {
      final rows = await _sb
          .from('saved_property_searches')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(20);
      return (rows as List)
          .map((e) => SavedPropertySearch.fromRow(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<bool> setNotify(String id, bool value) async {
    try {
      await _sb
          .from('saved_property_searches')
          .update({'notify': value}).eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> delete(String id) async {
    try {
      await _sb.from('saved_property_searches').delete().eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }
}
