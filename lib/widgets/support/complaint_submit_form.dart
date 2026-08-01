import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/branding/app_branding.dart';
import '../../core/support/support_whatsapp_launcher.dart';
import '../../core/support/support_whatsapp_config.dart';
import '../../services/compliance_audit_service.dart';
import '../../services/support_ticket_service.dart';
import '../aqar_text_field.dart';

enum SupportContactChannel { whatsapp, inApp }

/// نموذج «تقديم شكوى / اقتراحات» داخل التطبيق.
class ComplaintSubmitForm extends StatefulWidget {
  const ComplaintSubmitForm({
    super.key,
    required this.isAr,
    required this.userId,
    required this.accentColor,
    this.onSubmittedInApp,
  });

  final bool isAr;
  final String userId;
  final Color accentColor;
  final VoidCallback? onSubmittedInApp;

  @override
  State<ComplaintSubmitForm> createState() => _ComplaintSubmitFormState();
}

class _ComplaintSubmitFormState extends State<ComplaintSubmitForm> {
  final _subjectCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();
  late final SupportTicketService _service =
      SupportTicketService(Supabase.instance.client);

  String? _kind;
  SupportContactChannel? _channel;
  bool _submitting = false;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _detailsCtrl.dispose();
    super.dispose();
  }

  bool get _subjectReady => _subjectCtrl.text.trim().length >= 2;
  bool get _detailsReady => _detailsCtrl.text.trim().length >= 5;
  bool get _canSubmit =>
      _kind != null &&
      _subjectReady &&
      _detailsReady &&
      _channel != null &&
      !_submitting;

  String _kindLabel(String k) {
    if (widget.isAr) {
      return k == 'suggestion' ? 'اقتراح' : 'شكوى';
    }
    return k == 'suggestion' ? 'Suggestion' : 'Complaint';
  }

  String _composeWhatsAppText() {
    final lines = <String>[
      widget.isAr
          ? 'طلب دعم — ${AppBranding.brandNameAr}'
          : 'Support — ${AppBranding.brandNameEn}',
      '${widget.isAr ? 'النوع' : 'Type'}: ${_kindLabel(_kind ?? 'complaint')}',
      '${widget.isAr ? 'الموضوع' : 'Subject'}: ${_subjectCtrl.text.trim()}',
      '${widget.isAr ? 'التفاصيل' : 'Details'}: ${_detailsCtrl.text.trim()}',
      if (widget.userId.isNotEmpty)
        '${widget.isAr ? 'معرّف المستخدم' : 'User ID'}: ${widget.userId}',
    ];
    return lines.join('\n');
  }

  Future<void> _sendViaWhatsAppAllLines() async {
    final text = _composeWhatsAppText();
    // 1) حفظ في النظام أولاً — يصل للإدارة حتى بدون واتساب
    unawaited(
      _service.submit(
        kind: _kind!,
        subject: _subjectCtrl.text.trim(),
        body: _detailsCtrl.text.trim(),
        contactChannel: 'whatsapp',
      ),
    );
    unawaited(
      ComplianceAuditService.instance.log('complaint.whatsapp_all', {
        'kind': _kind,
        'lines': SupportWhatsappConfig.lines.map((e) => e.display).toList(),
      }),
    );
    if (!mounted) return;
    await SupportWhatsappLauncher.openAllSupportLines(
      context: context,
      isAr: widget.isAr,
      message: text,
    );
    if (!mounted) return;
    _subjectCtrl.clear();
    _detailsCtrl.clear();
    setState(() {
      _kind = null;
      _channel = null;
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    try {
      if (_channel == SupportContactChannel.whatsapp) {
        await _sendViaWhatsAppAllLines();
        return;
      }

      final row = await _service.submit(
        kind: _kind!,
        subject: _subjectCtrl.text.trim(),
        body: _detailsCtrl.text.trim(),
        contactChannel: 'in_app',
      );
      if (!mounted) return;
      if (row == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isAr
                ? 'تعذّر إرسال الطلب — حاول لاحقاً.'
                : 'Could not submit — try again later.'),
          ),
        );
        return;
      }
      unawaited(
        ComplianceAuditService.instance.log('complaint.submitted', {
          'complaint_id': row.id,
          'channel': 'in_app',
        }),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isAr
              ? 'تم إرسال ${_kindLabel(_kind!)} — تابعها من تبويب التذاكر.'
              : 'Your ${_kindLabel(_kind!)} was sent — track it under Tickets.'),
        ),
      );
      _subjectCtrl.clear();
      _detailsCtrl.clear();
      setState(() {
        _kind = null;
        _channel = null;
      });
      widget.onSubmittedInApp?.call();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAr = widget.isAr;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isAr ? 'تقديم شكوى / اقتراحات' : 'Submit complaint / suggestion',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              isAr
                  ? 'جميع الحقول إلزامية. اختر طريقة التواصل ثم اضغط إرسال.'
                  : 'All fields are required. Choose contact method then send.',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _kind,
              decoration: InputDecoration(
                labelText: isAr ? 'النوع *' : 'Type *',
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: 'complaint',
                  child: Text(isAr ? 'شكوى' : 'Complaint'),
                ),
                DropdownMenuItem(
                  value: 'suggestion',
                  child: Text(isAr ? 'اقتراح' : 'Suggestion'),
                ),
              ],
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _kind = v),
            ),
            if (_kind != null) ...[
              const SizedBox(height: 12),
              AqarTextField(
                controller: _subjectCtrl,
                enabled: !_submitting,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: isAr ? 'الموضوع *' : 'Subject *',
                  hintText: isAr ? 'اكتب موضوعاً واضحاً' : 'Enter a clear subject',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            if (_kind != null && _subjectReady) ...[
              const SizedBox(height: 12),
              AqarTextField(
                controller: _detailsCtrl,
                enabled: !_submitting,
                minLines: 4,
                maxLines: 8,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: isAr ? 'التفاصيل *' : 'Details *',
                  hintText: isAr
                      ? 'اشرح المشكلة أو الاقتراح بالتفصيل'
                      : 'Describe the issue or suggestion',
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ],
            if (_kind != null && _subjectReady && _detailsReady) ...[
              const SizedBox(height: 16),
              Text(
                isAr ? 'طريقة التواصل *' : 'Contact method *',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              SegmentedButton<SupportContactChannel>(
                segments: [
                  ButtonSegment(
                    value: SupportContactChannel.whatsapp,
                    label: Text(isAr ? 'واتساب' : 'WhatsApp'),
                    icon: const Icon(Icons.chat_rounded, size: 18),
                  ),
                  ButtonSegment(
                    value: SupportContactChannel.inApp,
                    label: Text(isAr ? 'داخل التطبيق' : 'In-app'),
                    icon: const Icon(Icons.support_agent_outlined, size: 18),
                  ),
                ],
                selected: _channel == null ? {} : {_channel!},
                onSelectionChanged: _submitting
                    ? null
                    : (s) => setState(() => _channel = s.first),
              ),
              if (_channel == SupportContactChannel.whatsapp) ...[
                const SizedBox(height: 8),
                Text(
                  isAr
                      ? 'يُحفظ الطلب في النظام ويُفتح واتساب مع الأرقام الثلاثة (0555317770، 0501967955، 0500229909) — اضغط «إرسال» في كل محادثة.'
                      : 'Saved in-app and opens WhatsApp for all 3 lines (0555317770, 0501967955, 0500229909) — tap Send in each chat.',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _canSubmit ? _submit : null,
                icon: _submitting
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.onPrimary,
                        ),
                      )
                    : Icon(
                        _channel == SupportContactChannel.whatsapp
                            ? Icons.chat_rounded
                            : Icons.send_rounded,
                      ),
                label: Text(
                  _channel == SupportContactChannel.whatsapp
                      ? (isAr ? 'إرسال عبر واتساب' : 'Send via WhatsApp')
                      : (isAr ? 'إرسال داخل التطبيق' : 'Send in-app'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
