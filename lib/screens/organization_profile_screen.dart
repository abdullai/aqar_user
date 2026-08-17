import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../services/org_team_service.dart';
import '../widgets/app_logo_loading.dart';

/// صفحة عامة للمنشأة (أي مستخدم مسجّل).
class OrganizationProfileScreen extends StatefulWidget {
  const OrganizationProfileScreen({
    super.key,
    required this.orgId,
    required this.lang,
  });

  final String orgId;
  final String lang;

  @override
  State<OrganizationProfileScreen> createState() =>
      _OrganizationProfileScreenState();
}

class _OrganizationProfileScreenState extends State<OrganizationProfileScreen> {
  final _svc = OrgTeamService(Supabase.instance.client);
  Map<String, dynamic>? _data;
  bool _loading = true;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final d = await _svc.publicOrganizationProfile(widget.orgId);
    if (!mounted) return;
    setState(() {
      _data = d;
      _loading = false;
    });
  }

  String _name(Map<String, dynamic>? m) {
    if (m == null) return '';
    final ar = (m['display_name_ar'] ?? '').toString().trim();
    final en = (m['display_name_en'] ?? '').toString().trim();
    if (_isAr) return ar.isNotEmpty ? ar : en;
    return en.isNotEmpty ? en : ar;
  }

  String _desc(Map<String, dynamic>? m) {
    if (m == null) return '';
    final ar = (m['description_ar'] ?? '').toString().trim();
    final en = (m['description_en'] ?? '').toString().trim();
    if (_isAr) return ar.isNotEmpty ? ar : en;
    return en.isNotEmpty ? en : ar;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.orgProfileTitle),
      ),
      body: _loading
          ? const Center(child: AppLogoLoading())
          : _data == null
              ? Center(
                  child: Text(_isAr ? 'تعذر التحميل' : 'Could not load'),
                )
              : CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if ((_data!['cover_url'] ?? '').toString().trim().isNotEmpty)
                            SizedBox(
                              height: 160,
                              child: CachedNetworkImage(
                                imageUrl:
                                    _data!['cover_url'].toString().trim(),
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => const SizedBox.shrink(),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if ((_data!['logo_url'] ?? '')
                                    .toString()
                                    .trim()
                                    .isNotEmpty)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: CachedNetworkImage(
                                      imageUrl: _data!['logo_url']
                                          .toString()
                                          .trim(),
                                      width: 64,
                                      height: 64,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                if ((_data!['logo_url'] ?? '')
                                    .toString()
                                    .trim()
                                    .isNotEmpty)
                                  const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _name(_data),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w900,
                                            ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${t.orgMembersCount(int.tryParse('${_data!['member_count']}') ?? 0)} / ${_data!['seat_limit']}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(color: cs.primary),
                                      ),
                                      if ((_data!['fal_public_code'] ?? '')
                                          .toString()
                                          .trim()
                                          .isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 8),
                                          child: Text(
                                            t.orgFalBadge(
                                              _data!['fal_public_code']
                                                  .toString()
                                                  .trim(),
                                            ),
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_desc(_data).isNotEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                _desc(_data),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
