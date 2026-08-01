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
import 'core/auth/auth_signed_out_navigation_guard.dart';
import 'core/auth/auth_local_sign_out.dart';
import 'core/session/user_appearance_session.dart';
import 'core/session/return_after_auth.dart';
import 'core/session/web_session_ttl.dart';
import 'core/session/web_visibility.dart';
import 'core/navigation/web_bootstrap_diag.dart';
import 'core/navigation/web_dashboard_hash.dart';
import 'core/subscription/app_subscription_gate.dart';
import 'widgets/web_browser_lifecycle_host.dart';

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
import 'screens/register_screen.dart';
import 'screens/entry_choice_screen.dart';

// ✅ NEW: Account Type + Verification Screens
import 'screens/account_type_setup_screen.dart';
import 'screens/verification_request_screen.dart';

import 'services/inactivity_service.dart';
import 'services/fast_login_service.dart';
import 'services/account_completion_service.dart';
import 'services/user_session_coordination_service.dart';
import 'services/user_install_session_service.dart';
import 'services/session_manager.dart';
import 'services/connectivity_guard.dart';
import 'theme.dart';
import 'core/theme/app_accent.dart';
import 'core/theme/app_appearance_bridge.dart';
import 'core/gestures/hardware_keyboard_scroll.dart';
import 'core/gestures/soft_keyboard_ensure_visible.dart';
import 'core/utils/listing_date_display.dart';
import 'core/listing/property_type_custom_registry.dart';
import 'widgets/app_logo_loading.dart';
import 'widgets/app_busy_indicator.dart';
import 'core/branding/app_branding.dart';
import 'core/platform/app_web_splash.dart';
import 'core/haptics/app_haptics.dart';
import 'core/motion/app_motion_policy.dart';
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
import 'core/navigation/web_dashboard_entry.dart';
import 'core/navigation/start_router_controller.dart';

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
/// مهلة إخفاء التبويب قبل القفل/الخروج — دقيقة واحدة كانت قصيرة جداً على ويندوز/Chrome.
const int kAppBackgroundLockGraceMinutesDefault = 15;

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

  await Future.wait([
    _loadAppDotEnv(),
    _tryLoadWebSupabaseRuntimeConfig(),
  ]);

  try {
    await Future.wait([
      intl_locale.initializeDateFormatting('ar'),
      intl_locale.initializeDateFormatting('en'),
      intl_locale.initializeDateFormatting('ar_SA'),
      intl_locale.initializeDateFormatting('en_US'),
    ]);
  } catch (e) {
    debugPrint('initializeDateFormatting failed: $e');
  }

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}');
    debugPrint('${details.stack}');
    if (kIsWeb) {
      WebBootstrapDiag.warn('FlutterError', details.exceptionAsString());
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('PlatformError: $error');
    if (kIsWeb) {
      WebBootstrapDiag.warn('PlatformError', error.toString());
    }
    return true;
  };

  final prefs = await SharedPreferences.getInstance();

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

  // تفضيلات مستقلة — تحميل متوازٍ لتقليل زمن ما قبل runApp.
  await Future.wait([
    PropertyTypeCustomRegistry.ensureLoaded(),
    AppMotionPolicy.bootstrap(),
    InAppNotificationSoundPrefs.loadFromPrefs(),
    ChatMessageSoundPrefs.loadFromPrefs(),
    ListingDateDisplay.loadFromPrefs(),
    loadAppAccentFromPrefs(),
    AccountRoleCache.loadFromPrefs(),
  ]);
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
        final vt = AppListingLinks.verifyTokenFromVerifyUri(initialUri);
        if (vt != null && vt.isNotEmpty) {
          await prefs.setString(
            AppListingLinks.pendingContractVerifyTokenPrefKey,
            vt,
          );
        } else {
          await prefs.remove(AppListingLinks.pendingContractVerifyTokenPrefKey);
        }
      }
    } catch (_) {}
  }

  // =========================================================
  // ✅ Web: جلسة ذكية — لا مسح أعمى عند كل تحميل (كان يُسبب حلقات وتجمّد)
  // =========================================================
  if (kIsWeb) {
    WebBootstrapDiag.log('app.main', 'bootstrap web session');
    try {
      await SessionManager.bootstrapWebAfterSupabaseInit(
        Supabase.instance.client,
      );
      WebBootstrapDiag.log(
        'app.main',
        'session uid=${Supabase.instance.client.auth.currentUser?.id ?? "none"}',
      );
    } catch (e) {
      WebBootstrapDiag.warn('app.main', 'session bootstrap failed: $e');
    }
  }

  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  // الويب: لا نحتاج Firebase قبل أول إطار (FCM معطّل). الجوال: يبقى قبل الإقلاع.
  if (kIsWeb) {
    unawaited(() async {
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } catch (e, st) {
        debugPrint('Firebase.initializeApp (web deferred) error: $e');
        debugPrint('$st');
      }
    }());
  } else {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    unawaited(
      NotificationService.init()
          .timeout(const Duration(seconds: 6), onTimeout: () => null)
          .catchError((e, st) {
        debugPrint('NotificationService.init error: $e');
        debugPrint('$st');
      }),
    );
  }

  recoveryFlowNotifier.value = _isRecoveryUrlOrCode();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppSession()),
        ChangeNotifierProvider(
          create: (_) {
            final gate = AppSubscriptionGate(Supabase.instance.client);
            gate.bindLifecycle();
            return gate;
          },
        ),
      ],
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
  /// الويب: بدون Realtime (WebSocket) — يمنع ERR_NAME_NOT_RESOLVED وتجمّد main thread.
  void _ensureInAppNotificationRealtime() {
    if (kIsWeb) return;
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
    InactivityService.dismissBlockingPromptCallback =
        _inactivity.dismissBlockingPrompt;
    _inactivity.start();

    UserSessionCoordinationService.navigatorKey = _navKey;

    if (!kIsWeb) {
      NotificationService.bindFcmNavigation(
        _navKey,
        langResolver: () => langNotifier.value,
      );
    }

    AppHardwareKeyboardScroll.install(_navKey);
    AppSoftKeyboardEnsureVisible.install();

    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      final event = data.event;

      // ✅ لا تعمل أي redirect على initialSession
      if (event == AuthChangeEvent.initialSession) return;

      // FCM: جوال فقط — الويب بدون Service Worker يسبب AbortError
      if (!kIsWeb &&
          data.session != null &&
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
        // كل دخول جديد: أعد بوابة استكمال البيانات (حتى بعد «ذكرني لاحقاً»).
        unawaited(AccountCompletionService.clearEnrollmentDeferred());
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
        if (SessionManager.duringPublicSessionReset) {
          return;
        }
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

        // ضيف الويب/الجوال: signOut(local) بعد setGuest يطلق signedOut — لا نعيد
        // التوجيه إلى '/' وإلا نُعاد لـ [StartRouter] (شاشة تحميل) ويُشعَر بتعليق.
        if (isProtected &&
            !isGuest &&
            !AuthSignedOutNavigationGuard.suppressRootRedirectOnSignedOut) {
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
      // تحديث الصفحة / رجوع المتصفح يطلقان pagehide — لا نسجّل خروجاً هنا.
      // نبقي فقط ختم وقت الإخفاء للأمان عند العودة بعد مهلة طويلة.
      listenDocumentPageHide(({required bool persisted}) {
        unawaited(_stampWebPageHidePause(persisted: persisted));
      });
    }

    if (!kIsWeb) {
      _appLinksSub = AppLinks().uriLinkStream.listen((uri) {
        final nav = _navKey.currentState;
        if (nav == null) return;
        final lang = langNotifier.value;

        final cid = AppListingLinks.contractIdFromVerifyUri(uri);
        if (cid != null && cid.isNotEmpty) {
          final vt = AppListingLinks.verifyTokenFromVerifyUri(uri) ?? '';
          nav.pushNamed<void>(
            AppRoutes.contractVerify,
            arguments: <String, String>{
              'contractId': cid,
              'lang': lang,
              if (vt.isNotEmpty) 'verifyToken': vt,
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
    final onDashboard =
        current == '/userDashboard' || current == '/userdashboard';
    if (!onDashboard) {
      final reg =
          await UserInstallSessionService.registerDeviceSlotAfterSignIn();
      if (!reg.ok && reg.code == 'device_limit') {
        if (!mounted) return;
        _navKey.currentState?.pushNamedAndRemoveUntil(
          AppRoutes.deviceManagement,
          (route) => false,
          arguments: <String, dynamic>{'mandatory': true},
        );
        return;
      }
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
  /// **الويب:** تبديل التبويب لا يخرج فوراً. تحديث الصفحة لا يخرج (انظر [_stampWebPageHidePause]).
  Future<void> _stampWebPageHidePause({required bool persisted}) async {
    if (recoveryFlowNotifier.value) return;
    if (suspendAutoLock.value) return;
    FastLoginService.clearRuntimeUnlock();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        kPrefAppPausedAtMs,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
    // persisted / تحديث: نبقي JWT في التخزين المحلي ليعود المستخدم لنفس الجلسة.
  }

  /// إخفاء التطبيق: مع الدخول السريع نُبقي الجلسة ونسجّل وقت الخلفية؛ وإلا نخرج كسابق.
  ///
  /// تبديل التبويب فقط لا يُخرج فوراً — يعتمد العدّاد. إغلاق التبويب لم يعد يمسح الجلسة
  /// عند pagehide حتى لا يُقطع تحديث F5/رجوع المتصفح.
  Future<void> _signOutOnBackgroundHide({bool pageHide = false}) async {
    if (recoveryFlowNotifier.value) return;
    if (suspendAutoLock.value) return;
    // أي إخفاء للواجهة يُبطل فتح الجلسة الحالي — عند العودة يُطلب الدخول المفضّل.
    FastLoginService.clearRuntimeUnlock();
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
      // ويب: لا خروج صامت عند pagehide/إخفاء — ختم الوقت فقط.
      // الأمان: خمول + FastLogin عند العودة بعد المهلة.
      if (pageHide) {
        await _stampWebPageHidePause(persisted: false);
        return;
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
          kPrefAppPausedAtMs,
          DateTime.now().millisecondsSinceEpoch,
        );
      } catch (_) {}
      return;
    }

    if (hasLock && !pageHide) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        kPrefAppPausedAtMs,
        DateTime.now().millisecondsSinceEpoch,
      );
      return;
    }

    // بلا قفل سريع: لا نسجّل خروجاً فورياً عند الخلفية —
    // حوار العدّ التنازلي في InactivityService هو المسار الوحيد.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        kPrefAppPausedAtMs,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
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

    // مستخدم مسجّل: بعد مهلة الخلفية → قفل سريع (بصمة/PIN) أو تسجيل دخول كامل.
    FastLoginService.clearRuntimeUnlock();
    final session = Supabase.instance.client.auth.currentSession;
    final hasLock = await FastLoginService.hasAnyLockEnabled();

    if (session != null && hasLock) {
      unawaited(ReturnAfterAuth.saveFromNavigatorKey(_navKey));
      _inactivity.dismissBlockingPrompt();
      nav.pushNamedAndRemoveUntil('/fastLogin', (r) => false);
      return;
    }

    if (session == null) {
      nav.pushNamedAndRemoveUntil('/login', (r) => false);
      return;
    }

    // جلسة موجودة بلا قفل سريع بعد تجاوز المهلة → خروج إلى شاشة الدخول.
    _inactivity.stop();
    try {
      await AuthLocalSignOut.signOutLocal(
        Supabase.instance.client,
        tryRemoteRevoke: true,
      );
    } catch (_) {
      try {
        await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      } catch (_) {}
    }
    if (mounted) _inactivity.start();
    nav.pushNamedAndRemoveUntil('/login', (r) => false);
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
    AppSoftKeyboardEnsureVisible.uninstall();
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
    if (state == AppLifecycleState.detached) {
      unawaited(_signOutOnBackgroundHide(pageHide: true));
      return;
    }
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden) {
      return;
    }
    unawaited(NotificationService.clearOsApplicationIconBadge());
    FastLoginService.clearRuntimeUnlock();
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
                            // عجلة الفأرة/إشارة التمرير لا تعيد مهلة الخمول — كانت تمنع ظهور النافذة.
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
                            final child = appChild ?? const SizedBox.shrink();
                            // جوال + ويب: شريط علوي فقط — لا IgnorePointer على كامل التطبيق.
                            // الطبقة الكاملة كانت تجمّد اللمس بعد الدخول عند فشل فحص خاطئ.
                            if (session.hasInternet) return child;
                            final loc = l10n;
                            final cs = Theme.of(context).colorScheme;
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                child,
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  child: Material(
                                    elevation: 4,
                                    color: cs.errorContainer,
                                    child: SafeArea(
                                      bottom: false,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.wifi_off_rounded,
                                              size: 20,
                                              color: cs.onErrorContainer,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                loc?.noInternetConnectionTitle ??
                                                    (lang == 'ar'
                                                        ? 'لا يوجد اتصال بالإنترنت'
                                                        : 'No Internet Connection'),
                                                style: TextStyle(
                                                  color: cs.onErrorContainer,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            if (session.networkCheckBusy)
                                              SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: cs.onErrorContainer,
                                                ),
                                              )
                                            else
                                              TextButton(
                                                onPressed: () => unawaited(
                                                  session.refreshConnectivity(
                                                    userInitiated: true,
                                                  ),
                                                ),
                                                child: Text(
                                                  loc?.retryLabel ??
                                                      (lang == 'ar'
                                                          ? 'إعادة المحاولة'
                                                          : 'Retry'),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                          child: wrapped,
                        );

                        wrapped = InAppNotificationToastHost(
                          lang: lang,
                          child: wrapped,
                        );

                        if (kIsWeb) {
                          wrapped = WebBrowserLifecycleHost(
                            lang: lang,
                            child: wrapped,
                          );
                        }

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
                        '/register': (context) => const RegisterScreen(),

                        // ✅ NEW routes
                        '/accountTypeSetup': (_) =>
                            const AccountTypeSetupScreen(),
                        '/verificationRequest': (_) =>
                            const VerificationRequestScreen(),

                        '/userDashboard': (context) => kIsWeb
                            ? WebDashboardEntryRedirect(lang: lang)
                            : UserDashboard(
                                key: const ValueKey('dashboard'),
                                lang: lang,
                              ),
                        '/userdashboard': (context) => kIsWeb
                            ? WebDashboardEntryRedirect(lang: lang)
                            : UserDashboard(
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
                          var verifyToken = '';
                          String resolvedLang = lang;
                          if (args is Map) {
                            contractId =
                                (args['contractId'] ?? args['id'] ?? '')
                                    .toString();
                            verifyToken =
                                (args['verifyToken'] ?? args['vt'] ?? '')
                                    .toString();
                            final l = (args['lang'] ?? '').toString();
                            if (l.isNotEmpty) resolvedLang = l;
                          }
                          if (contractId.trim().isEmpty)
                            return const GateScreen();
                          return ContractVerifyPage(
                            contractId: contractId.trim(),
                            lang: resolvedLang,
                            verifyToken:
                                verifyToken.trim().isEmpty ? null : verifyToken.trim(),
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

class _StartRouterState extends State<StartRouter> {
  bool _loading = true;
  Widget? _target;

  bool _retryingNet = false;
  StreamSubscription<AuthState>? _authSub;

  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      StartRouterController.register(_refreshAfterWebAuth);
    }
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      if (data.event == AuthChangeEvent.signedOut) {
        if (SessionManager.duringPublicSessionReset) return;
        // ضيف: مسح JWT بعد setGuest يطلق signedOut — لا نُعيد شاشة التحميل (كان يعلّق).
        unawaited(() async {
          try {
            final prefs = await SharedPreferences.getInstance();
            final guest = prefs.getBool(kPrefGuestMode) ?? false;
            final entry =
                (prefs.getString(kPrefEntryMode) ?? '').trim().toLowerCase();
            if (guest || entry == 'guest') return;
          } catch (_) {}
          if (!mounted) return;
          // الويب: اللوحة مُضمّنة — لا تُعد التحميل عند signedOut عرضي.
          if (kIsWeb && _target != null) return;
          setState(() {
            _loading = true;
            _target = null;
          });
          unawaited(_resolve());
        }());
      }
    });
    unawaited(_resolve());
  }

  @override
  void dispose() {
    if (kIsWeb) {
      StartRouterController.unregister(_refreshAfterWebAuth);
    }
    _authSub?.cancel();
    super.dispose();
  }

  /// مايو: فتح اللوحة مباشرة داخل StartRouter — بدون WebDashboardShell.
  Future<void> _openWebDashboardInPlace() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final entryMode =
        (prefs.getString(kPrefEntryMode) ?? '').trim().toLowerCase();
    final guestMode = prefs.getBool(kPrefGuestMode) ?? false;
    final session = Supabase.instance.client.auth.currentSession;
    // Auth حيّ = مستخدم مسجّل حتى لو بقيت prefs الضيف.
    final isGuest =
        session == null && (guestMode || entryMode == 'guest');
    if (session != null && (guestMode || entryMode == 'guest')) {
      try {
        await prefs.setBool(kPrefGuestMode, false);
        await prefs.setString(kPrefEntryMode, 'user');
      } catch (_) {}
    }

    if (isGuest || session == null) {
      if (!mounted) return;
      setState(() {
        _target = UserDashboard(
          key: const ValueKey('dashboard-guest'),
          lang: widget.lang,
        );
        _loading = false;
      });
      if (kIsWeb) syncWebDashboardHashInAddressBar();
      return;
    }

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
    if (kIsWeb) syncWebDashboardHashInAddressBar();
  }

  /// بعد OTP/ضيف: تحديث اللوحة داخل نفس [StartRouter] دون إعادة بناء المكدس.
  Future<void> _refreshAfterWebAuth() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final entryMode =
        (prefs.getString(kPrefEntryMode) ?? '').trim().toLowerCase();
    final guestMode = prefs.getBool(kPrefGuestMode) ?? false;
    final session = Supabase.instance.client.auth.currentSession;
    final isGuest =
        session == null && (guestMode || entryMode == 'guest');

    if (isGuest) {
      await _openWebDashboardInPlace();
      return;
    }

    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id ?? '';
    final verified = uid.isNotEmpty
        ? (prefs.getBool(otpVerifiedKey(uid)) ?? false)
        : false;

    if (verified) {
      await _openWebDashboardInPlace();
      return;
    }
    await _resolve();
  }

  Future<bool> _hasInternet() async {
    // فشل مفتوح: لا نمنع الدخول للوحة بسبب فحص شبكة بطيء/فاشل.
    try {
      return await ConnectivityGuard.hasPluginLink()
          .timeout(const Duration(seconds: 5), onTimeout: () => true);
    } catch (_) {
      return true;
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

    final okNet = kIsWeb ? true : await _hasInternet();
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

    final prefs = await SharedPreferences.getInstance();

    final String entryMode =
        (prefs.getString(kPrefEntryMode) ?? '').trim().toLowerCase();
    final bool guestMode = prefs.getBool(kPrefGuestMode) ?? false;

    final sb = Supabase.instance.client;
    Session? session = sb.auth.currentSession;

    // جلسة Auth حية تلغي prefs الضيف المتأخرة (كانت تسبب إقلاع مزدوج على الويب).
    final bool isGuest =
        (session == null) && (guestMode || entryMode == 'guest');
    if (session != null && (guestMode || entryMode == 'guest')) {
      try {
        await prefs.setBool(kPrefGuestMode, false);
        await prefs.setString(kPrefEntryMode, 'user');
      } catch (_) {}
    }

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
          key: const ValueKey('dashboard-guest'),
          lang: widget.lang,
        );
        _loading = false;
      });
      if (kIsWeb) syncWebDashboardHashInAddressBar();
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

        // عند كل فتح جديد للعملية: إن وُجد قفل سريع (PIN/بصمة) يُطلب قبل اللوحة.
        if (await FastLoginService.hasAnyLockEnabled() &&
            !FastLoginService.hasUnlockedThisRuntimeSession) {
          if (!mounted) return;
          setState(() {
            _target = const FastLoginScreen();
            _loading = false;
          });
          return;
        }

        // مايو: فتح مباشر دون WebDashboardShell.
        // لا نوجّه المسوّق إلى MarketerDashboardPage (لوحة فريق فقط) —
        // الرئيسية/إعلاناتي/طلباتي كلها داخل UserDashboard.
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
        if (kIsWeb) syncWebDashboardHashInAddressBar();
        return;
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
      if (kIsWeb) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          removeWebHtmlSplash();
        });
      }
      return Scaffold(
        backgroundColor: const Color(0xFFF3F6F8),
        body: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.92, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, scale, child) {
              return Opacity(
                opacity: ((scale - 0.92) / 0.08).clamp(0.0, 1.0),
                child: Transform.scale(scale: scale, child: child),
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  AppBranding.bootLogoAsset(context),
                  width: (MediaQuery.sizeOf(context).shortestSide * 0.42)
                      .clamp(140.0, 220.0),
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, __, ___) => AppBusyIndicator.page(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      AppBranding.welcomeHeadline(
                        context,
                        isAr: widget.lang.toLowerCase() != 'en',
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0B1220),
                        height: 1.25,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                AppBusyIndicator.page(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        removeWebHtmlSplash();
      });
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
