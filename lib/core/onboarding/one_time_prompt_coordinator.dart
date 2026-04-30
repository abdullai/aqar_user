import 'package:shared_preferences/shared_preferences.dart';

/// مركزية لرسائل/خطوات تُعرض **مرة واحدة** حسب ترتيب [defaultPromptOrder].
///
/// منفصلة عن إشعارات Realtime داخل الجلسة ([InAppNotificationHub]): تلك تُصفّ في طابور
/// ويُعاد عرضها عند الإغلاق؛ أما المفاتيح هنا فللتلميحات/المدربات وليس لكل إشعار.
///
/// - كل معرف [promptId] يُخزَّن في `SharedPreferences` تحت المفتاح `one_time_prompt_seen_<promptId>`.
/// - استخدم [firstPending] لمعرفة أول عنصر في القائمة لم يُكمَل بعد.
/// - اربط واجهاتك (شروط، أذونات، تلميحات) بهذه الدالة بدل تكرار مفاتيح متفرقة.
///
/// أمثلة معرفات (يمكن توسيعها دون كسر التوافق):
/// - `welcome_dashboard_hint`
/// - `notification_settings_coach_mark`
/// - `legal_terms_policy_coach_v1` — يُعرض فقط إذا كان `terms_version_accepted` يطابق النسخة النشطة (انظر LegalTermsPromptService).
abstract final class OneTimePromptCoordinator {
  static String _storageKey(String promptId) =>
      'one_time_prompt_seen_${promptId.trim()}';

  /// ترتيب افتراضي لعناصر «مرة واحدة» القادمة (بعد إكمال جولة لوحة التحكم).
  static const List<String> defaultPromptOrder = <String>[
    'legal_terms_policy_coach_v1',
    'dashboard_onboarding_v3',
    'accent_color_prompt_v1',
  ];

  /// ترحيب قديم (شريط) — للتوافق.
  static const String _legacyWelcomeKey = 'one_time_prompt_seen_welcome_after_login';

  /// يضمن عدم تكرار الجولة لمن أكمل [dashboard_onboarding_v2] أو الترحيب القديم.
  static Future<void> migrateLegacyOnboardingKeysIfNeeded() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_legacyWelcomeKey) == true) {
      await markSeen('dashboard_onboarding_v3');
    }
    if (p.getBool(_storageKey('dashboard_onboarding_v2')) == true) {
      await markSeen('dashboard_onboarding_v3');
    }
  }

  static Future<bool> hasSeen(String promptId) async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_storageKey(promptId)) ?? false;
  }

  static Future<void> markSeen(String promptId) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_storageKey(promptId), true);
  }

  static Future<void> resetForDebug(String promptId) async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_storageKey(promptId));
  }

  /// أول [promptId] في [orderedIds] لم يُعلَم كمشاهد بعد، أو `null` إن انتهت القائمة.
  static Future<String?> firstPending(Iterable<String> orderedIds) async {
    for (final id in orderedIds) {
      final trimmed = id.trim();
      if (trimmed.isEmpty) continue;
      if (!await hasSeen(trimmed)) return trimmed;
    }
    return null;
  }

  /// يعادل [firstPending(defaultPromptOrder)].
  static Future<String?> nextDefaultPending() =>
      firstPending(defaultPromptOrder);
}
