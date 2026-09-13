import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/branding/app_branding.dart';
import '../../core/gestures/app_keyboard_inset.dart';
import '../../core/support/support_identity.dart';
import '../../core/support/support_whatsapp_launcher.dart';
import '../../core/support/support_whatsapp_config.dart';
import '../../core/utils/phone_display.dart';
import '../../l10n/app_localizations.dart';
import '../../services/compliance_audit_service.dart';
import '../../services/support_ticket_service.dart';
import '../aqar_text_field.dart';
import 'support_attachment_picker.dart';
import 'support_labeled_table.dart';

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
  String _displayName = '';
  String _phone = '';
  List<SupportLocalAttachment> _attachments = [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadIdentity());
  }

  Future<void> _loadIdentity() async {
    if (widget.userId.isEmpty) return;
    final ident = await SupportIdentity.load(
      Supabase.instance.client,
      widget.userId,
      isAr: widget.isAr,
    );
    if (!mounted) return;
    setState(() {
      _displayName = ident.name;
      _phone = PhoneDisplay.localTenDigits(ident.phone);
    });
  }

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

  String _kindLabel(AppLocalizations l10n, String k) {
    return k == 'suggestion'
        ? l10n.supportComplaintKindSuggestion
        : l10n.supportComplaintKindComplaint;
  }

  String _composeWhatsAppText(AppLocalizations l10n) {
    final lines = <String>[
      widget.isAr
          ? 'طلب دعم — ${AppBranding.brandNameAr}'
          : 'Support — ${AppBranding.brandNameEn}',
      '${l10n.supportComplaintKindLabel}: ${_kindLabel(l10n, _kind ?? 'complaint')}',
      '${l10n.supportComplaintSubjectLabel}: ${_subjectCtrl.text.trim()}',
      '${l10n.supportComplaintDetailsLabel}: ${_detailsCtrl.text.trim()}',
      if (_displayName.isNotEmpty)
        '${l10n.supportSubmitterNameLabel}: $_displayName',
      if (_phone.isNotEmpty) '${l10n.supportSubmitterPhoneLabel}: $_phone',
    ];
    return lines.join('\n');
  }

  Future<void> _sendViaWhatsAppAllLines(AppLocalizations l10n) async {
    final text = _composeWhatsAppText(l10n);
    await _service.submit(
      kind: _kind!,
      subject: _subjectCtrl.text.trim(),
      body: _detailsCtrl.text.trim(),
      contactChannel: 'whatsapp',
      submitterName: _displayName,
      submitterPhone: _phone,
      attachments: _attachments,
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
    _resetForm();
  }

  void _resetForm() {
    _subjectCtrl.clear();
    _detailsCtrl.clear();
    setState(() {
      _kind = null;
      _channel = null;
      _attachments = [];
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _submitting = true);
    try {
      if (_channel == SupportContactChannel.whatsapp) {
        await _sendViaWhatsAppAllLines(l10n);
        return;
      }

      final row = await _service.submit(
        kind: _kind!,
        subject: _subjectCtrl.text.trim(),
        body: _detailsCtrl.text.trim(),
        contactChannel: 'in_app',
        submitterName: _displayName,
        submitterPhone: _phone,
        attachments: _attachments,
      );
      if (!mounted) return;
      if (row == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.supportComplaintSubmitFailed)),
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
        SnackBar(content: Text(l10n.supportComplaintSubmitOk)),
      );
      _resetForm();
      widget.onSubmittedInApp?.call();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _bareFieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + AppKeyboardInset.bottomOf(context).clamp(0, 24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.supportComplaintFormTitle,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.supportComplaintFormHint,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${l10n.supportComplaintKindLabel} *',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'complaint',
                  label: Text(l10n.supportComplaintKindComplaint),
                  icon: const Icon(Icons.report_outlined, size: 18),
                ),
                ButtonSegment(
                  value: 'suggestion',
                  label: Text(l10n.supportComplaintKindSuggestion),
                  icon: const Icon(Icons.lightbulb_outline, size: 18),
                ),
              ],
              selected: _kind == null ? {} : {_kind!},
              emptySelectionAllowed: true,
              onSelectionChanged: _submitting
                  ? null
                  : (s) => setState(() => _kind = s.isEmpty ? null : s.first),
            ),
            const SizedBox(height: 12),
            SupportLabeledTable(
              rows: [
                if (_displayName.isNotEmpty)
                  SupportLabeledRow(
                    label: l10n.supportSubmitterNameLabel,
                    child: Text(
                      _displayName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                if (_phone.isNotEmpty)
                  SupportLabeledRow(
                    label: l10n.supportSubmitterPhoneLabel,
                    child: Text(
                      PhoneDisplay.forUi(_phone, isAr: widget.isAr),
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                SupportLabeledRow(
                  label: l10n.supportComplaintSubjectLabel,
                  child: AqarTextField(
                    controller: _subjectCtrl,
                    enabled: !_submitting,
                    minLines: 2,
                    maxLines: 6,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    onChanged: (_) => setState(() {}),
                    decoration: _bareFieldDecoration(
                      l10n.supportComplaintSubjectHint,
                    ),
                  ),
                ),
                SupportLabeledRow(
                  label: l10n.supportComplaintDetailsLabel,
                  child: AqarTextField(
                    controller: _detailsCtrl,
                    enabled: !_submitting,
                    minLines: 5,
                    maxLines: 14,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    onChanged: (_) => setState(() {}),
                    decoration: _bareFieldDecoration(
                      l10n.supportComplaintDetailsHint,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SupportAttachmentPicker(
              files: _attachments,
              enabled: !_submitting,
              onChanged: (next) => setState(() => _attachments = next),
            ),
            const SizedBox(height: 16),
            Text(
              '${l10n.supportComplaintChannelLabel} *',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SegmentedButton<SupportContactChannel>(
              segments: [
                ButtonSegment(
                  value: SupportContactChannel.whatsapp,
                  label: Text(l10n.supportComplaintChannelWhatsApp),
                  icon: const Icon(Icons.chat_rounded, size: 18),
                ),
                ButtonSegment(
                  value: SupportContactChannel.inApp,
                  label: Text(l10n.supportComplaintChannelInApp),
                  icon: const Icon(Icons.support_agent_outlined, size: 18),
                ),
              ],
              selected: _channel == null ? {} : {_channel!},
              emptySelectionAllowed: true,
              onSelectionChanged: _submitting
                  ? null
                  : (s) => setState(() => _channel = s.isEmpty ? null : s.first),
            ),
            if (_channel == SupportContactChannel.whatsapp) ...[
              const SizedBox(height: 8),
              Text(
                l10n.supportComplaintWhatsAppHint,
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
                    ? l10n.supportComplaintSendWhatsApp
                    : l10n.supportComplaintSendInApp,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
