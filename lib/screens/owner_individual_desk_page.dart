import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/app_logo_loading.dart';

/// «إدارتي» للمعلن الفرد: ملخص وإحصائيات ورسوم بيانية بسيطة.
class OwnerIndividualDeskPage extends StatefulWidget {
  const OwnerIndividualDeskPage({
    super.key,
    required this.lang,
    required this.userId,
  });

  final String lang;
  final String userId;

  @override
  State<OwnerIndividualDeskPage> createState() =>
      _OwnerIndividualDeskPageState();
}

class _OwnerIndividualDeskPageState extends State<OwnerIndividualDeskPage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _err;
  int _total = 0;
  int _viewsSum = 0;
  final Map<String, int> _byStatus = {};
  final List<_PropMini> _topByViews = [];

  bool get _isAr => widget.lang.toLowerCase() != 'en';
  int get _avgViews => _total == 0 ? 0 : (_viewsSum / _total).round();
  _PropMini? get _bestListing => _topByViews.isEmpty ? null : _topByViews.first;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final rows = await _sb
          .from('properties')
          .select('id,status,views,title')
          .eq('owner_id', widget.userId)
          .order('views', ascending: false);

      final list = (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      var sum = 0;
      final byStatus = <String, int>{};
      for (final r in list) {
        final v = (r['views'] as num?)?.toInt() ?? 0;
        sum += v;
        final st = (r['status'] ?? '—').toString();
        byStatus[st] = (byStatus[st] ?? 0) + 1;
      }

      final top = <_PropMini>[];
      for (var i = 0; i < list.length && i < 8; i++) {
        final r = list[i];
        top.add(
          _PropMini(
            title: (r['title'] ?? '').toString().trim(),
            views: (r['views'] as num?)?.toInt() ?? 0,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _total = list.length;
        _viewsSum = sum;
        _byStatus
          ..clear()
          ..addAll(byStatus);
        _topByViews
          ..clear()
          ..addAll(top);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = _isAr ? 'إدارتي' : 'My desk';

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _load,
            ),
          ],
        ),
        body: _loading
            ? const Center(child: AppLogoLoading())
            : _err != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: SelectableText(_err!),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          _isAr ? 'ملخص إعلاناتك' : 'Your listings overview',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _SummaryCard(
                                label: _isAr ? 'عدد الإعلانات' : 'Listings',
                                value: '$_total',
                                color: cs.primaryContainer,
                                onColor: cs.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _SummaryCard(
                                label:
                                    _isAr ? 'إجمالي المشاهدات' : 'Total views',
                                value: '$_viewsSum',
                                color: cs.secondaryContainer,
                                onColor: cs.onSecondaryContainer,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _PerformancePulseCard(
                          isAr: _isAr,
                          avgViews: _avgViews,
                          bestTitle: _bestListing?.title ?? '',
                          bestViews: _bestListing?.views ?? 0,
                        ),
                        const SizedBox(height: 20),
                        if (_byStatus.isNotEmpty) ...[
                          Text(
                            _isAr ? 'توزيع حسب الحالة' : 'By status',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 200,
                            child: PieChart(
                              PieChartData(
                                sectionsSpace: 2,
                                centerSpaceRadius: 36,
                                sections: _pieSections(cs),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        if (_topByViews.isNotEmpty) ...[
                          Text(
                            _isAr
                                ? 'أعلى الإعلانات مشاهدة'
                                : 'Top listings by views',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ..._topByViews.map(
                            (p) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(
                                  p.title.isNotEmpty
                                      ? p.title
                                      : (_isAr ? 'بدون عنوان' : 'Untitled'),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Text(
                                  '${p.views}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }

  List<PieChartSectionData> _pieSections(ColorScheme cs) {
    final entries = _byStatus.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final colors = [
      cs.primary,
      cs.secondary,
      cs.tertiary,
      Colors.teal.shade600,
      Colors.orange.shade600,
      Colors.indigo.shade400,
    ];
    var i = 0;
    return entries.map((e) {
      final c = colors[i % colors.length];
      i++;
      return PieChartSectionData(
        color: c,
        value: e.value.toDouble(),
        title: '${e.key}\n${e.value}',
        radius: 52,
        titleStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      );
    }).toList();
  }
}

class _PropMini {
  _PropMini({required this.title, required this.views});
  final String title;
  final int views;
}

class _PerformancePulseCard extends StatelessWidget {
  const _PerformancePulseCard({
    required this.isAr,
    required this.avgViews,
    required this.bestTitle,
    required this.bestViews,
  });

  final bool isAr;
  final int avgViews;
  final String bestTitle;
  final int bestViews;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasBest = bestTitle.trim().isNotEmpty || bestViews > 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: cs.primaryContainer,
            foregroundColor: cs.onPrimaryContainer,
            child: const Icon(Icons.auto_graph_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAr ? 'نبض الأداء' : 'Performance pulse',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isAr
                      ? 'متوسط المشاهدات لكل إعلان: $avgViews'
                      : 'Average views per listing: $avgViews',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (hasBest) ...[
                  const SizedBox(height: 4),
                  Text(
                    isAr
                        ? 'أفضل إعلان حالياً: ${bestTitle.trim().isEmpty ? 'بدون عنوان' : bestTitle} ($bestViews مشاهدة)'
                        : 'Best listing now: ${bestTitle.trim().isEmpty ? 'Untitled' : bestTitle} ($bestViews views)',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 26,
              color: onColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: onColor.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}
