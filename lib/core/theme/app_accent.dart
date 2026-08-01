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

/// هل حفظ المستخدم لوناً مخصّصاً لحسابه؟
Future<bool> userHasCustomAccent({String? userId}) async {
  String? uid = userId;
  try {
    uid ??= Supabase.instance.client.auth.currentUser?.id;
  } catch (_) {}
  final u = (uid ?? '').trim();
  if (u.isEmpty) return false;
  final p = await SharedPreferences.getInstance();
  return p.containsKey(_accentKeyForUser(u));
}

/// لوحة محدودة (5) لألوان التمييز — نفس البذور للوضعين الفاتح والداكن عبر AppTheme.
abstract final class AppAccent {
  static const int count = 5;

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

/// يحمّل لون التمييز للمستخدم الحالي فقط.
/// إن لم يخصص المستخدم لوناً → الافتراضي (لا وراثة من جهاز/حساب آخر).
Future<void> loadAppAccentFromPrefs({String? userId}) async {
  final p = await SharedPreferences.getInstance();
  String? uid = userId;
  try {
    uid ??= Supabase.instance.client.auth.currentUser?.id;
  } catch (_) {}
  final u = (uid ?? '').trim();

  if (u.isEmpty) {
    // ضيف / بلا جلسة: لون الجهاز أو الافتراضي.
    final id = (p.getInt(kPrefAccentId) ?? 0).clamp(0, AppAccent.count - 1);
    accentSeedNotifier.value = AppAccent.seedForIndex(id);
    return;
  }

  final key = _accentKeyForUser(u);
  if (!p.containsKey(key)) {
    // حساب بلا تخصيص → افتراضي المنصة (لا نسخ من جهاز مشترك).
    accentSeedNotifier.value = AppAccent.seeds[0];
    return;
  }
  final id = (p.getInt(key) ?? 0).clamp(0, AppAccent.count - 1);
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
  // حدّث مفتاح الجهاز فقط للضيف؛ المسجّل يبقى حسابه معزولاً.
  if ((uid ?? '').trim().isEmpty) {
    await p.setInt(kPrefAccentId, i);
  }
  accentSeedNotifier.value = AppAccent.seedForIndex(i);
}

/// فهرس اللون الحالي للمستخدم (أو 0 إن لم يُخصَّص).
Future<int> currentAppAccentIndex({String? userId}) async {
  final p = await SharedPreferences.getInstance();
  String? uid = userId;
  try {
    uid ??= Supabase.instance.client.auth.currentUser?.id;
  } catch (_) {}
  final u = (uid ?? '').trim();
  if (u.isEmpty) {
    return (p.getInt(kPrefAccentId) ?? 0).clamp(0, AppAccent.count - 1);
  }
  final key = _accentKeyForUser(u);
  if (!p.containsKey(key)) return 0;
  return (p.getInt(key) ?? 0).clamp(0, AppAccent.count - 1);
}
