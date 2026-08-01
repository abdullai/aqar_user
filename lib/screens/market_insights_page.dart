// lib/screens/market_insights_page.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/market_insights_config.dart';
import '../l10n/app_localizations.dart';
import '../models/market_insights_snapshot.dart';
import '../services/market_insights_service.dart';
import 'market_insights_widgets.dart';

enum _LeaderboardFilter { all, individuals, marketers }

/// تحديث خلفي: إذا مرّت مدة [_staleAfter] منذ آخر نجاح، يُعاد الجلب تلقائياً.
class MarketInsightsPage extends StatefulWidget {
  final String lang;

  /// عند `true`: بدون [AppBar] (للدمج مع شريط لوحة التحكم الخارجية).
  final bool embedAppBar;

  const MarketInsightsPage({
    super.key,
    required this.lang,
    this.embedAppBar = false,
  });

  @override
  State<MarketInsightsPage> createState() => _MarketInsightsPageState();
}

class _MarketInsightsPageState extends State<MarketInsightsPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final MarketInsightsService _svc =
      MarketInsightsService(Supabase.instance.client);

  static const Duration _staleAfter = MarketInsightsConfig.staleAfter;
  static const Duration _pollInterval = MarketInsightsConfig.pollInterval;

  MarketInsightsSnapshot? _snap;
  String? _err;
  bool _loading = true;
  bool _backgroundRefreshing = false;
  Timer? _pollTimer;
  DateTime? _lastClientRefresh;
  Future<void>? _loadInFlight;

  /// تبويبات لم يُبنَ محتواها بعد (تقليل تكلفة fl_chart والقوائم الطويلة).
  final Set<int> _materializedTabs = {0};

  late TabController _tabController;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  bool get _isGuest =>
      Supabase.instance.client.auth.currentUser == null;

  String _num(int n) =>
      NumberFormat.decimalPattern(_isAr ? 'ar' : 'en').format(n);

  String _timeLabel(DateTime utc) {
    final loc = _isAr ? 'ar' : 'en';
    return DateFormat.yMMMd(loc).add_Hm().format(utc.toLocal());
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabControllerTick);
    WidgetsBinding.instance.addObserver(this);
    _load();
    _startPollTimer();
  }

  void _onTabControllerTick() {
    if (_tabController.indexIsChanging) return;
    final i = _tabController.index;
    if (!_materializedTabs.contains(i)) {
      setState(() => _materializedTabs.add(i));
    }
  }

  void _startPollTimer() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _silentRefreshIfStale());
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabControllerTick);
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPollTimer();
      _silentRefreshIfStale();
    } else if (state == AppLifecycleState.paused) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  void _silentRefreshIfStale() {
    final last = _lastClientRefresh;
    if (last == null) return;
    if (DateTime.now().difference(last) < _staleAfter) return;
    if (_loadInFlight != null) return;
    _load(silent: true);
  }

  Future<void> _load({bool silent = false}) {
    return _loadInFlight ??=
        _runLoad(silent: silent).whenComplete(() => _loadInFlight = null);
  }

  Future<void> _runLoad({bool silent = false}) async {
    if (!silent) {
      setState(() {
        if (_snap == null) _loading = true;
        _err = null;
      });
    } else {
      if (mounted) {
        setState(() => _backgroundRefreshing = true);
      }
    }
    try {
      final s = await _svc.fetchSnapshot();
      if (!mounted) return;
      setState(() {
        if (s != null) {
          _snap = s;
          _err = null;
          _lastClientRefresh = DateTime.now();
        } else if (_snap == null) {
          _err = 'parse';
        }
        _loading = false;
        _backgroundRefreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_snap == null) _err = e.toString();
        _loading = false;
        _backgroundRefreshing = false;
      });
    }
  }

  String _accountLabel(BuildContext context, String key) {
    final l10n = AppLocalizations.of(context)!;
    final k = key.toLowerCase().trim();
    switch (k) {
      case 'individual_seller':
      case 'owner_individual':
        return l10n.marketInsightsLeaderboardIndividuals;
      case 'marketer':
      case 'agency':
      case 'office':
      case 'company':
      case 'institution':
        return l10n.marketInsightsLeaderboardMarketers;
      case 'user':
      default:
        return key.isEmpty ? '—' : key;
    }
  }

  String _shareBody(AppLocalizations l10n, MarketInsightsSnapshot s) {
    final b = StringBuffer();
    b.writeln(l10n.marketInsightsTitle);
    b.writeln(
      l10n.marketInsightsLastUpdated(
        _timeLabel(_lastClientRefresh ?? s.generatedAt),
      ),
    );
    b.writeln('');
    b.writeln('${l10n.marketInsightsKpiTotal}: ${_num(s.listings.publishedTotal)}');
    b.writeln('${l10n.marketInsightsNew7d}: ${_num(s.listings.newLast7d)}');
    b.writeln('${l10n.marketInsightsNew30d}: ${_num(s.listings.newLast30d)}');
    b.writeln('${l10n.marketInsightsFeatured}: ${_num(s.listings.featuredTotal)}');
    b.writeln('${l10n.marketInsightsListingRequests}: ${_num(s.listingRequests.total)}');
    b.writeln('${l10n.marketInsightsOrgsRegistered}: ${_num(s.orgs.registered)}');
    final ex = s.extras;
    if (ex != null) {
      b.writeln(
        '${l10n.marketInsightsDistinctPublishers}: ${_num(ex.distinctListingPublishers)}',
      );
      b.writeln(
        '${l10n.marketInsightsRegisteredProfiles}: ${_num(ex.registeredProfiles)}',
      );
    }
    if (s.viewer != null) {
      b.writeln('');
      b.writeln(l10n.marketInsightsYourListings(s.viewer!.publishedListings));
      if (s.viewer!.rankGlobal != null) {
        b.writeln(
          l10n.marketInsightsYourRankGlobal(_num(s.viewer!.rankGlobal!)),
        );
      }
    }
    return b.toString();
  }

  Future<void> _shareSummary(AppLocalizations l10n) async {
    final s = _snap;
    if (s == null) return;
    await Share.share(
      _shareBody(l10n, s),
      subject: l10n.marketInsightsTitle,
    );
  }

  Future<void> _copySummary(AppLocalizations l10n) async {
    final s = _snap;
    if (s == null) return;
    await Clipboard.setData(ClipboardData(text: _shareBody(l10n, s)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.marketInsightsCopied)),
    );
  }

  void _goLogin() {
    Navigator.of(context).pushNamed('/login');
  }

  Widget _tabPlaceholder(BuildContext context, ColorScheme cs) {
    return RefreshIndicator(
      color: cs.primary,
      onRefresh: () => _load(),
      child: LayoutBuilder(
        builder: (context, c) {
          final h = c.hasBoundedHeight && c.maxHeight.isFinite
              ? c.maxHeight * 0.35
              : 160.0;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              16 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              SizedBox(height: h),
              Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final titleRow = Row(
      children: [
        Expanded(
          child: Text(
            l10n.marketInsightsTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (_backgroundRefreshing) ...[
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ],
    );
    final actions = [
      IconButton(
        tooltip: l10n.marketInsightsShareSummary,
        icon: const Icon(Icons.share_outlined),
        onPressed: _snap == null ? null : () => _shareSummary(l10n),
      ),
      IconButton(
        tooltip: l10n.marketInsightsCopySummary,
        icon: const Icon(Icons.copy_outlined),
        onPressed: _snap == null ? null : () => _copySummary(l10n),
      ),
    ];
    final tabBar = TabBar(
      controller: _tabController,
      isScrollable: true,
      tabs: [
        Tab(text: l10n.marketInsightsTabOverview),
        Tab(text: l10n.marketInsightsTabAnalytics),
        Tab(text: l10n.marketInsightsTabCommunity),
      ],
    );
    final bodyContent = _loading && _snap == null
        ? Center(child: CircularProgressIndicator(color: cs.primary))
        : _err != null && _snap == null
            ? _buildErrorState(context, l10n, theme, cs)
            : _snap == null
                ? const SizedBox.shrink()
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildOverviewTab(context, l10n, theme, cs),
                      _materializedTabs.contains(1)
                          ? _buildAnalyticsTab(context, l10n, theme, cs)
                          : _tabPlaceholder(context, cs),
                      _materializedTabs.contains(2)
                          ? _MarketInsightsCommunityTab(
                              snap: _snap!,
                              formatNum: _num,
                              accountLabel: (k) => _accountLabel(context, k),
                              onReload: () => _load(),
                            )
                          : _tabPlaceholder(context, cs),
                    ],
                  );

    if (widget.embedAppBar) {
      return Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: cs.surface,
              elevation: 0.5,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: titleRow),
                    ...actions,
                  ],
                ),
              ),
            ),
            Material(
              color: cs.surface,
              child: tabBar,
            ),
            Expanded(child: bodyContent),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: titleRow,
        actions: actions,
        bottom: tabBar,
      ),
      body: bodyContent,
    );
  }

  Widget _buildErrorState(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme cs,
  ) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
        Icon(Icons.cloud_off_outlined, size: 48, color: cs.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(
          l10n.marketInsightsLoadError,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => _load(),
          child: Text(l10n.marketInsightsRetry),
        ),
      ],
    );
  }

  Widget _buildOverviewTab(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme cs,
  ) {
    final s = _snap!;
    return RefreshIndicator(
      color: cs.primary,
      onRefresh: () => _load(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              16 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              Text(
                l10n.marketInsightsRefreshHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              if (_lastClientRefresh != null) ...[
                const SizedBox(height: 4),
                Text(
                  l10n.marketInsightsLastUpdated(
                    _timeLabel(_lastClientRefresh!),
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.leaderboard_outlined, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.marketInsightsCompetitiveHint,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_isGuest) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.marketInsightsGuestHint,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed: _goLogin,
                          child: Text(l10n.marketInsightsSignInToSeeRank),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (!_isGuest && s.viewer != null) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.marketInsightsYourSnapshot,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.marketInsightsYourListings(
                            s.viewer!.publishedListings,
                          ),
                        ),
                        Text(
                          s.viewer!.rankGlobal != null
                              ? l10n.marketInsightsYourRankGlobal(
                                  _num(s.viewer!.rankGlobal!),
                                )
                              : l10n.marketInsightsYourRankGlobal('—'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                l10n.marketInsightsPublishedTotal,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              MarketInsightsKpiSection(
                maxWidth: constraints.maxWidth,
                tiles: [
                  MarketInsightsKpiTile(
                    label: l10n.marketInsightsKpiTotal,
                    value: _num(s.listings.publishedTotal),
                    icon: Icons.list_alt_rounded,
                    colorScheme: cs,
                  ),
                  MarketInsightsKpiTile(
                    label: l10n.marketInsightsNew7d,
                    value: _num(s.listings.newLast7d),
                    icon: Icons.calendar_view_week_rounded,
                    colorScheme: cs,
                  ),
                  MarketInsightsKpiTile(
                    label: l10n.marketInsightsNew30d,
                    value: _num(s.listings.newLast30d),
                    icon: Icons.calendar_month_rounded,
                    colorScheme: cs,
                  ),
                  MarketInsightsKpiTile(
                    label: l10n.marketInsightsFeatured,
                    value: _num(s.listings.featuredTotal),
                    icon: Icons.star_outline_rounded,
                    colorScheme: cs,
                  ),
                ],
              ),
              if (s.extras != null) ...[
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: MarketInsightsKpiTile(
                        label: l10n.marketInsightsDistinctPublishers,
                        value: _num(s.extras!.distinctListingPublishers),
                        icon: Icons.groups_outlined,
                        colorScheme: cs,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MarketInsightsKpiTile(
                        label: l10n.marketInsightsRegisteredProfiles,
                        value: _num(s.extras!.registeredProfiles),
                        icon: Icons.person_search_outlined,
                        colorScheme: cs,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildAnalyticsTab(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme cs,
  ) {
    final s = _snap!;
    final chartH = (MediaQuery.sizeOf(context).shortestSide * 0.42)
        .clamp(170.0, 240.0);

    return RefreshIndicator(
      color: cs.primary,
      onRefresh: () => _load(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Text(
            l10n.marketInsightsListingRequests,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              _num(s.listingRequests.total),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: cs.primary,
              ),
            ),
          ),
          if (s.listingRequests.byStatus.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: chartH,
              child: MarketInsightsBarMapChart(
                data: s.listingRequests.byStatus,
                color: cs.primary,
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (s.listings.byAccountType.isNotEmpty) ...[
            Text(
              l10n.marketInsightsByAccountType,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: chartH,
              child: MarketInsightsBarMapChart(
                data: s.listings.byAccountType,
                color: cs.tertiary,
                labelFormatter: (k) => _accountLabel(context, k),
              ),
            ),
            const SizedBox(height: 24),
          ],
          if (s.listings.byPropertyType.isNotEmpty) ...[
            Text(
              l10n.marketInsightsByPropertyType,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: chartH,
              child: MarketInsightsBarMapChart(
                data: s.listings.byPropertyType,
                color: cs.secondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

List<MarketLeaderboardEntry> _filterLeaderboard(
  List<MarketLeaderboardEntry> rows,
  _LeaderboardFilter filter,
) {
  switch (filter) {
    case _LeaderboardFilter.all:
      return rows;
    case _LeaderboardFilter.individuals:
      return rows.where((e) => e.isIndividualSegment).toList();
    case _LeaderboardFilter.marketers:
      return rows.where((e) => e.isMarketerSegment).toList();
  }
}

class _MarketInsightsCommunityTab extends StatefulWidget {
  final MarketInsightsSnapshot snap;
  final String Function(int n) formatNum;
  final String Function(String key) accountLabel;
  final Future<void> Function() onReload;

  const _MarketInsightsCommunityTab({
    required this.snap,
    required this.formatNum,
    required this.accountLabel,
    required this.onReload,
  });

  @override
  State<_MarketInsightsCommunityTab> createState() =>
      _MarketInsightsCommunityTabState();
}

class _MarketInsightsCommunityTabState
    extends State<_MarketInsightsCommunityTab> {
  _LeaderboardFilter _filter = _LeaderboardFilter.all;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = widget.snap;
    final filtered = _filterLeaderboard(s.topPublishers, _filter);

    return RefreshIndicator(
      color: cs.primary,
      onRefresh: widget.onReload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Text(
            l10n.marketInsightsOrgsRegistered,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              widget.formatNum(s.orgs.registered),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: cs.primary,
              ),
            ),
          ),
          if (s.orgs.top.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l10n.marketInsightsTopOrgs,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            ...s.orgs.top.map(
              (o) => Card(
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    backgroundColor: cs.primaryContainer,
                    child: Text(
                      widget.formatNum(o.listingCount),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                  title: Text(
                    o.label,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    o.kind,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            l10n.marketInsightsLeaderboard,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: FilterChip(
                    label: Text(l10n.marketInsightsFilterAll),
                    selected: _filter == _LeaderboardFilter.all,
                    onSelected: (v) {
                      if (v) {
                        setState(() => _filter = _LeaderboardFilter.all);
                      }
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: FilterChip(
                    label: Text(l10n.marketInsightsLeaderboardIndividuals),
                    selected: _filter == _LeaderboardFilter.individuals,
                    onSelected: (v) {
                      if (v) {
                        setState(
                          () => _filter = _LeaderboardFilter.individuals,
                        );
                      }
                    },
                  ),
                ),
                FilterChip(
                  label: Text(l10n.marketInsightsLeaderboardMarketers),
                  selected: _filter == _LeaderboardFilter.marketers,
                  onSelected: (v) {
                    if (v) {
                      setState(() => _filter = _LeaderboardFilter.marketers);
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                l10n.marketInsightsEmpty,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            )
          else
            ...filtered.map(
              (e) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: cs.primaryContainer,
                    child: Text(
                      '${e.rank}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                  title: Text(
                    e.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${widget.accountLabel(e.accountType)} · ${widget.formatNum(e.listingCount)} ${l10n.marketInsightsListingsShort}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
