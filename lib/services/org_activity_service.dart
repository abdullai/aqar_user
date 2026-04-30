import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// تسجيل نشاط المؤسسة (لا يعطل الواجهة عند الفشل).
class OrgActivityService {
  OrgActivityService._();

  static final _sb = Supabase.instance.client;

  static Future<void> _log(
    String action, {
    String? entityType,
    String? entityId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final raw = await _sb.rpc('my_org_context');
      if (raw is! Map) return;
      final orgId = raw['org_id'];
      if (orgId == null) return;
      await _sb.rpc(
        'log_org_activity',
        params: {
          'p_org_id': orgId,
          'p_action': action,
          'p_entity_type': entityType,
          'p_entity_id': entityId,
          'p_metadata': metadata ?? <String, dynamic>{},
        },
      );
    } catch (_) {}
  }

  static void logSessionStart() {
    unawaited(_log('session.start'));
  }

  static void logListingCreated(String propertyId) {
    unawaited(_log(
      'listing.created',
      entityType: 'property',
      entityId: propertyId,
    ));
  }

  static void logListingRequestCreated(String requestId) {
    unawaited(_log(
      'listing_request.created',
      entityType: 'listing_request',
      entityId: requestId,
    ));
  }

  static void logChatOpen({String? threadId}) {
    unawaited(_log(
      'chat.open',
      entityType: 'chat',
      entityId: threadId,
    ));
  }
}
