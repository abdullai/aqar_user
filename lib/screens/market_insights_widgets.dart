// lib/screens/market_insights_widgets.dart

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// KPI tiles without [GridView.shrinkWrap] (lighter inside [ListView]).
class MarketInsightsKpiSection extends StatelessWidget {
  final double maxWidth;
  final List<Widget> tiles;

  const MarketInsightsKpiSection({
    super.key,
    required this.maxWidth,
    required this.tiles,
  });

  @override
  Widget build(BuildContext context) {
    assert(tiles.length == 4);
    final w = maxWidth;
    if (w >= 720) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: tiles[i]),
          ],
        ],
      );
    }
    if (w >= 340) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: tiles[0]),
              const SizedBox(width: 10),
              Expanded(child: tiles[1]),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: tiles[2]),
              const SizedBox(width: 10),
              Expanded(child: tiles[3]),
            ],
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          tiles[i],
        ],
      ],
    );
  }
}

class MarketInsightsKpiTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final ColorScheme colorScheme;

  const MarketInsightsKpiTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = colorScheme.primary.withValues(alpha: 0.28);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MarketInsightsBarMapChart extends StatelessWidget {
  final Map<String, int> data;
  final Color color;
  final String Function(String key)? labelFormatter;

  const MarketInsightsBarMapChart({
    super.key,
    required this.data,
    required this.color,
    this.labelFormatter,
  });

  static String shortLabel(String raw) {
    if (raw.length <= 10) return raw;
    return '${raw.substring(0, 8)}…';
  }

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.length > 8 ? entries.sublist(0, 8) : entries;
    if (top.isEmpty) return const SizedBox.shrink();

    final maxY = top.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final cap = maxY == 0 ? 1.0 : maxY * 1.15;
    final bottomReserved =
        MediaQuery.sizeOf(context).width < 360 ? 44.0 : 38.0;
    final theme = Theme.of(context);
    final outlineVariant = theme.colorScheme.outlineVariant
        .withValues(alpha: 0.5);
    final labelStyle = theme.textTheme.labelSmall;

    return RepaintBoundary(
      child: BarChart(
        BarChartData(
          maxY: cap.toDouble(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: outlineVariant,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (v, _) => Text(
                  v.toInt().toString(),
                  style: labelStyle,
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: bottomReserved,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= top.length) return const SizedBox();
                  final raw = top[i].key;
                  final label =
                      labelFormatter?.call(raw) ?? shortLabel(raw);
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: labelStyle,
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < top.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: top[i].value.toDouble(),
                    width: 12,
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
