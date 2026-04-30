import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../services/org_activity_service.dart';
import '../services/legacy_data_quality_service.dart';
import '../services/profile_compliance_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/fast_login_offer_host.dart';
import '../services/org_team_service.dart';
import 'change_password_screen.dart';
import 'fal_renewal_gate_screen.dart';
import 'legal_terms_acceptance_screen.dart';
import 'legacy_data_quality_gate_screen.dart';
import 'profile_signature_gate_screen.dart';
import 'profile_data_revision_gate_screen.dart';
import 'mandatory_data_completion_screen.dart';
import 'org_join_pending_gate_screen.dart';
import 'profile_record_gate_screen.dart';
import 'device_management_page.dart';
import '../core/workflow/post_auth_gate_pipeline.dart';

/// بعد التحقق (OTP): ترتيب البوابات — انظر [PostAuthGatePipeline] / [PostAuthShellStep].
///
/// عند **العودة للتطبيق** (ويب/جوال/سطح مكتب) يُعاد جلب الشروط والامتثال بصمت
/// ([_silentGateRefresh]) حتى يُحجَب المستخدم فوراً إن انتهت فالاً أو لزم توقيعاً…
///
/// الخادم: RPCs وأعمدة `users_profiles` موثّقة في `supabase/sql/20260415_post_auth_gate_contract_doc.sql`
/// و`20260323_org_teams_legal_devices.sql`.
class PostAuthShell extends StatefulWidget {
  final String lang;
  final Widget child;

  const PostAuthShell({
    super.key,
    required this.lang,
    required this.child,
  });

  @override
  State<PostAuthShell> createState() => _PostAuthShellState();
}

class _PostAuthShellState extends State<PostAuthShell>
    with WidgetsBindingObserver {
  final _svc = OrgTeamService(Supabase.instance.client);

  /// بعد العودة من الخلفية/قفل الشاشة: إعادة جلب الشروط دون إعادة تسجيل الجهاز.
  Timer? _resumeRefreshTimer;

  /// أثناء التشغيل الطبيعي: إعادة فحص الامتثال دورياً (فال/توقيع/مراجعة…).
  Timer? _complianceWatchdog;

  bool _loading = true;
  bool _showTerms = false;
  bool _needPassword = false;
  Map<String, dynamic>? _legal;

  bool _deviceBusy = false;
  bool _deviceReady = false;
  bool _deviceBlocked = false;

  Map<String, dynamic>? _complianceRow;
  Map<String, dynamic>? _pendingOrgJoin;
  bool _dataQualityRequired = false;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  Future<void> _loadComplianceProfile() async {
    try {
      final row = await ProfileComplianceService.loadProfileRow(
          Supabase.instance.client);
      final hasDataQualityIssues =
          await LegacyDataQualityService(Supabase.instance.client)
              .hasCurrentUserRepairIssues();
      if (!mounted) return;
      setState(() {
        _complianceRow = row;
        _dataQualityRequired = hasDataQualityIssues;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _complianceRow = null;
        _dataQualityRequired = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _resumeRefreshTimer?.cancel();
    _complianceWatchdog?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _updateComplianceWatchdogIfNeeded(PostAuthShellStep step) {
    final want = step == PostAuthShellStep.ready ||
        step == PostAuthShellStep.readyWithFalWeekBanner;
    if (!want) {
      _complianceWatchdog?.cancel();
      _complianceWatchdog = null;
      return;
    }
    if (_complianceWatchdog != null) return;
    _complianceWatchdog = Timer.periodic(const Duration(seconds: 75), (_) {
      _scheduleSilentGateRefresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleSilentGateRefresh();
    }
  }

  void _scheduleSilentGateRefresh() {
    if (_loading) return;
    _resumeRefreshTimer?.cancel();
    _resumeRefreshTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted) unawaited(_silentGateRefresh());
    });
  }

  /// إعادة تقييم الشروط (شروط، كلمة مرور، امتثال فال/توقيع، مراجعة بيانات…)
  /// بسرعة ودون شاشة تحميل كاملة — يُستدعى عند العودة للتطبيق.
  Future<void> _silentGateRefresh() async {
    if (!mounted || _loading) return;
    try {
      final profile = await _svc.myProfileGates();
      final legal = await _svc.activeLegalVersion();

      final accepted = profile?['terms_version_accepted']?.toString() ?? '';
      final activeVersion = legal?['version']?.toString() ?? '';
      final needTerms = legal != null &&
          activeVersion.isNotEmpty &&
          accepted != activeVersion;
      final needPwd = profile?['must_change_password'] == true;

      Map<String, dynamic>? pendingJoin;
      try {
        pendingJoin = await _svc.myPendingOrgJoinBanner();
      } catch (_) {}

      await _loadComplianceProfile();

      if (!mounted) return;
      setState(() {
        _legal = legal ?? _legal;
        _showTerms = needTerms;
        _needPassword = needPwd;
        _pendingOrgJoin = pendingJoin;
      });
    } catch (_) {
      await _loadComplianceProfile();
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _showTerms = false;
      _needPassword = false;
      _legal = null;
      _deviceBlocked = false;
      _deviceReady = false;
      _complianceRow = null;
      _dataQualityRequired = false;
      _pendingOrgJoin = null;
    });

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final profile = await _svc.myProfileGates();
        final legal = await _svc.activeLegalVersion();

        final accepted = profile?['terms_version_accepted']?.toString() ?? '';
        final activeVersion = legal?['version']?.toString() ?? '';
        final needTerms = legal != null &&
            activeVersion.isNotEmpty &&
            accepted != activeVersion;

        final needPwd = profile?['must_change_password'] == true;

        if (!mounted) return;
        setState(() {
          _legal = legal;
          _showTerms = needTerms;
          _needPassword = needPwd;
          _loading = false;
        });

        if (!needTerms && !needPwd) {
          unawaited(_ensureDevice());
        }
        return;
      } catch (_) {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 450));
          continue;
        }
        if (!mounted) return;
        setState(() {
          _loading = false;
          _showTerms = false;
          _needPassword = false;
        });
        unawaited(_ensureDevice());
      }
    }
  }

  Future<void> _onTermsAccepted(String version) async {
    try {
      await _svc.acceptTerms(version);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _showTerms = false);
    if (_needPassword) return;
    unawaited(_ensureDevice());
  }

  Future<void> _onMandatoryPasswordDone() async {
    if (!mounted) return;
    setState(() => _needPassword = false);
    unawaited(_ensureDevice());
  }

  Future<void> _ensureDevice() async {
    if (_deviceReady || _deviceBlocked || _deviceBusy) return;
    if (!mounted) return;
    setState(() => _deviceBusy = true);
    final r = await _svc.registerTrustedDevice();
    if (!mounted) return;
    final ok = r['ok'] == true;
    final err = r['error']?.toString() ?? '';
    if (err.contains('device_limit')) {
      setState(() {
        _deviceBlocked = true;
        _deviceBusy = false;
      });
      return;
    }
    if (ok) {
      OrgActivityService.logSessionStart();
    }
    Map<String, dynamic>? pendingJoin;
    try {
      pendingJoin = await _svc.myPendingOrgJoinBanner();
    } catch (_) {}
    await _loadComplianceProfile();
    if (!mounted) return;
    setState(() {
      _deviceReady = true;
      _deviceBusy = false;
      _pendingOrgJoin = pendingJoin;
    });
  }

  Future<void> _declineTerms() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
  }

  Future<void> _onDeviceLimitResolved() async {
    Map<String, dynamic>? pendingJoin;
    try {
      pendingJoin = await _svc.myPendingOrgJoinBanner();
    } catch (_) {}
    await _loadComplianceProfile();
    if (!mounted) return;
    setState(() {
      _deviceBlocked = false;
      _deviceBusy = false;
      _deviceReady = true;
      _pendingOrgJoin = pendingJoin;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final step = PostAuthGatePipeline.resolve(
      loading: _loading,
      showTerms: _showTerms,
      legal: _legal,
      needPassword: _needPassword,
      deviceBlocked: _deviceBlocked,
      deviceReady: _deviceReady,
      complianceRow: _complianceRow,
      dataQualityRequired: _dataQualityRequired,
      pendingOrgJoin: _pendingOrgJoin,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateComplianceWatchdogIfNeeded(step);
    });

    switch (step) {
      case PostAuthShellStep.checkingLoading:
        return Directionality(
          textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogoLoading(),
                  const SizedBox(height: 16),
                  Text(
                    t?.postAuthChecking ??
                        (_isAr ? 'جاري التحقق…' : 'Checking account…'),
                  ),
                ],
              ),
            ),
          ),
        );

      case PostAuthShellStep.legalTerms:
        return LegalTermsAcceptanceScreen(
          lang: widget.lang,
          legal: _legal!,
          onAccept: _onTermsAccepted,
          onDecline: _declineTerms,
        );

      case PostAuthShellStep.mandatoryPassword:
        return ChangePasswordScreen(
          mandatoryTeamReset: true,
          onMandatorySuccess: _onMandatoryPasswordDone,
        );

      case PostAuthShellStep.deviceLimitBlocked:
        return Directionality(
          textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
          child: DeviceManagementPage(
            mandatory: true,
            onMandatoryResolved: _onDeviceLimitResolved,
          ),
        );

      case PostAuthShellStep.deviceRegistering:
        if (!_deviceBusy) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(_ensureDevice());
          });
        }
        return Directionality(
          textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogoLoading(size: 72),
                  const SizedBox(height: 12),
                  Text(t?.postAuthChecking ?? '…'),
                ],
              ),
            ),
          ),
        );

      case PostAuthShellStep.profileRecordMissing:
        return ProfileRecordGateScreen(
          lang: widget.lang,
          onRetry: () async {
            await _loadComplianceProfile();
            if (mounted) setState(() {});
          },
        );

      case PostAuthShellStep.pendingOrgJoinApproval:
        return OrgJoinPendingGateScreen(
          lang: widget.lang,
          pending: _pendingOrgJoin ?? const <String, dynamic>{},
          onSignedOut: () async {
            try {
              await Supabase.instance.client.auth.signOut();
            } catch (_) {}
            if (!mounted) return;
            Navigator.of(context)
                .pushNamedAndRemoveUntil('/login', (r) => false);
          },
          onRecheck: () async {
            try {
              final p = await _svc.myPendingOrgJoinBanner();
              if (!mounted) return;
              setState(() => _pendingOrgJoin = p);
            } catch (_) {}
          },
        );

      case PostAuthShellStep.mandatoryUnifiedNational:
        return MandatoryDataCompletionScreen(
          lang: widget.lang,
          onDone: () async {
            await _loadComplianceProfile();
            if (mounted) setState(() {});
          },
        );

      case PostAuthShellStep.profileDataRevision:
        return ProfileDataRevisionGateScreen(
          lang: widget.lang,
          onDone: () async {
            await _loadComplianceProfile();
            if (mounted) setState(() {});
          },
        );

      case PostAuthShellStep.legacyDataQualityRequired:
        return LegacyDataQualityGateScreen(
          lang: widget.lang,
          onDone: () async {
            await _loadComplianceProfile();
            if (mounted) setState(() {});
          },
        );

      case PostAuthShellStep.falBlockedExpired:
        return FalRenewalGateScreen(
          lang: widget.lang,
          onRenewed: () async {
            await _loadComplianceProfile();
            if (mounted) setState(() {});
          },
        );

      case PostAuthShellStep.signatureRequired:
        return ProfileSignatureGateScreen(
          lang: widget.lang,
          onDone: () async {
            await _loadComplianceProfile();
            if (mounted) setState(() {});
          },
        );

      case PostAuthShellStep.readyWithFalWeekBanner:
        return Stack(
          children: [
            FastLoginOfferHost(lang: widget.lang, child: widget.child),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                color: Colors.orange.shade800,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      t?.falExpiryBannerWeek ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );

      case PostAuthShellStep.ready:
        return FastLoginOfferHost(lang: widget.lang, child: widget.child);
    }
  }
}
