import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/utils/compound_display_name.dart';
import '../core/utils/date_helper.dart';
import '../core/presence/presence_display_prefs.dart';
import '../l10n/app_localizations.dart';
import 'aqar_marquee_text.dart';
import 'user_presence_strip.dart';

/// لوحة حقائق إتمام الصفقة للمالك والمتقدم — اسم ذكي بلا التفاف، تواريخ يوم/شهر/سنةم ثم الوقت.
class DealApplicantTransparencyBoard extends StatefulWidget {
  const DealApplicantTransparencyBoard({
    super.key,
    required this.isAr,
    required this.applicantName,
    required this.requestedAt,
    this.expiresAt,
    this.applicantAddress,
    this.applicantNote,
    this.applicantUserId,
    this.ownerName,
    this.ownerUserId,
    this.approvedAt,
    this.ownerApproved = false,
    this.queueIndex,
    this.queueTotal,
    this.showSecretQueueHint = true,
  });

  final bool isAr;
  final String applicantName;
  final DateTime? requestedAt;
  final DateTime? expiresAt;
  final String? applicantAddress;
  final String? applicantNote;
  final String? applicantUserId;
  final String? ownerName;
  final String? ownerUserId;
  final DateTime? approvedAt;
  final bool ownerApproved;
  final int? queueIndex;
  final int? queueTotal;
  final bool showSecretQueueHint;

  @override
  State<DealApplicantTransparencyBoard> createState() =>
      _DealApplicantTransparencyBoardState();
}

class _DealApplicantTransparencyBoardState
    extends State<DealApplicantTransparencyBoard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  DateTime? get _windowEnd {
    if (widget.expiresAt != null) return widget.expiresAt;
    final start = widget.requestedAt;
    if (start == null) return null;
    return start.add(const Duration(hours: 72));
  }

  int? get _minutesLeft {
    final end = _windowEnd;
    if (end == null) return null;
    final m = end.difference(DateTime.now()).inMinutes;
    return m < 0 ? 0 : m;
  }

  String _fmt(DateTime dt) =>
      DateHelper.fmtCivilDateTime(dt.toLocal(), isAr: widget.isAr);

  String _smartName(String raw, double width) {
    final compact = width < 260;
    final medium = width < 420;
    return CompoundDisplayName.forToolbar(
      raw,
      compact: compact,
      medium: medium,
    );
  }

  Future<void> _copySummary(AppLocalizations l10n) async {
    final buf = StringBuffer();
    buf.writeln(l10n.dealFactsApplicantParty);
    buf.writeln(widget.applicantName);
    if (widget.requestedAt != null) {
      buf.writeln('${l10n.dealFactsRequestedAt}: ${_fmt(widget.requestedAt!)}');
    }
    final mins = _minutesLeft;
    if (mins != null) {
      buf.writeln(l10n.dealFactsRemainingMinutes(mins));
    }
    final addr = (widget.applicantAddress ?? '').trim();
    if (addr.isNotEmpty) {
      buf.writeln('${l10n.dealFactsAddress}: $addr');
    }
    final note = (widget.applicantNote ?? '').trim();
    if (note.isNotEmpty) {
      buf.writeln('${l10n.dealFactsApplicantNote}: $note');
    }
    if (widget.ownerApproved) {
      buf.writeln(l10n.dealFactsOwnerParty);
      final on = (widget.ownerName ?? '').trim();
      if (on.isNotEmpty) buf.writeln(on);
      if (widget.approvedAt != null) {
        buf.writeln(
          '${l10n.dealFactsOwnerApprovedAt}: ${_fmt(widget.approvedAt!)}',
        );
      }
    }
    await Clipboard.setData(ClipboardData(text: buf.toString().trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.dealFactsSummaryCopied)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final mins = _minutesLeft;
    final addr = (widget.applicantAddress ?? '').trim();
    final note = (widget.applicantNote ?? '').trim();
    final qIndex = widget.queueIndex;
    final qTotal = widget.queueTotal;

    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final applicantShown = _smartName(widget.applicantName, w);
        final ownerShown = _smartName(widget.ownerName ?? '', w);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.person_outline, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: AqarMarqueeText(
                      text: applicantShown.isEmpty
                          ? l10n.dealFactsApplicantParty
                          : applicantShown,
                      height: 18,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: l10n.dealFactsCopySummary,
                    onPressed: () => unawaited(_copySummary(l10n)),
                    icon: const Icon(Icons.copy_all_outlined, size: 18),
                  ),
                ],
              ),
              if (qIndex != null && qTotal != null && qTotal > 0) ...[
                const SizedBox(height: 2),
                Text(
                  l10n.dealFactsQueueRank(qIndex, qTotal),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                    color: cs.primary,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (widget.requestedAt != null)
                    _factChip(
                      cs,
                      Icons.event_outlined,
                      '${l10n.dealFactsRequestedAt} ${_fmt(widget.requestedAt!)}',
                    ),
                  if (mins != null)
                    _factChip(
                      cs,
                      Icons.hourglass_bottom_outlined,
                      l10n.dealFactsRemainingMinutes(mins),
                      emphasize: mins <= 180,
                    ),
                ],
              ),
              if (mins != null) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.dealFactsMinutesLeftShort(mins),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    color: mins <= 180 ? cs.error : cs.primary,
                    height: 1.1,
                  ),
                ),
              ],
              if (addr.isNotEmpty) ...[
                const SizedBox(height: 8),
                _labeledBlock(l10n.dealFactsAddress, addr, cs),
              ],
              if (note.isNotEmpty) ...[
                const SizedBox(height: 8),
                _labeledBlock(l10n.dealFactsApplicantNote, note, cs),
              ],
              if (widget.ownerApproved) ...[
                const SizedBox(height: 10),
                Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
                const SizedBox(height: 8),
                Text(
                  l10n.dealOwnerAcceptedPartner,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: cs.primary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.verified_outlined, size: 16, color: cs.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: AqarMarqueeText(
                        text: ownerShown.isEmpty
                            ? l10n.dealFactsOwnerParty
                            : ownerShown,
                        height: 18,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.approvedAt != null) ...[
                  const SizedBox(height: 6),
                  _factChip(
                    cs,
                    Icons.task_alt_outlined,
                    '${l10n.dealFactsOwnerApprovedAt} ${_fmt(widget.approvedAt!)}',
                  ),
                ],
                const SizedBox(height: 8),
                if ((widget.applicantUserId ?? '').trim().isNotEmpty)
                  UserPresenceStrip(
                    userId: widget.applicantUserId!.trim(),
                    isAr: widget.isAr,
                    compact: true,
                    fallbackTimestamp: widget.requestedAt,
                    surface: PresenceDisplaySurface.listingCards,
                  ),
                if ((widget.ownerUserId ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  UserPresenceStrip(
                    userId: widget.ownerUserId!.trim(),
                    isAr: widget.isAr,
                    compact: true,
                    fallbackTimestamp: widget.approvedAt,
                    surface: PresenceDisplaySurface.listingCards,
                  ),
                ],
              ] else if (widget.showSecretQueueHint) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.dealFactsSecretUntil72,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _factChip(
    ColorScheme cs,
    IconData icon,
    String text, {
    bool emphasize = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: emphasize
              ? cs.error.withValues(alpha: 0.45)
              : cs.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: emphasize ? cs.error : cs.primary),
          const SizedBox(width: 4),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              color: emphasize ? cs.error : cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _labeledBlock(String label, String body, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 11,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          body,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            height: 1.35,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
