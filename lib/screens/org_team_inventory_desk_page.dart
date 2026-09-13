import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/l10n/locale_content.dart';
import '../core/listing/property_type_catalog.dart';
import '../core/utils/app_money.dart';
import '../core/utils/date_helper.dart';
import '../l10n/app_localizations.dart';
import '../main.dart' show langNotifier;
import '../services/org_team_service.dart';
import '../widgets/app_logo_loading.dart';

/// إعلانات وطلبات كل أعضاء الفريق — طبقة «إدارتي» للمنشأة (ليست صفحتي الشخصية).
class OrgTeamInventoryDeskPage extends StatefulWidget {
  const OrgTeamInventoryDeskPage({super.key, required this.lang});

  final String lang;

  @override
  State<OrgTeamInventoryDeskPage> createState() =>
      _OrgTeamInventoryDeskPageState();
}

enum _TeamInventoryFilter { listings, marketing, market }

class _OrgTeamInventoryDeskPageState extends State<OrgTeamInventoryDeskPage> {
  final _svc = OrgTeamService(Supabase.instance.client);
  bool _loading = true;
  bool _failed = false;
  _TeamInventoryFilter _filter = _TeamInventoryFilter.listings;
  List<Map<String, dynamic>> _listings = const [];
  List<Map<String, dynamic>> _marketing = const [];
  List<Map<String, dynamic>> _market = const [];
  Map<String, String> _names = const {};

  bool get _isAr {
    final v = langNotifier.value.trim();
    if (v.isNotEmpty) return v != 'en';
    return widget.lang.toLowerCase() != 'en';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final ctx = await _svc.myOrgContext();
      final oid = '${ctx?['org_id'] ?? ''}'.trim();
      if (oid.isEmpty) {
        if (!mounted) return;
        setState(() {
          _listings = const [];
          _marketing = const [];
          _market = const [];
          _names = const {};
          _loading = false;
        });
        return;
      }
      final inv = await _svc.fetchTeamInventory(oid);
      if (!mounted) return;
      setState(() {
        _listings = inv.listings;
        _marketing = inv.marketingRequests;
        _market = inv.marketRequests;
        _names = inv.memberNames;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _visible {
    switch (_filter) {
      case _TeamInventoryFilter.listings:
        return _listings;
      case _TeamInventoryFilter.marketing:
        return _marketing;
      case _TeamInventoryFilter.market:
        return _market;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: AppLogoLoading());

    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip(
                  cs,
                  l10n.deskTabTeamInventoryListings,
                  _TeamInventoryFilter.listings,
                  _listings.length,
                ),
                _chip(
                  cs,
                  l10n.deskTabTeamInventoryMarketingRequests,
                  _TeamInventoryFilter.marketing,
                  _marketing.length,
                ),
                _chip(
                  cs,
                  l10n.deskTabTeamInventoryMarketRequests,
                  _TeamInventoryFilter.market,
                  _market.length,
                ),
              ],
            ),
          ),
          Expanded(child: _body(cs, l10n)),
        ],
      ),
    );
  }

  Widget _chip(
    ColorScheme cs,
    String label,
    _TeamInventoryFilter value,
    int count,
  ) {
    final selected = _filter == value;
    return FilterChip(
      selected: selected,
      label: Text('$label ($count)'),
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  Widget _body(ColorScheme cs, AppLocalizations l10n) {
    if (_failed) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 48),
          Text(
            l10n.deskTabTeamInventoryLoadError,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    final rows = _visible;
    if (rows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 48),
          Icon(
            Icons.inbox_outlined,
            size: 56,
            color: cs.onSurface.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.deskTabTeamInventoryEmpty,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _tile(cs, l10n, rows[i]),
    );
  }

  Widget _tile(
    ColorScheme cs,
    AppLocalizations l10n,
    Map<String, dynamic> r,
  ) {
    final rawTitle = (r['title'] ?? '').toString().trim();
    final title = rawTitle.isEmpty
        ? l10n.deskTabTeamInventoryUntitled
        : LocaleContent.forUi(rawTitle, isAr: _isAr);
    final status = LocaleContent.forUi(
      (r['status'] ?? r['workflow_stage'] ?? '').toString(),
      isAr: _isAr,
    );
    final city = LocaleContent.forUi(
      (r['city'] ?? '').toString(),
      isAr: _isAr,
    );
    final typeKey = (r['type_key'] ?? r['property_type'] ?? r['type'] ?? '')
        .toString()
        .trim();
    final typeLabel = typeKey.isEmpty
        ? ''
        : PropertyTypeCatalog.label(typeKey, _isAr);
    final uid = (r['member_user_id'] ?? r['owner_id'] ?? r['requester_id'] ?? '')
        .toString();
    final member = (_names[uid] ?? '').trim();
    final price = (r['price'] as num?)?.toDouble();
    final views = (r['views'] as num?)?.toInt();
    final created = DateHelper.tryParse(r['created_at']);
    final subtitle = [
      if (member.isNotEmpty) member,
      if (typeLabel.isNotEmpty) typeLabel,
      if (city.isNotEmpty) city,
      if (status.isNotEmpty) status,
      if (price != null && price > 0)
        AppMoney.sarPhrase(price.toStringAsFixed(0), isAr: _isAr),
      if (created != null) DateHelper.timeAgo(created, isAr: _isAr),
    ].join(' · ');
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          foregroundColor: cs.onPrimaryContainer,
          child: Icon(_iconForKind((r['kind'] ?? '').toString())),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: views == null
            ? null
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.visibility_outlined, size: 16, color: cs.primary),
                  const SizedBox(height: 2),
                  Text(
                    '$views',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
      ),
    );
  }

  IconData _iconForKind(String kind) {
    switch (kind) {
      case 'marketing_request':
        return Icons.handshake_outlined;
      case 'market_request':
        return Icons.travel_explore_outlined;
      default:
        return Icons.apartment_outlined;
    }
  }
}
