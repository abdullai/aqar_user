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

  /// محاولات PIN الفاشلة + قفل مؤقت.
  static const _kPinFailCount = 'fast_pin_fail_count';
  static const _kPinLockUntilMs = 'fast_pin_lock_until_ms';
  static const int kPinMaxAttempts = 5;
  static const Duration kPinLockout = Duration(minutes: 2);

  /// لقطة استئناف الحساب بعد الخروج الكامل (كلمة المرور فقط — بدون أسرار القفل).
  static const _kResumeUid = 'fast_resume_uid';
  static const _kResumeDisplayName = 'fast_resume_display_name';
  static const _kResumeUsername = 'fast_resume_username';

  /// يطابق مفاتيح `main.dart` لمسار شاشة القفل عند فتح التطبيق.
  static const kPrefBootstrapFastEnabled = 'fast_login_enabled';
  static const kPrefBootstrapPinSet = 'fast_login_pin_set';

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  /// إخفاء رقم الهوية/الإقامة للعرض الآمن (يظهر آخر 4 أرقام فقط).
  static String maskNationalId(String? raw) {
    final d = normalizeDigits((raw ?? '').trim());
    if (d.isEmpty) return '';
    if (d.length <= 4) return '••••$d';
    final tail = d.substring(d.length - 4);
    return '${'•' * (d.length - 4)}$tail';
  }

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
    if (await isPinTemporarilyLocked()) return false;
    final pin = normalizeDigits(pinRaw);
    final p = await _prefs();
    final hash = p.getString(_kPinHash);
    if (hash == null || hash.isEmpty) return false;
    final ok = _hashPin(pin) == hash;
    if (ok) {
      await clearPinFailState();
      return true;
    }
    await registerPinFailure();
    return false;
  }

  static Future<bool> isPinTemporarilyLocked() async {
    final p = await _prefs();
    final until = p.getInt(_kPinLockUntilMs) ?? 0;
    if (until <= 0) return false;
    if (DateTime.now().millisecondsSinceEpoch >= until) {
      await p.remove(_kPinLockUntilMs);
      await p.setInt(_kPinFailCount, 0);
      return false;
    }
    return true;
  }

  static Future<int> pinLockRemainingSeconds() async {
    final p = await _prefs();
    final until = p.getInt(_kPinLockUntilMs) ?? 0;
    if (until <= 0) return 0;
    final sec =
        ((until - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
    return sec.clamp(0, kPinLockout.inSeconds);
  }

  static Future<void> registerPinFailure() async {
    final p = await _prefs();
    final n = (p.getInt(_kPinFailCount) ?? 0) + 1;
    await p.setInt(_kPinFailCount, n);
    if (n >= kPinMaxAttempts) {
      await p.setInt(
        _kPinLockUntilMs,
        DateTime.now().add(kPinLockout).millisecondsSinceEpoch,
      );
      await p.setInt(_kPinFailCount, 0);
    }
  }

  static Future<void> clearPinFailState() async {
    final p = await _prefs();
    await p.remove(_kPinFailCount);
    await p.remove(_kPinLockUntilMs);
  }

  static Future<int> pinFailCount() async {
    final p = await _prefs();
    return p.getInt(_kPinFailCount) ?? 0;
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

    String? resolvedName = displayName?.trim();
    if (resolvedName != null) {
      if (resolvedName.isNotEmpty) {
        await p.setString(_kCtxDisplayName, resolvedName);
      } else {
        await p.remove(_kCtxDisplayName);
        resolvedName = null;
      }
    } else {
      resolvedName = p.getString(_kCtxDisplayName);
    }

    if (lang != null) {
      final v = lang.trim();
      if (v.isNotEmpty) {
        await p.setString(_kCtxLang, v);
      } else {
        await p.remove(_kCtxLang);
      }
    }

    String? resolvedUser = usernameNationalId != null
        ? normalizeDigits(usernameNationalId).trim()
        : null;
    if (resolvedUser != null) {
      if (resolvedUser.isNotEmpty) {
        await p.setString(_kCtxUsernameNationalId, resolvedUser);
      } else {
        await p.remove(_kCtxUsernameNationalId);
        resolvedUser = null;
      }
    } else {
      resolvedUser = p.getString(_kCtxUsernameNationalId);
    }

    await p.setString(_kResumeUid, uid);
    if ((resolvedName ?? '').isNotEmpty) {
      await p.setString(_kResumeDisplayName, resolvedName!);
    }
    if ((resolvedUser ?? '').isNotEmpty) {
      await p.setString(_kResumeUsername, resolvedUser!);
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

  /// هل يمكن قفل الجلسة ناعماً بعد الخمول؟ (جلسة + سياق مستخدم أو قفل)
  static Future<bool> canSoftLockSession() async {
    if (await hasAnyLockEnabled()) return true;
    var u = await getUsernameNationalId();
    if (u != null && u.trim().length >= 10) return true;
    final resume = await getResumeAccount();
    final ru = normalizeDigits((resume.username ?? '').trim());
    if (ru.length >= 10) {
      // أعد ملء السياق من لقطة الاستئناف حتى تعمل شاشة القفل بكلمة المرور.
      final uid = resume.uid ?? '';
      if (uid.isNotEmpty) {
        await saveUserContext(
          uid: uid,
          displayName: resume.displayName,
          usernameNationalId: ru,
        );
      } else {
        final p = await _prefs();
        await p.setString(_kCtxUsernameNationalId, ru);
        if ((resume.displayName ?? '').trim().isNotEmpty) {
          await p.setString(_kCtxDisplayName, resume.displayName!.trim());
        }
      }
      return true;
    }
    return false;
  }

  static Future<({String? uid, String? displayName, String? username})>
      getResumeAccount() async {
    final p = await _prefs();
    return (
      uid: p.getString(_kResumeUid),
      displayName: p.getString(_kResumeDisplayName),
      username: p.getString(_kResumeUsername),
    );
  }

  static Future<void> clearResumeAccount() async {
    final p = await _prefs();
    await p.remove(_kResumeUid);
    await p.remove(_kResumeDisplayName);
    await p.remove(_kResumeUsername);
  }

  /// عند الخروج الكامل: أزل أسرار القفل لكن أبقِ لقطة الاستئناف (كلمة المرور).
  static Future<void> clearSecretsKeepResume() async {
    final p = await _prefs();
    final resumeUid = p.getString(_kResumeUid) ?? p.getString(_kCtxUid);
    final resumeName =
        p.getString(_kResumeDisplayName) ?? p.getString(_kCtxDisplayName);
    final resumeUser =
        p.getString(_kResumeUsername) ?? p.getString(_kCtxUsernameNationalId);

    await p.remove(_kPinEnabled);
    await p.remove(_kPinHash);
    await p.remove(_kPinLength);
    await p.remove(_kBioEnabled);
    await p.remove(_kBioFaceEnabled);
    await p.remove(_kBioFingerprintEnabled);
    await p.remove(_kPinFailCount);
    await p.remove(_kPinLockUntilMs);

    await p.remove(_kCtxUid);
    await p.remove(_kCtxDisplayName);
    await p.remove(_kCtxLang);
    await p.remove(_kCtxUsernameNationalId);

    await p.setBool(kPrefBootstrapFastEnabled, false);
    await p.setBool(kPrefBootstrapPinSet, false);
    clearRuntimeUnlock();

    if ((resumeUid ?? '').isNotEmpty) {
      await p.setString(_kResumeUid, resumeUid!);
    }
    if ((resumeName ?? '').isNotEmpty) {
      await p.setString(_kResumeDisplayName, resumeName!);
    }
    if ((resumeUser ?? '').isNotEmpty) {
      await p.setString(_kResumeUsername, resumeUser!);
    }
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
    await p.remove(_kPinFailCount);
    await p.remove(_kPinLockUntilMs);

    await p.remove(_kPromptState);
    await p.remove(_kPromptLoginCount);
    await p.remove(_kPromptLastShownAt);

    await p.remove(_kCtxUid);
    await p.remove(_kCtxDisplayName);
    await p.remove(_kCtxLang);
    await p.remove(_kCtxUsernameNationalId);

    await p.remove(_kResumeUid);
    await p.remove(_kResumeDisplayName);
    await p.remove(_kResumeUsername);

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