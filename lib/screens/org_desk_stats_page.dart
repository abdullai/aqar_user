import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../services/org_team_service.dart';
import '../widgets/app_logo_loading.dart';

/// ملخص سريع للمقاعد والنشاط الأخير داخل «إدارتي».
class OrgDeskStatsPage extends StatefulWidget {
  const OrgDeskStatsPage({super.key, required this.lang});

  final String lang;

  @override
  State<OrgDeskStatsPage> createState() => _OrgDeskStatsPageState();
}

class _OrgDeskStatsPageState extends State<OrgDeskStatsPage> {
  final _svc = OrgTeamService(Supabase.instance.client);

  bool _loading = true;
  String? _errorKey;
  int _used = 0;
  int _limit = 0;
  List<Map<String, dynamic>> _log = [];

  bool get _isAr => widget.lang.toLowerCase() != 'en';

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
    final used = await _svc.memberCount(orgId);
    final lim = await _svc.effectiveSeatLimit(orgId);
    final log = await _svc.activityLog(orgId, limit: 25);
    if (!mounted) return;
    setState(() {
      _used = used;
      _limit = lim;
      _log = log;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const Center(child: AppLogoLoading());
    }
    if (_errorKey == 'no_org') {
      return Center(
        child: Text(
          t.orgNoOrg,
          textAlign: TextAlign.center,
        ),
      );
    }

    return RefreshIndicator(
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
                    t.deskTabInsights,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isAr
                        ? 'للرسوم التفصيلية وسجل النشاط الأوسع، افتح تبويب «المراقبة» في شريط إدارتي أعلاه.'
                        : 'For detailed charts and a fuller activity log, open the «Monitoring» tab in the My desk bar above.',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t.orgSeatUsage(_used, _limit),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _isAr ? 'آخر النشاط' : 'Recent activity',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 8),
          if (_log.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_isAr ? 'لا يوجد نشاط مسجّل بعد.' : 'No activity yet.'),
            )
          else
            ..._log.map(
              (r) => ListTile(
                dense: true,
                title: Text(
                  '${r['action'] ?? ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('${r['created_at'] ?? ''}'),
              ),
            ),
        ],
      ),
    );
  }
}
