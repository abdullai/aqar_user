// lib/screens/password_setup.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aqar_user/main.dart'; // themeModeNotifier + langNotifier
import '../services/connectivity_guard.dart';

class PasswordSetupScreen extends StatefulWidget {
  const PasswordSetupScreen({super.key});

  @override
  State<PasswordSetupScreen> createState() => _PasswordSetupScreenState();
}

class _PasswordSetupScreenState extends State<PasswordSetupScreen> {
  static const Color _bankColor = Color(0xFF0F766E);

  final _nidCtrl = TextEditingController();
  final _nidFocus = FocusNode();

  final _emailCtrl = TextEditingController();
  final _emailFocus = FocusNode();

  final _phoneCtrl = TextEditingController();
  final _phoneFocus = FocusNode();

  final _nameCtrl = TextEditingController();
  final _nameFocus = FocusNode();

  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  final _p1Focus = FocusNode();
  final _p2Focus = FocusNode();

  bool _busy = false;
  bool _offline = false;
  bool _retryingNet = false;
  String? _err;
  String? _ok;

  bool _obscure1 = true;
  bool _obscure2 = true;

  bool get _isAr => langNotifier.value != 'en';
  ThemeMode get _currentTheme => themeModeNotifier.value;
  bool get _isLight => _currentTheme == ThemeMode.light;

  Color get _pageBg =>
      _isLight ? const Color(0xFFF5F7FA) : const Color(0xFF0E0F13);
  Color get _textPrimary => _isLight ? const Color(0xFF0B1220) : Colors.white;
  Color get _textSecondary =>
      _isLight ? const Color(0xFF5B6475) : const Color(0xFFB8C0D4);
  Color get _fieldFill => _isLight ? Colors.white : const Color(0xFF0F1425);
  Color get _fieldBorder =>
      _isLight ? const Color(0xFFE5E7EB) : const Color(0xFF2A355A);
  Color get _hintColor =>
      _isLight ? const Color(0xFF64748B) : const Color(0xFFCBD5E1);
  Color get _iconColor =>
      _isLight ? const Color(0xFF64748B) : const Color(0xFFCBD5E1);

  @override
  void initState() {
    super.initState();

    _prefillFromAuth();
    _prefillFromPendingProfile();

    _nidCtrl.addListener(() {
      final normalized = _normalizeDigits(_nidCtrl.text);
      if (_nidCtrl.text != normalized) {
        _nidCtrl.text = normalized;
        _nidCtrl.selection = TextSelection.collapsed(offset: normalized.length);
      }
    });

    _phoneCtrl.addListener(() {
      // ✅ إصلاح: ضمان أن + في البداية دائمًا، وليس النهاية
      final normalized = _normalizePhone(_phoneCtrl.text);
      if (_phoneCtrl.text != normalized) {
        _phoneCtrl.text = normalized;
        _phoneCtrl.selection =
            TextSelection.collapsed(offset: normalized.length);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nidFocus.requestFocus();
    });
  }

  Future<void> _prefillFromAuth() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final meta = user.userMetadata ?? {};
    final email = (meta['email'] is String) ? (meta['email'] as String) : null;
    final phone = (meta['phone'] is String) ? (meta['phone'] as String) : null;
    final fullName =
        (meta['full_name'] is String) ? (meta['full_name'] as String) : null;
    final username =
        (meta['username'] is String) ? (meta['username'] as String) : null;

    if (_emailCtrl.text.trim().isEmpty && email != null && email.isNotEmpty) {
      _emailCtrl.text = email;
    }
    if (_phoneCtrl.text.trim().isEmpty && phone != null && phone.isNotEmpty) {
      _phoneCtrl.text = _normalizePhone(phone);
    }
    if (_nameCtrl.text.trim().isEmpty &&
        fullName != null &&
        fullName.isNotEmpty) {
      _nameCtrl.text = fullName;
    }
    if (_nidCtrl.text.trim().isEmpty &&
        username != null &&
        username.isNotEmpty) {
      _nidCtrl.text = _normalizeDigits(username);
    }
  }

  Future<void> _prefillFromPendingProfile() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final ready = sp.getBool('pending_profile_ready') ?? false;
      if (!ready) return;

      // نملأ الحقول إن كانت فاضية فقط
      final pUsername = sp.getString('pending_p_username');
      final pEmail = sp.getString('pending_p_email');
      final pPhone = sp.getString('pending_p_phone');

      final pFullAr = sp.getString('pending_p_full_name_ar');
      final pFullEn = sp.getString('pending_p_full_name_en');

      if (_nidCtrl.text.trim().isEmpty && (pUsername ?? '').isNotEmpty) {
        _nidCtrl.text = _normalizeDigits(pUsername!);
      }
      if (_emailCtrl.text.trim().isEmpty && (pEmail ?? '').isNotEmpty) {
        _emailCtrl.text = (pEmail ?? '').trim().toLowerCase();
      }
      if (_phoneCtrl.text.trim().isEmpty && (pPhone ?? '').isNotEmpty) {
        _phoneCtrl.text = _normalizePhone(pPhone!);
      }
      if (_nameCtrl.text.trim().isEmpty) {
        final name = _isAr ? (pFullAr ?? '') : (pFullEn ?? '');
        if (name.trim().isNotEmpty) _nameCtrl.text = name.trim();
      }
    } catch (_) {
      // ignore
    }
  }

  @override
  void dispose() {
    _nidCtrl.dispose();
    _nidFocus.dispose();

    _emailCtrl.dispose();
    _emailFocus.dispose();

    _phoneCtrl.dispose();
    _phoneFocus.dispose();

    _nameCtrl.dispose();
    _nameFocus.dispose();

    _p1.dispose();
    _p2.dispose();
    _p1Focus.dispose();
    _p2Focus.dispose();

    super.dispose();
  }

  // =========================
  // Internet guard
  // =========================

  Future<bool> _hasInternet() async {
    try {
      return await ConnectivityGuard.hasInternet();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _ensureInternetOrShow() async {
    final ok = await _hasInternet();
    if (!mounted) return false;
    if (!ok) {
      setState(() => _offline = true);
      _toast(_isAr ? 'لا يوجد اتصال بالإنترنت.' : 'No internet connection.');
      return false;
    }
    if (_offline) setState(() => _offline = false);
    return true;
  }

  Future<void> _retryInternet() async {
    if (_retryingNet) return;
    setState(() => _retryingNet = true);
    final ok = await _hasInternet();
    if (!mounted) return;
    setState(() {
      _offline = !ok;
      _retryingNet = false;
    });
  }

  // =========================
  // Helpers
  // =========================

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _normalizeDigits(String input) {
    const arabic = {
      '٠': '0',
      '١': '1',
      '٢': '2',
      '٣': '3',
      '٤': '4',
      '٥': '5',
      '٦': '6',
      '٧': '7',
      '٨': '8',
      '٩': '9'
    };
    const indic = {
      '۰': '0',
      '۱': '1',
      '۲': '2',
      '۳': '3',
      '۴': '4',
      '۵': '5',
      '۶': '6',
      '۷': '7',
      '۸': '8',
      '۹': '9'
    };

    final b = StringBuffer();
    for (final ch in input.characters) {
      if (arabic.containsKey(ch)) {
        b.write(arabic[ch]);
      } else if (indic.containsKey(ch)) {
        b.write(indic[ch]);
      } else {
        b.write(ch);
      }
    }
    return b.toString();
  }

  String _normalizePhone(String input) {
    var s = input.trim();
    s = _normalizeDigits(s);

    // أبقِ '+' فقط في البداية إن وجد، وأزل أي '+' أخرى/رموز
    s = s.replaceAll(RegExp(r'[^\d\+]'), '');
    s = s.replaceAll('+', ''); // نزيلها مؤقتًا
    s = s.replaceAll(RegExp(r'[^\d]'), '');

    // صيغ سعودية شائعة
    if (s.startsWith('05') && s.length == 10) {
      // 05xxxxxxxx -> +9665xxxxxxxx
      s = '966${s.substring(1)}';
    } else if (RegExp(r'^5\d{8}$').hasMatch(s)) {
      // 5xxxxxxxx -> +9665xxxxxxxx
      s = '966$s';
    } else if (s.startsWith('966') && s.length == 12) {
      // 9665xxxxxxxx -> +9665xxxxxxxx
      // ok
    } else if (s.startsWith('00966') && s.length == 14) {
      // 009665xxxxxxxx -> +9665xxxxxxxx
      s = s.substring(2);
    }

    // أضف + في البداية فقط
    if (s.isEmpty) return '';
    if (s.startsWith('966')) return '+$s';
    // إن كتب المستخدم شيء غريب، رجّعه كأرقام فقط (بدون إضافة + خاطئة)
    return s;
  }

  bool _isValidNationalId(String s) => RegExp(r'^\d{10}$').hasMatch(s);
  bool _isValidEmail(String s) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s.trim());
  bool _isValidPhoneE164Saudi(String s) =>
      RegExp(r'^\+9665\d{8}$').hasMatch(s.trim());

  List<String> _nameTokens(String fullName) {
    final cleaned = fullName
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[^\p{L}\s\-]', unicode: true), '')
        .trim();
    if (cleaned.isEmpty) return [];
    final raw = cleaned.split(' ').where((e) => e.trim().isNotEmpty).toList();

    if (_isAr) return raw;

    final banned = <String>{'bin', 'ibn', 'bint'};
    return raw.where((t) => !banned.contains(t.toLowerCase())).toList();
  }

  Map<String, String?> _splitNameToParts(String fullName) {
    final t = _nameTokens(fullName);

    if (!_isAr && t.length < 4) {
      throw 'English full name must be 4 parts (first/second/third/fourth).';
    }
    if (_isAr && t.length < 3) {
      throw 'أدخل الاسم الثلاثي على الأقل (ويُفضّل الرباعي).';
    }

    String pick(int i) => (i >= 0 && i < t.length) ? t[i] : '';

    final first = pick(0);
    final second = pick(1);
    final third = pick(2);
    final fourth = pick(3);

    final four =
        [first, second, third, fourth].where((e) => e.isNotEmpty).toList();
    final full4 = four.join(' ');

    return {
      'first': first.isEmpty ? null : first,
      'second': second.isEmpty ? null : second,
      'third': third.isEmpty ? null : third,
      'fourth': fourth.isEmpty ? null : fourth,
      'full4': full4.isEmpty ? null : full4,
      'fullRaw': fullName.trim().replaceAll(RegExp(r'\s+'), ' '),
    };
  }

  Future<String> _loadLocale() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final savedLang = sp.getString('language');
      if (savedLang == 'en') return 'en';
      return 'ar';
    } catch (_) {
      return _isAr ? 'ar' : 'en';
    }
  }

  Future<bool> _usernameExists(String username) async {
    final sb = Supabase.instance.client;
    final res = await sb
        .from('users_profiles')
        .select('user_id')
        .eq('username', username)
        .limit(1);
    return (res.isNotEmpty);
  }

  Future<bool> _phoneExists(String phone) async {
    final sb = Supabase.instance.client;
    final res = await sb
        .from('users_profiles')
        .select('user_id')
        .eq('phone', phone)
        .limit(1);
    return (res.isNotEmpty);
  }

  Future<void> _savePendingProfile(Map<String, dynamic> data) async {
    try {
      final sp = await SharedPreferences.getInstance();

      // نحفظها بمفاتيح واضحة
      await sp.setString(
          'pending_p_username', (data['p_username'] ?? '').toString());
      await sp.setString('pending_p_email', (data['p_email'] ?? '').toString());
      await sp.setString('pending_p_phone', (data['p_phone'] ?? '').toString());

      await sp.setString(
          'pending_p_full_name_ar', (data['p_full_name_ar'] ?? '').toString());
      await sp.setString('pending_p_first_name_ar',
          (data['p_first_name_ar'] ?? '').toString());
      await sp.setString('pending_p_second_name_ar',
          (data['p_second_name_ar'] ?? '').toString());
      await sp.setString('pending_p_third_name_ar',
          (data['p_third_name_ar'] ?? '').toString());
      await sp.setString('pending_p_fourth_name_ar',
          (data['p_fourth_name_ar'] ?? '').toString());

      await sp.setString(
          'pending_p_full_name_en', (data['p_full_name_en'] ?? '').toString());
      await sp.setString('pending_p_first_name_en',
          (data['p_first_name_en'] ?? '').toString());
      await sp.setString('pending_p_second_name_en',
          (data['p_second_name_en'] ?? '').toString());
      await sp.setString('pending_p_third_name_en',
          (data['p_third_name_en'] ?? '').toString());
      await sp.setString('pending_p_fourth_name_en',
          (data['p_fourth_name_en'] ?? '').toString());

      await sp.setString(
          'pending_p_locale', (data['p_locale'] ?? 'ar').toString());
      await sp.setBool('pending_profile_ready', true);
    } catch (_) {}
  }

  Future<void> _clearPendingProfile() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final keys = sp.getKeys().where((k) => k.startsWith('pending_')).toList();
      for (final k in keys) {
        await sp.remove(k);
      }
    } catch (_) {}
  }

  // =========================
  // Submit
  // =========================

  Future<void> _createAccount() async {
    if (!await _ensureInternetOrShow()) return;

    setState(() {
      _busy = true;
      _err = null;
      _ok = null;
    });

    final nid = _normalizeDigits(_nidCtrl.text).trim();
    final email = _emailCtrl.text.trim().toLowerCase();
    final phone = _normalizePhone(_phoneCtrl.text).trim();
    final name = _nameCtrl.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final p1 = _p1.text.trim();
    final p2 = _p2.text.trim();

    // تحقق مفصل
    if (!_isValidNationalId(nid)) {
      setState(() {
        _busy = false;
        _err = _isAr
            ? 'أدخل رقم الهوية/الإقامة الصحيح (10 أرقام).'
            : 'Enter a valid ID/Iqama (10 digits).';
      });
      _nidFocus.requestFocus();
      return;
    }

    if (!_isValidEmail(email)) {
      setState(() {
        _busy = false;
        _err =
            _isAr ? 'أدخل بريدًا إلكترونيًا صحيحًا.' : 'Enter a valid email.';
      });
      _emailFocus.requestFocus();
      return;
    }

    if (!_isValidPhoneE164Saudi(phone)) {
      setState(() {
        _busy = false;
        _err = _isAr
            ? 'أدخل رقم جوال سعودي بصيغة صحيحة مثل: +9665XXXXXXXX أو 05XXXXXXXX.'
            : 'Enter a Saudi phone number like +9665XXXXXXXX (or 05XXXXXXXX).';
      });
      _phoneFocus.requestFocus();
      return;
    }

    if (name.isEmpty) {
      setState(() {
        _busy = false;
        _err = _isAr ? 'الاسم الكامل مطلوب.' : 'Full name is required.';
      });
      _nameFocus.requestFocus();
      return;
    }

    if (p1.isEmpty || p2.isEmpty) {
      setState(() {
        _busy = false;
        _err =
            _isAr ? 'الرجاء إدخال كلمة المرور مرتين.' : 'Enter password twice.';
      });
      _p1Focus.requestFocus();
      return;
    }

    if (p1 != p2) {
      setState(() {
        _busy = false;
        _err =
            _isAr ? 'كلمتا المرور غير متطابقتين.' : 'Passwords do not match.';
      });
      _p2Focus.requestFocus();
      return;
    }

    if (p1.length < 8) {
      setState(() {
        _busy = false;
        _err = _isAr
            ? 'كلمة المرور يجب أن تتكون من 8 أحرف على الأقل.'
            : 'Password must be at least 8 characters long.';
      });
      _p1Focus.requestFocus();
      return;
    }

    Map<String, String?> parts;
    try {
      parts = _splitNameToParts(name);
    } catch (e) {
      setState(() {
        _busy = false;
        _err = e.toString();
      });
      _nameFocus.requestFocus();
      return;
    }

    try {
      final username = nid; // username = رقم الهوية/الإقامة
      final sb = Supabase.instance.client;

      if (await _usernameExists(username)) {
        setState(() {
          _busy = false;
          _err = _isAr
              ? 'هذه الهوية/الإقامة مسجلة مسبقًا.'
              : 'This ID/Iqama is already registered.';
        });
        return;
      }

      if (await _phoneExists(phone)) {
        setState(() {
          _busy = false;
          _err = _isAr
              ? 'رقم الجوال مسجل مسبقًا.'
              : 'This phone number is already registered.';
        });
        return;
      }

      final locale = await _loadLocale();

      // تجهيز بارامترات البروفايل (مطابقة لدالة upsert_my_profile)
      final profileParams = <String, dynamic>{
        'p_username': username,
        'p_email': email,
        'p_phone': phone,
        'p_full_name_ar': null,
        'p_first_name_ar': null,
        'p_second_name_ar': null,
        'p_third_name_ar': null,
        'p_fourth_name_ar': null,
        'p_full_name_en': null,
        'p_first_name_en': null,
        'p_second_name_en': null,
        'p_third_name_en': null,
        'p_fourth_name_en': null,
        'p_locale': locale,
      };

      if (_isAr) {
        profileParams.addAll({
          'p_full_name_ar': parts['full4'] ?? parts['fullRaw'] ?? name,
          'p_first_name_ar': parts['first'],
          'p_second_name_ar': parts['second'],
          'p_third_name_ar': parts['third'],
          'p_fourth_name_ar': parts['fourth'],
        });
      } else {
        profileParams.addAll({
          'p_full_name_en': parts['full4'] ?? parts['fullRaw'] ?? name,
          'p_first_name_en': parts['first'],
          'p_second_name_en': parts['second'],
          'p_third_name_en': parts['third'],
          'p_fourth_name_en': parts['fourth'],
        });
      }

      // ✅ أهم نقطة لحل مشكلة "لا يعمل إلا بعد استعادة كلمة المرور":
      // لا تنفذ أي شيء يعتمد على session (مثل RPC يعتمد auth.uid())
      // إلا إذا session موجودة. وإلا خزّن محليًا فقط.
      final signUpRes = await sb.auth.signUp(
        email: email,
        password: p1,
        data: {
          'username': username,
          'phone': phone,
          'locale': locale,
          'full_name': parts['fullRaw'] ?? name,
        },
      );

      final user = signUpRes.user;
      if (user == null) {
        setState(() {
          _busy = false;
          _err = _isAr
              ? 'فشل إنشاء الحساب. تحقق من إعدادات تأكيد البريد.'
              : 'Sign up failed. Check email confirmation settings.';
        });
        return;
      }

      if (kDebugMode) {
        // ignore: avoid_print
        print('SIGNUP user id: ${user.id}');
        // ignore: avoid_print
        print('SIGNUP session: ${signUpRes.session != null}');
      }

      if (signUpRes.session != null) {
        // يوجد session => نرفع البروفايل الآن
        if (!await _ensureInternetOrShow()) {
          // لو انقطع النت بعد التسجيل مباشرة
          await _savePendingProfile(profileParams);
        } else {
          await sb.rpc('upsert_my_profile', params: profileParams);
          await _clearPendingProfile();
        }
      } else {
        // لا يوجد session (البريد غير مؤكد) => خزّن البروفايل محليًا
        await _savePendingProfile(profileParams);
      }

      if (!mounted) return;
      setState(() {
        _busy = false;
        _ok = signUpRes.session != null
            ? (_isAr
                ? 'تم إنشاء الحساب وحفظ البيانات.'
                : 'Account created and profile saved.')
            : (_isAr
                ? 'تم إنشاء الحساب. يرجى تأكيد البريد ثم تسجيل الدخول، وسيتم رفع بياناتك تلقائيًا.'
                : 'Account created. Please confirm email then login; your profile will be uploaded automatically.');
      });

      // خروج احتياطي
      await Future.delayed(const Duration(milliseconds: 400));
      try {
        await sb.auth.signOut();
      } catch (_) {}

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false);
    } on AuthException catch (e) {
      setState(() {
        _busy = false;
        _err = _isAr
            ? 'خطأ في إنشاء الحساب: ${e.message}'
            : 'Sign up error: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _err = _isAr ? 'حدث خطأ غير متوقع: $e' : 'Unexpected error: $e';
      });
    }
  }

  // =========================
  // UI helpers
  // =========================

  double _hintFontSize(BuildContext context) {
    // تصغير/تكبير حسب العرض مع حد أعلى لمنع التفاف النص
    final w = MediaQuery.of(context).size.width;
    final base = 14.0;
    final f = (w / 390.0);
    final size = base * f;
    return size.clamp(11.0, 14.0);
  }

  InputDecoration _dec(
    BuildContext context, {
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    final hintSize = _hintFontSize(context);
    return InputDecoration(
      hintText: hint,
      hintMaxLines: 1,
      hintStyle: TextStyle(
        color: _hintColor,
        fontWeight: FontWeight.w800,
        fontSize: hintSize,
        overflow: TextOverflow.ellipsis, // ✅ لا التفاف
      ),
      prefixIcon: Icon(icon, color: _iconColor, size: 22),
      suffixIcon: suffix,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _fieldBorder, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _bankColor, width: 2.0),
      ),
      fillColor: _fieldFill,
      filled: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  Widget _offlineOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.6),
        alignment: Alignment.center,
        child: Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off_rounded, size: 48),
                const SizedBox(height: 8),
                Text(_isAr ? 'لا يوجد إنترنت' : 'No internet'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _retryingNet ? null : _retryInternet,
                  child: _retryingNet
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isAr ? 'إعادة المحاولة' : 'Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _messageBox({required String text, required bool isError}) {
    final bgColor = isError ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4);
    final borderColor =
        isError ? const Color(0xFFFECACA) : const Color(0xFFBBF7D0);
    final textColor =
        isError ? const Color(0xFF991B1B) : const Color(0xFF166534);
    final iconColor =
        isError ? const Color(0xFFDC2626) : const Color(0xFF16A34A);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
            color: iconColor,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0F1425),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isLight ? const Color(0xFFE2E8F0) : const Color(0xFF2A355A),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _bankColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.person_add_alt_1_rounded,
                color: _bankColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isAr ? 'تسجيل حساب' : 'Sign up',
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _isAr ? 'بيانات إلزامية' : 'Required information',
                  style: TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required double maxWidth, required bool allowScroll}) {
    final cardColor = _isLight
        ? Colors.white.withOpacity(0.98)
        : const Color(0xFF171A22).withOpacity(0.98);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(),
        const SizedBox(height: 16),
        Text(
          _isAr ? 'إنشاء حساب جديد' : 'Create a new account',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: _textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _isAr
              ? 'أدخل بياناتك لتسجيل حسابك وربط البريد مع رقم الهوية/الإقامة والجوال.'
              : 'Enter your details to link email with your ID/Iqama and phone.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: _textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 18),
        _fieldNationalId(),
        const SizedBox(height: 12),
        _fieldEmail(),
        const SizedBox(height: 12),
        _fieldPhone(),
        const SizedBox(height: 12),
        _fieldFullName(),
        const SizedBox(height: 12),
        _fieldPassword1(),
        const SizedBox(height: 12),
        _fieldPassword2(),
        const SizedBox(height: 14),
        if (_err != null) _messageBox(text: _err!, isError: true),
        if (_ok != null) _messageBox(text: _ok!, isError: false),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _bankColor,
              foregroundColor: Colors.white,
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: (_busy || _offline) ? null : _createAccount,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _busy
                  ? Row(
                      key: const ValueKey('busy'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _isAr ? 'جاري الإنشاء...' : 'Creating...',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      _isAr ? 'إنشاء الحساب' : 'Create account',
                      key: const ValueKey('text'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: _isAr ? Alignment.centerRight : Alignment.centerLeft,
          child: TextButton(
            onPressed: (_busy || _offline)
                ? null
                : () => Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/',
                      (r) => false,
                    ),
            child: Text(
              _isAr ? 'لدي حساب بالفعل' : 'I already have an account',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: _bankColor,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );

    final child = Padding(
      padding: const EdgeInsets.all(20),
      child: allowScroll
          ? SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: content,
            )
          : content,
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Card(
        elevation: 8,
        shadowColor: Colors.black.withOpacity(0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        color: cardColor,
        child: child,
      ),
    );
  }

  Widget _fieldNationalId() {
    return TextField(
      controller: _nidCtrl,
      focusNode: _nidFocus,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(10),
      ],
      maxLength: 10,
      textInputAction: TextInputAction.next,
      onSubmitted: (_) => _emailFocus.requestFocus(),
      style: TextStyle(
        color: _textPrimary,
        fontWeight: FontWeight.w900,
        fontSize: 15,
      ),
      decoration: _dec(
        context,
        hint: _isAr ? 'رقم الهوية/الإقامة (10 أرقام)' : 'ID/Iqama (10 digits)',
        icon: Icons.badge_outlined,
      ).copyWith(counterText: ''),
    );
  }

  Widget _fieldEmail() {
    return TextField(
      controller: _emailCtrl,
      focusNode: _emailFocus,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      onSubmitted: (_) => _phoneFocus.requestFocus(),
      style: TextStyle(
        color: _textPrimary,
        fontWeight: FontWeight.w900,
        fontSize: 15,
      ),
      decoration: _dec(
        context,
        hint: _isAr ? 'البريد الإلكتروني' : 'Email address',
        icon: Icons.email_outlined,
      ),
    );
  }

  Widget _fieldPhone() {
    return TextField(
      controller: _phoneCtrl,
      focusNode: _phoneFocus,
      keyboardType: TextInputType.phone,
      inputFormatters: [LengthLimitingTextInputFormatter(16)],
      textInputAction: TextInputAction.next,
      onSubmitted: (_) => _nameFocus.requestFocus(),
      style: TextStyle(
        color: _textPrimary,
        fontWeight: FontWeight.w900,
        fontSize: 15,
      ),
      decoration: _dec(
        context,
        hint:
            _isAr ? 'رقم الجوال (مثال 05xxxxxxxx)' : 'Phone (e.g. 05xxxxxxxx)',
        icon: Icons.phone_outlined,
      ),
    );
  }

  Widget _fieldFullName() {
    return TextField(
      controller: _nameCtrl,
      focusNode: _nameFocus,
      keyboardType: TextInputType.name,
      textInputAction: TextInputAction.next,
      onSubmitted: (_) => _p1Focus.requestFocus(),
      style: TextStyle(
        color: _textPrimary,
        fontWeight: FontWeight.w900,
        fontSize: 15,
      ),
      decoration: _dec(
        context,
        hint: _isAr
            ? 'الاسم الكامل (رباعي يُفضّل)'
            : 'Full name (4 parts required)',
        icon: Icons.person_outline,
      ),
    );
  }

  Widget _fieldPassword1() {
    return TextField(
      controller: _p1,
      focusNode: _p1Focus,
      obscureText: _obscure1,
      enableSuggestions: false,
      autocorrect: false,
      textInputAction: TextInputAction.next,
      onSubmitted: (_) => _p2Focus.requestFocus(),
      style: TextStyle(
        color: _textPrimary,
        fontWeight: FontWeight.w900,
        fontSize: 15,
      ),
      decoration: _dec(
        context,
        hint: _isAr ? 'كلمة المرور (8 أحرف+)' : 'Password (8+ chars)',
        icon: Icons.lock_outline,
        suffix: IconButton(
          onPressed: () => setState(() => _obscure1 = !_obscure1),
          icon: Icon(
            _obscure1 ? Icons.visibility : Icons.visibility_off,
            color: _iconColor,
            size: 22,
          ),
          tooltip: _obscure1
              ? (_isAr ? 'إظهار' : 'Show')
              : (_isAr ? 'إخفاء' : 'Hide'),
        ),
      ),
    );
  }

  Widget _fieldPassword2() {
    return TextField(
      controller: _p2,
      focusNode: _p2Focus,
      obscureText: _obscure2,
      enableSuggestions: false,
      autocorrect: false,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _createAccount(),
      style: TextStyle(
        color: _textPrimary,
        fontWeight: FontWeight.w900,
        fontSize: 15,
      ),
      decoration: _dec(
        context,
        hint: _isAr ? 'تأكيد كلمة المرور' : 'Confirm password',
        icon: Icons.lock_outline,
        suffix: IconButton(
          onPressed: () => setState(() => _obscure2 = !_obscure2),
          icon: Icon(
            _obscure2 ? Icons.visibility : Icons.visibility_off,
            color: _iconColor,
            size: 22,
          ),
          tooltip: _obscure2
              ? (_isAr ? 'إظهار' : 'Show')
              : (_isAr ? 'إخفاء' : 'Hide'),
        ),
      ),
    );
  }

  // =========================
  // UI
  // =========================

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeModeNotifier,
        builder: (context, _, __) {
          return Scaffold(
            backgroundColor: _pageBg,
            body: SafeArea(
              child: Stack(
                children: [
                  LayoutBuilder(
                    builder: (context, c) {
                      final w = c.maxWidth;
                      final h = c.maxHeight;
                      final allowScroll = h < 820;
                      final maxWidth = (w >= 780) ? 620.0 : 640.0;

                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: _card(
                            maxWidth: maxWidth,
                            allowScroll: allowScroll,
                          ),
                        ),
                      );
                    },
                  ),
                  if (_offline) _offlineOverlay(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
