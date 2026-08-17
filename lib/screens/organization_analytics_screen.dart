import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../main.dart' show langNotifier;
import '../services/org_team_service.dart';
import '../services/permission_service.dart';
import '../widgets/app_logo_loading.dart';

/// تقارير وإحصائيات الفريق — رسوم بيانية + جدول + تصدير CSV خفيف.
class OrganizationAnalyticsScreen extends StatefulWidget {
  const OrganizationAnalyticsScreen({
    super.key,
    required this.lang,
    this.embedded = true,
  });

  final String lang;
  final bool embedded;

  @override
  State<OrganizationAnalyticsScreen> createState() =>
      _OrganizationAnalyticsScreenState();
}

class _OrganizationAnalyticsScreenState
    extends State<OrganizationAnalyticsScreen> {
  final _svc = OrgTeamService(Supabase.instance.client);

  bool _loading = true;
  String? _orgId;
  List<Map<String, dynamic>> _members = [];
  Map<String, Map<String, int>> _contrib = {};
  List<Map<String, dynamic>> _log = [];
  bool _canExport = false;

  bool get _isAr => langNotifier.value != 'en';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final ctx = await _svc.myOrgContext();
    if (ctx == null || ctx['org_id'] == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final oid = '${ctx['org_id']}';
    final owner = ctx['is_owner'] == true;
    Map<String, dynamic>? pmap;
    final p = ctx['permissions'];
    if (p is Map) {
      pmap = Map<String, dynamic>.from(
        p.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    final canExport = PermissionService(pmap, isOwner: owner).exportData;
    final members = await _svc.listMembers(oid);
    final contrib = await _svc.fetchOrgMemberContribution(oid);
    final log = await _svc.activityLog(oid, limit: 400);
    if (!mounted) return;
    setState(() {
      _orgId = oid;
      _members = members;
      _contrib = contrib;
      _log = log;
      _canExport = canExport;
      _loading = false;
    });
  }

  Map<String, int> _last30DayCounts() {
    final now = DateTime.now();
    final map = <String, int>{};
    for (var i = 29; i >= 0; i--) {
      final d = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final k =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      map[k] = 0;
    }
    for (final r in _log) {
      final dt = DateTime.tryParse('${r['created_at']}')?.toLocal();
      if (dt == null) continue;
      final k =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      if (map.containsKey(k)) map[k] = map[k]! + 1;
    }
    return map;
  }

  int _soldRentEstForUser(String uid) {
    var n = 0;
    for (final row in _log) {
      final actor = '${row['actor_user_id'] ?? ''}';
      final action = '${row['action'] ?? ''}'.toLowerCase();
      if (actor == uid &&
          (action.contains('complete') ||
              action.contains('sold') ||
              action.contains('rent'))) {
        n++;
      }
    }
    return n;
  }

  Future<void> _exportCsv(AppLocalizations t) async {
    if (_orgId == null) return;
    final isAr = _isAr;
    final buf = StringBuffer();
    buf.writeln(
      '\uFEFFuser_id,name,properties,ads,deals_est',
    );
    for (final m in _members) {
      final uid = '${m['user_id'] ?? ''}';
      if (uid.isEmpty) continue;
      final prof =
          (m['profile'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final name = isAr
          ? '${prof['full_name_ar'] ?? prof['username'] ?? uid}'
          : '${prof['full_name_en'] ?? prof['username'] ?? uid}';
      final c = _contrib[uid] ?? {};
      buf.writeln(
        '$uid,${jsonEncode(name)},${c['properties'] ?? 0},${c['ads'] ?? 0},${_soldRentEstForUser(uid)}',
      );
    }
    await Share.share(
      buf.toString(),
      subject: isAr ? 'تقرير الفريق' : 'Team analytics export',
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const Center(child: AppLogoLoading());
    }
    if (_orgId == null) {
      return Center(child: Text(t.orgNoOrg));
    }

    final daily = _last30DayCounts();
    final entries = daily.entries.toList();
    final spots = <FlSpot>[
      for (var i = 0; i < entries.length; i++)
        FlSpot(i.toDouble(), entries[i].value.toDouble()),
    ];

    final pieSlices = <PieChartSectionData>[];
    var idx = 0;
    for (final m in _members) {
      final uid = '${m['user_id'] ?? ''}';
      if (uid.isEmpty) continue;
      final c = _contrib[uid] ?? {};
      final score = (c['properties'] ?? 0) + (c['ads'] ?? 0);
      if (score <= 0) continue;
      final hue = (idx * 47) % 360;
      pieSlices.add(
        PieChartSectionData(
          value: score.toDouble(),
          title: '$score',
          radius: 54,
          titleStyle: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: cs.onPrimary,
          ),
          color: HSLColor.fromAHSL(1, hue.toDouble(), 0.45, 0.55).toColor(),
        ),
      );
      idx++;
    }

    final body = RefreshIndicator(
      onRefresh: _load,
      child: Scrollbar(
        thumbVisibility: true,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_canExport)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton.tonalIcon(
                  onPressed: () => _exportCsv(t),
                  icon: const Icon(Icons.ios_share_outlined),
                  label: Text(t.orgExportCsv),
                ),
              ),
            if (_canExport) const SizedBox(height: 12),
            Text(
              t.deskTabAnalyticsReports,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 1,
                    getDrawingHorizontalLine: (v) => FlLine(
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (v, _) => Text(
                          v.toInt().toString(),
                          style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 5,
                        getTitlesWidget: (v, m) {
                          final i = v.toInt();
                          if (i < 0 || i >= daily.length) return const SizedBox();
                          final day = daily.keys.elementAt(i).substring(8);
                          return Text(
                            day,
                            style: TextStyle(
                              fontSize: 9,
                              color: cs.onSurfaceVariant,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: cs.primary,
                      barWidth: 3,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: cs.primary.withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              t.orgLeaderboardTitle,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: pieSlices.isEmpty ? 80 : 220,
              child: pieSlices.isEmpty
                  ? Center(child: Text(t.orgAnalyticsEmpty))
                  : PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 32,
                        sections: pieSlices,
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            ..._members.map((m) {
              final uid = '${m['user_id'] ?? ''}';
              final prof =
                  (m['profile'] as Map?)?.cast<String, dynamic>() ??
                      <String, dynamic>{};
              final name = _isAr
                  ? '${prof['full_name_ar'] ?? prof['username'] ?? uid}'
                  : '${prof['full_name_en'] ?? prof['username'] ?? uid}';
              final c = _contrib[uid] ?? {};
              final props = c['properties'] ?? 0;
              final ads = c['ads'] ?? 0;
              final deals = _soldRentEstForUser(uid);
              final score = props + ads + deals;
              final pct = (score / 48).clamp(0.0, 1.0);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text('${t.orgLeaderboardProps}: $props · ${t.orgLeaderboardAds}: $ads · ${t.organalyticsSoldRented}: $deals'),
                      const SizedBox(height: 6),
                      Text(t.organalyticsScore),
                      LinearProgressIndicator(value: pct == 0 ? null : pct),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text(t.deskTabAnalyticsReports)),
      body: body,
    );
  }
}
