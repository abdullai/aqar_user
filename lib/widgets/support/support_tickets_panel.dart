import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/gestures/app_keyboard_inset.dart';
import '../../core/gestures/app_keyboard_popups.dart';
import '../../core/support/support_ticket_policy.dart';
import '../../core/support/support_whatsapp_launcher.dart';
import '../../core/utils/date_helper.dart';
import '../../core/utils/phone_display.dart';
import '../../core/utils/rpc_user_message.dart';
import '../../l10n/app_localizations.dart';
import '../../services/support_ticket_service.dart';
import '../../widgets/aqar_text_field.dart';
import 'support_labeled_table.dart';

/// تبويب التذاكر — عرض ومتابعة الشكاوى والاقتراحات.
class SupportTicketsPanel extends StatefulWidget {
  const SupportTicketsPanel({
    super.key,
    required this.isAr,
    required this.userId,
    required this.accentColor,
  });

  final bool isAr;
  final String userId;
  final Color accentColor;

  @override
  State<SupportTicketsPanel> createState() => SupportTicketsPanelState();
}

class SupportTicketsPanelState extends State<SupportTicketsPanel> {
  late final SupportTicketService _service =
      SupportTicketService(Supabase.instance.client);
  List<SupportTicketRow> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> reload() => _reload();

  Future<void> _reload() async {
    if (widget.userId.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final rows = await _service.listMine(widget.userId);
    if (mounted) {
      setState(() {
        _rows = rows;
        _loading = false;
      });
    }
  }

  String _statusLabel(AppLocalizations l10n, SupportTicketRow t) {
    if (SupportTicketPolicy.isResolved(t)) {
      return l10n.supportTicketStatusResolved;
    }
    if (SupportTicketPolicy.isEscalated(t)) {
      return l10n.supportTicketStatusEscalated;
    }
    if (t.userResolution == 'unresolved') {
      return l10n.supportTicketStatusOpenUnresolved;
    }
    return l10n.supportTicketStatusOpen;
  }

  String _fmtWhen(DateTime? d) {
    if (d == null) return '—';
    return DateHelper.fmtCivilDateTime(d.toLocal(), isAr: widget.isAr);
  }

  Future<void> _openWhatsAppResend(SupportTicketRow t) async {
    final l10n = AppLocalizations.of(context)!;
    final text = [
      widget.isAr ? 'متابعة تذكرة دعم' : 'Support ticket follow-up',
      '${l10n.supportTicketRefLabel}: ${t.shortRef}',
      '${l10n.supportComplaintSubjectLabel}: ${t.subject}',
      '${l10n.supportComplaintDetailsLabel}: ${t.body}',
      if (t.submitterName.isNotEmpty)
        '${l10n.supportSubmitterNameLabel}: ${t.submitterName}',
      if (t.submitterPhone.isNotEmpty)
        '${l10n.supportSubmitterPhoneLabel}: ${t.submitterPhone}',
    ].join('\n');
    await SupportWhatsappLauncher.openAllSupportLines(
      context: context,
      isAr: widget.isAr,
      message: text,
    );
  }

  Future<void> _copyTicketSnapshot(SupportTicketRow t) async {
    final l10n = AppLocalizations.of(context)!;
    final text = [
      '${l10n.supportTicketRefLabel}: ${t.shortRef}',
      '${l10n.supportComplaintSubjectLabel}: ${t.subject}',
      '${l10n.supportComplaintDetailsLabel}: ${t.body}',
      '${l10n.supportTicketSubmittedAt}: ${_fmtWhen(t.createdAt)}',
      '${l10n.supportTicketStatusLabel}: ${_statusLabel(l10n, t)}',
      if (t.submitterName.isNotEmpty)
        '${l10n.supportSubmitterNameLabel}: ${t.submitterName}',
      if (t.submitterPhone.isNotEmpty)
        '${l10n.supportSubmitterPhoneLabel}: ${t.submitterPhone}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.supportTicketCopied)),
    );
  }

  Future<void> _openAttachment(SupportRemoteAttachment a) async {
    final url = await _service.signedAttachmentUrl(a);
    if (url == null || url.isEmpty) return;
    final u = Uri.tryParse(url);
    if (u == null) return;
    try {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        await launchUrl(u, mode: LaunchMode.platformDefault);
      } catch (_) {}
    }
  }

  Widget _bodyText(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
        color: cs.onSurface,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
    );
  }

  List<Map<String, dynamic>> _publicThread(SupportTicketRow t) {
    final out = <Map<String, dynamic>>[];
    for (final m in t.chatThread) {
      final text = '${m['text'] ?? ''}'.trim();
      if (text.isEmpty) continue;
      if (SupportTicketPolicy.isInternalDraftText(text)) continue;
      out.add(Map<String, dynamic>.from(m));
    }
    return out;
  }

  String _slaRemainingLabel(AppLocalizations l10n, SupportTicketRow t) {
    final left = SupportTicketPolicy.slaRemaining(t);
    if (left == null) return '—';
    if (left == Duration.zero) return l10n.supportTicketEscalateReady;
    return l10n.supportSlaCountdownHours(left.inHours, left.inMinutes % 60);
  }

  Future<void> _showRatingDialog(SupportTicketRow t) async {
    final l10n = AppLocalizations.of(context)!;
    var stars = 0;
    final notesCtrl = TextEditingController();
    String? noteText;
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(l10n.supportTicketRateTitle),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if ((t.resolvedBy ?? '').isNotEmpty)
                      Text(
                        l10n.supportTicketResolvedBy(t.resolvedBy!),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    if ((t.solutionSummary ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(t.solutionSummary!),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (i) {
                        return IconButton(
                          onPressed: () => setLocal(() => stars = i + 1),
                          icon: Icon(
                            i < stars
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: Colors.amber.shade700,
                          ),
                        );
                      }),
                    ),
                    AqarTextField(
                      controller: notesCtrl,
                      minLines: 2,
                      maxLines: 5,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        labelText: l10n.supportTicketRateNotes,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(l10n.supportTicketRateSkip),
                ),
                FilledButton(
                  onPressed: stars > 0
                      ? () {
                          noteText = notesCtrl.text.trim();
                          Navigator.pop(ctx, true);
                        }
                      : null,
                  child: Text(l10n.supportTicketRateSend),
                ),
              ],
            );
          },
        );
      },
    );
    notesCtrl.dispose();
    if (ok != true || stars <= 0) return;
    await _runFeedback(
      ticketId: t.id,
      action: 'resolved',
      rating: stars,
      feedback: (noteText ?? '').isEmpty ? null : noteText,
    );
  }

  Future<void> _runFeedback({
    required String ticketId,
    required String action,
    int? rating,
    String? feedback,
  }) async {
    try {
      await _service.userFeedback(
        ticketId: ticketId,
        action: action,
        rating: rating,
        feedback: feedback,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(RpcUserMessage.of(e, isAr: widget.isAr)),
        ),
      );
      return;
    }
    await _reload();
  }

  Future<void> _openTicketDetail(SupportTicketRow t) async {
    final l10n = AppLocalizations.of(context)!;
    await showAppModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final ack = t.details['auto_ack']?.toString();
        final ackEn = t.details['auto_ack_en']?.toString();
        final ackText = widget.isAr
            ? (ack ?? ackEn ?? '')
            : (ackEn ?? ack ?? '');
        final adminReply = (t.adminReply ?? '').trim();
        final publicReply = adminReply.isNotEmpty &&
                !SupportTicketPolicy.isInternalDraftText(adminReply) &&
                !SupportTicketPolicy.isWelcomeText(adminReply)
            ? adminReply
            : '';
        final hasStaff = SupportTicketPolicy.hasStaffReply(t);
        final canResolve = SupportTicketPolicy.canMarkResolved(t);
        final canUnresolved = SupportTicketPolicy.canMarkUnresolved(t);
        final canEscalate = SupportTicketPolicy.canEscalate(t);
        final escalated = SupportTicketPolicy.isEscalated(t);
        final replyAt = DateHelper.tryParse(t.details['admin_reply_at']);
        final replyBy =
            '${t.details['admin_reply_by_name'] ?? t.details['assigned_name'] ?? ''}'
                .trim();
        final escalatedAt = DateHelper.tryParse(t.details['escalated_at']);
        final thread = _publicThread(t);
        final availableAt = SupportTicketPolicy.escalateAvailableAt(t);

        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: AppKeyboardInset.bottomOf(ctx) + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                SupportSectionCard(
                  title: l10n.supportTicketReceiptSection,
                  child: SupportLabeledTable(
                    rows: [
                      SupportLabeledRow(
                        label: l10n.supportTicketRefLabel,
                        child: _bodyText(ctx, t.shortRef),
                      ),
                      SupportLabeledRow(
                        label: l10n.supportComplaintSubjectLabel,
                        child: _bodyText(ctx, t.subject),
                      ),
                      SupportLabeledRow(
                        label: l10n.supportComplaintDetailsLabel,
                        child: _bodyText(ctx, t.body),
                      ),
                      SupportLabeledRow(
                        label: l10n.supportTicketSubmittedAt,
                        child: _bodyText(ctx, _fmtWhen(t.createdAt)),
                      ),
                      SupportLabeledRow(
                        label: l10n.supportTicketStatusLabel,
                        child: _bodyText(ctx, _statusLabel(l10n, t)),
                      ),
                      if (t.submitterName.isNotEmpty)
                        SupportLabeledRow(
                          label: l10n.supportSubmitterNameLabel,
                          child: _bodyText(ctx, t.submitterName),
                        ),
                      if (t.submitterPhone.isNotEmpty)
                        SupportLabeledRow(
                          label: l10n.supportSubmitterPhoneLabel,
                          child: Text(
                            PhoneDisplay.forUi(
                              t.submitterPhone,
                              isAr: widget.isAr,
                            ),
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      if (t.receivedByName.isNotEmpty)
                        SupportLabeledRow(
                          label: l10n.supportTicketReceivedBy,
                          child: _bodyText(ctx, t.receivedByName),
                        ),
                      if (t.receivedAt != null)
                        SupportLabeledRow(
                          label: l10n.supportTicketReceivedAt,
                          child: _bodyText(ctx, _fmtWhen(t.receivedAt)),
                        ),
                    ],
                  ),
                ),
                if (t.attachments.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SupportSectionCard(
                    title: l10n.supportAttachmentsLabel,
                    child: Column(
                      children: [
                        for (final a in t.attachments)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.attach_file_rounded),
                            title: Text(a.name),
                            trailing: TextButton(
                              onPressed: () => unawaited(_openAttachment(a)),
                              child: Text(l10n.supportTicketOpenAttachment),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (ackText.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SupportSectionCard(
                    title: l10n.supportTicketAckSection,
                    child: SupportLabeledTable(
                      rows: [
                        SupportLabeledRow(
                          label: l10n.supportTicketMessageBody,
                          child: _bodyText(ctx, ackText.trim()),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SupportSectionCard(
                  title: l10n.supportTicketReplySection,
                  child: hasStaff && publicReply.isNotEmpty
                      ? SupportLabeledTable(
                          rows: [
                            if (replyBy.isNotEmpty)
                              SupportLabeledRow(
                                label: l10n.supportTicketReplyBy,
                                child: _bodyText(ctx, replyBy),
                              ),
                            SupportLabeledRow(
                              label: l10n.supportTicketReplyAt,
                              child: _bodyText(ctx, _fmtWhen(replyAt)),
                            ),
                            SupportLabeledRow(
                              label: l10n.supportTicketMessageBody,
                              child: _bodyText(ctx, publicReply),
                            ),
                          ],
                        )
                      : _bodyText(ctx, l10n.supportTicketReplyEmpty),
                ),
                const SizedBox(height: 12),
                SupportSectionCard(
                  title: l10n.supportTicketConversationSection,
                  child: thread.isEmpty
                      ? _bodyText(ctx, l10n.supportTicketNoConversation)
                      : SupportLabeledTable(
                          rows: [
                            for (final m in thread) ...[
                              SupportLabeledRow(
                                label: l10n.supportTicketMessageFrom,
                                child: _bodyText(
                                  ctx,
                                  SupportTicketPolicy.isWelcomeText(
                                    '${m['text'] ?? ''}',
                                  )
                                      ? l10n.supportTicketWelcomeRow
                                      : ('${m['role'] ?? ''}' == 'staff'
                                          ? '${m['staff_name'] ?? l10n.supportTicketStaff}'
                                          : l10n.supportTicketYou),
                                ),
                              ),
                              SupportLabeledRow(
                                label: l10n.supportTicketMessageAt,
                                child: _bodyText(
                                  ctx,
                                  _fmtWhen(DateHelper.tryParse(m['at'])),
                                ),
                              ),
                              SupportLabeledRow(
                                label: l10n.supportTicketMessageBody,
                                child: _bodyText(ctx, '${m['text'] ?? ''}'),
                              ),
                            ],
                          ],
                        ),
                ),
                const SizedBox(height: 12),
                SupportSectionCard(
                  title: l10n.supportTicketEscalationSection,
                  tone: escalated || canEscalate
                      ? cs.error.withValues(alpha: 0.45)
                      : null,
                  child: SupportLabeledTable(
                    rows: [
                      SupportLabeledRow(
                        label: l10n.supportTicketStatusLabel,
                        child: _bodyText(
                          ctx,
                          escalated
                              ? l10n.supportTicketStatusEscalated
                              : (canEscalate
                                  ? l10n.supportTicketEscalateReady
                                  : l10n.supportTicketEscalateHint),
                        ),
                      ),
                      if (escalated)
                        SupportLabeledRow(
                          label: l10n.supportTicketSubmittedAt,
                          child: _bodyText(ctx, _fmtWhen(escalatedAt)),
                        )
                      else if (availableAt != null) ...[
                        SupportLabeledRow(
                          label: l10n.supportTicketEscalateAvailableAt,
                          child: _bodyText(ctx, _fmtWhen(availableAt)),
                        ),
                        if (!canEscalate)
                          SupportLabeledRow(
                            label: l10n.supportTicketEscalateRemaining,
                            child: _SupportSlaClock(
                              ticket: t,
                              isAr: widget.isAr,
                              labelOf: (row) => _slaRemainingLabel(l10n, row),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => unawaited(_copyTicketSnapshot(t)),
                  icon: const Icon(Icons.copy_rounded),
                  label: Text(l10n.supportTicketCopySnapshot),
                ),
                const SizedBox(height: 8),
                if (!hasStaff)
                  Text(
                    l10n.supportTicketUnresolvedLocked,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                if (canResolve || canUnresolved || canEscalate) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (canResolve)
                        FilledButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _showRatingDialog(t);
                          },
                          child: Text(l10n.supportTicketResolvedCta),
                        ),
                      if (canUnresolved)
                        OutlinedButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _runFeedback(
                              ticketId: t.id,
                              action: 'unresolved',
                            );
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(l10n.supportTicketUnresolvedOk),
                                ),
                              );
                            }
                          },
                          child: Text(l10n.supportTicketUnresolvedCta),
                        ),
                      if (canEscalate)
                        FilledButton.tonal(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _runFeedback(
                              ticketId: t.id,
                              action: 'escalate',
                            );
                          },
                          child: Text(l10n.supportTicketEscalateCta),
                        ),
                    ],
                  ),
                ],
                if (t.contactChannel == 'whatsapp') ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _openWhatsAppResend(t),
                    icon: const Icon(
                      Icons.chat_rounded,
                      color: Color(0xFF25D366),
                    ),
                    label: Text(l10n.supportTicketFollowWhatsApp),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.supportTicketEmpty,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final t = _rows[i];
          return Card(
            child: ListTile(
              leading: Icon(
                t.kind == 'suggestion'
                    ? Icons.lightbulb_outline
                    : Icons.report_outlined,
                color: widget.accentColor,
              ),
              title: Text(
                t.subject,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                '${_statusLabel(l10n, t)}\n${_fmtWhen(t.createdAt)}',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _openTicketDetail(t),
            ),
          );
        },
      ),
    );
  }
}

class _SupportSlaClock extends StatefulWidget {
  const _SupportSlaClock({
    required this.ticket,
    required this.isAr,
    required this.labelOf,
  });

  final SupportTicketRow ticket;
  final bool isAr;
  final String Function(SupportTicketRow ticket) labelOf;

  @override
  State<_SupportSlaClock> createState() => _SupportSlaClockState();
}

class _SupportSlaClockState extends State<_SupportSlaClock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      widget.labelOf(widget.ticket),
      style: const TextStyle(fontWeight: FontWeight.w800),
    );
  }
}
