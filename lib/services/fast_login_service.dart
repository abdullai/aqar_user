// lib/services/fast_login_service.dart
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ✅ Biometrics (يتطلب إضافة local_auth في pubspec.yaml إذا لم يكن موجوداً)
import 'package:local_auth/local_auth.dart';

class FastLoginService {
  FastLoginService._();

  /// ✅ لتوافق GateScreen الذي يستخدم FastLoginService.instance
  static final FastLoginService instance = FastLoginService._();

  /// بعد نجاح PIN/بصمة: يمنع إعادة فتح القفل فوراً عند `Navigator` إلى `/`.
  /// يُصفَّر عند فتح [FastLoginScreen] أو قفل من الخمول/الخلفية.
  static bool _unlockedThisRuntimeSession = false;

  static bool get hasUnlockedThisRuntimeSession => _unlockedThisRuntimeSession;

  static void markRuntimeUnlocked() {
    _unlockedThisRuntimeSession = true;
  }

  static void clearRuntimeUnlock() {
    _unlockedThisRuntimeSession = false;
  }

  // -----------------------------
  // Keys
  // -----------------------------
  static const _kPinEnabled = 'fast_pin_enabled';
  static const _kPinHash = 'fast_pin_hash';
  static const _kBioEnabled = 'fast_bio_enabled';
  static const _kBioFaceEnabled = 'fast_bio_face_enabled';
  static const _kBioFingerprintEnabled = 'fast_bio_fingerprint_enabled';
  static const _kBioPrefsMigrated = 'fast_bio_prefs_migrated_v2';

  /// ✅ حالة رسالة الاقتراح:
  /// - 'never' : المستخدم ضغط "لا" => لا تعرض مرة أخرى
  /// - 'later' : المستخدم ضغط "ذكرني لاحقاً" (لا تمنع العرض مستقبلاً)
  /// - 'done'  : تم تفعيل الدخول السريع (PIN أو بصمة) => لا داعي لعرض الرسالة
  /// - null    : لم تُعرض/لم يقرر بعد
  static const _kPromptState = 'fast_prompt_state';

  /// ✅ عداد تسجيل الدخول الناجح (نزيده عند دخول الداشبور بعد login)
  static const _kPromptLoginCount = 'fast_prompt_login_count';

  /// ✅ وقت آخر عرض للرسالة (اختياري)
  static const _kPromptLastShownAt = 'fast_prompt_last_shown_at';

  static const _kCtxUid = 'fast_ctx_uid';
  static const _kCtxDisplayName = 'fast_ctx_display_name';
  static const _kCtxLang = 'fast_ctx_lang';

  // ✅ جديد لتوافق verify_screen.dart (usernameNationalId)
  static const _kCtxUsernameNationalId = 'fast_ctx_username_national_id';

  static const _kPinLength = 'fast_pin_length';

  /// يطابق مفاتيح `main.dart` لمسار شاشة القفل عند فتح التطبيق.
  static const kPrefBootstrapFastEnabled = 'fast_login_enabled';
  static const kPrefBootstrapPinSet = 'fast_login_pin_set';

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  /// طول رمز PIN المحفوظ (للواجهة). الافتراضي 6 لتوافق الحسابات القديمة.
  static Future<int> storedPinLength() async {
    final p = await _prefs();
    return p.getInt(_kPinLength) ?? 6;
  }

  /// مزامنة أعلام البداية مع حالة القفل الفعلية (PIN/بصمة).
  static Future<void> syncBootstrapRoutePrefs() async {
    final p = await _prefs();
    final pin = await isPinEnabled();
    final bio = await hasAnyBiometricUnlockConfigured();
    final gate = pin || bio;
    await p.setBool(kPrefBootstrapFastEnabled, gate);
    await p.setBool(kPrefBootstrapPinSet, pin);
  }

  static Future<void> _ensureBioPrefsMigrated() async {
    final p = await _prefs();
    if (p.getBool(_kBioPrefsMigrated) == true) return;
    final oldBio = p.getBool(_kBioEnabled) ?? false;
    if (oldBio) {
      await p.setBool(_kBioFaceEnabled, true);
      await p.setBool(_kBioFingerprintEnabled, true);
    }
    await p.setBool(_kBioPrefsMigrated, true);
  }

  static Future<bool> deviceReportsFaceSensor() async {
    final t = await getAvailableBiometricTypes();
    return _typesHaveFace(t);
  }

  static Future<bool> deviceReportsFingerprintSensor() async {
    final t = await getAvailableBiometricTypes();
    return _typesHaveFingerprint(t);
  }

  static Future<List<BiometricType>> getAvailableBiometricTypes() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return const [];
    }
  }

  static bool _typesHaveFace(Iterable<BiometricType> types) {
    for (final t in types) {
      if (t == BiometricType.face ||
          t == BiometricType.iris ||
          t == BiometricType.strong) {
        return true;
      }
    }
    return false;
  }

  static bool _typesHaveFingerprint(Iterable<BiometricType> types) {
    for (final t in types) {
      if (t == BiometricType.fingerprint ||
          t == BiometricType.weak ||
          t == BiometricType.strong) {
        return true;
      }
    }
    return false;
  }

  /// المستخدم فعّل خياراً بومترياً (واجهة الإعدادات).
  static Future<bool> isFaceLoginPreferred() async {
    await _ensureBioPrefsMigrated();
    final p = await _prefs();
    return p.getBool(_kBioFaceEnabled) ?? false;
  }

  static Future<bool> isFingerprintLoginPreferred() async {
    await _ensureBioPrefsMigrated();
    final p = await _prefs();
    return p.getBool(_kBioFingerprintEnabled) ?? false;
  }

  /// هل يمكن استخدام البصمة فعلياً على شاشة القفل (جهاز + خيارات المستخدم).
  static Future<bool> hasAnyBiometricUnlockConfigured() async {
    await _ensureBioPrefsMigrated();
    if (!await canCheckBiometrics()) return false;
    final types = await getAvailableBiometricTypes();
    if (types.isEmpty) return false;
    final p = await _prefs();
    final faceOn = p.getBool(_kBioFaceEnabled) ?? false;
    final fpOn = p.getBool(_kBioFingerprintEnabled) ?? false;
    final legacy = p.getBool(_kBioEnabled) ?? false;
    if (legacy && !faceOn && !fpOn) {
      return true;
    }
    if (faceOn && _typesHaveFace(types)) return true;
    if (fpOn && _typesHaveFingerprint(types)) return true;
    return false;
  }

  // -----------------------------
  // Helpers
  // -----------------------------
  static String normalizeDigits(String input) {
    final s = input.trim();
    if (s.isEmpty) return s;

    const ar = '٠١٢٣٤٥٦٧٨٩';
    const fa = '۰۱۲۳۴۵۶۷۸۹';

    final buf = StringBuffer();
    for (final ch in s.runes) {
      final c = String.fromCharCode(ch);
      final ai = ar.indexOf(c);
      if (ai >= 0) {
        buf.write(ai);
        continue;
      }
      final fi = fa.indexOf(c);
      if (fi >= 0) {
        buf.write(fi);
        continue;
      }
      buf.write(c);
    }
    return buf.toString();
  }

  static String _hashPin(String pin) {
    final bytes = utf8.encode(pin);
    return sha256.convert(bytes).toString();
  }

  // -----------------------------
  // Prompt state
  // -----------------------------
  static Future<String?> promptState() async {
    final p = await _prefs();
    return p.getString(_kPromptState);
  }

  static Future<void> setPromptState(String state) async {
    final p = await _prefs();
    await p.setString(_kPromptState, state);
  }

  static Future<bool> isPromptNever() async {
    final st = await promptState();
    return st == 'never';
  }

  static Future<void> markPromptNever() async {
    await setPromptState('never');
  }

  static Future<void> markPromptLater() async {
    await setPromptState('later');
  }

  static Future<void> markPromptDone() async {
    await setPromptState('done');
  }

  static Future<int> bumpPromptLoginCountAndGet() async {
    final p = await _prefs();
    final v = (p.getInt(_kPromptLoginCount) ?? 0) + 1;
    await p.setInt(_kPromptLoginCount, v);
    return v;
  }

  static Future<int> getPromptLoginCount() async {
    final p = await _prefs();
    return p.getInt(_kPromptLoginCount) ?? 0;
  }

  static Future<void> setPromptLastShownNow() async {
    final p = await _prefs();
    await p.setInt(_kPromptLastShownAt, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<int?> getPromptLastShownAtMs() async {
    final p = await _prefs();
    return p.getInt(_kPromptLastShownAt);
  }

  /// عرض اقتراح الدخول السريع (بعد «ذكرني لاحقاً»): أول مرة أو بعد [hoursBetween] ساعة.
  static Future<bool> shouldShowScheduledReminder({
    int hoursBetween = 24,
  }) async {
    if (await isPromptNever()) return false;
    if (await hasAnyLockEnabled()) {
      await markPromptDone();
      return false;
    }
    final st = await promptState();
    if (st == 'done') return false;

    final last = await getPromptLastShownAtMs();
    if (last == null) return true;
    final elapsed = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(last),
    );
    return elapsed.inHours >= hoursBetween;
  }

  // -----------------------------
  // PIN
  // -----------------------------
  static Future<bool> isPinEnabled() async {
    final p = await _prefs();
    return p.getBool(_kPinEnabled) ?? false;
  }

  static Future<void> setPinEnabled(bool enabled) async {
    final p = await _prefs();
    await p.setBool(_kPinEnabled, enabled);
    await syncBootstrapRoutePrefs();
  }

  static Future<void> setPin(String pinRaw) async {
    final pin = normalizeDigits(pinRaw);
    if (pin.length < 4 || pin.length > 8) {
      throw Exception('PIN_TOO_SHORT');
    }
    final p = await _prefs();
    await p.setString(_kPinHash, _hashPin(pin));
    await p.setInt(_kPinLength, pin.length);
    await p.setBool(_kPinEnabled, true);

    // ✅ طالما المستخدم أنشأ PIN إذن الدخول السريع صار مفعلاً (لا داعي لعرض الرسالة لاحقاً)
    await markPromptDone();
    await syncBootstrapRoutePrefs();
  }

  static Future<bool> verifyPin(String pinRaw) async {
    final pin = normalizeDigits(pinRaw);
    final p = await _prefs();
    final hash = p.getString(_kPinHash);
    if (hash == null || hash.isEmpty) return false;
    return _hashPin(pin) == hash;
  }

  // -----------------------------
  // Biometrics
  // -----------------------------
  static final LocalAuthentication _auth = LocalAuthentication();

  static Future<bool> canCheckBiometrics() async {
    try {
      final can = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      return can && supported;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isBiometricEnabled() async {
    await _ensureBioPrefsMigrated();
    final p = await _prefs();
    return (p.getBool(_kBioFaceEnabled) ?? false) ||
        (p.getBool(_kBioFingerprintEnabled) ?? false) ||
        (p.getBool(_kBioEnabled) ?? false);
  }

  static Future<void> setBiometricEnabled(bool enabled) async {
    final p = await _prefs();
    await p.setBool(_kBioEnabled, enabled);
    await p.setBool(_kBioFaceEnabled, enabled);
    await p.setBool(_kBioFingerprintEnabled, enabled);

    if (enabled) {
      await markPromptDone();
    }
    await syncBootstrapRoutePrefs();
  }

  static Future<void> setFaceLoginEnabled(bool enabled) async {
    await _ensureBioPrefsMigrated();
    final p = await _prefs();
    await p.setBool(_kBioFaceEnabled, enabled);
    if (enabled) {
      await markPromptDone();
      await p.setBool(_kBioEnabled, true);
    } else {
      final fp = p.getBool(_kBioFingerprintEnabled) ?? false;
      if (!fp) await p.setBool(_kBioEnabled, false);
    }
    await syncBootstrapRoutePrefs();
  }

  static Future<void> setFingerprintLoginEnabled(bool enabled) async {
    await _ensureBioPrefsMigrated();
    final p = await _prefs();
    await p.setBool(_kBioFingerprintEnabled, enabled);
    if (enabled) {
      await markPromptDone();
      await p.setBool(_kBioEnabled, true);
    } else {
      final face = p.getBool(_kBioFaceEnabled) ?? false;
      if (!face) await p.setBool(_kBioEnabled, false);
    }
    await syncBootstrapRoutePrefs();
  }

  static Future<bool> authenticateBiometric({required bool isAr}) async {
    try {
      if (!await hasAnyBiometricUnlockConfigured()) return false;
      if (!await _auth.isDeviceSupported()) return false;
      if (!await _auth.canCheckBiometrics) return false;

      final pinFallback = await isPinEnabled();
      // stickyAuth: يبقي نافذة البصمة عند تغيير التطبيق قليلاً.
      // عند عدم وجود PIN نفضّل biometricOnly لتقوية مسار البصمة/الوجه فقط.
      final ok = await _auth.authenticate(
        localizedReason: isAr
            ? 'تأكيد الهوية لفتح التطبيق'
            : 'Confirm your identity to unlock the app',
        options: AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: !pinFallback,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      );
      return ok;
    } catch (_) {
      return false;
    }
  }

  // -----------------------------
  // Combined
  // -----------------------------
  static Future<bool> hasAnyLockEnabled() async {
    final pin = await isPinEnabled();
    final bio = await hasAnyBiometricUnlockConfigured();
    return pin || bio;
  }

  // -----------------------------
  // User context (اختياري لعرض الاسم في شاشة الدخول السريع)
  // -----------------------------
  /// ✅ تم توسيع التوقيع لدعم:
  /// verify_screen.dart: usernameNationalId: ...
  /// وأيضاً لدعم الاستدعاءات القديمة: uid / displayName / lang
  static Future<void> saveUserContext({
    required String uid,
    String? displayName,
    String? lang,

    // ✅ الجديد
    String? usernameNationalId,
  }) async {
    final p = await _prefs();
    await p.setString(_kCtxUid, uid);

    if (displayName != null) {
      final v = displayName.trim();
      if (v.isNotEmpty) {
        await p.setString(_kCtxDisplayName, v);
      } else {
        await p.remove(_kCtxDisplayName);
      }
    }

    if (lang != null) {
      final v = lang.trim();
      if (v.isNotEmpty) {
        await p.setString(_kCtxLang, v);
      } else {
        await p.remove(_kCtxLang);
      }
    }

    if (usernameNationalId != null) {
      final v = normalizeDigits(usernameNationalId).trim();
      if (v.isNotEmpty) {
        await p.setString(_kCtxUsernameNationalId, v);
      } else {
        await p.remove(_kCtxUsernameNationalId);
      }
    }
  }

  static Future<String?> getDisplayName() async {
    final p = await _prefs();
    return p.getString(_kCtxDisplayName);
  }

  static Future<String?> getCtxUid() async {
    final p = await _prefs();
    return p.getString(_kCtxUid);
  }

  static Future<String?> getCtxLang() async {
    final p = await _prefs();
    return p.getString(_kCtxLang);
  }

  static Future<String?> getUsernameNationalId() async {
    final p = await _prefs();
    return p.getString(_kCtxUsernameNationalId);
  }

  // -----------------------------
  // Instance helpers (لتوافق GateScreen)
  // -----------------------------
  /// ✅ يستخدمه GateScreen لتحديد هل يفتح شاشة الدخول السريع أو لا
  Future<bool> hasValidUser() async {
    final uid = await getCtxUid();
    if (uid == null || uid.trim().isEmpty) return false;

    // يجب وجود أي قفل (PIN أو بصمة) حتى يعتبر الدخول السريع مفعلاً
    final hasLock = await hasAnyLockEnabled();
    if (!hasLock) return false;

    return true;
  }

  // -----------------------------
  // Clear
  // -----------------------------
  static Future<void> clearAll() async {
    final p = await _prefs();
    await p.remove(_kPinEnabled);
    await p.remove(_kPinHash);
    await p.remove(_kPinLength);
    await p.remove(_kBioEnabled);
    await p.remove(_kBioFaceEnabled);
    await p.remove(_kBioFingerprintEnabled);
    await p.remove(_kBioPrefsMigrated);

    await p.remove(_kPromptState);
    await p.remove(_kPromptLoginCount);
    await p.remove(_kPromptLastShownAt);

    await p.remove(_kCtxUid);
    await p.remove(_kCtxDisplayName);
    await p.remove(_kCtxLang);
    await p.remove(_kCtxUsernameNationalId);

    await p.setBool(kPrefBootstrapFastEnabled, false);
    await p.setBool(kPrefBootstrapPinSet, false);
    clearRuntimeUnlock();
  }

  // -----------------------------
  // Debug hint (اختياري)
  // -----------------------------
  static void debugPrintState() async {
    if (!kDebugMode) return;
    final pin = await isPinEnabled();
    final bio = await hasAnyBiometricUnlockConfigured();
    final st = await promptState();
    final cnt = await getPromptLoginCount();
    final uid = await getCtxUid();
    final name = await getDisplayName();
    final nid = await getUsernameNationalId();
    // ignore: avoid_print
    print(
        'FastLogin: uid=$uid name=$name nid=$nid pin=$pin bio=$bio prompt=$st count=$cnt');
  }
}