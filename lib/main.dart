// lib/main.dart
import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart' as intl_locale;

// ✅ Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'firebase_messaging_background.dart';

// ✅ Provider
import 'package:provider/provider.dart';

// ✅ Session
import 'core/security/inactivity_policy.dart';
import 'core/config/app_config.dart';
import 'core/session/account_role_cache.dart';
import 'core/theme/app_text_scale.dart';
import 'core/session/app_session.dart';
import 'core/session/user_appearance_session.dart';
import 'core/session/return_after_auth.dart';
import 'core/session/web_session_ttl.dart';
import 'core/session/web_visibility.dart';

// ✅ L10n
import 'package:aqar_user/l10n/app_localizations.dart';

import 'shared/core/supabase_config.dart';
import 'shared/core/root_dotenv_loader.dart';
import 'shared/core/supabase_runtime_overrides.dart';
import 'core/share/app_listing_links.dart';
import 'screens/listing_loader_page.dart';
import 'screens/contract_verify_page.dart';
import 'screens/login_screen.dart';
import 'screens/user_dashboard.dart';
import 'screens/verify_screen.dart';
import 'screens/settings_page.dart';
import 'screens/reset_password_screen.dart';
import 'screens/change_password_screen.dart';
import 'screens/gate_screen.dart';
import 'screens/fast_login_screen.dart';
import 'screens/password_setup.dart';
import 'screens/entry_choice_screen.dart';

// ✅ NEW: Account Type + Verification Screens
import 'screens/account_type_setup_screen.dart';
import 'screens/verification_request_screen.dart';

import 'services/inactivity_service.dart';
import 'services/fast_login_service.dart';
import 'services/user_session_coordination_service.dart';
import 'services/user_install_session_service.dart';
import 'services/connectivity_guard.dart';
import 'theme.dart';
import 'core/theme/app_accent.dart';
import 'core/theme/app_appearance_bridge.dart';
import 'core/gestures/hardware_keyboard_scroll.dart';
import 'core/utils/listing_date_display.dart';
import 'core/listing/property_type_custom_registry.dart';
import 'widgets/app_logo_loading.dart';
import 'core/haptics/app_haptics.dart';
import 'core/notifications/in_app_notification_sound.dart';
import 'core/notifications/chat_message_sound.dart';

// ✅ Notifications
import 'services/notification_service.dart';

// ✅ Marketing Flow
import 'routes.dart';
import 'services/marketing_flow_service.dart';
import 'screens/owner_requests_page.dart';
import 'screens/marketer_dashboard_page.dart';
import 'screens/listing_request_status_page.dart';
import 'screens/owner_offers_page.dart';
import 'screens/submit_offer_page.dart';
import 'screens/submit_permits_page.dart';
import 'screens/device_management_page.dart';

// ✅ In-app notifications page
import 'screens/in_app_notifications_page.dart';
import 'screens/market_insights_page.dart';
import 'services/in_app_notification_hub.dart';
import 'widgets/in_app_notification_toast_overlay.dart';

// ✅ Org team / post-auth gates
import 'screens/post_auth_shell.dart';
import 'screens/org_team_management_page.dart';
import 'screens/org_monitor_dashboard_page.dart';
import 'screens/create_listing_request_page.dart';

final ValueNotifier<bool> recoveryFlowNotifier = ValueNotifier<bool>(false);

// ✅ NEW: تعطيل القفل التلقائي أثناء فتح الكاميرا/الاستديو/منتقي الملفات
final ValueNotifier<bool> suspendAutoLock = ValueNotifier<bool>(false);

/// لمراقبة العودة من الإعدادات وتحديث واجهة تسجيل الدخول (مثل زر الدخول السريع).
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

// ✅ مفاتيح موحدة — المصدر [AppConfig] (هنا أسماء متوافقة مع الاستيراد القديم من main).
const String kPrefGuestMode = AppConfig.prefGuestModeKey;
const String kPrefEntryMode = AppConfig.prefEntryModeKey;
const String kPrefFastLoginEnabled = AppConfig.prefFastLoginEnabledKey;
const String kPrefFastLoginPinSet = AppConfig.prefFastLoginPinSetKey;
const String kPrefAppPausedAtMs = AppConfig.prefAppPausedAtMsKey;
const String kPrefBgLockGraceMinutes = AppConfig.prefBgLockGraceMinutesKey;
const int kAppBackgroundLockGraceMinutesDefault = 3;

Future<Duration> readAppBackgroundLockGrace() async {
  final p = await SharedPreferences.getInstance();
  final m = p.getInt(kPrefBgLockGraceMinutes) ??
      kAppBackgroundLockGraceMinutesDefault;
  return Duration(minutes: m.clamp(1, 60));
}

Future<void> setAppBackgroundLockGraceMinutes(int minutes) async {
  final p = await SharedPreferences.getInstance();
  await p.setInt(kPrefBgLockGraceMinutes, minutes.clamp(1, 60));
}

String otpVerifiedKey(String uid) => 'otp_verified_$uid';

const String kPrefLang = AppConfig.prefLangKey;
const String kPrefTheme = AppConfig.prefThemeKey;
const String kPrefHapticsEnabled = AppConfig.prefHapticsEnabledKey;
const String kPrefTextScale = AppConfig.prefTextScaleKey;
const double kAppTextScaleMin = AppConfig.textScaleMin;
const double kAppTextScaleMax = AppConfig.textScaleMax;

// ✅ Notifiers (ثابتة حسب اختيار المستخدم)
final ValueNotifier<String> langNotifier = ValueNotifier<String>('ar');
final ValueNotifier<ThemeMode> themeModeNotifier =
    ValueNotifier<ThemeMode>(ThemeMode.light);
final ValueNotifier<double> textScaleNotifier = ValueNotifier<double>(1.0);

Future<void> setAppLang(String lang) async {
  final v = (lang.toLowerCase() == 'en') ? 'en' : 'ar';
  await UserAppearanceSession.persistLangChoice(v);
  langNotifier.value = v;
}

Future<void> setAppTheme(ThemeMode mode) async {
  final v = (mode == ThemeMode.dark) ? 'dark' : 'light';
  await UserAppearanceSession.persistThemeChoice(v);
  themeModeNotifier.value = (v == 'dark') ? ThemeMode.dark : ThemeMode.light;
}

Future<void> setAppHapticsEnabled(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kPrefHapticsEnabled, enabled);
  AppHaptics.enabled = enabled;
}

/// معامل تكبير نص التطبيق (0.85–1.40)، يُحفظ ويُطبَّق على كل الشاشات.
Future<void> setAppTextScaleFactor(double factor) async {
  final f = factor.clamp(AppConfig.textScaleMin, AppConfig.textScaleMax);
  textScaleNotifier.value = f;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setDouble(kPrefTextScale, f);
}

/// عند غياب مفتاح Supabase: لا نرمي [StateError] قبل [runApp] — على الويب يظهر خطأ JS؛
/// على الجوال كان يظهر **شاشة بيضاء** أو إغلاقاً فورياً لأن لا واجهة تُرسم.
void _runSupabaseConfigMissingApp() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.settings_suggest_outlined, size: 48),
                      const SizedBox(height: 16),
                      const Text(
                        'Supabase configuration missing',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        kIsWeb
                            ? 'SUPABASE_ANON_KEY is not set or was rejected (placeholder / too short).\n\n'
                                'Supabase → Project Settings → API Keys:\n'
                                '  • Use the Publishable key (sb_publishable_…) — copy the FULL value.\n'
                                '  • Or the legacy anon JWT (eyJ…) if your project still shows it.\n'
                                '  • Never use sb_secret_ in the app.\n\n'
                                'Web: web/supabase_config.json or:\n'
                                '  flutter build web --dart-define=SUPABASE_ANON_KEY=<full key>\n\n'
                                '— عربي: انسخ مفتاح Publishable كاملاً من API Keys (ليس YOUR_KEY_HERE).'
                            : 'SUPABASE_ANON_KEY is not set or was rejected (placeholder / too short).\n\n'
                                'Supabase → Project Settings → API Keys:\n'
                                '  • Use the Publishable key (sb_publishable_…) — copy the FULL value.\n'
                                '  • Or the legacy anon JWT (eyJ…) if your project still shows it.\n'
                                '  • Never use sb_secret_ in the app.\n\n'
                                'Android release APK example:\n'
                                '  flutter build apk --release '
                                '--dart-define=SUPABASE_ANON_KEY=<full key>\n\n'
                                'أو ضَع المفتاح في assets/env/default.env (لا ترفع الأسرار لـ git) '
                                'أو أضف .env في الجذر وفعّله في pubspec.\n\n'
                                '— White screen was likely this: app crashed in main() before runApp.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(height: 1.45),
                      ),
                    ],
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

/// يدمج [assets/env/default.env] مع [`.env`] في جذر المشروع عند التشغيل من القرص (VM فقط)،
/// أو مع أصل مضمّن [`.env`] إن أضفته إلى `flutter.assets`.
/// ويب: يحمّل [supabase_config.json] من نفس أصل الموقع (يُنسخ من مجلد [web/] عند البناء).
Future<void> _tryLoadWebSupabaseRuntimeConfig() async {
  if (!kIsWeb) return;
  try {
    final uri = Uri.base.resolve('supabase_config.json');
    final res = await http.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return;
    final raw = res.body.trimLeft();
    if (raw.startsWith('<')) {
      if (kDebugMode) {
        debugPrint(
          '[web] supabase_config.json missing or overridden by SPA rewrite '
          '(got HTML). Add web/supabase_config.json before flutter build web / firebase deploy.',
        );
      }
      return;
    }
    final dec = jsonDecode(res.body);
    if (dec is Map<String, dynamic>) {
      SupabaseRuntimeOverrides.applyFromJson(dec);
    } else if (dec is Map) {
      SupabaseRuntimeOverrides.applyFromJson(
        Map<String, dynamic>.from(dec),
      );
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[web] supabase_config.json not loaded: $e');
    }
  }
}

Future<void> _loadAppDotEnv() async {
  try {
    final base = await rootBundle.loadString('assets/env/default.env');
    final buf = StringBuffer(base.trimRight());
    // 1) `.env` بجانب المشروع (الأفضل للتطوير على سطح المكتب مع `flutter run`)
    final fromDisk = await tryReadOptionalProjectDotEnv();
    if (fromDisk != null && fromDisk.trim().isNotEmpty) {
      buf.write('\n');
      buf.write(fromDisk);
    } else {
      // 2) أصل اختياري مضمّن — يحتاج `- .env` في pubspec
      try {
        if (!kIsWeb) {
          buf.write('\n');
          buf.write(await rootBundle.loadString('.env'));
        }
      } catch (_) {}
    }
    dotenv.testLoad(fileInput: buf.toString());
  } catch (e, st) {
    debugPrint('_loadAppDotEnv failed (assets/env/default.env): $e');
    debugPrint('$st');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _loadAppDotEnv();
  await _tryLoadWebSupabaseRuntimeConfig();

  try {
    await intl_locale.initializeDateFormatting('ar');
    await intl_locale.initializeDateFormatting('en');
  } catch (_) {}

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}');
    debugPrint('${details.stack}');
  };

  final prefs = await SharedPreferences.getInstance();

  await PropertyTypeCustomRegistry.ensureLoaded();

  // =========================
  // ✅ One-time legacy migration (إذا كانت مفاتيح قديمة موجودة)
  // =========================
  try {
    final legacyLang = prefs.getString('language');
    if (legacyLang != null && !prefs.containsKey(kPrefLang)) {
      await prefs.setString(kPrefLang, legacyLang);
    }

    final legacyTheme = prefs.getString('themeMode');
    if (legacyTheme != null && !prefs.containsKey(kPrefTheme)) {
      final v = (legacyTheme.toLowerCase().contains('dark')) ? 'dark' : 'light';
      await prefs.setString(kPrefTheme, v);
    }
  } catch (_) {}

  // =========================
  // ✅ Load user-selected language/theme
  // =========================
  final savedLang = prefs.getString(kPrefLang) ?? 'ar';
  final savedTheme = prefs.getString(kPrefTheme) ?? 'light';

  langNotifier.value = (savedLang == 'en') ? 'en' : 'ar';
  themeModeNotifier.value =
      (savedTheme == 'dark') ? ThemeMode.dark : ThemeMode.light;
  AppHaptics.enabled = prefs.getBool(kPrefHapticsEnabled) ?? true;
  final savedScale = prefs.getDouble(kPrefTextScale);
  textScaleNotifier.value = savedScale == null
      ? 1.0
      : savedScale.clamp(AppConfig.textScaleMin, AppConfig.textScaleMax);
  await InAppNotificationSoundPrefs.loadFromPrefs();
  await ChatMessageSoundPrefs.loadFromPrefs();
  await ListingDateDisplay.loadFromPrefs();
  await loadAppAccentFromPrefs();
  reloadAppAppearanceFromStoredPrefs = () async {
    final p = await SharedPreferences.getInstance();
    final st = p.getString(kPrefTheme) ?? 'light';
    themeModeNotifier.value = (st == 'dark') ? ThemeMode.dark : ThemeMode.light;
    final sc = p.getDouble(kPrefTextScale);
    textScaleNotifier.value = sc == null
        ? 1.0
        : sc.clamp(AppConfig.textScaleMin, AppConfig.textScaleMax);
    final uid = Supabase.instance.client.auth.currentUser?.id;
    await loadAppAccentFromPrefs(userId: uid);
    await UserAppearanceSession.applyNotifiersToMatchStoredSession(
      langNotifier: langNotifier,
      themeModeNotifier: themeModeNotifier,
    );
  };
  syncSessionAppearanceNotifiers = () async {
    await UserAppearanceSession.applyNotifiersToMatchStoredSession(
      langNotifier: langNotifier,
      themeModeNotifier: themeModeNotifier,
    );
  };
  await AccountRoleCache.loadFromPrefs();

  final supabaseAnon = SupabaseConfig.supabaseAnonKey;
  if (supabaseAnon.isEmpty) {
    _runSupabaseConfigMissingApp();
    return;
  }

  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: supabaseAnon,
  );

  await UserAppearanceSession.applyNotifiersToMatchStoredSession(
    langNotifier: langNotifier,
    themeModeNotifier: themeModeNotifier,
  );

  if (!kIsWeb) {
    try {
      final initialUri = await AppLinks().getInitialLink();
      final lid = AppListingLinks.listingIdFromUri(initialUri);
      if (lid != null && lid.isNotEmpty) {
        await prefs.setString(AppListingLinks.pendingListingPrefKey, lid);
      }
      final cid = AppListingLinks.contractIdFromVerifyUri(initialUri);
      if (cid != null && cid.isNotEmpty) {
        await prefs.setString(
          AppListingLinks.pendingContractVerifyPrefKey,
          cid,
        );
      }
    } catch (_) {}
  }

  // =========================================================
  // ✅ Web: لا نسمح باستعادة جلسة/كاش سابق (إغلاق المتصفح ثم العودة)
  // =========================================================
  if (kIsWeb) {
    // مسح الجلسة محلياً فقط عند وجود جلسة فعلية.
    // استدعاء /auth/v1/logout بدون refresh token صالح يعيد 403 ويظهر في Network بدون فائدة.
    try {
      final auth = Supabase.instance.client.auth;
      if (auth.currentSession != null) {
        await auth.signOut(scope: SignOutScope.local);
      }
    } catch (_) {}

    try {
      await prefs.remove(kPrefGuestMode);
      await prefs.remove(kPrefEntryMode);
      await prefs.remove(kPrefWebGuestLastActivityMs);

      final keys = prefs.getKeys().toList();
      for (final k in keys) {
        if (k.startsWith('otp_verified_')) {
          await prefs.remove(k);
        }
      }

      await prefs.remove(kPrefFastLoginEnabled);
      await prefs.remove(kPrefFastLoginPinSet);
    } catch (_) {}
  }

  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // لا تمنع الإقلاع
  unawaited(
    NotificationService.init()
        .timeout(const Duration(seconds: 6), onTimeout: () => null)
        .catchError((e, st) {
      debugPrint('NotificationService.init error: $e');
      debugPrint('$st');
    }),
  );

  recoveryFlowNotifier.value = _isRecoveryUrlOrCode();

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppSession(),
      child: const AqarUserApp(),
    ),
  );
}

class AqarUserApp extends StatefulWidget {
  const AqarUserApp({super.key});

  @override
  State<AqarUserApp> createState() => _AqarUserAppState();
}

class _AqarUserAppState extends State<AqarUserApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  StreamSubscription<AuthState>? _sub;
  StreamSubscription<Uri>? _appLinksSub;
  RealtimeChannel? _inAppNotifChannel;

  late final InactivityService _inactivity;

  bool _navigating = false;

  /// بعد أول إطار: لا يعيق [main] — يبقي الإقلاع خفيفاً.
  void _ensureInAppNotificationRealtime() {
    if (_inAppNotifChannel != null) return;
    try {
      _inAppNotifChannel = Supabase.instance.client
          .channel('public:in_app_notifications')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'in_app_notifications',
            callback: (payload) {
              final rec = payload.newRecord;
              if (kDebugMode) {
                debugPrint('in_app_notifications insert: $rec');
              }
              final row = Map<String, dynamic>.from(rec);
              InAppNotificationHub.onInsertRecord(row);
              final toast = InAppNotificationHub.toast.value;
              if (toast != null) {
                NotificationService.handleIncomingWorkflowAlert(
                  title: toast.titleForLang(langNotifier.value),
                  body: toast.bodyForLang(langNotifier.value),
                  dedupeKey: toast.id,
                );
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'in_app_notifications',
            callback: (payload) {
              final rec = payload.newRecord;
              if (kDebugMode) {
                debugPrint('in_app_notifications update: $rec');
              }
              InAppNotificationHub.onRecordUpdated(
                Map<String, dynamic>.from(rec),
              );
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.delete,
            schema: 'public',
            table: 'in_app_notifications',
            callback: (payload) {
              final rec = payload.oldRecord;
              if (kDebugMode) {
                debugPrint('in_app_notifications delete: $rec');
              }
              InAppNotificationHub.onRecordDeleted(
                Map<String, dynamic>.from(rec),
              );
            },
          );
      _inAppNotifChannel!.subscribe();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('in_app_notifications subscribe failed: $e\n$st');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final idleMobileNative = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final useLongIdle = kIsWeb || !idleMobileNative;
    _inactivity = InactivityService(
      navigatorKey: _navKey,
      idleBeforePrompt: useLongIdle
          ? InactivityPolicy.webDesktopIdleBeforeLock
          : InactivityPolicy.idleBeforePrompt,
      promptCountdown: idleMobileNative
          ? InactivityPolicy.promptCountdown
          : InactivityPolicy.webDesktopAutoLogoutCountdown,
      useIdleBlurOverlay: !idleMobileNative,
    );
    _inactivity.start();

    UserSessionCoordinationService.navigatorKey = _navKey;

    if (!kIsWeb) {
      NotificationService.bindFcmNavigation(
        _navKey,
        langResolver: () => langNotifier.value,
      );
    }

    AppHardwareKeyboardScroll.install(_navKey);

    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      final event = data.event;

      // ✅ لا تعمل أي redirect على initialSession
      if (event == AuthChangeEvent.initialSession) return;

      // ✅ عند تسجيل الدخول/تحديث التوكن: زامن FCM token (لكن لا تعلق)
      if (data.session != null &&
          (event == AuthChangeEvent.signedIn ||
              event == AuthChangeEvent.tokenRefreshed ||
              event == AuthChangeEvent.userUpdated)) {
        unawaited(
          NotificationService.init()
              .timeout(const Duration(seconds: 6), onTimeout: () => null)
              .catchError((_) {}),
        );
      }

      // ADMIN_HOOK: Fetch live session logs — اربط لوحة الإدارة بـ user_login_audit / Edge Function.
      // ADMIN_HOOK: Remote force-logout trigger — استخدم Admin API أو bump_user_session_epoch من الخادم.
      if (event == AuthChangeEvent.signedIn && data.session != null) {
        final uid = data.session!.user.id;
        unawaited(_completePostSignIn(uid));
        unawaited(
          loadAppAccentFromPrefs(userId: uid),
        );
        unawaited(
          UserAppearanceSession.applyNotifiersToMatchStoredSession(
            langNotifier: langNotifier,
            themeModeNotifier: themeModeNotifier,
          ),
        );
      }

      // ✅ Recovery
      if (event == AuthChangeEvent.passwordRecovery) {
        recoveryFlowNotifier.value = true;
        _safeNavTo('/resetPassword');
        return;
      }

      // ✅ SignedOut
      if (event == AuthChangeEvent.signedOut) {
        UserSessionCoordinationService.dispose();
        recoveryFlowNotifier.value = false;

        bool isGuest = false;
        try {
          final prefs = await SharedPreferences.getInstance();
          final entryMode =
              (prefs.getString(kPrefEntryMode) ?? '').trim().toLowerCase();
          final guestMode = prefs.getBool(kPrefGuestMode) ?? false;
          isGuest = guestMode || entryMode == 'guest';
        } catch (_) {}

        final ctx = _navKey.currentContext;
        if (ctx != null && ctx.mounted) {
          final sessionProvider = ctx.read<AppSession>();
          if (isGuest) {
            unawaited((() async {
              await sessionProvider.setGuest();
              await syncSessionAppearanceNotifiers?.call();
            })());
          } else {
            unawaited(sessionProvider.logout());
            unawaited(loadAppAccentFromPrefs(userId: null));
            unawaited(
              UserAppearanceSession.applyNotifiersToMatchStoredSession(
                langNotifier: langNotifier,
                themeModeNotifier: themeModeNotifier,
              ),
            );
          }
        }

        final current = _currentRouteName();
        final isProtected = current == '/userDashboard' ||
            current == '/settings' ||
            current == AppRoutes.ownerRequests ||
            current == AppRoutes.marketerDashboard;

        if (isProtected) {
          _safeNavTo('/');
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureInAppNotificationRealtime();
      if (_isRecoveryUrlOrCode()) {
        recoveryFlowNotifier.value = true;
        _safeNavTo('/resetPassword');
      }
    });

    if (kIsWeb) {
      listenDocumentVisibilityHidden(() {
        _inactivity.onAppPaused();
        unawaited(_signOutOnBackgroundHide());
      });
      listenDocumentVisibilityShown(() {
        if (suspendAutoLock.value) return;
        unawaited(_inactivity.onAppResumedAfterBackground());
        unawaited(_onAppResumedCheckAppLock());
        unawaited(UserInstallSessionService.reconcileSlotOnForeground());
      });
    }

    if (!kIsWeb) {
      _appLinksSub = AppLinks().uriLinkStream.listen((uri) {
        final nav = _navKey.currentState;
        if (nav == null) return;
        final lang = langNotifier.value;

        final cid = AppListingLinks.contractIdFromVerifyUri(uri);
        if (cid != null && cid.isNotEmpty) {
          nav.pushNamed<void>(
            AppRoutes.contractVerify,
            arguments: <String, String>{
              'contractId': cid,
              'lang': lang,
            },
          );
          return;
        }

        final id = AppListingLinks.listingIdFromUri(uri);
        if (id == null || id.isEmpty) return;
        nav.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => ListingLoaderPage(propertyId: id, lang: lang),
          ),
        );
      });
    }
  }

  String _currentRouteName() {
    final nav = _navKey.currentState;
    if (nav == null) return '';
    final ctx = _navKey.currentContext;
    return ModalRoute.of(ctx ?? nav.context)?.settings.name ?? '';
  }

  Future<void> _completePostSignIn(String userId) async {
    final current = _currentRouteName();
    if (current == '/login' || current == '/verify') {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final otpVerified = prefs.getBool(otpVerifiedKey(userId)) ?? false;
      if (!otpVerified) return;
    } catch (_) {
      return;
    }
    final reg = await UserInstallSessionService.registerDeviceSlotAfterSignIn();
    if (!reg.ok && reg.code == 'device_limit') {
      if (!mounted) return;
      _navKey.currentState?.pushNamedAndRemoveUntil(
        AppRoutes.deviceManagement,
        (route) => false,
        arguments: <String, dynamic>{'mandatory': true},
      );
      return;
    }
    final hints = await UserInstallSessionService.sessionHintsForBump();
    await UserSessionCoordinationService.afterSignIn(
      userId,
      cityHint: hints.city,
      deviceLabel: hints.label,
    );
  }

  /// إخفاء التطبيق: مع الدخول السريع نُبقي الجلسة ونسجّل وقت الخلفية؛ وإلا نخرج كسابق.
  ///
  /// **الويب:** لا نُسجّل خروجاً عند إخفاء التبويب فقط (كان يُلغي حوار الخمول ويُظهر
  /// «سجّل الدخول» دون عدّاد). الخروج يتم عبر انتهاء العدّ في [InactivityService] أو انتهاء الجلسة.
  Future<void> _signOutOnBackgroundHide() async {
    if (recoveryFlowNotifier.value) return;
    if (suspendAutoLock.value) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final guest = prefs.getBool(kPrefGuestMode) ?? false;
      final entry =
          (prefs.getString(kPrefEntryMode) ?? '').trim().toLowerCase();
      if (guest || entry == 'guest') {
        await prefs.setInt(
          kPrefAppPausedAtMs,
          DateTime.now().millisecondsSinceEpoch,
        );
        return;
      }
    } catch (_) {}
    if (Supabase.instance.client.auth.currentSession == null) return;

    final hasLock = await FastLoginService.hasAnyLockEnabled();

    if (kIsWeb) {
      if (hasLock) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
          kPrefAppPausedAtMs,
          DateTime.now().millisecondsSinceEpoch,
        );
      }
      return;
    }

    if (hasLock) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        kPrefAppPausedAtMs,
        DateTime.now().millisecondsSinceEpoch,
      );
      return;
    }

    _inactivity.stop();
    try {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.global);
    } catch (_) {}
    if (mounted) _inactivity.start();
  }

  Future<void> _onAppResumedCheckAppLock() async {
    if (recoveryFlowNotifier.value) return;
    if (suspendAutoLock.value) return;

    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return;
    }

    final guest = prefs.getBool(kPrefGuestMode) ?? false;
    final entry = (prefs.getString(kPrefEntryMode) ?? '').trim().toLowerCase();
    final isGuest = guest || entry == 'guest';

    final at = prefs.getInt(kPrefAppPausedAtMs);
    await prefs.remove(kPrefAppPausedAtMs);
    if (at == null) return;

    final elapsed = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(at),
    );
    final grace = await readAppBackgroundLockGrace();
    if (elapsed < grace) return;

    final nav = _navKey.currentState;
    if (nav == null) return;

    final route = _currentRouteName();
    if (route == '/fastLogin' ||
        route == '/login' ||
        route == '/gate' ||
        route == '/entryChoice' ||
        route == '/verify' ||
        route == '/resetPassword' ||
        route == '/passwordSetup') {
      return;
    }

    // ضيف (موبايل أو ويب): بعد الخلفية/إخفاء التبويب وانتهاء المهلة → شاشة اختيار الدخول.
    if (isGuest) {
      if (!kIsWeb && elapsed > const Duration(hours: 24)) {
        return;
      }

      unawaited(ReturnAfterAuth.saveFromNavigatorKey(_navKey));
      FastLoginService.clearRuntimeUnlock();
      final ctx = _navKey.currentContext;
      if (ctx != null && ctx.mounted) {
        await ctx.read<AppSession>().logout();
      }
      unawaited(clearWebGuestIdleStamp());
      nav.pushNamedAndRemoveUntil('/entryChoice', (r) => false);
      return;
    }

    // للمستخدم المسجل نترك نافذة الخمول تعرض العدّاد وأزرار الاستمرار/الخروج.
    // عند انتهاء العدّاد فقط ينقل InactivityService المستخدم للقفل أو تسجيل الدخول.
    if (Supabase.instance.client.auth.currentSession != null) return;
  }

  void _safeNavTo(String route) {
    if (_navigating) return;

    final nav = _navKey.currentState;
    if (nav == null) return;

    final currentName = _currentRouteName();
    if (currentName == route) return;

    _navigating = true;
    try {
      nav.pushNamedAndRemoveUntil(route, (r) => false);
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigating = false;
      });
    }
  }

  @override
  void dispose() {
    AppHardwareKeyboardScroll.uninstall();
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _appLinksSub?.cancel();
    try {
      _inAppNotifChannel?.unsubscribe();
    } catch (_) {}
    _inAppNotifChannel = null;
    _inactivity.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (recoveryFlowNotifier.value == true) return;

    if (state == AppLifecycleState.resumed) {
      unawaited(NotificationService.clearOsApplicationIconBadge());
      if (suspendAutoLock.value != true) {
        unawaited(_inactivity.onAppResumedAfterBackground());
        unawaited(_onAppResumedCheckAppLock());
        unawaited(UserInstallSessionService.reconcileSlotOnForeground());
      }
      return;
    }

    if (suspendAutoLock.value == true) return;
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden) {
      return;
    }
    unawaited(NotificationService.clearOsApplicationIconBadge());
    _inactivity.onAppPaused();
    unawaited(_signOutOnBackgroundHide());
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return ValueListenableBuilder<String>(
          valueListenable: langNotifier,
          builder: (context, lang, __) {
            return ValueListenableBuilder<Color>(
              valueListenable: accentSeedNotifier,
              builder: (context, accentSeed, ___) {
                return ValueListenableBuilder<double>(
                  valueListenable: textScaleNotifier,
                  builder: (context, _, __) {
                    final isRtl = (lang == 'ar');

                    return MaterialApp(
                      navigatorKey: _navKey,
                      navigatorObservers: <NavigatorObserver>[appRouteObserver],
                      scrollBehavior: const AqarScrollBehavior(),
                      debugShowCheckedModeBanner: false,
                      localizationsDelegates:
                          AppLocalizations.localizationsDelegates,
                      supportedLocales: AppLocalizations.supportedLocales,
                      locale: Locale(lang),
                      onGenerateTitle: (context) =>
                          AppLocalizations.of(context)?.appTitle ??
                          'Motawoq Real Estate',
                      theme: AppTheme.lightThemeFor(accentSeed),
                      darkTheme: AppTheme.darkThemeFor(accentSeed),
                      themeMode: mode,
                      initialRoute: '/',
                      builder: (context, child) {
                        final l10n = AppLocalizations.of(context);
                        Widget wrapped = child ?? const SizedBox.shrink();

                        final mq0 = MediaQuery.of(context);
                        final scaler = buildAppCombinedTextScaler(
                          mq: mq0,
                          userSliderFactor: textScaleNotifier.value,
                          logicalSize: mq0.size,
                        );
                        wrapped = MediaQuery(
                          data: mq0.copyWith(textScaler: scaler),
                          child: wrapped,
                        );

                        wrapped = Focus(
                          // Root autofocus steals text-field focus on Flutter web (incl. mobile browsers).
                          autofocus: !kIsWeb,
                          onKeyEvent: (node, event) {
                            _inactivity.userActivity();
                            return KeyEventResult.ignored;
                          },
                          child: Listener(
                            behavior: HitTestBehavior.translucent,
                            onPointerDown: (_) => _inactivity.userActivity(),
                            onPointerMove: (_) => _inactivity.userActivity(),
                            onPointerSignal: (_) => _inactivity.userActivity(),
                            child: wrapped,
                          ),
                        );

                        if (AppLayout.shouldConstrainAppShell(context)) {
                          wrapped = Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: AppConfig.maxContentWidth,
                              ),
                              child: wrapped,
                            ),
                          );
                        }

                        if (kIsWeb) {
                          wrapped = FocusTraversalGroup(
                            policy: WidgetOrderTraversalPolicy(),
                            child: wrapped,
                          );
                        }

                        wrapped = Consumer<AppSession>(
                          builder: (context, session, appChild) {
                            if (session.hasInternet) return appChild!;
                            final loc = l10n;
                            return PopScope(
                              canPop: false,
                              child: Stack(
                                children: [
                                  IgnorePointer(
                                    ignoring: true,
                                    child: appChild,
                                  ),
                                  Positioned.fill(
                                    child: _GlobalOfflineOverlay(
                                      isAr: lang == 'ar',
                                      title: loc?.noInternetConnectionTitle ??
                                          (lang == 'ar'
                                              ? 'لا يوجد اتصال بالإنترنت'
                                              : 'No Internet Connection'),
                                      message: [
                                        loc?.ensureInternetThenRetry ??
                                            (lang == 'ar'
                                                ? 'تأكد من اتصال الإنترنت ثم أعد المحاولة.'
                                                : 'Make sure you are online, then retry.'),
                                        loc?.offlineGlobalOverlayHint ??
                                            (lang == 'ar'
                                                ? 'جلسة تسجيل الدخول تبقى على هذا الجهاز.'
                                                : 'Your session stays on this device.'),
                                      ].join('\n\n'),
                                      retryLabel: loc?.retryLabel ??
                                          (lang == 'ar'
                                              ? 'إعادة المحاولة'
                                              : 'Retry'),
                                      verifying: session.networkCheckBusy,
                                      onRetry: () => unawaited(
                                        session.refreshConnectivity(
                                            userInitiated: true),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                          child: wrapped,
                        );

                        wrapped = InAppNotificationToastHost(
                          lang: lang,
                          child: wrapped,
                        );

                        return Directionality(
                          textDirection:
                              isRtl ? TextDirection.rtl : TextDirection.ltr,
                          child: wrapped,
                        );
                      },
                      routes: {
                        '/': (context) => StartRouter(lang: lang),
                        '/gate': (context) => const GateScreen(),
                        '/entryChoice': (context) => const EntryChoiceScreen(),
                        '/login': (context) => const LoginScreen(),
                        '/verify': (context) => const VerifyScreen(),
                        '/resetPassword': (context) =>
                            const ResetPasswordScreen(),
                        '/changePassword': (context) =>
                            const ChangePasswordScreen(),
                        '/passwordSetup': (context) =>
                            const PasswordSetupScreen(),

                        // ✅ NEW routes
                        '/accountTypeSetup': (_) =>
                            const AccountTypeSetupScreen(),
                        '/verificationRequest': (_) =>
                            const VerificationRequestScreen(),

                        '/userDashboard': (context) => UserDashboard(
                              key: const ValueKey('dashboard'),
                              lang: lang,
                            ),
                        '/settings': (context) => const SettingsPage(),
                        '/fastLogin': (context) => const FastLoginScreen(),
                        AppRoutes.deviceManagement: (context) {
                          final args =
                              ModalRoute.of(context)?.settings.arguments;
                          var mandatory = false;
                          if (args is Map && args['mandatory'] == true) {
                            mandatory = true;
                          }
                          return DeviceManagementPage(mandatory: mandatory);
                        },

                        // ✅ Marketing Flow Routes
                        AppRoutes.ownerRequests: (_) =>
                            OwnerRequestsPage(lang: lang),
                        AppRoutes.marketerDashboard: (_) =>
                            MarketerDashboardPage(lang: lang),

                        // ✅ FIX: استخدم AppRoutes بدل '/inAppNotifications'
                        AppRoutes.inAppNotifications: (_) =>
                            InAppNotificationsPage(lang: lang),

                        AppRoutes.marketInsights: (_) =>
                            MarketInsightsPage(lang: lang),

                        AppRoutes.orgTeamManagement: (_) =>
                            const OrgTeamManagementPage(),
                        AppRoutes.orgMonitoring: (_) =>
                            const OrgMonitorDashboardPage(),

                        AppRoutes.createListingRequest: (_) =>
                            const CreateListingRequestPage(),
                        AppRoutes.listingRequestStatus: (context) {
                          final args =
                              ModalRoute.of(context)?.settings.arguments;
                          var requestId = '';
                          String resolvedLang = lang;
                          if (args is Map) {
                            requestId = (args['requestId'] ?? '').toString();
                            final l = (args['lang'] ?? '').toString();
                            if (l.isNotEmpty) resolvedLang = l;
                          }
                          if (requestId.isEmpty) return const GateScreen();
                          return ListingRequestStatusPage(
                            requestId: requestId,
                            lang: resolvedLang,
                          );
                        },
                        AppRoutes.ownerOffers: (context) {
                          final args =
                              ModalRoute.of(context)?.settings.arguments;
                          var requestId = '';
                          String resolvedLang = lang;
                          if (args is Map) {
                            requestId = (args['requestId'] ?? '').toString();
                            final l = (args['lang'] ?? '').toString();
                            if (l.isNotEmpty) resolvedLang = l;
                          }
                          if (requestId.isEmpty) return const GateScreen();
                          return OwnerOffersPage(
                            requestId: requestId,
                            lang: resolvedLang,
                          );
                        },
                        AppRoutes.submitOffer: (context) {
                          final args =
                              ModalRoute.of(context)?.settings.arguments;
                          var requestId = '';
                          var inviteId = '';
                          String resolvedLang = lang;
                          if (args is Map) {
                            requestId = (args['requestId'] ?? '').toString();
                            inviteId = (args['inviteId'] ?? '').toString();
                            final l = (args['lang'] ?? '').toString();
                            if (l.isNotEmpty) resolvedLang = l;
                          }
                          if (requestId.isEmpty) return const GateScreen();
                          return SubmitOfferPage(
                            requestId: requestId,
                            lang: resolvedLang,
                            inviteId: inviteId.isEmpty ? null : inviteId,
                          );
                        },
                        AppRoutes.submitPermits: (context) {
                          final args =
                              ModalRoute.of(context)?.settings.arguments;
                          var requestId = '';
                          String resolvedLang = lang;
                          if (args is Map) {
                            requestId = (args['requestId'] ?? '').toString();
                            final l = (args['lang'] ?? '').toString();
                            if (l.isNotEmpty) resolvedLang = l;
                          }
                          if (requestId.isEmpty) return const GateScreen();
                          return SubmitPermitsPage(
                            requestId: requestId,
                            lang: resolvedLang,
                          );
                        },
                        AppRoutes.contractVerify: (context) {
                          final args =
                              ModalRoute.of(context)?.settings.arguments;
                          var contractId = '';
                          String resolvedLang = lang;
                          if (args is Map) {
                            contractId =
                                (args['contractId'] ?? args['id'] ?? '')
                                    .toString();
                            final l = (args['lang'] ?? '').toString();
                            if (l.isNotEmpty) resolvedLang = l;
                          }
                          if (contractId.trim().isEmpty)
                            return const GateScreen();
                          return ContractVerifyPage(
                            contractId: contractId.trim(),
                            lang: resolvedLang,
                          );
                        },
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class StartRouter extends StatefulWidget {
  final String lang;
  const StartRouter({super.key, required this.lang});

  @override
  State<StartRouter> createState() => _StartRouterState();
}

class _GlobalOfflineOverlay extends StatelessWidget {
  final bool isAr;
  final String title;
  final String message;
  final String retryLabel;
  final bool verifying;
  final VoidCallback onRetry;

  const _GlobalOfflineOverlay({
    required this.isAr,
    required this.title,
    required this.message,
    required this.retryLabel,
    this.verifying = false,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xEE0B1220) : const Color(0xEEF5F7FA);
    final card = isDark ? const Color(0xFF121A2A) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF0B1220);
    final subColor = isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569);

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: AbsorbPointer(
        absorbing: verifying,
        child: ColoredBox(
          color: bg,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                color: card,
                elevation: 16,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_off_rounded, size: 56, color: titleColor),
                      const SizedBox(height: 10),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: subColor,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cs.primary,
                            foregroundColor: cs.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: verifying ? null : onRetry,
                          icon: verifying
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: cs.onPrimary,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded),
                          label: Text(retryLabel),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StartRouterState extends State<StartRouter> {
  bool _loading = true;
  Widget? _target;

  bool _retryingNet = false;

  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<bool> _hasInternet() async {
    try {
      return await ConnectivityGuard.hasReachableInternet()
          .timeout(const Duration(seconds: 20), onTimeout: () => false);
    } catch (_) {
      return false;
    }
  }

  Future<void> _retryInternet() async {
    if (_retryingNet) return;
    setState(() => _retryingNet = true);
    try {
      await _resolve();
    } finally {
      if (mounted) setState(() => _retryingNet = false);
    }
  }

  Future<void> _resolve() async {
    if (_isRecoveryUrlOrCode()) {
      if (!mounted) return;
      setState(() {
        _target = const ResetPasswordScreen();
        _loading = false;
      });
      return;
    }

    final okNet = await _hasInternet();
    if (!mounted) return;

    if (!okNet) {
      setState(() {
        _loading = false;
        _target = OfflineGate(
          lang: widget.lang,
          retrying: _retryingNet,
          onRetry: _retryInternet,
        );
      });
      return;
    }

    await Future.delayed(const Duration(milliseconds: 80));

    final prefs = await SharedPreferences.getInstance();

    final String entryMode =
        (prefs.getString(kPrefEntryMode) ?? '').trim().toLowerCase();
    final bool guestMode = prefs.getBool(kPrefGuestMode) ?? false;

    final sb = Supabase.instance.client;
    Session? session = sb.auth.currentSession;

    final bool isGuest = guestMode || entryMode == 'guest';

    if (kIsWeb && session != null && !isGuest) {
      if (await shouldForceWebReauthDueToIdle()) {
        final uid = sb.auth.currentUser?.id;
        await clearWebSessionAfterForcedLogout(uid);
        try {
          await sb.auth.signOut(scope: SignOutScope.global);
        } catch (_) {}
        session = sb.auth.currentSession;
      }
    }

    if (isGuest) {
      if (kIsWeb && await shouldForceWebGuestEndDueToIdle()) {
        await clearWebGuestIdleStamp();
        try {
          await prefs.remove(kPrefGuestMode);
          await prefs.remove(kPrefEntryMode);
        } catch (_) {}
        if (!mounted) return;
        setState(() {
          _target = const EntryChoiceScreen();
          _loading = false;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _target = UserDashboard(
          key: const ValueKey('dashboard'),
          lang: widget.lang,
        );
        _loading = false;
      });
      return;
    }

    if (session != null) {
      final uid = sb.auth.currentUser?.id ?? '';
      final verified = uid.isNotEmpty
          ? (prefs.getBool(otpVerifiedKey(uid)) ?? false)
          : false;

      // ✅ Dashboard إذا session != null && otpVerified == true
      if (verified) {
        unawaited(FastLoginService.syncBootstrapRoutePrefs());

        if (_isMobile &&
            await FastLoginService.hasAnyLockEnabled() &&
            !FastLoginService.hasUnlockedThisRuntimeSession) {
          if (!mounted) return;
          setState(() {
            _target = const FastLoginScreen();
            _loading = false;
          });
          return;
        }

        try {
          final svc = MarketingFlowService(Supabase.instance.client);
          final isMarketer = await svc.isMarketer();
          if (!mounted) return;

          setState(() {
            _target = PostAuthShell(
              lang: widget.lang,
              child: isMarketer
                  ? MarketerDashboardPage(lang: widget.lang)
                  : UserDashboard(
                      key: const ValueKey('dashboard'),
                      lang: widget.lang,
                    ),
            );
            _loading = false;
          });
          return;
        } catch (_) {
          if (!mounted) return;
          setState(() {
            _target = PostAuthShell(
              lang: widget.lang,
              child: UserDashboard(
                key: const ValueKey('dashboard'),
                lang: widget.lang,
              ),
            );
            _loading = false;
          });
          return;
        }
      }
    }

    final bool isFirstRun =
        entryMode.isEmpty && (prefs.getBool(kPrefGuestMode) == null);

    if (isFirstRun) {
      if (!mounted) return;
      setState(() {
        _target = const EntryChoiceScreen();
        _loading = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _target = const LoginScreen();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Center(
          child: AppLogoLoading(
            size: MediaQuery.sizeOf(context).shortestSide < 360 ? 80 : 96,
          ),
        ),
      );
    }
    return _target ?? const SizedBox.shrink();
  }
}

class OfflineGate extends StatelessWidget {
  final String lang;
  final bool retrying;
  final VoidCallback onRetry;

  const OfflineGate({
    super.key,
    required this.lang,
    required this.retrying,
    required this.onRetry,
  });

  bool get _isAr => lang.toLowerCase() != 'en';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    final bg = isDark ? const Color(0xFF0B1220) : const Color(0xFFF5F7FA);
    final card = isDark ? const Color(0xFF121A2A) : Colors.white;
    final title = isDark ? Colors.white : const Color(0xFF0B1220);
    final sub = isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569);

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                color: card,
                elevation: 14,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_off_rounded, size: 56, color: title),
                      const SizedBox(height: 10),
                      Text(
                        l10n.offlineNoInternetTitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: title,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.offlineNoInternetBody,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: sub,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.primary,
                            foregroundColor:
                                Theme.of(context).colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: retrying ? null : onRetry,
                          icon: retrying
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child:
                                      AppLogoLoading(compact: true, size: 20),
                                )
                              : const Icon(Icons.refresh_rounded),
                          label: Text(l10n.retryLabel),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ✅ فحص: type=recovery أو وجود code (PKCE) أو access_token في fragment
bool _isRecoveryUrlOrCode() {
  if (!kIsWeb) return false;

  try {
    final uri = Uri.base;

    final qType = (uri.queryParameters['type'] ?? '').toLowerCase();
    if (qType == 'recovery') return true;

    if (uri.queryParameters.containsKey('code')) return true;

    final frag = uri.fragment;
    if (frag.isNotEmpty) {
      final fragParams = Uri.splitQueryString(frag);
      final fType = (fragParams['type'] ?? '').toLowerCase();
      if (fType == 'recovery') return true;

      if (fragParams.containsKey('access_token')) return true;
    }

    return false;
  } catch (_) {
    return false;
  }
}
