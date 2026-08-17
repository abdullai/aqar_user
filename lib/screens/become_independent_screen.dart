import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/account_switch_service.dart';
import '../services/org_team_service.dart';

enum AccountChangeMode { independence, changeType }

/// طلب استقلال أو تغيير نوع الحساب (يُراجع على الخادم).
class BecomeIndependentScreen extends StatefulWidget {
  const BecomeIndependentScreen({
    super.key,
    required this.lang,
    this.mode = AccountChangeMode.independence,
  });

  final String lang;
  final AccountChangeMode mode;

  @override
  State<BecomeIndependentScreen> createState() =>
      _BecomeIndependentScreenState();
}

class _BecomeIndependentScreenState extends State<BecomeIndependentScreen> {
  final _reason = TextEditingController();
  final _targetType = TextEditingController();
  final _orgCode = TextEditingController();
  bool _busy = false;

  final _switchSvc = AccountSwitchService(Supabase.instance.client);
  final _orgSvc = OrgTeamService(Supabase.instance.client);

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  @override
  void dispose() {
    _reason.dispose();
    _targetType.dispose();
    _orgCode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      String requested;
      if (widget.mode == AccountChangeMode.independence) {
        requested = 'independent_owner';
      } else {
        requested = _targetType.text.trim().isEmpty
            ? 'unspecified_change'
            : _targetType.text.trim();
      }
      final ctx = await _orgSvc.myOrgContext();
      final orgId = ctx?['org_id']?.toString();
      final res = await _switchSvc.submitChangeRequest(
        requestedType: requested,
        currentOrgUnitId: orgId,
        requestedOrganizationCode: _orgCode.text.trim().isEmpty
            ? null
            : _orgCode.text.trim(),
        reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
      );
      if (!mounted) return;
      if (res['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isAr ? 'تم إرسال الطلب' : 'Request submitted'),
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${res['error'] ?? 'failed'}')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.mode == AccountChangeMode.independence
        ? (_isAr ? 'طلب الاستقلال' : 'Independence request')
        : (_isAr ? 'تغيير نوع الحساب' : 'Account type change');
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.mode == AccountChangeMode.changeType)
            AqarTextField(
              controller: _targetType,
              decoration: InputDecoration(
                labelText: _isAr
                    ? 'النوع المطلوب (مثال: marketer / owner_individual)'
                    : 'Requested type (e.g. marketer / owner_individual)',
              ),
            ),
          if (widget.mode == AccountChangeMode.changeType)
            const SizedBox(height: 12),
          AqarTextField(
            controller: _orgCode,
            decoration: InputDecoration(
              labelText: _isAr ? 'رمز منشأة مرتبط (اختياري)' : 'Org code (optional)',
            ),
          ),
          const SizedBox(height: 12),
          AqarTextField(
            controller: _reason,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: _isAr ? 'السبب (مطلوب)' : 'Reason (required)',
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
