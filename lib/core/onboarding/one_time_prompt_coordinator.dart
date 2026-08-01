import 'package:shared_preferences/shared_preferences.dart';

/// مركزية لرسائل/خطوات تُعرض **مرة واحدة** حسب ترتيب [defaultPromptOrder].
///
/// - الشروط ولون التمييز: لكل **حساب** عبر [idForUser] حتى لا يتأثر حساب آخر على نفس الجهاز.
/// - الجولة التعريفية: مفتاح مشترك للجهاز مع ترحيل اختياري لكل مستخدم عبر [DeviceFirstRunPrefs].
abstract final class OneTimePromptCoordinator {
  static String _storageKey(String promptId) =>
      'one_time_prompt_seen_${promptId.trim()}';

  /// ترتيب افتراضي (مفاتيح أساسية — استخدم [defaultPromptOrderForUser] للعرض).
  static const List<String> defaultPromptOrder = <String>[
    'legal_terms_policy_coach_v2',
    'dashboard_onboarding_v3',
    'accent_color_prompt_v1',
  ];

  /// ترحيب قديم (شريط) — للتوافق.
  static const String _legacyWelcomeKey =
      'one_time_prompt_seen_welcome_after_login';

  /// مفتاح لكل مستخدم (شروط/لون) حتى لا يتأثر حساب آخر على نفس الجهاز.
  static String idForUser(String promptId, String? userId) {
    final base = promptId.trim();
    final u = (userId ?? '').trim();
    if (u.isEmpty) return base;
    return '${base}__$u';
  }

  /// ترتيب العرض للحساب الحالي: شروط → جولة → لون تمييز.
  static List<String> defaultPromptOrderForUser(String? userId) => <String>[
        idForUser('legal_terms_policy_coach_v2', userId),
        'dashboard_onboarding_v3',
        idForUser('accent_color_prompt_v1', userId),
      ];

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

  /// أول معلّق للحساب الحالي (شروط/لون مربوطان بـ uid).
  static Future<String?> nextDefaultPendingForUser(String? userId) =>
      firstPending(defaultPromptOrderForUser(userId));
}
