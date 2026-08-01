import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// تذكرة دعم / شكوى / اقتراح.
@immutable
class SupportTicketRow {
  const SupportTicketRow({
    required this.id,
    required this.kind,
    required this.subject,
    required this.body,
    required this.status,
    required this.contactChannel,
    required this.createdAt,
    required this.details,
  });

  final String id;
  final String kind;
  final String subject;
  final String body;
  final String status;
  final String contactChannel;
  final DateTime? createdAt;
  final Map<String, dynamic> details;

  bool get isOpen =>
      status == 'open' || status == 'escalated' || status == 'awaiting_user';

  String? get adminReply => details['admin_reply']?.toString();
  String? get resolvedBy => details['resolved_by']?.toString();
  String? get solutionSummary => details['solution_summary']?.toString();
  String get userResolution =>
      (details['user_resolution'] ?? 'open').toString();

  factory SupportTicketRow.fromMap(Map<String, dynamic> m) {
    final rawDetails = m['details'];
    Map<String, dynamic> details = {};
    if (rawDetails is Map) {
      details = Map<String, dynamic>.from(rawDetails);
    } else if (rawDetails is String && rawDetails.trim().isNotEmpty) {
      try {
        final d = jsonDecode(rawDetails);
        if (d is Map) details = Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    DateTime? created;
    final ca = m['created_at'];
    if (ca != null) {
      created = DateTime.tryParse(ca.toString());
    }
    return SupportTicketRow(
      id: '${m['id'] ?? ''}',
      kind: '${m['kind'] ?? 'complaint'}',
      subject: '${m['subject'] ?? ''}',
      body: '${m['body'] ?? ''}',
      status: '${m['status'] ?? 'open'}',
      contactChannel: '${m['contact_channel'] ?? 'in_app'}',
      createdAt: created,
      details: details,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'kind': kind,
        'subject': subject,
        'body': body,
        'status': status,
        'contact_channel': contactChannel,
        'created_at': createdAt?.toIso8601String(),
        'details': details,
      };
}

class SupportTicketService {
  SupportTicketService(this._sb);

  final SupabaseClient _sb;

  static String _localKey(String userId) => 'local_support_tickets_$userId';

  Future<List<SupportTicketRow>> listMine(String userId) async {
    try {
      final rows = await _sb
          .from('regc_user_complaints')
          .select(
            'id, kind, subject, body, status, contact_channel, details, created_at',
          )
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return (rows as List)
          .map((e) => SupportTicketRow.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[SupportTicketService] list: $e');
      return _loadLocal(userId);
    }
  }

  Future<SupportTicketRow?> submit({
    required String kind,
    required String subject,
    required String body,
    required String contactChannel,
  }) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;

    final details = {
      'user_resolution': 'open',
      'auto_ack': contactChannel == 'in_app'
          ? (kind == 'suggestion'
              ? 'تم استلام اقتراحك — سيتواصل معك فريق الدعم داخل التطبيق.'
              : 'تم استلام شكواك — سيتواصل معك فريق الدعم داخل التطبيق.')
          : null,
    };

    try {
      final res = await _sb.rpc('support_submit_complaint_v1', params: {
        'p_kind': kind,
        'p_subject': subject,
        'p_body': body,
        'p_contact_channel': contactChannel,
        'p_details': details,
      });
      final id = res?.toString();
      if (id == null || id.isEmpty) return null;
      final row = SupportTicketRow(
        id: id,
        kind: kind,
        subject: subject,
        body: body,
        status: 'open',
        contactChannel: contactChannel,
        createdAt: DateTime.now(),
        details: details,
      );
      await _appendLocal(uid, row);
      return row;
    } catch (e) {
      if (kDebugMode) debugPrint('[SupportTicketService] rpc submit: $e');
      try {
        final ins = await _sb
            .from('regc_user_complaints')
            .insert({
              'user_id': uid,
              'subject': subject,
              'body': body,
            })
            .select(
              'id, kind, subject, body, status, contact_channel, details, created_at',
            )
            .maybeSingle();
        if (ins == null) return null;
        final row = SupportTicketRow.fromMap(Map<String, dynamic>.from(ins));
        await _appendLocal(uid, row);
        return row;
      } catch (e2) {
        if (kDebugMode) debugPrint('[SupportTicketService] insert fallback: $e2');
        final local = SupportTicketRow(
          id: 'local-${DateTime.now().millisecondsSinceEpoch}',
          kind: kind,
          subject: subject,
          body: body,
          status: 'open',
          contactChannel: contactChannel,
          createdAt: DateTime.now(),
          details: details,
        );
        await _appendLocal(uid, local);
        return local;
      }
    }
  }

  Future<void> userFeedback({
    required String ticketId,
    required String action,
    int? rating,
    String? feedback,
  }) async {
    if (ticketId.startsWith('local-')) {
      return;
    }
    try {
      await _sb.rpc('support_complaint_user_feedback_v1', params: {
        'p_complaint_id': ticketId,
        'p_action': action,
        'p_rating': rating,
        'p_feedback': feedback,
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[SupportTicketService] feedback: $e');
      rethrow;
    }
  }

  Future<void> _appendLocal(String userId, SupportTicketRow row) async {
    final list = await _loadLocal(userId);
    list.insert(0, row);
    await _saveLocal(userId, list);
  }

  Future<List<SupportTicketRow>> _loadLocal(String userId) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_localKey(userId));
      if (raw == null) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .map((e) => SupportTicketRow.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveLocal(String userId, List<SupportTicketRow> rows) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _localKey(userId),
        jsonEncode(rows.map((e) => e.toMap()).toList()),
      );
    } catch (_) {}
  }
}
