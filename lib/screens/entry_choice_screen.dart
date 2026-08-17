// lib/screens/entry_choice_screen.dart
import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart'; // langNotifier + keys
import '../core/branding/app_branding.dart';
import '../core/branding/branding_logo_image.dart';
import '../core/session/app_session.dart';
import '../core/session/web_session_ttl.dart';
import '../core/theme/app_appearance_bridge.dart';

// ✅ Internet guard
import '../services/connectivity_guard.dart';
import '../core/navigation/post_auth_navigation.dart';
import '../core/auth/auth_local_sign_out.dart';
import '../services/fast_login_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/app_about_credits.dart';
import '../widgets/session_identity_panel.dart';

class EntryChoiceScreen extends StatefulWidget {
  const EntryChoiceScreen({super.key});

  static const Color primary = Color(0xFF0F766E);

  @override
  State<EntryChoiceScreen> createState() => _EntryChoiceScreenState();
}

class _EntryChoiceScreenState extends State<EntryChoiceScreen> {
  static const Color primary = EntryChoiceScreen.primary;

  bool get _isEnglish => langNotifier.value.toLowerCase().startsWith('en');

  // عرض هوية + اسم رباعي بدل الإيميل
  bool _loadingProfile = false;
  String? _profileUsername; // national id (10 digits)
  String? _profileFullName;
  String? _profileError;

  String _packageVersionLine = '';

  SupabaseClient get _sb => Supabase.instance.client;

  Map<String, String> _t(String lang) {
    final ar = <String, String>{
      'app': AppBranding.displayName(isAr: true),
      'choose': 'اختر طريقة الدخول',
      'asUser': 'الدخول كمستخدم',
      'asGuest': 'الدخول كضيف',
      'continueUser': 'متابعة كمستخدم',
      'logout': 'تسجيل خروج',
      'signed': 'مسجل دخول',
      'id': 'الهوية/الإقامة',
      'loadingProfile': 'جاري التحميل...',
      'errorLoadingProfile': 'خطأ في تحميل البيانات',
    };
    final en = <String, String>{
      'app': AppBranding.displayName(isAr: false),
      'choose': 'Choose how to continue',
      'asUser': 'Continue as user',
      'asGuest': 'Continue as guest',
      'continueUser': 'Continue as user',
      'logout': 'Sign out',
      'signed': 'Signed in',
      'id': 'ID/Iqama',
      'loadingProfile': 'Loading...',
      'errorLoadingProfile': 'Error loading profile',
    };
    return (lang.toLowerCase().startsWith('en')) ? en : ar;
  }

  Future<bool> _ensureInternetOrAlert() async {
    final ok = await ConnectivityGuard.hasInternet();
    return ok;
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadPackageVersionLine());
      _loadProfileIfSignedIn();
    });
  }

  Future<void> _loadPackageVersionLine() async {
    try {
      final p = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _packageVersionLine = '${p.version} (${p.buildNumber})';
      });
    } catch (_) {}
  }

  Future<void> _loadProfileIfSignedIn() async {
    SupabaseClient sb;
    try {
      sb = _sb;
    } catch (e, st) {
      debugPrint('EntryChoice: Supabase not ready: $e');
      debugPrint('$st');
      return;
    }

    final user = sb.auth.currentUser;
    if (user == null) {
      setState(() {
        _profileUsername = null;
        _profileFullName = null;
        _profileError = null;
      });
      return;
    }

    if (_loadingProfile) return;
    if (mounted) {
      setState(() {
        _loadingProfile = true;
        _profileError = null;
      });
    }

    try {
      final res = await sb
          .from('users_profiles')
          .select('username, full_name, full_name_ar, full_name_en')
          .eq('user_id', user.id)
          .limit(1)
          .maybeSingle();

      if (!mounted) return;

      if (res != null) {
        final username = (res['username'] ?? '').toString().trim();

        final fullNameAr = (res['full_name_ar'] ?? '').toString().trim();
        final fullNameEn = (res['full_name_en'] ?? '').toString().trim();
        final fullName = (res['full_name'] ?? '').toString().trim();

        final pickedName = (_isEnglish
                ? (fullNameEn.isNotEmpty ? fullNameEn : fullName)
                : (fullNameAr.isNotEmpty ? fullNameAr : fullName))
            .trim();

        setState(() {
          _profileUsername = username.isEmpty ? null : username;
          _profileFullName = pickedName.isEmpty ? null : pickedName;
          _profileError = null;
        });
      } else {
        setState(() {
          _profileUsername = null;
          _profileFullName = null;
          _profileError = null;
        });
      }
    } catch (e, st) {
      debugPrint('EntryChoice _loadProfile error: $e');
      debugPrint('$st');
      if (mounted) {
        setState(() {
          _profileError = e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _goUser() async {
    final okNet = await _ensureInternetOrAlert();
    if (!mounted) return;
    ConnectivityGuard.showOfflineSnackIfNeeded(context, okNet);
    if (!okNet) return;

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/login');
  }

  Future<void> _goGuest() async {
    final okNet = await _ensureInternetOrAlert();
    if (!mounted) return;
    ConnectivityGuard.showOfflineSnackIfNeeded(context, okNet);
    if (!okNet) return;

    if (!mounted) return;
    final appSession = context.read<AppSession>();

    // ✅ لا تعمل Supabase signOut هنا (كان يطلق signedOut ويصفر guest prefs)
    try {
      await appSession.setGuest(); // يضبط prefs + signOut local للموبايل
    } catch (e, st) {
      debugPrint('EntryChoice setGuest error: $e');
      debugPrint('$st');
    }
    unawaited(syncSessionAppearanceNotifiers?.call() ?? Future.value());

    if (!mounted) return;
    unawaited(touchWebGuestActivity());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(PostAuthNavigation.openDashboard(context));
    });
  }

  Future<void> _continueAsUser() async {
    final okNet = await _ensureInternetOrAlert();
    if (!mounted) return;
    ConnectivityGuard.showOfflineSnackIfNeeded(context, okNet);
    if (!okNet) return;

    if (!mounted) return;
    final appSession = context.read<AppSession>();

    final s = _sb.auth.currentSession;
    if (s == null) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
      return;
    }

    try {
      await appSession.setUser(s.user.id);
    } catch (e, st) {
      debugPrint('EntryChoice setUser error: $e');
      debugPrint('$st');
    }

    if (!mounted) return;
    unawaited(PostAuthNavigation.openDashboard(context));
  }

  Future<void> _signOutHere() async {
    final okNet = await _ensureInternetOrAlert();
    if (!mounted) return;
    ConnectivityGuard.showOfflineSnackIfNeeded(context, okNet);
    if (!okNet) return;

    if (!mounted) return;
    final appSession = context.read<AppSession>();

    try {
      await AuthLocalSignOut.signOutLocal(_sb);
    } catch (e, st) {
      debugPrint('EntryChoice signOut error: $e');
      debugPrint('$st');
    }

    try {
      await appSession.logout();
    } catch (e, st) {
      debugPrint('EntryChoice logout error: $e');
      debugPrint('$st');
    }

    setState(() {
      _profileUsername = null;
      _profileFullName = null;
      _profileError = null;
    });

    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final tr = _t(langNotifier.value);

    final bgTop = isDark ? const Color(0xFF071015) : const Color(0xFFF2FBF8);
    final bgBottom = isDark ? const Color(0xFF05070C) : const Color(0xFFF7F7F7);

    final user = _sb.auth.currentUser;
    final showSignedBox = user != null;

    return Directionality(
      textDirection: _isEnglish ? TextDirection.ltr : TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? Colors.black : Colors.white,
        body: SafeArea(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [bgTop, bgBottom],
              ),
            ),
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 600;

                  return SingleChildScrollView(
                    padding: EdgeInsets.all(isNarrow ? 16.0 : 24.0),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isNarrow ? double.infinity : 980,
                      ),
                      child: Card(
                        elevation: 0,
                        color: cs.surface.withOpacity(isDark ? 0.82 : 0.92),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: BorderSide(
                            color: primary.withOpacity(isDark ? 0.22 : 0.18),
                          ),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(isNarrow ? 20.0 : 32.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _header(
                                context: context,
                                appName: AppBranding.displayNameForContext(
                                  context,
                                  isAr: !_isEnglish,
                                ),
                                subtitle: tr['choose']!,
                                cs: cs,
                                isDark: isDark,
                              ),
                              SizedBox(height: isNarrow ? 20 : 24),
                              if (showSignedBox) ...[
                                SessionIdentityPanel(
                                  isAr: !_isEnglish,
                                  displayName: (_profileFullName ?? '').trim().isNotEmpty
                                      ? _profileFullName!.trim()
                                      : (tr['signed'] ?? ''),
                                  maskedId: FastLoginService.maskNationalId(
                                    _profileUsername,
                                  ),
                                  headline: _isEnglish
                                      ? 'Session active'
                                      : 'جلسة مفعّلة',
                                  statusLabel: _loadingProfile
                                      ? tr['loadingProfile']
                                      : (_profileError != null
                                          ? tr['errorLoadingProfile']
                                          : (_isEnglish
                                              ? 'Choose how to continue'
                                              : 'اختر طريقة المتابعة')),
                                  accent: primary,
                                  compact: isNarrow,
                                ),
                                Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: TextButton(
                                    onPressed: _signOutHere,
                                    child: Text(
                                      tr['logout']!,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(height: isNarrow ? 12 : 16),
                              ],
                              Wrap(
                                spacing: 16,
                                runSpacing: 16,
                                alignment: WrapAlignment.center,
                                children: [
                                  _buildChoiceTile(
                                    isNarrow: isNarrow,
                                    title: showSignedBox
                                        ? tr['continueUser']!
                                        : tr['asUser']!,
                                    icon: Icons.person_rounded,
                                    topBadgeIcon: Icons.badge_outlined,
                                    accent: primary,
                                    filled: true,
                                    onTap: showSignedBox ? _continueAsUser : _goUser,
                                  ),
                                  _buildChoiceTile(
                                    isNarrow: isNarrow,
                                    title: tr['asGuest']!,
                                    icon: Icons.person_outline_rounded,
                                    topBadgeIcon: Icons.how_to_reg_outlined,
                                    accent: primary,
                                    filled: false,
                                    onTap: _goGuest,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: _packageVersionLine.isEmpty
                                        ? const SizedBox.shrink()
                                        : SelectableText(
                                            _isEnglish
                                                ? '${kIsWeb ? 'Web' : 'Mobile app'} — Version: $_packageVersionLine'
                                                : '${kIsWeb ? 'منصّة ويب' : 'تطبيق جوّال'} — الإصدار: $_packageVersionLine',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: cs.onSurfaceVariant,
                                            ),
                                          ),
                                  ),
                                  const SizedBox(width: 8),
                                  Material(
                                    color: primary.withOpacity(
                                        isDark ? 0.22 : 0.12),
                                    shape: const CircleBorder(),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      onTap: () => AppAboutCredits.show(
                                        context,
                                        isAr: !_isEnglish,
                                        versionLine: _packageVersionLine,
                                      ),
                                      child: const Padding(
                                        padding: EdgeInsets.all(6),
                                        child: Icon(
                                          Icons.priority_high_rounded,
                                          size: 18,
                                          color: primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (kIsWeb) const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChoiceTile({
    required bool isNarrow,
    required String title,
    required IconData icon,
    required IconData topBadgeIcon,
    required Color accent,
    required bool filled,
    required Future<void> Function() onTap,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final width = isNarrow ? double.infinity : 280.0;

    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: filled ? accent : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: filled ? accent.withOpacity(0.0) : accent.withOpacity(0.50),
              width: 1.2,
            ),
            boxShadow: filled
                ? [
                    BoxShadow(
                      blurRadius: 18,
                      color: accent.withOpacity(0.22),
                      offset: const Offset(0, 12),
                    )
                  ]
                : const [],
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: filled
                      ? Colors.white.withOpacity(0.16)
                      : accent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 26,
                      color: filled ? Colors.white : accent,
                    ),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Icon(
                        topBadgeIcon,
                        size: 15,
                        color: filled ? Colors.white70 : accent.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    color: filled ? Colors.white : onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                ),
              ),
              Icon(
                _isEnglish ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
                color: filled ? Colors.white : accent,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header({
    required BuildContext context,
    required String appName,
    required String subtitle,
    required ColorScheme cs,
    required bool isDark,
  }) {
    return Column(
      children: [
        Container(
          height: 128,
          alignment: Alignment.center,
          child: BrandingLogoImage(
            height: 128,
            width: 128,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            errorIcon: Icons.home_work_outlined,
          ),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            appName,
            style: TextStyle(
              fontSize: AppBranding.titleFontSize(context),
              fontWeight: FontWeight.w900,
              color: cs.onSurface,
              letterSpacing: 0.2,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            softWrap: false,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: cs.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _signedBox({
    required ColorScheme cs,
    required bool isDark,
    required Map<String, String> tr,
    required Future<void> Function() onLogout,
    required bool loading,
    required String? username,
    required String? fullName,
    required String? error,
  }) {
    final boxBg = primary.withOpacity(isDark ? 0.14 : 0.10);
    final border = primary.withOpacity(isDark ? 0.28 : 0.20);

    final nameLine = (fullName ?? '').trim();
    final idLine = (username ?? '').trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: boxBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: primary.withOpacity(isDark ? 0.20 : 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.verified_user_rounded, color: primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      tr['signed']!,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                    ),
                    if (loading) ...[
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: AppLogoLoading(compact: true, size: 16),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                if (error != null)
                  Text(
                    tr['errorLoadingProfile']!,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: cs.error.withValues(alpha: 0.85),
                    ),
                  )
                else if (loading)
                  Text(
                    tr['loadingProfile']!,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: cs.onSurfaceVariant,
                    ),
                  )
                else ...[
                  if (nameLine.isNotEmpty)
                    Text(
                      nameLine,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                    ),
                  if (idLine.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${tr['id']!}: $idLine',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: onLogout,
            child: Text(
              tr['logout']!,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}