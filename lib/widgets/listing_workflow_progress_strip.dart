import 'dart:async';

import 'package:flutter/material.dart';

import '../core/notifications/hub_permit_deadline_sound.dart';
import '../core/workflow/listing_stage_ui_helper.dart';
import '../core/workflow/listing_workflow_stage.dart';
import '../services/marketing_workflow_hub.dart';

/// Shallow progress strip under listing cards (RTL-aware).
/// عند وجود [deadline] في مرحلة التصريح يُحدَّث النص كل ثانية (عدّ تنازلي حيّ).
class ListingWorkflowProgressStrip extends StatefulWidget {
  final ListingWorkflowStage stage;
  final bool compact;
  final DateTime? deadline;

  /// مسافات أخف وشريط أنحف داخل بطاقات القوائم.
  final bool dense;

  /// لتنبيه 6 ساعات + إعادة تحميل الدلوّق عند انتهاء المهلة.
  final String? permitSoundContextId;

  const ListingWorkflowProgressStrip({
    super.key,
    required this.stage,
    this.compact = true,
    this.deadline,
    this.dense = false,
    this.permitSoundContextId,
  });

  @override
  State<ListingWorkflowProgressStrip> createState() =>
      _ListingWorkflowProgressStripState();
}

class _ListingWorkflowProgressStripState
    extends State<ListingWorkflowProgressStrip> {
  Timer? _tick;

  bool get _useLiveDeadline {
    final d = widget.deadline;
    if (d == null) return false;
    if (widget.stage != ListingWorkflowStage.permitPending &&
        widget.stage != ListingWorkflowStage.permitIssued) {
      return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _armTicker();
  }

  @override
  void didUpdateWidget(ListingWorkflowProgressStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deadline != widget.deadline ||
        oldWidget.stage != widget.stage) {
      _armTicker();
    }
  }

  void _armTicker() {
    _tick?.cancel();
    _tick = null;
    if (!_useLiveDeadline) return;
    final d = widget.deadline!;
    if (d.difference(DateTime.now()).isNegative) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final left = d.difference(DateTime.now());
      if (left.isNegative) {
        _tick?.cancel();
        _tick = null;
        MarketingWorkflowHub.notifyBucketsChanged();
      }
      final ctx = widget.permitSoundContextId?.trim();
      if (ctx != null && ctx.isNotEmpty) {
        HubPermitDeadlineSoundCoordinator.maybePlaySixHourWarning(
          contextId: ctx,
          deadline: d,
        );
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final idx = ListingStageUiHelper.progressIndex(widget.stage);
    const labels = <String>[
      'استلام',
      'عروض',
      'اختيار',
      'عقد',
      'تصريح',
      'نشر',
      'حجز',
      '—',
      'إلغاء',
    ];
    final active = idx.clamp(0, labels.length - 1);
    final dl = ListingStageUiHelper.deadlineLabelAr(widget.deadline);

    final barH = widget.dense
        ? (widget.compact ? 2.5 : 3.0)
        : (widget.compact ? 3.0 : 4.0);
    final topPad = widget.dense ? 4.0 : 6.0;

    return Padding(
      padding: EdgeInsets.only(top: topPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: List.generate(labels.length, (i) {
              final done = i <= active;
              final c = done
                  ? ListingStageUiHelper.stageColor(widget.stage, cs)
                  : cs.outlineVariant;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: widget.dense ? 0.5 : 1),
                  child: Container(
                    height: barH,
                    decoration: BoxDecoration(
                      color: c.withValues(alpha: done ? 1 : 0.25),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              );
            }),
          ),
          if (!widget.compact) ...[
            SizedBox(height: widget.dense ? 3 : 4),
            Text(
              ListingStageUiHelper.stageLabelAr(widget.stage),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant,
                    fontSize: widget.dense ? 10.5 : null,
                  ),
            ),
          ],
          if (dl != null)
            Text(
              dl,
              maxLines: widget.dense ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.w600,
                    fontSize: widget.dense ? 10 : null,
                  ),
            ),
        ],
      ),
    );
  }
}
