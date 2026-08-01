import 'package:flutter/material.dart';

import '../core/market/instant_market_request_feed.dart';
import '../models/market_property_request_priority.dart';
import '../models/market_property_request_row.dart';

/// شارة «طلب فوري» — تظهر على البطاقات والخريطة والبحث.
class InstantMarketRequestBadge extends StatelessWidget {
  const InstantMarketRequestBadge({
    super.key,
    required this.isAr,
    this.compact = false,
    this.showRemaining = false,
    this.row,
    this.viewerRegion,
  });

  final bool isAr;
  final bool compact;
  final bool showRemaining;
  final MarketPropertyRequestRow? row;
  final String? viewerRegion;

  static bool showsFor(MarketPropertyRequestPriority p) =>
      p == MarketPropertyRequestPriority.immediate;

  String? _remainingLabel() {
    final r = row;
    if (r == null || !showRemaining) return null;
    final now = DateTime.now();
    final age = now.difference(r.sortTime);
    final requestRegion = r.regionLabel;
    final viewer = (viewerRegion ?? '').trim();
    final inRegion = viewer.isNotEmpty &&
        requestRegion.isNotEmpty &&
        InstantMarketRequestFeed.regionsMatch(viewer, requestRegion);
    final window = inRegion
        ? InstantMarketRequestFeed.sameRegionBoostDuration
        : InstantMarketRequestFeed.crossRegionBoostDuration;
    final left = window - age;
    if (left.isNegative) return null;
    final hours = left.inHours.clamp(1, 999);
    return isAr ? 'متبقي ~$hours س' : '~$hours h left';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = const Color(0xFFDC2626);
    final remaining = _remainingLabel();
    final label = compact
        ? (isAr ? 'فوري' : 'Instant')
        : (isAr ? 'طلب فوري — أولوية' : 'Instant — top priority');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 4 : 5,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_rounded, size: compact ? 13 : 14, color: accent),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            if (remaining != null) ...[
              const SizedBox(width: 6),
              Text(
                remaining,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// صف مميزات الطلب الفوري (مدفوع 30 ر.س).
class InstantMarketRequestFeatureStrip extends StatelessWidget {
  const InstantMarketRequestFeatureStrip({
    super.key,
    required this.isAr,
  });

  final bool isAr;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = isAr
        ? const [
            ('أسبوع', 'أولوية في منطقتك'),
            ('72 س', 'تعزيز باقي المناطق'),
            ('30 ر.س', 'عند اختيار «فوري» فقط'),
          ]
        : const [
            ('1 week', 'Top in your region'),
            ('72h', 'Boost elsewhere'),
            ('SAR 30', 'When you choose Instant'),
          ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (chip, tip) in items)
          Tooltip(
            message: tip,
            child: Chip(
              visualDensity: VisualDensity.compact,
              avatar: Icon(Icons.star_rounded, size: 14, color: cs.error),
              label: Text(
                chip,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
              ),
              side: BorderSide(color: cs.error.withValues(alpha: 0.35)),
              backgroundColor: cs.errorContainer.withValues(alpha: 0.35),
            ),
          ),
      ],
    );
  }
}
