import 'package:supabase_flutter/supabase_flutter.dart';

/// استدعاء Edge Function [verify_sa_commercial_reg] (وزارة التجارة — تجريبي/جزئي).
class CommercialRegLookupResult {
  CommercialRegLookupResult({
    required this.ok,
    this.validForActive = false,
    this.entityNameAr,
    this.registryStatusAr,
    this.commercialRegNo,
    this.issueDate,
    this.activityAr,
    this.capital,
    this.error,
    this.source,
  });

  final bool ok;
  final bool validForActive;
  final String? entityNameAr;
  final String? registryStatusAr;
  final String? commercialRegNo;
  final String? issueDate;
  final String? activityAr;
  final double? capital;
  final String? error;
  final String? source;

  static CommercialRegLookupResult fromJson(Map<String, dynamic> j) {
    return CommercialRegLookupResult(
      ok: j['ok'] == true,
      validForActive: j['valid_for_active'] == true,
      entityNameAr: j['entity_name_ar']?.toString(),
      registryStatusAr: j['registry_status_ar']?.toString(),
      commercialRegNo: j['commercial_reg_no']?.toString(),
      issueDate: j['issue_date']?.toString(),
      activityAr: j['activity_ar']?.toString(),
      capital: j['capital'] is num ? (j['capital'] as num).toDouble() : null,
      error: j['error']?.toString(),
      source: j['source']?.toString(),
    );
  }
}

class CommercialRegService {
  CommercialRegService(this._sb);

  final SupabaseClient _sb;

  Future<CommercialRegLookupResult> lookupUnified(String raw) async {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) {
      return CommercialRegLookupResult(
        ok: false,
        error: 'short',
      );
    }
    try {
      final res = await _sb.functions.invoke(
        'verify_sa_commercial_reg',
        body: {'unified_reg_no': digits.substring(0, 10)},
      );
      if (res.data is Map) {
        return CommercialRegLookupResult.fromJson(
          Map<String, dynamic>.from(res.data as Map),
        );
      }
      return CommercialRegLookupResult(ok: false, error: 'bad_response');
    } catch (e) {
      return CommercialRegLookupResult(ok: false, error: e.toString());
    }
  }
}
