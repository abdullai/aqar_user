import 'package:flutter/material.dart';

import '../core/workflow/listing_stage_ui_helper.dart';
import '../core/workflow/listing_workflow_stage.dart';

/// Shallow progress strip under listing cards (RTL-aware).
class ListingWorkflowProgressStrip extends StatelessWidget {
  final ListingWorkflowStage stage;
  final bool compact;
  final DateTime? deadline;

  /// مسافات أخف وشريط أنحف داخل بطاقات القوائم.
  final bool dense;

  const ListingWorkflowProgressStrip({
    super.key,
    required this.stage,
    this.compact = true,
    this.deadline,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final idx = ListingStageUiHelper.progressIndex(stage);
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
    final dl = ListingStageUiHelper.deadlineLabelAr(deadline);

    final barH = dense
        ? (compact ? 2.5 : 3.0)
        : (compact ? 3.0 : 4.0);
    final topPad = dense ? 4.0 : 6.0;

    return Padding(
      padding: EdgeInsets.only(top: topPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: List.generate(labels.length, (i) {
              final done = i <= active;
              final c = done
                  ? ListingStageUiHelper.stageColor(stage, cs)
                  : cs.outlineVariant;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: dense ? 0.5 : 1),
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
          if (!compact) ...[
            SizedBox(height: dense ? 3 : 4),
            Text(
              ListingStageUiHelper.stageLabelAr(stage),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant,
                    fontSize: dense ? 10.5 : null,
                  ),
            ),
          ],
          if (dl != null)
            Text(
              dl,
              maxLines: dense ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.w600,
                    fontSize: dense ? 10 : null,
                  ),
            ),
        ],
      ),
    );
  }
}
