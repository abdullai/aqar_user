import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../main.dart' show langNotifier;
import '../services/org_team_service.dart';
import '../widgets/app_logo_loading.dart';
import 'organization_settings_screen.dart';

/// بعد اختيار نوع منشأة: عرض الرخصة العامة وربط بإعدادات المنشأة.
class OrganizationSetupScreen extends StatefulWidget {
  const OrganizationSetupScreen({super.key});

  @override
  State<OrganizationSetupScreen> createState() =>
      _OrganizationSetupScreenState();
}

class _OrganizationSetupScreenState extends State<OrganizationSetupScreen> {
  final _svc = OrgTeamService(Supabase.instance.client);
  bool _busy = true;
  String? _orgId;
  String? _fal;
  String? _recruit;

  bool get _isAr => langNotifier.value != 'en';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _busy = true);
    await _svc.ensureMyOrgUnit();
    final org = await _svc.orgUnitForOwner();
    final code = await _svc.getMyRecruitJoinCode();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _orgId = org?['id']?.toString();
      _fal = org != null
          ? null // لوحة كاملة من استعلام لاحق إن لزم
          : null;
      _recruit = code;
    });
    if (_orgId != null) {
      final prof = await _svc.publicOrganizationProfile(_orgId!);
      if (!mounted) return;
      setState(() {
        _fal = prof?['fal_public_code']?.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(t.orgSetupTitle)),
      body: _busy
          ? const Center(child: AppLogoLoading())
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _fal != null && _fal!.trim().isNotEmpty
                        ? t.orgSetupFalLine(_fal!.trim())
                        : '',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    _isAr
                        ? 'رمز انضمام الفريق (10 أرقام):\n${_recruit ?? '—'}'
                        : 'Team join code (10 digits):\n${_recruit ?? '—'}',
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const OrganizationSettingsScreen(),
                        ),
                      );
                    },
                    child: Text(t.orgSettingsTitle),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(_isAr ? 'متابعة' : 'Continue'),
                  ),
                ],
              ),
            ),
    );
  }
}
