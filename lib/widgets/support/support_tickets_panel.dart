import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/support/support_whatsapp_launcher.dart';
import '../../services/support_ticket_service.dart';

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

  String _statusLabel(SupportTicketRow t) {
    if (widget.isAr) {
      switch (t.status) {
        case 'resolved':
          return 'تم الحل';
        case 'escalated':
          return 'مُصعَّد';
        default:
          return t.userResolution == 'unresolved' ? 'مفتوح — لم يُحل' : 'مفتوح';
      }
    }
    switch (t.status) {
      case 'resolved':
        return 'Resolved';
      case 'escalated':
        return 'Escalated';
      default:
        return t.userResolution == 'unresolved' ? 'Open — unresolved' : 'Open';
    }
  }

  Future<void> _openWhatsAppResend(SupportTicketRow t) async {
    final text = [
      widget.isAr ? 'متابعة تذكرة دعم' : 'Support ticket follow-up',
      '${widget.isAr ? 'الموضوع' : 'Subject'}: ${t.subject}',
      '${widget.isAr ? 'التفاصيل' : 'Details'}: ${t.body}',
      '${widget.isAr ? 'رقم التذكرة' : 'Ticket'}: ${t.id}',
    ].join('\n');
    await SupportWhatsappLauncher.openAllSupportLines(
      context: context,
      isAr: widget.isAr,
      message: text,
    );
  }

  Future<void> _showRatingDialog(SupportTicketRow t) async {
    var stars = 0;
    final notesCtrl = TextEditingController();
    String? noteText;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(widget.isAr ? 'تقييم الحل' : 'Rate the resolution'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if ((t.resolvedBy ?? '').isNotEmpty)
                    Text(
                      widget.isAr
                          ? 'من قام بالحل: ${t.resolvedBy}'
                          : 'Resolved by: ${t.resolvedBy}',
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
                          i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: Colors.amber.shade700,
                        ),
                      );
                    }),
                  ),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: widget.isAr ? 'ملاحظات (اختياري)' : 'Notes (optional)',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(widget.isAr ? 'تخطّي' : 'Skip'),
                ),
                FilledButton(
                  onPressed: stars > 0
                      ? () {
                          noteText = notesCtrl.text.trim();
                          Navigator.pop(ctx, true);
                        }
                      : null,
                  child: Text(widget.isAr ? 'إرسال التقييم' : 'Submit rating'),
                ),
              ],
            );
          },
        );
      },
    );
    notesCtrl.dispose();
    if (ok != true || stars <= 0) return;
    try {
      await _service.userFeedback(
        ticketId: t.id,
        action: 'resolved',
        rating: stars,
        feedback: (noteText ?? '').isEmpty ? null : noteText,
      );
    } catch (_) {}
    await _reload();
  }

  Future<void> _openTicketDetail(SupportTicketRow t) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final ack = t.details['auto_ack']?.toString();
        final adminReply = t.adminReply;
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t.subject,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  _statusLabel(t),
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (t.createdAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    DateFormat.yMMMd(
                      widget.isAr ? 'ar' : 'en',
                    ).add_Hm().format(t.createdAt!.toLocal()),
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 12),
                Text(t.body),
                if (ack != null && ack.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Material(
                    color: cs.primaryContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(ack, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
                if (adminReply != null && adminReply.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    widget.isAr ? 'رد الدعم' : 'Support reply',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(adminReply),
                ],
                const SizedBox(height: 16),
                Text(
                  widget.isAr ? 'هل تم حل المشكلة؟' : 'Was your issue resolved?',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _showRatingDialog(t);
                      },
                      child: Text(widget.isAr ? 'تم الحل' : 'Resolved'),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        try {
                          await _service.userFeedback(
                            ticketId: t.id,
                            action: 'unresolved',
                          );
                        } catch (_) {}
                        await _reload();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(widget.isAr
                                  ? 'التذكرة ما زالت مفتوحة.'
                                  : 'Ticket remains open.'),
                            ),
                          );
                        }
                      },
                      child: Text(widget.isAr ? 'لم يتم الحل' : 'Not resolved'),
                    ),
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        try {
                          await _service.userFeedback(
                            ticketId: t.id,
                            action: 'escalate',
                          );
                        } catch (_) {}
                        await _reload();
                      },
                      child: Text(widget.isAr ? 'تصعيد' : 'Escalate'),
                    ),
                  ],
                ),
                if (t.contactChannel == 'whatsapp') ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _openWhatsAppResend(t),
                    icon: const Icon(Icons.chat_rounded, color: Color(0xFF25D366)),
                    label: Text(widget.isAr ? 'متابعة عبر واتساب' : 'Follow up on WhatsApp'),
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            widget.isAr
                ? 'لا توجد تذاكر بعد. قدّم شكوى أو اقتراحاً من تبويب الدعم الفني.'
                : 'No tickets yet. Submit from the Help center tab.',
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
              subtitle: Text(_statusLabel(t)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _openTicketDetail(t),
            ),
          );
        },
      ),
    );
  }
}
