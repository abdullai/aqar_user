import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../main.dart' show langNotifier, themeModeNotifier;
import '../services/org_team_service.dart';
import '../widgets/app_logo_loading.dart';

/// لوحة مراقبة للمؤسسة: رسوم بيانية + سجل النشاط (المالك يرى الفريق، العضو يرى نشاطه فقط — RLS).
class OrgMonitorDashboardPage extends StatefulWidget {
  const OrgMonitorDashboardPage({super.key, this.embedded = false});

  /// عند `true` يُعرض المحتوى فقط (للتضمين داخل [TabBarView] في «إدارتي»).
  final bool embedded;

  @override
  State<OrgMonitorDashboardPage> createState() =>
      _OrgMonitorDashboardPageState();
}

class _OrgMonitorDashboardPageState extends State<OrgMonitorDashboardPage> {
  final _svc = OrgTeamService(Supabase.instance.client);

  bool _loading = true;
  String? _errorKey;
  bool _isOwner = false;
  List<Map<String, dynamic>> _log = [];
  List<Map<String, dynamic>> _members = [];

  bool get _isAr => langNotifier.value != 'en';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorKey = null;
    });
    final ctx = await _svc.myOrgContext();
    if (ctx == null || ctx['org_id'] == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorKey = 'no_org';
        });
      }
      return;
    }
    final orgId = '${ctx['org_id']}';
    final isOwner = ctx['is_owner'] == true;
    if (isOwner) {
      await _svc.ensureMyOrgUnit();
    }
    final rows = await _svc.activityLog(orgId, limit: 300);
    List<Map<String, dynamic>> members = [];
    if (isOwner) {
      members = await _svc.listMembers(orgId);
    }
    if (!mounted) return;
    setState(() {
      _isOwner = isOwner;
      _log = rows;
      _members = members;
      _loading = false;
    });
  }

  static DateTime? _parseDt(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  static List<String> _last14DayKeys() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return List.generate(14, (i) {
      final d = today.subtract(Duration(days: 13 - i));
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    });
  }

  static Map<String, int> _dailyCounts(List<Map<String, dynamic>> log) {
    final keys = _last14DayKeys();
    final map = {for (final k in keys) k: 0};
    for (final r in log) {
      final dt = _parseDt(r['created_at'])?.toLocal();
      if (dt == null) continue;
      final k =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      if (map.containsKey(k)) {
        map[k] = map[k]! + 1;
      }
    }
    return map;
  }

  static Map<String, int> _actionCounts(List<Map<String, dynamic>> log) {
    final m = <String, int>{};
    for (final r in log) {
      final a = '${r['action'] ?? '—'}'.trim();
      if (a.isEmpty) continue;
      m[a] = (m[a] ?? 0) + 1;
    }
    return m;
  }

  static Map<String, int> _actorCounts(List<Map<String, dynamic>> log) {
    final m = <String, int>{};
    for (final r in log) {
      final id = '${r['actor_user_id'] ?? ''}';
      if (id.isEmpty) continue;
      m[id] = (m[id] ?? 0) + 1;
    }
    return m;
  }

  /// وزن بسيط للأحداث — ليس تقييماً خارجياً.
  static double _engagementWeight(String action) {
    if (action.contains('listing.created')) return 5;
    if (action.contains('listing_request')) return 3;
    if (action.contains('chat.')) return 1.5;
    if (action.contains('session.')) return 0.5;
    return 1;
  }

  static Map<String, double> _engagementByActor(List<Map<String, dynamic>> log) {
    final m = <String, double>{};
    for (final r in log) {
      final id = '${r['actor_user_id'] ?? ''}';
      if (id.isEmpty) continue;
      final a = '${r['action'] ?? ''}';
      m[id] = (m[id] ?? 0) + _engagementWeight(a);
    }
    return m;
  }

  String _profileDisplayName(Map<String, dynamic>? p) {
    if (p == null || p.isEmpty) return '—';
    final ar = '${p['full_name_ar'] ?? ''}'.trim();
    final en = '${p['full_name_en'] ?? ''}'.trim();
    final un = '${p['username'] ?? ''}'.trim();
    if (_isAr) {
      if (ar.isNotEmpty) return ar;
      if (en.isNotEmpty) return en;
    } else {
      if (en.isNotEmpty) return en;
      if (ar.isNotEmpty) return ar;
    }
    if (un.isNotEmpty) return un;
    return '—';
  }

  String _nameForActor(String userId) {
    for (final row in _members) {
      if ('${row['user_id']}' == userId) {
        final p = row['profile'];
        if (p is Map) {
          return _profileDisplayName(Map<String, dynamic>.from(p));
        }
      }
    }
    if (userId.length >= 8) return userId.substring(0, 8);
    return userId;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final dayKeys = _last14DayKeys();
    final daily = _dailyCounts(_log);
    final dailyValues = dayKeys.map((k) => daily[k] ?? 0).toList();
    final maxDaily = dailyValues.fold<int>(0, (a, b) => a > b ? a : b);
    final maxYBar = maxDaily <= 0 ? 4.0 : (maxDaily * 1.25).ceilToDouble();

    final actions = _actionCounts(_log);
    final sortedActions = actions.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topActions = sortedActions.take(6).toList();

    final actors = _actorCounts(_log);
    final sortedActors = actors.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topActors = sortedActors.take(8).toList();

    final engagement = _engagementByActor(_log);
    final sortedEng = engagement.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topEng = sortedEng.take(8).toList();

    final hasChartData = _log.isNotEmpty;
    final pieColors = [
      cs.primary,
      cs.secondary,
      cs.tertiary,
      Colors.teal.shade600,
      Colors.indigo.shade400,
      Colors.orange.shade600,
    ];

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, _, __) {
        final body = _loading
            ? const Center(child: AppLogoLoading())
            : _errorKey != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        t.orgNoOrg,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _isOwner
                                          ? t.orgMonitorRoleOwner
                                          : t.orgMonitorRoleMember,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        _StatChip(
                                          label: t.orgMonitorTotalEvents,
                                          value: '${_log.length}',
                                          color: cs.primaryContainer,
                                          onColor: cs.onPrimaryContainer,
                                        ),
                                        const SizedBox(width: 8),
                                        _StatChip(
                                          label: t.orgStatsLogins,
                                          value:
                                              '${_log.where((r) => '${r['action']}' == 'session.start').length}',
                                          color: cs.secondaryContainer,
                                          onColor: cs.onSecondaryContainer,
                                        ),
                                        const SizedBox(width: 8),
                                        _StatChip(
                                          label: t.orgStatsListings,
                                          value:
                                              '${_log.where((r) => '${r['action']}'.contains('listing')).length}',
                                          color: cs.tertiaryContainer,
                                          onColor: cs.onTertiaryContainer,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              t.orgMonitorEngagementNote,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.outline,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (!hasChartData)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 24),
                                child: Text(
                                  t.orgMonitorEmptyCharts,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyLarge,
                                ),
                              )
                            else ...[
                              Text(
                                t.orgMonitorChartDaily,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 220,
                                child: BarChart(
                                  BarChartData(
                                    alignment: BarChartAlignment.spaceAround,
                                    maxY: maxYBar,
                                    barTouchData: BarTouchData(
                                      enabled: true,
                                      touchTooltipData: BarTouchTooltipData(
                                        getTooltipColor: (_) =>
                                            cs.surfaceContainerHighest,
                                      ),
                                    ),
                                    titlesData: FlTitlesData(
                                      show: true,
                                      topTitles: const AxisTitles(
                                        sideTitles: SideTitles(showTitles: false),
                                      ),
                                      rightTitles: const AxisTitles(
                                        sideTitles: SideTitles(showTitles: false),
                                      ),
                                      bottomTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          reservedSize: 28,
                                          getTitlesWidget: (v, meta) {
                                            final i = v.toInt();
                                            if (i < 0 || i >= dayKeys.length) {
                                              return const SizedBox.shrink();
                                            }
                                            // عرض يوم/شهر فقط
                                            final parts = dayKeys[i].split('-');
                                            final label = parts.length >= 3
                                                ? '${parts[2]}/${parts[1]}'
                                                : dayKeys[i];
                                            return Padding(
                                              padding: const EdgeInsets.only(top: 8),
                                              child: Text(
                                                label,
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  color: cs.onSurfaceVariant,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      leftTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          reservedSize: 32,
                                          interval: maxYBar <= 4 ? 1 : null,
                                          getTitlesWidget: (v, meta) => Text(
                                            v == v.roundToDouble()
                                                ? '${v.toInt()}'
                                                : '',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: cs.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    gridData: FlGridData(
                                      show: true,
                                      drawVerticalLine: false,
                                      horizontalInterval:
                                          maxYBar <= 4 ? 1 : maxYBar / 4,
                                    ),
                                    borderData: FlBorderData(show: false),
                                    barGroups: List.generate(14, (i) {
                                      return BarChartGroupData(
                                        x: i,
                                        barRods: [
                                          BarChartRodData(
                                            toY: dailyValues[i].toDouble(),
                                            color: cs.primary,
                                            width: 10,
                                            borderRadius:
                                                const BorderRadius.vertical(
                                              top: Radius.circular(4),
                                            ),
                                          ),
                                        ],
                                      );
                                    }),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                t.orgMonitorChartActions,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 200,
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 5,
                                      child: PieChart(
                                        PieChartData(
                                          sectionsSpace: 2,
                                          centerSpaceRadius: 36,
                                          sections: List.generate(
                                            topActions.length,
                                            (i) {
                                              final e = topActions[i];
                                              return PieChartSectionData(
                                                value: e.value.toDouble(),
                                                title: '${e.value}',
                                                radius: 52,
                                                titleStyle: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: cs.onPrimary,
                                                ),
                                                color: pieColors[
                                                    i % pieColors.length],
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 4,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: List.generate(
                                          topActions.length,
                                          (i) {
                                            final e = topActions[i];
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 6),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 10,
                                                    height: 10,
                                                    decoration: BoxDecoration(
                                                      color: pieColors[
                                                          i % pieColors.length],
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              2),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      e.key,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_isOwner && topActors.isNotEmpty) ...[
                                const SizedBox(height: 24),
                                Text(
                                  t.orgMonitorChartMembers,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 220,
                                  child: BarChart(
                                    BarChartData(
                                      alignment: BarChartAlignment.spaceAround,
                                      maxY: () {
                                        final m = topActors
                                            .map((e) => e.value)
                                            .fold<int>(
                                                0, (a, b) => a > b ? a : b);
                                        return m <= 0
                                            ? 4.0
                                            : (m * 1.2).ceilToDouble();
                                      }(),
                                      barTouchData: BarTouchData(
                                        enabled: true,
                                        touchTooltipData: BarTouchTooltipData(
                                          getTooltipColor: (_) =>
                                              cs.surfaceContainerHighest,
                                        ),
                                      ),
                                      titlesData: FlTitlesData(
                                        show: true,
                                        topTitles: const AxisTitles(
                                          sideTitles:
                                              SideTitles(showTitles: false),
                                        ),
                                        rightTitles: const AxisTitles(
                                          sideTitles:
                                              SideTitles(showTitles: false),
                                        ),
                                        bottomTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            reservedSize: 52,
                                            getTitlesWidget: (v, meta) {
                                              final i = v.toInt();
                                              if (i < 0 ||
                                                  i >= topActors.length) {
                                                return const SizedBox.shrink();
                                              }
                                              final name = _nameForActor(
                                                  topActors[i].key);
                                              return Padding(
                                                padding:
                                                    const EdgeInsets.only(
                                                        top: 4),
                                                child: Text(
                                                  name.length > 10
                                                      ? '${name.substring(0, 10)}…'
                                                      : name,
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    color: cs.onSurfaceVariant,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                        leftTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            reservedSize: 28,
                                            getTitlesWidget: (v, meta) => Text(
                                              v == v.roundToDouble()
                                                  ? '${v.toInt()}'
                                                  : '',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: cs.onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      gridData: const FlGridData(
                                        show: true,
                                        drawVerticalLine: false,
                                      ),
                                      borderData: FlBorderData(show: false),
                                      barGroups: List.generate(
                                        topActors.length,
                                        (i) => BarChartGroupData(
                                          x: i,
                                          barRods: [
                                            BarChartRodData(
                                              toY: topActors[i]
                                                  .value
                                                  .toDouble(),
                                              color: cs.secondary,
                                              width: 14,
                                              borderRadius:
                                                  const BorderRadius.vertical(
                                                top: Radius.circular(4),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  t.orgMonitorEngagementScore,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 200,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: topEng.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 12),
                                    itemBuilder: (context, i) {
                                      final e = topEng[i];
                                      final maxE = topEng.first.value;
                                      final ratio = maxE > 0
                                          ? (e.value / maxE).clamp(0.0, 1.0)
                                          : 0.0;
                                      return SizedBox(
                                        width: 88,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Expanded(
                                              child: Align(
                                                alignment:
                                                    Alignment.bottomCenter,
                                                child: Container(
                                                  width: 36,
                                                  height: 120 * ratio + 8,
                                                  decoration: BoxDecoration(
                                                    color: cs.tertiary,
                                                    borderRadius:
                                                        const BorderRadius
                                                            .vertical(
                                                      top: Radius.circular(6),
                                                    ),
                                                  ),
                                                  alignment:
                                                      Alignment.topCenter,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            top: 4),
                                                    child: Text(
                                                      e.value.toStringAsFixed(
                                                          0),
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: cs.onTertiary,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              _nameForActor(e.key),
                                              maxLines: 2,
                                              textAlign: TextAlign.center,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ],
                            const SizedBox(height: 24),
                            Text(
                              t.orgActivityTitle,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 17,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_log.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  t.orgMonitorEmptyCharts,
                                  textAlign: TextAlign.center,
                                ),
                              )
                            else
                              ..._log.map(
                                (r) => Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    dense: true,
                                    title: Text(
                                      '${r['action'] ?? '—'}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${_isOwner ? '${_nameForActor('${r['actor_user_id'] ?? ''}')} · ' : ''}'
                                      '${r['created_at'] ?? ''}\n'
                                      '${r['entity_type'] ?? ''} ${r['entity_id'] ?? ''}',
                                    ),
                                    isThreeLine: true,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );

        return Directionality(
          textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
          child: widget.embedded
              ? body
              : Scaffold(
                  appBar: AppBar(
                    title: Text(t.orgMonitoring),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _loading ? null : _load,
                      ),
                    ],
                  ),
                  body: body,
                ),
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
    required this.onColor,
  });

  final String label;
  final String value;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: onColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: onColor.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
