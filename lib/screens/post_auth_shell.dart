import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/auth/safe_sign_out_service.dart';
import '../main.dart' show suspendAutoLock;
import '../core/config/app_config.dart';
import '../core/onboarding/device_first_run_prefs.dart';
import '../core/onboarding/one_time_prompt_coordinator.dart';
import '../core/session/app_session.dart';
import '../l10n/app_localizations.dart';
import '../services/account_completion_service.dart';
import '../services/org_activity_service.dart';
import '../services/legacy_data_quality_service.dart';
import '../services/profile_compliance_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/fast_login_offer_host.dart';
import '../services/compliance_legal_service.dart';
import '../services/org_team_service.dart';
import '../services/user_install_session_service.dart';
import '../services/account_management_service.dart';
import 'change_password_screen.dart';
import 'fal_renewal_gate_screen.dart';
import 'legal_terms_acceptance_screen.dart';
import 'legacy_data_quality_gate_screen.dart';
import 'profile_signature_gate_screen.dart';
import 'profile_data_revision_gate_screen.dart';
import 'mandatory_data_completion_screen.dart';
import 'profile_enrollment_gate_screen.dart';
import 'org_join_pending_gate_screen.dart';
import 'profile_record_gate_screen.dart';
import 'device_management_page.dart';
import '../core/workflow/post_auth_gate_pipeline.dart';
import 'account_disabled_screen.dart';

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
  final _acctMgmt = AccountManagementService(Supabase.instance.client);

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
  Map<String, dynamic>? _platformBan;
  bool _dataQualityRequired = false;

  /// بعد الوصول لمرة إلى لوحة التطبيق: لا نُصفّر ملف الامتثال بسبب فشل عابر عند تحديث الصفحة/التركيز.
  bool _complianceRowEstablished = false;
  bool _complianceDeferredOnWeb = false;
  bool _profileEnrollmentDeferred = false;
  Timer? _deferredComplianceRetry;
  PostAuthShellStep? _lastComplianceWatchdogStep;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  void _scheduleDeferredComplianceRetry() {
    _deferredComplianceRetry?.cancel();
    _deferredComplianceRetry = Timer(const Duration(seconds: 2), () {
      if (!mounted || !_complianceDeferredOnWeb) return;
      unawaited(_loadComplianceProfile(
        preserveRowOnTransientFailure: _complianceRowEstablished,
      ));
    });
  }

  Future<void> _loadComplianceProfile({bool preserveRowOnTransientFailure = false}) async {
    final previous = _complianceRow;
    final sb = Supabase.instance.client;
    try {
      var row = await ProfileComplianceService.loadProfileRow(sb)
          .timeout(const Duration(seconds: 10), onTimeout: () => null);
      if (row == null && sb.auth.currentUser != null) {
        try {
          await sb.auth.refreshSession().timeout(const Duration(seconds: 8));
          row = await ProfileComplianceService.loadProfileRow(sb)
              .timeout(const Duration(seconds: 10), onTimeout: () => null);
        } catch (_) {}
      }
      final hasDataQualityIssues = await LegacyDataQualityService(sb)
          .hasCurrentUserRepairIssues()
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
      if (!mounted) return;
      if (row == null &&
          preserveRowOnTransientFailure &&
          previous != null &&
          _complianceRowEstablished) {
        setState(() {
          _dataQualityRequired = hasDataQualityIssues;
        });
        return;
      }
      // ويب + جوال: لا نُعلّق اللوحة عند فشل/تأخر الامتثال — إعادة محاولة لاحقاً.
      if (row == null && sb.auth.currentUser != null) {
        setState(() {
          _complianceDeferredOnWeb = true;
          _complianceRow = null;
          _dataQualityRequired = false;
        });
        _scheduleDeferredComplianceRetry();
        return;
      }
      setState(() {
        _complianceRow = row;
        _complianceDeferredOnWeb = false;
        _dataQualityRequired = hasDataQualityIssues;
      });
      unawaited(_refreshEnrollmentDeferredFlag());
    } catch (_) {
      if (!mounted) return;
      if (preserveRowOnTransientFailure &&
          previous != null &&
          _complianceRowEstablished) {
        return;
      }
      if (sb.auth.currentUser != null) {
        setState(() {
          _complianceDeferredOnWeb = true;
          _complianceRow = null;
          _dataQualityRequired = false;
        });
        _scheduleDeferredComplianceRetry();
        return;
      }
      setState(() {
        _complianceRow = null;
        _complianceDeferredOnWeb = false;
        _dataQualityRequired = false;
      });
    }
  }

  Future<void> _loadPlatformBan() async {
    try {
      final raw = await _acctMgmt.getMyPlatformBan();
      if (raw != null && raw['ok'] == true) {
        final ban = raw['ban'];
        if (ban is Map && ban.isNotEmpty) {
          if (mounted) {
            setState(() {
              _platformBan = Map<String, dynamic>.from(
                ban.map((k, v) => MapEntry(k.toString(), v)),
              );
            });
          }
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _platformBan = null);
  }

  Future<void> _refreshEnrollmentDeferredFlag() async {
    final deferred = await AccountCompletionService.isEnrollmentDeferred();
    if (!mounted) return;
    if (_profileEnrollmentDeferred == deferred) return;
    setState(() => _profileEnrollmentDeferred = deferred);
  }

  Future<void> _onRemindProfileEnrollmentLater() async {
    final tourDone = await DeviceFirstRunPrefs.isDashboardTourDone();
    await AccountCompletionService.markEnrollmentDeferred();
    if (tourDone) {
      await AccountCompletionService.requestOpenMyPageOnce();
    }
    if (!mounted) return;
    setState(() => _profileEnrollmentDeferred = true);
    await _loadComplianceProfile();
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_bootstrap());
      });
    } else {
      unawaited(_bootstrap());
    }
  }

  @override
  void dispose() {
    if (suspendAutoLock.value) suspendAutoLock.value = false;
    _resumeRefreshTimer?.cancel();
    _complianceWatchdog?.cancel();
    _deferredComplianceRetry?.cancel();
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

      await _loadComplianceProfile(
        preserveRowOnTransientFailure: _complianceRowEstablished,
      );

      if (!mounted) return;
      await _loadPlatformBan();
      if (!mounted) return;
      setState(() {
        _legal = legal ?? _legal;
        _showTerms = needTerms;
        _needPassword = needPwd;
        _pendingOrgJoin = pendingJoin;
      });
    } catch (_) {
      await _loadComplianceProfile(
        preserveRowOnTransientFailure: _complianceRowEstablished,
      );
    }
  }

  Future<void> _bootstrapLegalAndGates() async {
    final sb = Supabase.instance.client;
    if (sb.auth.currentSession != null) {
      try {
        await sb.auth.refreshSession().timeout(
          const Duration(seconds: 8),
          onTimeout: () => throw TimeoutException('refresh'),
        );
      } catch (_) {}
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final profile = await _svc.myProfileGates().timeout(
          const Duration(seconds: 8),
          onTimeout: () => null,
        );
        final legal = await _svc.activeLegalVersion().timeout(
          const Duration(seconds: 8),
          onTimeout: () => null,
        );

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
          _deviceReady = true;
        });

        if (!needTerms && !needPwd) {
          unawaited(_ensureDevice());
        }
        return;
      } catch (_) {
        if (attempt == 0) {
          try {
            await sb.auth
                .refreshSession()
                .timeout(const Duration(seconds: 6));
          } catch (_) {}
          await Future<void>.delayed(const Duration(milliseconds: 180));
          continue;
        }
        if (!mounted) return;
        _scheduleDeferredComplianceRetry();
        return;
      }
    }
  }

  Future<void> _bootstrap() async {
    // ابقَ في حالة التحقق حتى تُعرف بوابة الشروط — حتى تظهر على التطبيق وويب الجوال
    // بنفس سلوك ويندوز، ثم أكمل الجهاز/الامتثال في الخلفية.
    setState(() {
      _loading = true;
      _showTerms = false;
      _needPassword = false;
      _deviceReady = true;
      _complianceDeferredOnWeb = true;
      _deviceBlocked = false;
      _deviceBusy = false;
      _legal = null;
      _complianceRow = null;
      _dataQualityRequired = false;
      _pendingOrgJoin = null;
      _platformBan = null;
    });
    await _bootstrapLegalAndGates();
    if (!mounted) return;
    setState(() => _loading = false);
    if (!_showTerms && !_needPassword) {
      unawaited(_ensureDevice());
    }
  }

  Future<void> _onTermsAccepted(String version) async {
    try {
      await _svc.acceptTerms(version);
      await ComplianceLegalService.recordAfterTermsAccepted(
        version: version,
        lang: widget.lang,
      );
      // ثبّت جلسة المستخدم — لا تترك prefs ضيف عالقة بعد القبول.
      try {
        final uid = Supabase.instance.client.auth.currentUser?.id.trim() ?? '';
        if (uid.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(AppConfig.prefGuestModeKey, false);
          await prefs.setString(AppConfig.prefEntryModeKey, 'user');
          if (mounted) {
            try {
              await context.read<AppSession>().setUser(uid);
            } catch (_) {}
          }
          await OneTimePromptCoordinator.markSeen(
            OneTimePromptCoordinator.idForUser(
              'legal_terms_policy_coach_v2',
              uid,
            ),
          );
        }
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            widget.lang.toLowerCase() == 'en'
                ? 'Could not save terms acceptance. Please try again.'
                : 'تعذر حفظ قبول الشروط. أعد المحاولة.',
          ),
        ),
      );
      return;
    }
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
    if (_deviceBlocked || _deviceBusy) return;
    if (!mounted) return;
    // أظهر اللوحة فوراً (جوال مثل الويب) — لا ننتظر تسجيل الجهاز/الامتثال.
    setState(() {
      _deviceReady = true;
      _deviceBusy = true;
    });
    final reg = await UserInstallSessionService.registerDeviceSlotAfterSignIn()
        .timeout(const Duration(seconds: 12), onTimeout: () {
      // انتهاء المهلة: لا نحجب المستخدم — نعتبر التسجيل ناجحاً مؤقتاً.
      return RegisterDeviceSlotResult.success();
    });
    if (!mounted) return;
    if (!reg.ok && reg.code == 'device_limit') {
      setState(() {
        _deviceBlocked = true;
        _deviceBusy = false;
        _deviceReady = false;
      });
      return;
    }
    OrgActivityService.logSessionStart();
    try {
      await _svc
          .consumePendingSignupOrgJoin()
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
    Map<String, dynamic>? pendingJoin;
    try {
      pendingJoin = await _svc
          .myPendingOrgJoinBanner()
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
    unawaited(_loadComplianceProfile());
    unawaited(_loadPlatformBan());
    if (!mounted) return;
    setState(() {
      _deviceReady = true;
      _deviceBusy = false;
      _pendingOrgJoin = pendingJoin;
    });
  }

  Future<void> _declineTerms() async {
    if (!mounted) return;
    await SafeSignOutService.signOutAndNavigateToLogin(context);
  }

  Future<void> _onDeviceLimitResolved() async {
    if (!mounted) return;
    setState(() {
      _deviceBlocked = false;
      _deviceReady = false;
      _deviceBusy = false;
    });
    await _loadComplianceProfile();
    if (!mounted) return;
    await _ensureDevice();
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
      platformBan: _platformBan,
      complianceDeferredOnWeb: _complianceDeferredOnWeb,
      profileEnrollmentDeferred: _profileEnrollmentDeferred,
    );

    if (step == PostAuthShellStep.ready ||
        step == PostAuthShellStep.readyWithFalWeekBanner) {
      _complianceRowEstablished = true;
    }

    // أثناء الشروط/كلمة المرور: لا تخرج جلسة الويب بسبب تنبيه Chrome.
    final gateSensitive = step == PostAuthShellStep.legalTerms ||
        step == PostAuthShellStep.mandatoryPassword ||
        step == PostAuthShellStep.checkingLoading;
    if (suspendAutoLock.value != gateSensitive) {
      suspendAutoLock.value = gateSensitive;
    }

    if (_lastComplianceWatchdogStep != step) {
      _lastComplianceWatchdogStep = step;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateComplianceWatchdogIfNeeded(step);
      });
    }

    switch (step) {
      case PostAuthShellStep.checkingLoading:
        if (kIsWeb) {
          // ويب: اعرض اللوحة فوراً دون اقتراح الدخول السريع حتى تكتمل البوابات.
          return widget.child;
        }
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
        if (!kIsWeb && !_deviceBusy) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(_ensureDevice());
          });
        }
        // الويب: لا نحجب اللوحة حتى ينتهي تسجيل الجهاز (يُكمَل في الخلفية).
        if (kIsWeb) {
          return widget.child;
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

      case PostAuthShellStep.platformAccountSuspended:
        return AccountDisabledScreen(
          ban: _platformBan ?? const <String, dynamic>{},
        );

      case PostAuthShellStep.pendingOrgJoinApproval:
        return OrgJoinPendingGateScreen(
          lang: widget.lang,
          pending: _pendingOrgJoin ?? const <String, dynamic>{},
          onSignedOut: () async {
            if (!context.mounted) return;
            await SafeSignOutService.signOutAndNavigateToLogin(context);
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

      case PostAuthShellStep.mandatoryProfileEnrollment:
        return ProfileEnrollmentGateScreen(
          lang: widget.lang,
          onRecheck: () async {
            // أعد الجلب بأعمدة الأسماء الكاملة ثم اسمح بالمرور إن اكتمل الملف.
            await _loadComplianceProfile();
            if (!mounted) return;
            var row = _complianceRow;
            if (AccountCompletionService.needsMandatoryProfileEnrollment(row)) {
              // احتياطي: صف الامتثال قد ينقص أعمدة — افحص الصف الكامل.
              final full = await AccountCompletionService.loadRow(
                Supabase.instance.client,
              );
              if (!AccountCompletionService.needsMandatoryProfileEnrollment(
                full,
              )) {
                if (!mounted) return;
                setState(() {
                  if (full != null) {
                    _complianceRow = {
                      ...?_complianceRow,
                      ...full,
                    };
                  }
                });
              }
            }
            if (mounted) setState(() {});
          },
          onRemindLater: _onRemindProfileEnrollmentLater,
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
