import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import '../core/input/saudi_input_formatters.dart';
import '../main.dart' show langNotifier;
import '../services/org_team_service.dart';

/// حوار إضافة عضو: هوية/إقامة + جوال (10 أرقام تبدأ بـ 05).
Future<bool?> showTeamInviteMemberDialog(
  BuildContext context, {
  required OrgTeamService svc,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _TeamInviteMemberDialog(svc: svc),
  );
}

class _TeamInviteMemberDialog extends StatefulWidget {
  const _TeamInviteMemberDialog({required this.svc});

  final OrgTeamService svc;

  @override
  State<_TeamInviteMemberDialog> createState() => _TeamInviteMemberDialogState();
}

class _TeamInviteMemberDialogState extends State<_TeamInviteMemberDialog> {
  final _nationalId = TextEditingController();
  final _mobile = TextEditingController();
  bool _busy = false;

  bool get _isAr => langNotifier.value != 'en';

  @override
  void dispose() {
    _nationalId.dispose();
    _mobile.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final nid = _nationalId.text.replaceAll(RegExp(r'\D'), '');
    final mob = _mobile.text.replaceAll(RegExp(r'\D'), '');
    if (nid.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAr
                ? 'أدخل رقم هوية/إقامة من 10 أرقام.'
                : 'Enter a 10-digit national ID / Iqama.',
          ),
        ),
      );
      return;
    }
    if (!RegExp(r'^05\d{8}$').hasMatch(mob)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAr
                ? 'رقم الجوال: 10 أرقام تبدأ بـ 05.'
                : 'Mobile: 10 digits starting with 05.',
          ),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    final res = await widget.svc.createTeamInvitation(
      nationalId: nid,
      mobile: mob,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['ok'] == true) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAr
                ? 'تم إضافة طلب الانضمام للعضو. سيُكمل التسجيل خلال 72 ساعة.'
                : 'Join invitation sent. The member has 72 hours to register.',
          ),
        ),
      );
      return;
    }
    final err = '${res['error'] ?? ''}';
    final msg = _mapError(err);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _mapError(String code) {
    switch (code) {
      case 'invalid_national_id':
        return _isAr ? 'رقم الهوية غير صالح.' : 'Invalid national ID.';
      case 'invalid_mobile':
        return _isAr ? 'رقم الجوال غير صالح.' : 'Invalid mobile number.';
      case 'seat_limit_reached':
        return _isAr ? 'بلغت الحد الأقصى للمقاعد.' : 'Seat limit reached.';
      case 'owner_subscription_required':
        return _isAr
            ? 'يلزم اشتراك نشط لإضافة أعضاء.'
            : 'Active subscription required.';
      case 'national_id_already_registered':
        return _isAr
            ? 'رقم الهوية مسجّل مسبقاً.'
            : 'This national ID is already registered.';
      case 'duplicate_pending':
        return _isAr
            ? 'يوجد طلب معلّق بنفس البيانات.'
            : 'A pending invitation with these details already exists.';
      case 'not_owner':
        return _isAr
            ? 'إضافة الأعضاء للمالك فقط.'
            : 'Only the organization owner can invite.';
      default:
        return _isAr ? 'تعذر إرسال الطلب.' : 'Could not send invitation.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isAr ? 'إضافة عضو' : 'Add member'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AqarTextField(
              controller: _nationalId,
              keyboardType: TextInputType.number,
              maxLength: 10,
              inputFormatters: latinDigitsOnlyFormatters(maxLength: 10),
              decoration: InputDecoration(
                counterText: '',
                labelText: _isAr ? 'رقم الهوية / الإقامة' : 'National ID / Iqama',
              ),
            ),
            const SizedBox(height: 12),
            AqarTextField(
              controller: _mobile,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              inputFormatters: latinDigitsOnlyFormatters(maxLength: 10),
              decoration: InputDecoration(
                counterText: '',
                labelText: _isAr ? 'رقم الجوال' : 'Mobile number',
                hintText: '05xxxxxxxx',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(_isAr ? 'إلغاء' : 'Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isAr ? 'إرسال' : 'Send'),
        ),
      ],
    );
  }
}
