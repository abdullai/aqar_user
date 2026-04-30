import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// مفتاح تخزين لون التمييز **للجهاز** (ضيف أو بعد تسجيل الخروج).
const String kPrefAccentId = 'app_accent_id';

String _accentKeyForUser(String? userId) {
  final u = (userId ?? '').trim();
  if (u.isEmpty) return kPrefAccentId;
  return 'app_accent_id_$u';
}

/// لوحة محدودة (5) لألوان التمييز — نفس البذور للوضعين الفاتح والداكن عبر AppTheme.
/// الاختيار: أول دخول (حوار لوحة التحكم) أو الإعدادات في أي وقت (`kPrefAccentId`).
abstract final class AppAccent {
  static const int count = 5;

  /// ترتيب ثابت: افتراضي ثم بدائل متناغمة مع Material 3.
  static const List<Color> seeds = <Color>[
    Color(0xFF0F766E),
    Color(0xFF0369A1),
    Color(0xFF5B21B6),
    Color(0xFF0D9488),
    Color(0xFFCA8A04),
  ];

  static Color seedForIndex(int i) =>
      seeds[i.clamp(0, seeds.length - 1)];
}

/// يُحدَّث عند تغيير لون التمييز من الإعدادات أو حوار أول دخول.
final ValueNotifier<Color> accentSeedNotifier =
    ValueNotifier<Color>(AppAccent.seeds[0]);

/// يحمّل لون التمييز للمستخدم المسجّل الحالي إن وُجد [userId]، وإلا للجهاز الافتراضي.
/// عند أول دخول لمستخدم جديد: إن لم يُحفظ له لون، يُنسخ من لون الجهاز مرة واحدة.
Future<void> loadAppAccentFromPrefs({String? userId}) async {
  final p = await SharedPreferences.getInstance();
  final key = _accentKeyForUser(userId);
  if (userId != null && userId.trim().isNotEmpty && !p.containsKey(key)) {
    final dev = p.getInt(kPrefAccentId);
    if (dev != null) {
      await p.setInt(key, dev);
    }
  }
  final id = (p.getInt(key) ?? p.getInt(kPrefAccentId) ?? 0)
      .clamp(0, AppAccent.count - 1);
  accentSeedNotifier.value = AppAccent.seedForIndex(id);
}

Future<void> setAppAccentIndex(int index, {String? userId}) async {
  final i = index.clamp(0, AppAccent.count - 1);
  final p = await SharedPreferences.getInstance();
  String? uid = userId;
  try {
    uid ??= Supabase.instance.client.auth.currentUser?.id;
  } catch (_) {}
  final key = _accentKeyForUser(uid);
  await p.setInt(key, i);
  accentSeedNotifier.value = AppAccent.seedForIndex(i);
}
