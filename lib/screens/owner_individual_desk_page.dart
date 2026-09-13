import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import 'photographer_join_page.dart';
import 'photographer_hub_page.dart';
import '../services/photographer_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/app_page_close_button.dart';
import '../main.dart' show langNotifier;
import 'market_insights_page.dart';
import 'subscriptions/subscriptions_root_screen.dart';

/// «إدارتي» للمعلن المالك الفرد — شاشة بتبويبات منظّمة:
///   • نظرة عامة (إحصائيات + رسوم)
///   • تحليل السوق
///   • الاشتراك والمدفوعات
///
/// إدارة الإعلانات وطلبات التسويق من تبويب «صفحتي» في الشريط السفلي،
/// وليست من إدارتي. طبقة الفريق (كل إعلانات/طلبات الأعضاء) في لوحة المنشأة.
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
    _tab = TabController(length: 3, vsync: this);
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
          icon: const Icon(Icons.subscriptions_outlined),
          text: _isAr ? 'المدفوعات' : 'Payments',
        ),
      ],
    );

    final deskChildren = <Widget>[
      _OverviewTab(lang: widget.lang, userId: widget.userId),
      MarketInsightsPage(lang: widget.lang, embedAppBar: true),
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
          automaticallyImplyLeading: false,
          leading: !widget.suppressImpliedLeading
              ? AppPageCloseButton(
                  isArabic: _isAr,
                )
              : null,
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
          _PhotographerDeskEntry(lang: widget.lang),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.web_stories_outlined),
              title: Text(
                AppLocalizations.of(context)!.ownerDeskManageListingsInMyPage,
                style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35),
              ),
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

class _PhotographerDeskEntry extends StatelessWidget {
  const _PhotographerDeskEntry({required this.lang});

  final String lang;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.photo_camera_outlined),
        title: Text(
          l10n.photographerJoinCta,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(l10n.photographerReviewSla),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          PhotographerProfile? p;
          try {
            p = await PhotographerService(Supabase.instance.client).myProfile();
          } catch (_) {}
          if (!context.mounted) return;
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => p != null && p.isVerified
                  ? PhotographerHubPage(lang: lang)
                  : PhotographerJoinPage(lang: lang),
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
