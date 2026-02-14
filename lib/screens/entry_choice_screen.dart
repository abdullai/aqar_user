// lib/screens/entry_choice_screen.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart'; // langNotifier + kPrefGuestMode/kPrefEntryMode
import '../core/session/app_session.dart';

// ✅ Internet guard
import '../services/connectivity_guard.dart';
import '../shared/widgets/no_internet_dialog.dart';

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

  SupabaseClient get _sb => Supabase.instance.client;

  Map<String, String> _t(String lang) {
    final ar = <String, String>{
      'app': 'عقار موثوق',
      'choose': 'اختر طريقة الدخول',
      'asUser': 'الدخول كمستخدم',
      'asGuest': 'الدخول كضيف',
      'continueUser': 'متابعة كمستخدم',
      'logout': 'تسجيل خروج',
      'signed': 'مسجل دخول',
      'id': 'الهوية/الإقامة',
    };
    final en = <String, String>{
      'app': 'Aqar Mowthooq',
      'choose': 'Choose how to continue',
      'asUser': 'Continue as user',
      'asGuest': 'Continue as guest',
      'continueUser': 'Continue as user',
      'logout': 'Sign out',
      'signed': 'Signed in',
      'id': 'ID/Iqama',
    };
    return (lang.toLowerCase().startsWith('en')) ? en : ar;
  }

  Future<bool> _ensureInternetOrAlert() async {
    final ok = await ConnectivityGuard.hasInternet();
    if (!ok && mounted) {
      await showNoInternetDialog(context, isAr: !_isEnglish);
    }
    return ok;
  }

  @override
  void initState() {
    super.initState();

    // ✅ safer: run after first frame to avoid init-timing issues
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProfileIfSignedIn();
    });
  }

  Future<void> _loadProfileIfSignedIn() async {
    // ✅ guard: Supabase must be initialized
    SupabaseClient sb;
    try {
      sb = _sb;
    } catch (e, st) {
      debugPrint('EntryChoice: Supabase not ready: $e');
      debugPrint('$st');
      return;
    }

    final user = sb.auth.currentUser;
    if (user == null) return;

    if (_loadingProfile) return;
    if (mounted) setState(() => _loadingProfile = true);

    try {
      final res = await sb
          .from('users_profiles')
          .select('username, full_name, full_name_ar, full_name_en')
          .eq('user_id', user.id)
          .limit(1);

      if (!mounted) return;

      if (res is List && res.isNotEmpty) {
        final row = res.first as Map<String, dynamic>;
        final username = (row['username'] ?? '').toString().trim();

        final fullNameAr = (row['full_name_ar'] ?? '').toString().trim();
        final fullNameEn = (row['full_name_en'] ?? '').toString().trim();
        final fullName = (row['full_name'] ?? '').toString().trim();

        final pickedName = (_isEnglish
                ? (fullNameEn.isNotEmpty ? fullNameEn : fullName)
                : (fullNameAr.isNotEmpty ? fullNameAr : fullName))
            .trim();

        setState(() {
          _profileUsername = username.isEmpty ? null : username;
          _profileFullName = pickedName.isEmpty ? null : pickedName;
        });
      }
    } catch (e, st) {
      // ✅ don't ignore during diagnosis
      debugPrint('EntryChoice _loadProfile error: $e');
      debugPrint('$st');
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _setGuestModePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kPrefGuestMode, true);
      await prefs.setString(kPrefEntryMode, 'guest');
      await prefs.setBool('is_guest', true);
      await prefs.setBool('guest', true);
    } catch (e, st) {
      debugPrint('EntryChoice _setGuestModePrefs error: $e');
      debugPrint('$st');
    }
  }

  Future<void> _setUserModePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kPrefGuestMode, false);
      await prefs.setString(kPrefEntryMode, 'user');
      await prefs.remove('is_guest');
      await prefs.remove('guest');
    } catch (e, st) {
      debugPrint('EntryChoice _setUserModePrefs error: $e');
      debugPrint('$st');
    }
  }

  Future<void> _goUser() async {
    final okNet = await _ensureInternetOrAlert();
    if (!okNet) return;

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/login');
  }

  Future<void> _goGuest() async {
    final okNet = await _ensureInternetOrAlert();
    if (!okNet) return;

    try {
      await _sb.auth.signOut();
    } catch (e, st) {
      debugPrint('EntryChoice signOut (guest) error: $e');
      debugPrint('$st');
    }

    // ✅ Provider safety: handle missing provider without crashing
    try {
      await context.read<AppSession>().setGuest();
    } catch (e, st) {
      debugPrint('EntryChoice AppSession.setGuest missing provider? $e');
      debugPrint('$st');
    }

    await _setGuestModePrefs();

    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
  }

  Future<void> _continueAsUser() async {
    final okNet = await _ensureInternetOrAlert();
    if (!okNet) return;

    final s = _sb.auth.currentSession;
    if (s == null) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
      return;
    }

    // ✅ Provider safety: handle missing provider without crashing
    try {
      await context.read<AppSession>().setUser(s.user.id);
    } catch (e, st) {
      debugPrint('EntryChoice AppSession.setUser missing provider? $e');
      debugPrint('$st');
    }

    await _setUserModePrefs();

    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/userDashboard', (r) => false);
  }

  Future<void> _signOutHere() async {
    final okNet = await _ensureInternetOrAlert();
    if (!okNet) return;

    try {
      await _sb.auth.signOut();
    } catch (e, st) {
      debugPrint('EntryChoice signOut error: $e');
      debugPrint('$st');
    }

    // ✅ Provider safety
    try {
      await context.read<AppSession>().logout();
    } catch (e, st) {
      debugPrint('EntryChoice AppSession.logout missing provider? $e');
      debugPrint('$st');
    }

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

    final w = MediaQuery.of(context).size.width;

    // ====== تحجيم تلقائي للشاشات الصغيرة (بدون تحويلها عمودي) ======
    // clamp بين 0.82 و 1.0
    final scale = (w / 430.0).clamp(0.82, 1.0);
    final tileGap = 12.0 * scale;
    final outerPad = 18.0 * scale;

    final cardBg = cs.surface.withOpacity(isDark ? 0.82 : 0.92);
    final border = BorderSide(color: primary.withOpacity(isDark ? 0.22 : 0.18));

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
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Padding(
                  padding: EdgeInsets.all(outerPad),
                  child: Card(
                    elevation: 0,
                    color: cardBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: border,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(16 * scale),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _header(
                            appName: tr['app']!,
                            subtitle: tr['choose']!,
                            cs: cs,
                            isDark: isDark,
                            scale: scale,
                          ),
                          SizedBox(height: 14 * scale),

                          if (showSignedBox) ...[
                            _signedBox(
                              cs: cs,
                              isDark: isDark,
                              tr: tr,
                              onLogout: _signOutHere,
                              loading: _loadingProfile,
                              username: _profileUsername,
                              fullName: _profileFullName,
                              scale: scale,
                            ),
                            SizedBox(height: 14 * scale),
                          ],

                          // ✅ دائمًا بجانب بعض
                          Row(
                            children: [
                              Expanded(
                                child: _choiceTile(
                                  scale: scale,
                                  title: showSignedBox
                                      ? tr['continueUser']!
                                      : tr['asUser']!,
                                  icon: Icons.person_rounded,
                                  topBadgeIcon: Icons.badge_outlined,
                                  accent: primary,
                                  filled: true,
                                  onTap: showSignedBox
                                      ? _continueAsUser
                                      : _goUser,
                                ),
                              ),
                              SizedBox(width: tileGap),
                              Expanded(
                                child: _choiceTile(
                                  scale: scale,
                                  title: tr['asGuest']!,
                                  icon: Icons.person_outline_rounded,
                                  topBadgeIcon: Icons.how_to_reg_outlined,
                                  accent: primary,
                                  filled: false,
                                  onTap: _goGuest,
                                ),
                              ),
                            ],
                          ),

                          // ملاحظة صغيرة جدًا على الويب فقط (اختياري) بدون حشو نصوص
                          if (kIsWeb) SizedBox(height: 8 * scale),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header({
    required String appName,
    required String subtitle,
    required ColorScheme cs,
    required bool isDark,
    required double scale,
  }) {
    return Column(
      children: [
        Container(
          height: 102 * scale,
          alignment: Alignment.center,
          child: Image.asset(
            'assets/logo.png',
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) {
              return Container(
                width: 80 * scale,
                height: 80 * scale,
                decoration: BoxDecoration(
                  color: primary.withOpacity(isDark ? 0.18 : 0.08),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: primary.withOpacity(0.18)),
                ),
                child: const Icon(
                  Icons.home_work_outlined,
                  size: 44,
                  color: primary,
                ),
              );
            },
          ),
        ),
        SizedBox(height: 6 * scale),
        Text(
          appName,
          style: TextStyle(
            fontSize: 20 * scale,
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
            letterSpacing: 0.2,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: 3 * scale),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12.5 * scale,
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
    required double scale,
  }) {
    final boxBg = primary.withOpacity(isDark ? 0.14 : 0.10);
    final border = primary.withOpacity(isDark ? 0.28 : 0.20);

    final nameLine = (fullName ?? '').trim();
    final idLine = (username ?? '').trim();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 12 * scale),
      decoration: BoxDecoration(
        color: boxBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            width: 44 * scale,
            height: 44 * scale,
            decoration: BoxDecoration(
              color: primary.withOpacity(isDark ? 0.20 : 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.verified_user_rounded, color: primary, size: 22 * scale),
          ),
          SizedBox(width: 12 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      tr['signed']!,
                      style: TextStyle(
                        fontSize: 12.5 * scale,
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                    ),
                    if (loading) ...[
                      SizedBox(width: 10 * scale),
                      SizedBox(
                        width: 14 * scale,
                        height: 14 * scale,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: 4 * scale),
                if (nameLine.isNotEmpty)
                  Text(
                    nameLine,
                    style: TextStyle(
                      fontSize: 12.5 * scale,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (idLine.isNotEmpty) ...[
                  SizedBox(height: 2 * scale),
                  Text(
                    '${tr['id']!}: $idLine',
                    style: TextStyle(
                      fontSize: 12 * scale,
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: 10 * scale),
          TextButton(
            onPressed: onLogout,
            child: Text(
              tr['logout']!,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5 * scale),
            ),
          ),
        ],
      ),
    );
  }

  Widget _choiceTile({
    required double scale,
    required String title,
    required IconData icon,
    required IconData topBadgeIcon,
    required Color accent,
    required bool filled,
    required Future<void> Function() onTap,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return InkWell(
      onTap: () => onTap(),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: EdgeInsets.all(14 * scale),
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
              width: 50 * scale,
              height: 50 * scale,
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
                    size: 26 * scale,
                    color: filled ? Colors.white : accent,
                  ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Icon(
                      topBadgeIcon,
                      size: 15 * scale,
                      color: filled ? Colors.white70 : accent.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 12 * scale),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14.5 * scale,
                  fontWeight: FontWeight.w900,
                  color: filled ? Colors.white : onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              _isEnglish ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
              color: filled ? Colors.white : accent,
              size: 24 * scale,
            ),
          ],
        ),
      ),
    );
  }
}
