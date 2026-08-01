import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/org/org_join_qr_payload.dart';
import '../services/org_team_service.dart';
import '../widgets/team_membership_gate.dart';
import '../widgets/org_team_join_scan_sheet.dart';

final _uuidLike = RegExp(r'^[0-9a-fA-F-]{36}$');

/// إدخال رقم منشأة (UUID) أو رمز انضمام.
class JoinNewOrganizationScreen extends StatefulWidget {
  const JoinNewOrganizationScreen({
    super.key,
    required this.lang,
    this.fromBannedFlow = false,
  });

  final String lang;
  final bool fromBannedFlow;

  @override
  State<JoinNewOrganizationScreen> createState() =>
      _JoinNewOrganizationScreenState();
}

class _JoinNewOrganizationScreenState extends State<JoinNewOrganizationScreen> {
  final _codeCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  final _svc = OrgTeamService(Supabase.instance.client);
  bool _busy = false;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  @override
  void dispose() {
    _codeCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw = _codeCtrl.text.trim();
    if (raw.isEmpty) return;
    final code = _uuidLike.hasMatch(raw)
        ? raw
        : () {
            final n = OrgJoinQrPayload.parseRecruitOrOrgInput(raw);
            return n.isNotEmpty ? n : raw;
          }();
    if (code.isEmpty) return;
    setState(() => _busy = true);
    try {
      final msg = _msgCtrl.text.trim();
      Map<String, dynamic> res;
      if (_uuidLike.hasMatch(code)) {
        res = await _svc.submitJoinRequestByOrgId(
          orgId: code,
          message: msg.isEmpty ? null : msg,
        );
      } else {
        res = await _svc.submitJoinRequest(recruitCode: code);
      }
      if (!mounted) return;
      if (res['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isAr
                  ? 'تم إرسال طلب الانضمام بنجاح.\nسيُراجعه مدير المنشأة بعد تفعيل اشتراكه إن لزم، ثم تصلك إشعار بالموافقة.'
                  : 'Join request sent.\nThe organization owner will review it after activating their subscription if needed; you will be notified when approved.',
            ),
          ),
        );
        Navigator.pop(context);
      } else {
        final err = '${res['error'] ?? 'failed'}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TeamMembershipGate.mapJoinErrorMessage(err, isAr: _isAr),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isAr ? 'انضمام لمنشأة' : 'Join organization'),
        actions: [
          IconButton(
            tooltip: _isAr ? 'مسح رمز QR' : 'Scan QR code',
            onPressed: _busy
                ? null
                : () {
                    showOrgTeamJoinQrScanner(
                      context,
                      isAr: _isAr,
                      onCode: (parsed) {
                        setState(() {
                          _codeCtrl.text = parsed;
                        });
                      },
                    );
                  },
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.fromBannedFlow)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                _isAr
                    ? 'سيرسل طلبك للإدارة الجديدة. بعد الموافقة قد يُفعّل حسابك وفق سياسات المنصّة.'
                    : 'Your request goes to the new organization. Approval may lift restrictions per platform policy.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          AqarTextField(
            controller: _codeCtrl,
            decoration: InputDecoration(
              labelText: _isAr
                  ? 'معرّف المنشأة أو رمز الدعوة'
                  : 'Organization ID or invite code',
            ),
          ),
          const SizedBox(height: 12),
          AqarTextField(
            controller: _msgCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: _isAr ? 'رسالة (اختياري)' : 'Message (optional)',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_isAr ? 'إرسال' : 'Submit'),
          ),
        ],
      ),
    );
  }
}
