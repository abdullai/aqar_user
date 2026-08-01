import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/app_logo_loading.dart';
import '../main.dart' show langNotifier;
import 'market_insights_page.dart';
import 'subscriptions/subscriptions_root_screen.dart';

/// «إدارتي» للمعلن المالك الفرد — شاشة بتبويبات منظّمة:
///   • نظرة عامة (إحصائيات + رسوم)
///   • تحليل السوق (نُقل من قائمة الثلاث نقاط إلى تبويب مستقل)
///   • إعلاناتي (قائمة سريعة)
///   • الاشتراك والمدفوعات
class OwnerIndividualDeskPage extends StatefulWidget {
  const OwnerIndividualDeskPage({
    super.key,
    required this.lang,
    required this.userId,
    this.accountType,
    this.suppressImpliedLeading = false,
    this.embedAppBar = false,
  });

  final String lang;
  final String userId;

  /// نوع الحساب الفعلي (مثلاً `owner_individual`/`user`) — يُمرَّر إلى
  /// [SubscriptionsRootScreen] حتى تظهر الباقة الأساسية الصحيحة للفرد.
  final String? accountType;

  /// عند `true`: لا سهم رجوع ضمني — الرجوع من شريط اللوحة الخارجي.
  final bool suppressImpliedLeading;

  /// داخل لوحة الرئيسية: العنوان في AppBar الخارجي فقط.
  final bool embedAppBar;

  @override
  State<OwnerIndividualDeskPage> createState() =>
      _OwnerIndividualDeskPageState();
}

class _OwnerIndividualDeskPageState extends State<OwnerIndividualDeskPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  bool get _isAr => langNotifier.value != 'en';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = _isAr ? 'إدارتي' : 'My desk';

    final tabBar = TabBar(
      controller: _tab,
      isScrollable: true,
      indicatorColor: cs.primary,
      tabs: [
        Tab(
          icon: const Icon(Icons.dashboard_customize_outlined),
          text: _isAr ? 'نظرة عامة' : 'Overview',
        ),
        Tab(
          icon: const Icon(Icons.trending_up_outlined),
          text: _isAr ? 'تحليل السوق' : 'Market insights',
        ),
        Tab(
          icon: const Icon(Icons.list_alt_outlined),
          text: _isAr ? 'إعلاناتي' : 'My listings',
        ),
        Tab(
          icon: const Icon(Icons.subscriptions_outlined),
          text: _isAr ? 'المدفوعات' : 'Payments',
        ),
      ],
    );

    final deskChildren = <Widget>[
      _OverviewTab(lang: widget.lang, userId: widget.userId),
      MarketInsightsPage(lang: widget.lang, embedAppBar: true),
      _MyListingsTab(lang: widget.lang, userId: widget.userId),
      SubscriptionsRootScreen(
        lang: widget.lang,
        accountType: (widget.accountType == null ||
                widget.accountType!.trim().isEmpty)
            ? 'owner_individual'
            : widget.accountType!,
        embedAppBar: true,
      ),
    ];

    final tabView = kIsWeb
        ? AnimatedBuilder(
            animation: _tab,
            builder: (context, _) {
              final i = _tab.index.clamp(0, deskChildren.length - 1);
              return KeyedSubtree(
                key: ValueKey<int>(i),
                child: deskChildren[i],
              );
            },
          )
        : TabBarView(
            controller: _tab,
            children: deskChildren,
          );

    if (widget.embedAppBar) {
      return Directionality(
        textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: cs.surface,
                elevation: 0.5,
                shadowColor: Colors.black26,
                child: tabBar,
              ),
              Expanded(child: tabView),
            ],
          ),
        ),
      );
    }

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.suppressImpliedLeading,
          title: Text(title),
          bottom: tabBar,
        ),
        body: tabView,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// تبويب 1: نظرة عامة
// ---------------------------------------------------------------------------

class _OverviewTab extends StatefulWidget {
  const _OverviewTab({required this.lang, required this.userId});

  final String lang;
  final String userId;

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab>
    with AutomaticKeepAliveClientMixin {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _err;
  int _total = 0;
  int _viewsSum = 0;
  final Map<String, int> _byStatus = {};
  final List<_PropMini> _topByViews = [];

  bool get _isAr => langNotifier.value != 'en';
  int get _avgViews => _total == 0 ? 0 : (_viewsSum / _total).round();
  _PropMini? get _bestListing => _topByViews.isEmpty ? null : _topByViews.first;

  @override
  bool get wantKeepAlive => true;

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
    super.build(context);
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: AppLogoLoading());
    if (_err != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SelectableText(_err!),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _isAr ? 'ملخص إعلاناتك' : 'Your listings overview',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
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
                  label: _isAr ? 'إجمالي المشاهدات' : 'Total views',
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
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
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
              _isAr ? 'أعلى الإعلانات مشاهدة' : 'Top listings by views',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
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
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ),
          ],
        ],
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

// ---------------------------------------------------------------------------
// تبويب 3: إعلاناتي (قائمة سريعة)
// ---------------------------------------------------------------------------

class _MyListingsTab extends StatefulWidget {
  const _MyListingsTab({required this.lang, required this.userId});

  final String lang;
  final String userId;

  @override
  State<_MyListingsTab> createState() => _MyListingsTabState();
}

class _MyListingsTabState extends State<_MyListingsTab>
    with AutomaticKeepAliveClientMixin {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  String? _err;
  List<Map<String, dynamic>> _rows = const [];

  bool get _isAr => langNotifier.value != 'en';

  @override
  bool get wantKeepAlive => true;

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
          .select(
              'id,title,status,views,price,created_at,property_type,bedrooms,bathrooms,area_sqm')
          .eq('owner_id', widget.userId)
          .order('created_at', ascending: false)
          .limit(100);
      if (!mounted) return;
      setState(() {
        _rows = (rows as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
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
    super.build(context);
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: AppLogoLoading());
    if (_err != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SelectableText(_err!),
        ),
      );
    }
    if (_rows.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 80),
            Icon(Icons.inbox_outlined,
                size: 56, color: cs.onSurface.withValues(alpha: 0.45)),
            const SizedBox(height: 12),
            Center(
              child: Text(
                _isAr
                    ? 'لا توجد إعلانات بعد — ابدأ بنشر إعلانك الأول.'
                    : 'No listings yet — start by posting your first ad.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final r = _rows[i];
          final title = (r['title'] ?? '').toString().trim();
          final status = (r['status'] ?? '—').toString();
          final views = (r['views'] as num?)?.toInt() ?? 0;
          final price = (r['price'] as num?)?.toDouble();
          final type = (r['property_type'] ?? '').toString();
          final bed = (r['bedrooms'] as num?)?.toInt();
          final bath = (r['bathrooms'] as num?)?.toInt();
          final area = (r['area_sqm'] as num?)?.toDouble();
          return Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.primaryContainer,
                foregroundColor: cs.onPrimaryContainer,
                child: const Icon(Icons.apartment_outlined),
              ),
              title: Text(
                title.isNotEmpty ? title : (_isAr ? 'بدون عنوان' : 'Untitled'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                [
                  if (type.isNotEmpty) type,
                  if (bed != null) (_isAr ? '$bed غرف' : '$bed bed'),
                  if (bath != null) (_isAr ? '$bath حمام' : '$bath bath'),
                  if (area != null) (_isAr ? '${area.toStringAsFixed(0)} م²' : '${area.toStringAsFixed(0)} m²'),
                  if (price != null)
                    (_isAr
                        ? '${price.toStringAsFixed(0)} ر.س'
                        : '${price.toStringAsFixed(0)} SAR'),
                  status,
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.visibility_outlined, size: 16, color: cs.primary),
                  const SizedBox(height: 2),
                  Text('$views',
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// عناصر مشتركة
// ---------------------------------------------------------------------------

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
                      fontWeight: FontWeight.w900, fontSize: 15),
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
