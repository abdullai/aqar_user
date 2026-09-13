import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/support/support_identity.dart';
import '../core/support/support_ticket_assist.dart';
import '../core/utils/phone_display.dart';

class SupportLocalAttachment {
  const SupportLocalAttachment({
    required this.name,
    required this.bytes,
    this.mime = 'application/octet-stream',
  });

  final String name;
  final Uint8List bytes;
  final String mime;
}

class SupportRemoteAttachment {
  const SupportRemoteAttachment({
    required this.name,
    required this.path,
    this.mime = 'application/octet-stream',
    this.url = '',
  });

  final String name;
  final String path;
  final String mime;
  final String url;

  Map<String, dynamic> toMap() => {
        'name': name,
        'path': path,
        'mime': mime,
        if (url.isNotEmpty) 'url': url,
      };

  factory SupportRemoteAttachment.fromMap(Map<String, dynamic> m) =>
      SupportRemoteAttachment(
        name: '${m['name'] ?? ''}',
        path: '${m['path'] ?? ''}',
        mime: '${m['mime'] ?? 'application/octet-stream'}',
        url: '${m['url'] ?? ''}',
      );
}

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
    this.userId = '',
  });

  final String id;
  final String kind;
  final String subject;
  final String body;
  final String status;
  final String contactChannel;
  final DateTime? createdAt;
  final Map<String, dynamic> details;
  final String userId;

  bool get isOpen =>
      status == 'open' || status == 'escalated' || status == 'awaiting_user';

  String? get adminReply => details['admin_reply']?.toString();
  String? get resolvedBy => details['resolved_by']?.toString();
  String? get solutionSummary => details['solution_summary']?.toString();
  String get userResolution =>
      (details['user_resolution'] ?? 'open').toString();

  String get submitterName =>
      '${details['submitter_name'] ?? details['requester_name'] ?? ''}'.trim();

  String get submitterPhone => PhoneDisplay.localTenDigits(
        '${details['submitter_phone'] ?? details['requester_phone'] ?? ''}',
      );

  String get receivedByName =>
      '${details['received_by_name'] ?? details['assigned_name'] ?? ''}'.trim();

  DateTime? get receivedAt =>
      DateTime.tryParse('${details['received_at'] ?? details['assigned_at'] ?? ''}');

  String get shortRef {
    final raw = id.replaceAll('-', '');
    if (raw.length >= 8) return raw.substring(0, 8).toUpperCase();
    return id;
  }

  List<SupportRemoteAttachment> get attachments {
    final raw = details['attachments'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => SupportRemoteAttachment.fromMap(Map<String, dynamic>.from(e)))
        .where((e) => e.path.isNotEmpty || e.url.isNotEmpty)
        .toList();
  }

  List<Map<String, dynamic>> get chatThread {
    final raw = details['chat_thread'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

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
      userId: '${m['user_id'] ?? ''}',
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
        'user_id': userId,
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
    String submitterName = '',
    String submitterPhone = '',
    List<SupportLocalAttachment> attachments = const [],
  }) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;

    if (submitterName.trim().isEmpty || submitterPhone.trim().isEmpty) {
      final ident = await SupportIdentity.load(_sb, uid, isAr: true);
      if (submitterName.trim().isEmpty) submitterName = ident.name;
      if (submitterPhone.trim().isEmpty) submitterPhone = ident.phone;
    }

    final uploaded = await _uploadAttachments(uid: uid, files: attachments);

    final category = SupportTicketAssist.classify(
      subject: subject,
      body: body,
      kind: kind,
    );
    final details = <String, dynamic>{
      'user_resolution': 'open',
      'assist_category': category,
      'submitter_name': submitterName.trim(),
      'requester_name': submitterName.trim(),
      'submitter_phone': PhoneDisplay.localTenDigits(submitterPhone),
      'requester_phone': PhoneDisplay.localTenDigits(submitterPhone),
      'attachments': uploaded.map((e) => e.toMap()).toList(),
      'auto_ack': contactChannel == 'in_app'
          ? SupportTicketAssist.draftAck(
              isAr: true,
              category: category,
              kind: kind,
            )
          : null,
      'auto_ack_en': contactChannel == 'in_app'
          ? SupportTicketAssist.draftAck(
              isAr: false,
              category: category,
              kind: kind,
            )
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

  static const _attachmentBucket = 'property-images';

  Future<List<SupportRemoteAttachment>> _uploadAttachments({
    required String uid,
    required List<SupportLocalAttachment> files,
  }) async {
    if (files.isEmpty) return const [];
    final out = <SupportRemoteAttachment>[];
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final safe = f.name.replaceAll(RegExp(r'[^\w.\-]+'), '_');
      final path =
          'support-uploads/$uid/${DateTime.now().millisecondsSinceEpoch}_${i}_$safe';
      try {
        await _sb.storage.from(_attachmentBucket).uploadBinary(
              path,
              f.bytes,
              fileOptions: FileOptions(
                contentType: f.mime,
                upsert: false,
              ),
            );
        final url = _sb.storage.from(_attachmentBucket).getPublicUrl(path);
        out.add(
          SupportRemoteAttachment(
            name: f.name,
            path: path,
            mime: f.mime,
            url: url,
          ),
        );
      } catch (e) {
        if (kDebugMode) debugPrint('[SupportTicketService] attach: $e');
      }
    }
    return out;
  }

  Future<String?> signedAttachmentUrl(SupportRemoteAttachment a) async {
    if (a.url.trim().isNotEmpty) return a.url.trim();
    if (a.path.trim().isEmpty) return null;
    try {
      return await _sb.storage.from(_attachmentBucket).createSignedUrl(
            a.path,
            60 * 60,
          );
    } catch (_) {
      try {
        return _sb.storage.from(_attachmentBucket).getPublicUrl(a.path);
      } catch (_) {
        return null;
      }
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

  Future<List<SupportTicketRow>> listForStaff({int limit = 80}) async {
    try {
      final rows = await _sb.rpc(
        'platform_staff_list_complaints',
        params: {'p_limit': limit},
      );
      if (rows is List) {
        return rows
            .whereType<Map>()
            .map((e) => SupportTicketRow.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[SupportTicketService] staff list: $e');
    }
    return const [];
  }

  Future<Map<String, dynamic>> staffReply({
    required String complaintId,
    required String reply,
    String status = 'awaiting_user',
  }) async {
    try {
      final raw = await _sb.rpc(
        'platform_staff_reply_complaint',
        params: {
          'p_complaint_id': complaintId,
          'p_reply': reply,
          'p_status': status,
        },
      );
      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
    return {'ok': false, 'error': 'bad_response'};
  }

  Future<Map<String, dynamic>> staffOpenTicket(String complaintId) async {
    try {
      final raw = await _sb.rpc(
        'platform_staff_open_ticket',
        params: {'p_complaint_id': complaintId},
      );
      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
    return {'ok': false, 'error': 'bad_response'};
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
