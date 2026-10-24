/// منطق نقي لبطاقات «صفحتي»: الترتيب (الأحدث أولاً) والتحديث المحلي الفوري.
class HubCardRows {
  HubCardRows._();

  static const List<String> _createdKeys = [
    'created_at',
    'request_created_at',
    'listing_request_created_at',
    'submitted_at',
    'updated_at',
  ];

  static const Set<String> deadOfferStatuses = {
    'withdrawn',
    'cancelled',
    'rejected',
    'owner_rejected',
    'declined',
  };

  static DateTime? createdAtOf(Map<String, dynamic> row) {
    for (final k in _createdKeys) {
      final v = row[k];
      if (v == null) continue;
      final d = v is DateTime ? v : DateTime.tryParse(v.toString());
      if (d != null) return d.toUtc();
    }
    return null;
  }

  /// ترتيب ثابت: الأحدث أولاً، والصفوف بلا تاريخ في النهاية بترتيبها الأصلي.
  static List<Map<String, dynamic>> newestFirst(
    Iterable<Map<String, dynamic>> rows,
  ) {
    final indexed = rows.toList().asMap().entries.toList();
    indexed.sort((a, b) {
      final da = createdAtOf(a.value);
      final db = createdAtOf(b.value);
      if (da == null && db == null) return a.key.compareTo(b.key);
      if (da == null) return 1;
      if (db == null) return -1;
      final c = db.compareTo(da);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
    return indexed.map((e) => e.value).toList();
  }

  /// يزيل العرض المرفوض من معاينة المالك فوراً قبل وصول إعادة التحميل.
  static List<Map<String, dynamic>> withOfferDeclined(
    List<Map<String, dynamic>> requests, {
    required String offerId,
    required String requestId,
  }) {
    return requests.map((r) {
      final rid = (r['request_id'] ?? r['id'] ?? '').toString().trim();
      if (rid != requestId) return r;
      final next = Map<String, dynamic>.from(r);
      final preview = next['_owner_pending_offers_preview'];
      if (preview is List) {
        next['_owner_pending_offers_preview'] = preview
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((e) => (e['id'] ?? '').toString().trim() != offerId)
            .toList();
      }
      final count = int.tryParse('${next['_owner_pending_offers_count']}') ?? 0;
      final left = count > 0 ? count - 1 : 0;
      next['_owner_pending_offers_count'] = left;
      if (left == 0) {
        next['_owner_has_repeat_pending_offer'] = false;
        for (final k in const ['status', 'workflow_stage']) {
          if ('${next[k]}'.trim().toLowerCase() == 'offers_received') {
            next[k] = 'waiting_marketers';
          }
        }
      }
      return next;
    }).toList();
  }

  /// Moves an accepted offer out of pending cards before the refresh returns.
  static List<Map<String, dynamic>> withOfferAccepted(
    List<Map<String, dynamic>> requests,
    String offerId,
  ) {
    final oid = offerId.trim();
    if (oid.isEmpty) return requests;
    return requests.map((row) {
      final preview = row['_owner_pending_offers_preview'];
      if (preview is! List) return row;
      final matches = preview.whereType<Map>().map(
            (e) => Map<String, dynamic>.from(e),
          );
      Map<String, dynamic>? accepted;
      for (final offer in matches) {
        if ((offer['id'] ?? '').toString().trim() == oid) {
          accepted = offer;
          break;
        }
      }
      if (accepted == null) return row;

      final next = Map<String, dynamic>.from(row)
        ..['selected_offer_id'] = oid
        ..['status'] = 'assigned'
        ..['workflow_stage'] = 'marketer_selected'
        ..['_owner_pending_offers_count'] = 0
        ..['_owner_pending_offers_preview'] = const <Map<String, dynamic>>[]
        ..['_owner_has_repeat_pending_offer'] = false;
      final marketerId = (accepted['marketer_id'] ?? '').toString().trim();
      if (marketerId.isNotEmpty) {
        next['selected_marketer_id'] = marketerId;
      }
      return next;
    }).toList();
  }

  static List<Map<String, dynamic>> withoutOfferId(
    List<Map<String, dynamic>> rows,
    String offerId,
  ) {
    return rows
        .where((r) => (r['id'] ?? '').toString().trim() != offerId)
        .toList();
  }
}
