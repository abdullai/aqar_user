import 'package:supabase_flutter/supabase_flutter.dart';

/// فحص رقم الصك داخل التطبيق أثناء التطوير.
///
/// ربط مستقبلي — إدارة المشروع:
/// - [futureAuthorityHook]: التحقق الحكومي من رقم الصك وبياناته (الهيئة/الصكوك).
/// - [futureOpsDeskHook]: تنبيه مكتب العمليات عند تكرار أو تعارض صفقة قائمة.
///
/// [verifyWithAuthority] و [notifyProjectOps] يعيدان null/no-op حتى تتوفر الاعتمادات.
abstract final class DeedNumberIntegrity {
  static const futureAuthorityHook = 'rega_deed_verify';
  static const futureOpsDeskHook = 'project_ops_deed_conflict';

  static const saleLikePurposes = {'sale', 'auction', 'investment'};

  static const goneStatuses = {
    'archived',
    'deleted',
    'inactive',
    'closed',
    'hidden',
    'rejected',
    'cancelled',
    'sold',
    'completed',
    'withdrawn',
  };

  static String normalize(String raw) =>
      raw.replaceAll(RegExp(r'\s+'), '').trim();

  static bool isSaleLikePurpose(String? purpose) {
    final p = (purpose ?? '').toLowerCase().trim();
    return saleLikePurposes.contains(p);
  }

  static bool stillListedForSaleLike(Map<String, dynamic> row) {
    if (row['deleted_by_user'] == true || row['delete_approved'] == true) {
      return false;
    }
    final st = (row['status'] ?? '').toString().toLowerCase();
    if (goneStatuses.contains(st)) return false;
    var purp = (row['purpose'] ?? 'sale').toString().toLowerCase();
    if (purp.isEmpty) purp = 'sale';
    if (row['is_auction'] == true) purp = 'auction';
    return saleLikePurposes.contains(purp);
  }

  /// فحص محلي مقابل إعلانات المنصة — ليس تحققاً حكومياً.
  static Future<DeedDuplicateMatch?> findActiveSaleLikeDuplicate({
    required SupabaseClient client,
    required String deedNumber,
    String? excludePropertyId,
  }) async {
    final deed = normalize(deedNumber);
    if (deed.isEmpty) return null;
    try {
      final exclude = excludePropertyId?.trim() ?? '';
      final filter = client
          .from('properties')
          .select(
            'id,title,status,purpose,is_auction,deleted_by_user,delete_approved',
          )
          .eq('deed_number', deed);
      final res = await (exclude.isEmpty
              ? filter
              : filter.neq('id', exclude))
          .limit(40);
      for (final raw in (res as List)) {
        final row = Map<String, dynamic>.from(raw as Map);
        if (!stillListedForSaleLike(row)) continue;
        return DeedDuplicateMatch(
          id: (row['id'] ?? '').toString(),
          title: (row['title'] ?? '').toString().trim(),
        );
      }
    } catch (_) {}
    return null;
  }

  /// نقطة ربط حكومية مستقبلية — تُترك فارغة في التطوير.
  static Future<DeedAuthorityVerdict?> verifyWithAuthority({
    required String deedNumber,
  }) async {
    assert(futureAuthorityHook.isNotEmpty);
    return null;
  }

  /// نقطة ربط مكتب إدارة المشروع — no-op حتى يُفعَّل التنبيه التشغيلي.
  static Future<void> notifyProjectOps({
    required String deedNumber,
    required String reason,
  }) async {
    assert(futureOpsDeskHook.isNotEmpty);
    return;
  }
}

class DeedDuplicateMatch {
  const DeedDuplicateMatch({required this.id, required this.title});

  final String id;
  final String title;
}

class DeedAuthorityVerdict {
  const DeedAuthorityVerdict({
    required this.ok,
    this.summaryAr = '',
    this.summaryEn = '',
  });

  final bool ok;
  final String summaryAr;
  final String summaryEn;
}
