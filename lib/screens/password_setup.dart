import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signature/signature.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:aqar_user/main.dart';
import 'package:aqar_user/widgets/app_logo_loading.dart';
import '../core/permissions/runtime_permission_helper.dart';
import '../core/input/email_domain_catalog.dart';
import '../l10n/app_localizations.dart';
import '../core/input/input_normalizers.dart';
import '../core/input/password_arabic_script_guard.dart';
import '../core/utils/signature_blue_ink.dart';
import '../core/config/app_config.dart';
import '../services/commercial_reg_service.dart';
import '../services/name_translation_service.dart';
import '../services/profile_compliance_service.dart';
import 'fal_license_web_verify_page.dart';

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

  final _name1Ctrl = TextEditingController();
  final _name2Ctrl = TextEditingController();
  final _name3Ctrl = TextEditingController();
  final _name4Ctrl = TextEditingController();
  final _name1Focus = FocusNode();
  final _name2Focus = FocusNode();
  final _name3Focus = FocusNode();
  final _name4Focus = FocusNode();

  late final SignatureController _signupSigCtrl;
  Uint8List? _pendingSignaturePng;
  bool _signupSigBusy = false;
  String? _signupSigErr;

  /// لوحة التوقيع معطّلة افتراضياً حتى لا يُلتقط التمرير العمودي كخطوط.
  bool _signupSigPadArmed = false;

  final _falLicenseCtrl = TextEditingController();
  final _falLicenseFocus = FocusNode();

  final _unifiedCrCtrl = TextEditingController();
  final _unifiedCrFocus = FocusNode();

  final _unifiedNatCtrl = TextEditingController();
  final _unifiedNatFocus = FocusNode();

  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  final _p1Focus = FocusNode();
  final _p2Focus = FocusNode();

  bool _busy = false;
  bool _verifyingFal = false;
  bool _commercialBusy = false;

  String? _err;
  String? _ok;

  bool _obscure1 = true;
  bool _obscure2 = true;

  String _accountType = 'individual_seller';

  bool _falVerified = false;
  String? _falOwnerName;
  DateTime? _falStartDate;
  DateTime? _falEndDate;
  String? _falStatus;

  Map<String, dynamic>? _commercialSnapshot;
  bool _commercialVerified = false;

  /// بريد مُعبأ من بيانات الهيئة/فال — إن بقي كما هو نخفي اقتراحات النطاق للحسابات المهنية.
  String? _emailFromRegulatorSnapshot;

  late final CommercialRegService _commercialSvc =
      CommercialRegService(Supabase.instance.client);

  bool get _isAr => langNotifier.value != 'en';

  DateTime? _lastPasswordArabicDialogAt;

  void _schedulePasswordArabicDialog() {
    final n = DateTime.now();
    if (_lastPasswordArabicDialogAt != null &&
        n.difference(_lastPasswordArabicDialogAt!) <
            const Duration(milliseconds: 900)) {
      return;
    }
    _lastPasswordArabicDialogAt = n;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showPasswordArabicNotAllowedDialog(context, isAr: _isAr);
    });
  }
  ThemeMode get _currentTheme => themeModeNotifier.value;
  bool get _isLight => _currentTheme == ThemeMode.light;

  bool get _isProfessionalAccount =>
      _accountType == 'marketer' ||
      _accountType == 'office' ||
      _accountType == 'company' ||
      _accountType == 'institution';

  /// مكتب / مؤسسة / شركة — يتطلب السجل التجاري الموحّد (استعلام وزارة التجارة).
  bool get _needsUnifiedCommercialReg =>
      _accountType == 'office' ||
      _accountType == 'institution' ||
      _accountType == 'company';

  bool get _showProfessionalDetails =>
      !_isProfessionalAccount ||
      (_falVerified &&
          (!_needsUnifiedCommercialReg || _commercialVerified));

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

    _signupSigCtrl = SignatureController(
      disabled: true,
      penStrokeWidth: 3,
      penColor: const Color.fromARGB(
        255,
        kSignatureInkR,
        kSignatureInkG,
        kSignatureInkB,
      ),
      exportBackgroundColor: Colors.white,
      exportPenColor: const Color.fromARGB(
        255,
        kSignatureInkR,
        kSignatureInkG,
        kSignatureInkB,
      ),
    );

    _prefillFromAuth();
    _prefillFromPendingProfile();

    _nidCtrl.addListener(() {
      final normalized = _normalizeDigits(_nidCtrl.text);
      if (_nidCtrl.text != normalized) {
        _nidCtrl.text = normalized;
        _nidCtrl.selection = TextSelection.collapsed(offset: normalized.length);
      }
    });

    _unifiedNatCtrl.addListener(() {
      final t = _unifiedNatCtrl.text;
      var n = normalizeUnifiedNationalInput(t);
      if (n.length > 10) n = n.substring(0, 10);
      if (t != n) {
        _unifiedNatCtrl.value = TextEditingValue(
          text: n,
          selection: TextSelection.collapsed(offset: n.length),
        );
      }
    });

    _phoneCtrl.addListener(() {
      final fixed = _normalizeSaudiPhoneForInput(_phoneCtrl.text);
      if (_phoneCtrl.text != fixed) {
        _phoneCtrl.text = fixed;
        _phoneCtrl.selection = TextSelection.collapsed(offset: fixed.length);
      }
    });

    _falLicenseCtrl.addListener(() {
      final normalized = _normalizeDigits(_falLicenseCtrl.text)
          .replaceAll(RegExp(r'[^0-9]'), '');

      if (_falLicenseCtrl.text != normalized) {
        _falLicenseCtrl.text = normalized;
        _falLicenseCtrl.selection =
            TextSelection.collapsed(offset: normalized.length);
      }

      if (_falVerified) {
        setState(() {
          _falVerified = false;
          _falOwnerName = null;
          _falStartDate = null;
          _falEndDate = null;
          _falStatus = null;
          _ok = null;
          _commercialVerified = false;
          _commercialSnapshot = null;
          _unifiedCrCtrl.clear();
          if (_isProfessionalAccount) {
            _clearQuadNameFields();
          }
        });
      }
    });

    _unifiedCrCtrl.addListener(() {
      final normalized = _normalizeDigits(_unifiedCrCtrl.text)
          .replaceAll(RegExp(r'[^0-9]'), '');
      if (_unifiedCrCtrl.text != normalized) {
        _unifiedCrCtrl.text = normalized;
        _unifiedCrCtrl.selection =
            TextSelection.collapsed(offset: normalized.length);
      }
      if (_commercialVerified) {
        setState(() {
          _commercialVerified = false;
          _commercialSnapshot = null;
          _ok = null;
        });
      }
    });

    _emailCtrl.addListener(_onEmailCtrlChangedForRegulatorSnapshot);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isProfessionalAccount) {
        _falLicenseFocus.requestFocus();
      } else {
        _nidFocus.requestFocus();
      }
    });
  }

  void _onEmailCtrlChangedForRegulatorSnapshot() {
    if (_emailCtrl.text.trim().isEmpty) {
      _emailFromRegulatorSnapshot = null;
    }
  }

  /// مكاتب/مسوّقين/شركات/مؤسسات: لا اقتراحات نطاق طالما البريد لم يُغيّر عن ما جاء من فال/الجهة.
  bool _blockEmailDomainAutocomplete() {
    if (!_isProfessionalAccount) return false;
    final snap = _emailFromRegulatorSnapshot;
    if (snap == null || snap.isEmpty) return false;
    return _emailCtrl.text.trim().toLowerCase() == snap.trim().toLowerCase();
  }

  @override
  void dispose() {
    _emailCtrl.removeListener(_onEmailCtrlChangedForRegulatorSnapshot);

    _nidCtrl.dispose();
    _nidFocus.dispose();

    _emailCtrl.dispose();
    _emailFocus.dispose();

    _phoneCtrl.dispose();
    _phoneFocus.dispose();

    _name1Ctrl.dispose();
    _name2Ctrl.dispose();
    _name3Ctrl.dispose();
    _name4Ctrl.dispose();
    _name1Focus.dispose();
    _name2Focus.dispose();
    _name3Focus.dispose();
    _name4Focus.dispose();

    _signupSigCtrl.dispose();

    _falLicenseCtrl.dispose();
    _falLicenseFocus.dispose();

    _unifiedCrCtrl.dispose();
    _unifiedCrFocus.dispose();
    _unifiedNatCtrl.dispose();
    _unifiedNatFocus.dispose();

    _p1.dispose();
    _p2.dispose();
    _p1Focus.dispose();
    _p2Focus.dispose();

    super.dispose();
  }

  void _clearQuadNameFields() {
    _name1Ctrl.clear();
    _name2Ctrl.clear();
    _name3Ctrl.clear();
    _name4Ctrl.clear();
  }

  void _clearAllFields() {
    _nidCtrl.clear();
    _emailCtrl.clear();
    _phoneCtrl.clear();
    _clearQuadNameFields();
    _falLicenseCtrl.clear();
    _unifiedCrCtrl.clear();
    _unifiedNatCtrl.clear();
    _p1.clear();
    _p2.clear();

    _accountType = 'individual_seller';

    _falVerified = false;
    _falOwnerName = null;
    _falStartDate = null;
    _falEndDate = null;
    _falStatus = null;
    _commercialVerified = false;
    _commercialSnapshot = null;

    _err = null;
    _ok = null;
    _emailFromRegulatorSnapshot = null;

    _signupSigCtrl.clear();
    _pendingSignaturePng = null;
    _signupSigErr = null;
    _signupSigPadArmed = false;
    _signupSigCtrl.disabled = true;
  }

  Future<void> _prefillFromAuth() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final meta = user.userMetadata ?? {};

    final email = meta['email']?.toString();
    final phone = meta['phone']?.toString();
    final fullName = meta['full_name']?.toString();
    final username = meta['username']?.toString();
    final accountType = meta['account_type']?.toString();
    final falLicense = meta['fal_license']?.toString();
    final falOwnerName = meta['fal_owner_name']?.toString();
    final falStatus = meta['fal_status']?.toString();
    final falStartDate = meta['fal_start_date']?.toString();
    final falEndDate = meta['fal_end_date']?.toString();

    if (_emailCtrl.text.trim().isEmpty && (email ?? '').isNotEmpty) {
      _emailCtrl.text = email!.trim();
    }

    if (_phoneCtrl.text.trim().isEmpty && (phone ?? '').isNotEmpty) {
      _phoneCtrl.text = _toLocal05(phone!) ?? '';
    }

    if (_allQuadNameFieldsEmpty() && (fullName ?? '').isNotEmpty) {
      _applyFullNameStringToFields(fullName!);
    }

    if (_nidCtrl.text.trim().isEmpty && (username ?? '').isNotEmpty) {
      _nidCtrl.text = _normalizeDigits(username!);
    }

    if ((accountType ?? '').isNotEmpty) {
      _accountType = accountType!;
    }

    if (_falLicenseCtrl.text.trim().isEmpty && (falLicense ?? '').isNotEmpty) {
      _falLicenseCtrl.text = _normalizeDigits(falLicense!);
    }

    _falOwnerName = (falOwnerName ?? '').trim().isEmpty ? null : falOwnerName;
    _falStatus = (falStatus ?? '').trim().isEmpty ? null : falStatus;

    if ((falStartDate ?? '').isNotEmpty) {
      _falStartDate = _parseLooseDate(falStartDate);
    }
    if ((falEndDate ?? '').isNotEmpty) {
      _falEndDate = _parseLooseDate(falEndDate);
    }

    if (_isProfessionalAccount &&
        _falLicenseCtrl.text.trim().isNotEmpty &&
        _falStartDate != null &&
        _falEndDate != null &&
        (_falStatus?.toLowerCase() == 'active' ||
            _falStatus == 'سارية' ||
            _falStatus == 'valid')) {
      _falVerified = true;
      if (_allQuadNameFieldsEmpty() &&
          (_falOwnerName ?? '').trim().isNotEmpty) {
        _applyFullNameStringToFields(_falOwnerName!);
      }
    }

    if (mounted) setState(() {});
  }

  Future<void> _prefillFromPendingProfile() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final ready = sp.getBool('pending_profile_ready') ?? false;
      if (!ready) return;

      final pUsername = sp.getString('pending_p_username');
      final pEmail = sp.getString('pending_p_email');
      final pPhone = sp.getString('pending_p_phone');
      final pFullAr = sp.getString('pending_p_full_name_ar');
      final pFullEn = sp.getString('pending_p_full_name_en');
      final pAccountType = sp.getString('pending_p_account_type');
      final pFalLicense = sp.getString('pending_p_fal_license');
      final pFalStartDate = sp.getString('pending_p_fal_start_date');
      final pFalEndDate = sp.getString('pending_p_fal_end_date');
      final pFalOwnerName = sp.getString('pending_p_fal_owner_name');
      final pFalStatus = sp.getString('pending_p_fal_status');

      if (_nidCtrl.text.trim().isEmpty && (pUsername ?? '').isNotEmpty) {
        _nidCtrl.text = _normalizeDigits(pUsername!);
      }
      if (_emailCtrl.text.trim().isEmpty && (pEmail ?? '').isNotEmpty) {
        _emailCtrl.text = pEmail!.trim().toLowerCase();
      }
      if (_phoneCtrl.text.trim().isEmpty && (pPhone ?? '').isNotEmpty) {
        _phoneCtrl.text = _toLocal05(pPhone!) ?? '';
      }

      if ((pAccountType ?? '').isNotEmpty) {
        _accountType = pAccountType!;
      }

      if (_falLicenseCtrl.text.trim().isEmpty &&
          (pFalLicense ?? '').isNotEmpty) {
        _falLicenseCtrl.text = pFalLicense!;
      }

      _falOwnerName = (pFalOwnerName ?? '').isEmpty ? null : pFalOwnerName;
      _falStatus = (pFalStatus ?? '').isEmpty ? null : pFalStatus;

      if ((pFalStartDate ?? '').isNotEmpty) {
        _falStartDate = _parseLooseDate(pFalStartDate);
      }
      if ((pFalEndDate ?? '').isNotEmpty) {
        _falEndDate = _parseLooseDate(pFalEndDate);
      }

      _falVerified = _isProfessionalAccount &&
          (_falLicenseCtrl.text.trim().isNotEmpty) &&
          _falStartDate != null &&
          _falEndDate != null &&
          (_falStatus?.toLowerCase() == 'active' ||
              _falStatus == 'سارية' ||
              _falStatus == 'valid');

      if (_allQuadNameFieldsEmpty()) {
        if (_isProfessionalAccount &&
            _falVerified &&
            (_falOwnerName ?? '').trim().isNotEmpty) {
          _applyFullNameStringToFields(_falOwnerName!);
        } else {
          final pk1 = _isAr
              ? sp.getString('pending_p_first_name_ar')
              : sp.getString('pending_p_first_name_en');
          final pk2 = _isAr
              ? sp.getString('pending_p_second_name_ar')
              : sp.getString('pending_p_second_name_en');
          final pk3 = _isAr
              ? sp.getString('pending_p_third_name_ar')
              : sp.getString('pending_p_third_name_en');
          final pk4 = _isAr
              ? sp.getString('pending_p_fourth_name_ar')
              : sp.getString('pending_p_fourth_name_en');
          if ((pk1 ?? '').trim().isNotEmpty ||
              (pk2 ?? '').trim().isNotEmpty ||
              (pk3 ?? '').trim().isNotEmpty ||
              (pk4 ?? '').trim().isNotEmpty) {
            _name1Ctrl.text = (pk1 ?? '').trim();
            _name2Ctrl.text = (pk2 ?? '').trim();
            _name3Ctrl.text = (pk3 ?? '').trim();
            _name4Ctrl.text = (pk4 ?? '').trim();
          } else {
            final name = _isAr ? (pFullAr ?? '') : (pFullEn ?? '');
            if (name.trim().isNotEmpty) {
              _applyFullNameStringToFields(name);
            }
          }
        }
      }

      if (mounted) setState(() {});
    } catch (_) {}
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
      '٩': '9',
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
      '۹': '9',
    };

    final b = StringBuffer();
    for (final ch in input.split('')) {
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

  DateTime? _parseLooseDate(String? input) {
    final s = (input ?? '').trim();
    if (s.isEmpty) return null;

    final direct = DateTime.tryParse(s);
    if (direct != null) return direct;

    final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(s);
    if (m != null) {
      final dd = int.tryParse(m.group(1)!);
      final mm = int.tryParse(m.group(2)!);
      final yyyy = int.tryParse(m.group(3)!);
      if (dd != null && mm != null && yyyy != null) {
        return DateTime(yyyy, mm, dd);
      }
    }

    return null;
  }

  bool _allQuadNameFieldsEmpty() {
    return _name1Ctrl.text.trim().isEmpty &&
        _name2Ctrl.text.trim().isEmpty &&
        _name3Ctrl.text.trim().isEmpty &&
        _name4Ctrl.text.trim().isEmpty;
  }

  void _applyFullNameStringToFields(String raw) {
    final trimmed = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty) return;
    final t = _nameTokens(trimmed);
    _name1Ctrl.text = t.isNotEmpty ? t[0] : '';
    _name2Ctrl.text = t.length > 1 ? t[1] : '';
    _name3Ctrl.text = t.length > 2 ? t[2] : '';
    _name4Ctrl.text = t.length > 3 ? t[3] : '';
  }

  Map<String, String?> _partsFromFourFields() {
    final n1 = _name1Ctrl.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final n2 = _name2Ctrl.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final n3 = _name3Ctrl.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final n4 = _name4Ctrl.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final four = <String>[];
    if (n1.isNotEmpty) four.add(n1);
    if (n2.isNotEmpty) four.add(n2);
    if (n3.isNotEmpty) four.add(n3);
    if (n4.isNotEmpty) four.add(n4);
    final full4 = four.join(' ');
    return {
      'first': n1.isEmpty ? null : n1,
      'second': n2.isEmpty ? null : n2,
      'third': n3.isEmpty ? null : n3,
      'fourth': n4.isEmpty ? null : n4,
      'full4': full4.isEmpty ? null : full4,
      'fullRaw': full4.isEmpty ? null : full4,
    };
  }

  List<String> _nameTokensEnglish(String fullName) {
    final cleaned = fullName
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[^\p{L}\s\-]', unicode: true), '')
        .trim();

    if (cleaned.isEmpty) return [];
    final raw = cleaned.split(' ').where((e) => e.trim().isNotEmpty).toList();

    final banned = <String>{'bin', 'ibn', 'bint'};
    return raw.where((t) => !banned.contains(t.toLowerCase())).toList();
  }

  Map<String, String?> _splitEnglishFullNameToParts(String fullName) {
    final t = _nameTokensEnglish(fullName);
    if (t.length < 4) {
      throw _isAr
          ? 'لم يُمكّن تقسيم الاسم الإنجليزي المترجم إلى أربعة أجزاء.'
          : 'Translated English name must split into 4 parts.';
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

  Map<String, String?> _fallbackEnglishNameParts(String fullEn) {
    final t = fullEn
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .split(' ')
        .where((e) => e.isNotEmpty)
        .toList();
    String at(int i) => i < t.length ? t[i] : '';
    final n1 = at(0);
    final n2 = at(1);
    final n3 = at(2);
    final n4 = at(3);
    final four = [n1, n2, n3, n4].where((e) => e.isNotEmpty).toList();
    return {
      'first': n1.isEmpty ? null : n1,
      'second': n2.isEmpty ? null : n2,
      'third': n3.isEmpty ? null : n3,
      'fourth': n4.isEmpty ? null : n4,
      'full4': four.isEmpty ? null : four.join(' '),
      'fullRaw': fullEn.trim().replaceAll(RegExp(r'\s+'), ' '),
    };
  }

  Future<void> _persistPendingSignupSignatureIfNeeded() async {
    final b = _pendingSignaturePng;
    if (b == null || b.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        ProfileComplianceService.kPrefPendingSignupSignatureB64,
        base64Encode(b),
      );
    } catch (_) {}
  }

  String _normalizeSaudiPhoneForInput(String input) {
    var s = _normalizeDigits(input).trim();
    s = s.replaceAll(RegExp(r'[^0-9]'), '');

    if (s.isEmpty) return '';

    if (RegExp(r'^5\d{8}$').hasMatch(s)) {
      s = '0$s';
    }

    if (s.startsWith('00966')) {
      s = s.substring(2);
    }
    if (s.startsWith('966')) {
      if (s.length == 12 && s.substring(3, 4) == '5') {
        s = '0${s.substring(3)}';
      }
    }

    if (s.length > 10) s = s.substring(0, 10);
    return s;
  }

  String? _toE164Saudi(String input) {
    final s = _normalizeDigits(input).trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (!RegExp(r'^05\d{8}$').hasMatch(s)) return null;
    return '+966${s.substring(1)}';
  }

  String? _toLocal05(String input) {
    var s = _normalizeDigits(input).trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (s.startsWith('00966')) s = s.substring(2);
    if (s.startsWith('966') && s.length == 12 && s.substring(3, 4) == '5') {
      return '0${s.substring(3)}';
    }
    if (RegExp(r'^05\d{8}$').hasMatch(s)) return s;
    if (RegExp(r'^5\d{8}$').hasMatch(s)) return '0$s';
    return null;
  }

  bool _isValidNationalId(String s) => RegExp(r'^\d{10}$').hasMatch(s);
  bool _isValidEmail(String s) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s.trim());
  bool _isValidPhoneLocal05(String s) =>
      RegExp(r'^05\d{8}$').hasMatch(s.trim());
  bool _isValidFalLicense(String s) => RegExp(r'^\d{10}$').hasMatch(s.trim());

  bool _isFalStillValid(DateTime? endDate) {
    if (endDate == null) return false;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endOnly = DateTime(endDate.year, endDate.month, endDate.day);

    return !endOnly.isBefore(today);
  }

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

  Future<String> _loadLocale() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final savedLang = sp.getString(AppConfig.prefLangKey);
      if (savedLang == 'en') return 'en';
      return 'ar';
    } catch (_) {
      return _isAr ? 'ar' : 'en';
    }
  }

  static bool _coerceRpcBool(dynamic raw) {
    if (raw is bool) return raw;
    final s = (raw ?? '').toString().toLowerCase();
    return s == 'true' || s == 't';
  }

  /// يتجاوز RLS عبر دوال SECURITY DEFINER على الخادم — انظر supabase/sql/20260416_signup_rls_safe_checks.sql
  /// يعيد `null` عند فشل الشبكة (مثلاً Safari / حظر طلبات) حتى لا نعرض خطأ تقني خام.
  Future<bool?> _usernameExists(String username) async {
    try {
      final raw = await Supabase.instance.client.rpc(
        'signup_username_taken',
        params: {'p_username': username},
      );
      return _coerceRpcBool(raw);
    } catch (_) {
      return null;
    }
  }

  Future<bool?> _phoneExistsE164(String phoneE164) async {
    try {
      final raw = await Supabase.instance.client.rpc(
        'signup_phone_taken',
        params: {'p_phone': phoneE164},
      );
      return _coerceRpcBool(raw);
    } catch (_) {
      return null;
    }
  }

  Future<bool?> _unifiedNationalTaken(String tenDigits) async {
    try {
      final raw = await Supabase.instance.client.rpc(
        'signup_unified_national_taken',
        params: {'p_digits': tenDigits},
      );
      return _coerceRpcBool(raw);
    } catch (_) {
      return null;
    }
  }

  /// نتيجة التحقق من WebView (أندرويد/آيفون/سطح المكتب) أو من Edge Function على الويب.
  void _applyFalVerificationMap(Map<String, dynamic> map) {
    final errDetail = map['_error_detail']?.toString().trim();
    final bool valid = map['valid'] == true;
    final String ownerName = (map['owner_name'] ?? '').toString().trim();
    final String status = (map['status'] ?? '').toString().trim();
    final String startStr = (map['start_date'] ?? '').toString().trim();
    final String endStr = (map['end_date'] ?? '').toString().trim();

    var startDate = _parseLooseDate(startStr);
    final endDate = _parseLooseDate(endStr);

    if (valid && startDate == null && endDate != null) {
      startDate = DateTime(endDate.year - 1, endDate.month, endDate.day);
    }

    if (!valid) {
      setState(() {
        _falVerified = false;
        _falOwnerName = ownerName.isEmpty ? null : ownerName;
        _falStartDate = startDate;
        _falEndDate = endDate;
        _falStatus = status.isEmpty ? null : status;
        if (errDetail != null && errDetail.isNotEmpty) {
          _err = _isAr
              ? 'رخصة فال: $errDetail'
              : 'FAL verification: $errDetail';
        } else {
          _err = _isAr
              ? 'رخصة فال غير صحيحة أو لم يتم العثور عليها.'
              : 'FAL license is invalid or not found.';
        }
      });
      return;
    }

    if (!_isFalStillValid(endDate)) {
      setState(() {
        _falVerified = false;
        _falOwnerName = ownerName.isEmpty ? null : ownerName;
        _falStartDate = startDate;
        _falEndDate = endDate;
        _falStatus = status.isEmpty ? 'expired' : status;
        _err = _isAr
            ? 'رخصة فال منتهية، لا يمكن إنشاء الحساب.'
            : 'FAL license is expired. Account creation is not allowed.';
      });
      return;
    }

    setState(() {
      _falVerified = true;
      _falOwnerName = ownerName.isEmpty ? null : ownerName;
      _falStartDate = startDate;
      _falEndDate = endDate;
      _falStatus = status.isEmpty ? 'active' : status;
      if ((_falOwnerName ?? '').trim().isNotEmpty) {
        _applyFullNameStringToFields(_falOwnerName!);
      }
      final be = (map['broker_email'] ?? '').toString().trim();
      final bm = (map['broker_mobile'] ?? '').toString().trim();
      if (be.isNotEmpty &&
          _emailCtrl.text.trim().isEmpty &&
          _isValidEmail(be)) {
        final em = be.toLowerCase();
        _emailCtrl.text = em;
        _emailFromRegulatorSnapshot = em;
      }
      if (bm.isNotEmpty && _phoneCtrl.text.trim().isEmpty) {
        final local = _toLocal05(bm) ?? _normalizeSaudiPhoneForInput(bm);
        if (local.isNotEmpty && _isValidPhoneLocal05(local)) {
          _phoneCtrl.text = local;
        }
      }
      final bnid = (map['broker_national_id'] ?? '')
          .toString()
          .replaceAll(RegExp(r'\D'), '')
          .trim();
      if (bnid.length == 10 &&
          _isValidNationalId(bnid) &&
          _nidCtrl.text.trim().isEmpty) {
        _nidCtrl.text = bnid;
      }
      _ok = _isAr
          ? 'تم التحقق من رخصة فال بنجاح. أكمل بقية البيانات.'
          : 'FAL license verified successfully. Complete the remaining fields.';
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_needsUnifiedCommercialReg) {
        _unifiedCrFocus.requestFocus();
      } else {
        _nidFocus.requestFocus();
      }
    });
  }

  Future<void> _runCommercialLookup() async {
    if (!_falVerified || !_needsUnifiedCommercialReg) return;
    final digits = _normalizeDigits(_unifiedCrCtrl.text)
        .replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 10) {
      setState(() {
        _err = _isAr
            ? 'الرقم الموحّد للسجل التجاري يجب أن يكون 10 أرقام.'
            : 'Unified commercial registration number must be 10 digits.';
      });
      _unifiedCrFocus.requestFocus();
      return;
    }

    setState(() {
      _commercialBusy = true;
      _err = null;
      _ok = null;
    });

    try {
      final res = await _commercialSvc.lookupUnified(digits);
      if (!mounted) return;
      setState(() => _commercialBusy = false);

      if (!res.ok) {
        setState(() {
          _commercialVerified = false;
          _commercialSnapshot = null;
          _err = res.error ??
              (_isAr
                  ? 'تعذر استعلام السجل التجاري.'
                  : 'Commercial registry lookup failed.');
        });
        return;
      }
      if (!res.validForActive) {
        setState(() {
          _commercialVerified = false;
          _commercialSnapshot = null;
          _err = _isAr
              ? 'السجل التجاري غير ساري (مثلاً مشطوب). لا يمكن المتابعة.'
              : 'Commercial registration is not active. You cannot continue.';
        });
        return;
      }

      _commercialSnapshot = {
        'entity_name_ar': res.entityNameAr,
        'registry_status_ar': res.registryStatusAr,
        'commercial_reg_no': res.commercialRegNo,
        'issue_date': res.issueDate,
        'activity_ar': res.activityAr,
        'capital': res.capital,
        'valid_for_active': true,
        'source': res.source,
      };

      final entity = (res.entityNameAr ?? '').trim();
      setState(() {
        _commercialVerified = true;
        if (entity.isNotEmpty) {
          _applyFullNameStringToFields(entity);
        }
        _ok = _isAr
            ? 'تم التحقق من السجل التجاري. أكمل رقم الهوية والبريد وكلمة المرور.'
            : 'Commercial registry verified. Complete ID, email, and password.';
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _nidFocus.requestFocus();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _commercialBusy = false;
        _commercialVerified = false;
        _err = _isAr
            ? 'فشل استعلام السجل التجاري: $e'
            : 'Commercial registry lookup failed: $e';
      });
    }
  }

  Future<void> _verifyFalLicense() async {
    final license = _normalizeDigits(_falLicenseCtrl.text)
        .trim()
        .replaceAll(RegExp(r'[^0-9]'), '');

    if (!_isValidFalLicense(license)) {
      setState(() {
        _err = _isAr
            ? 'رقم رخصة فال يجب أن يكون 10 أرقام.'
            : 'FAL license must be 10 digits.';
        _falVerified = false;
        _falOwnerName = null;
        _falStartDate = null;
        _falEndDate = null;
        _falStatus = null;
        _ok = null;
      });
      _falLicenseFocus.requestFocus();
      return;
    }

    setState(() {
      _verifyingFal = true;
      _err = null;
      _ok = null;
    });

    try {
      late final Map<String, dynamic> map;

      final result = await Navigator.push<Map<String, dynamic>?>(
        context,
        MaterialPageRoute(
          builder: (_) => FalLicenseWebVerifyPage(licenseNo: license),
        ),
      );

      if (result == null) {
        setState(() {
          _falVerified = false;
          _falOwnerName = null;
          _falStartDate = null;
          _falEndDate = null;
          _falStatus = null;
          _err = _isAr
              ? 'تم إغلاق صفحة التحقق قبل اكتمال العملية.'
              : 'Verification page was closed before completion.';
        });
        return;
      }

      map = Map<String, dynamic>.from(result);

      _applyFalVerificationMap(map);
    } catch (e) {
      setState(() {
        _falVerified = false;
        _falOwnerName = null;
        _falStartDate = null;
        _falEndDate = null;
        _falStatus = null;
        _err = _isAr
            ? 'فشل التحقق من رخصة فال: $e'
            : 'Failed to verify FAL license: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _verifyingFal = false);
      }
    }
  }

  Future<void> _savePendingProfile(Map<String, dynamic> data) async {
    try {
      final sp = await SharedPreferences.getInstance();

      await sp.setString(
          'pending_p_username', (data['p_username'] ?? '').toString());
      await sp.setString('pending_p_email', (data['p_email'] ?? '').toString());
      await sp.setString('pending_p_phone', (data['p_phone'] ?? '').toString());

      await sp.setString(
          'pending_p_full_name_ar', (data['p_full_name_ar'] ?? '').toString());
      await sp.setString(
          'pending_p_first_name_ar', (data['p_first_name_ar'] ?? '').toString());
      await sp.setString('pending_p_second_name_ar',
          (data['p_second_name_ar'] ?? '').toString());
      await sp.setString(
          'pending_p_third_name_ar', (data['p_third_name_ar'] ?? '').toString());
      await sp.setString('pending_p_fourth_name_ar',
          (data['p_fourth_name_ar'] ?? '').toString());

      await sp.setString(
          'pending_p_full_name_en', (data['p_full_name_en'] ?? '').toString());
      await sp.setString(
          'pending_p_first_name_en', (data['p_first_name_en'] ?? '').toString());
      await sp.setString('pending_p_second_name_en',
          (data['p_second_name_en'] ?? '').toString());
      await sp.setString(
          'pending_p_third_name_en', (data['p_third_name_en'] ?? '').toString());
      await sp.setString('pending_p_fourth_name_en',
          (data['p_fourth_name_en'] ?? '').toString());

      await sp.setString(
          'pending_p_locale', (data['p_locale'] ?? 'ar').toString());
      await sp.setString('pending_p_account_type',
          (data['account_type'] ?? 'individual_seller').toString());
      await sp.setString(
          'pending_p_fal_license', (data['fal_license'] ?? '').toString());
      await sp.setString('pending_p_fal_owner_name',
          (data['fal_owner_name'] ?? '').toString());
      await sp.setString(
          'pending_p_fal_status', (data['fal_status'] ?? '').toString());
      await sp.setString('pending_p_fal_start_date',
          (data['fal_start_date'] ?? '').toString());
      await sp.setString(
          'pending_p_fal_end_date', (data['fal_end_date'] ?? '').toString());

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
      await sp.remove('pending_profile_ready');
    } catch (_) {}
  }

  Future<void> _createAccount() async {
    setState(() {
      _busy = true;
      _err = null;
      _ok = null;
    });

    final nid = _normalizeDigits(_nidCtrl.text).trim();
    final email = _emailCtrl.text.trim().toLowerCase();
    final phoneLocal = _normalizeSaudiPhoneForInput(_phoneCtrl.text).trim();
    final phoneE164 = _toE164Saudi(phoneLocal);
    final falLicense = _normalizeDigits(_falLicenseCtrl.text)
        .trim()
        .replaceAll(RegExp(r'[^0-9]'), '');
    final p1 = _p1.text.trim();
    final p2 = _p2.text.trim();
    final unifiedNatDigits = normalizeUnifiedNationalInput(_unifiedNatCtrl.text);

    if (_isProfessionalAccount) {
      if (!_isValidFalLicense(falLicense)) {
        setState(() {
          _busy = false;
          _err = _isAr
              ? 'رخصة فال مطلوبة ويجب أن تكون 10 أرقام.'
              : 'FAL license is required and must be 10 digits.';
        });
        _falLicenseFocus.requestFocus();
        return;
      }

      if (!_falVerified ||
          _falStartDate == null ||
          _falEndDate == null ||
          !_isFalStillValid(_falEndDate)) {
        setState(() {
          _busy = false;
          _err = _isAr
              ? 'يجب التحقق من رخصة فال السارية قبل إنشاء الحساب.'
              : 'You must verify a valid FAL license before creating the account.';
        });
        _falLicenseFocus.requestFocus();
        return;
      }

      if (_needsUnifiedCommercialReg) {
        final u = _normalizeDigits(_unifiedCrCtrl.text)
            .replaceAll(RegExp(r'[^0-9]'), '');
        if (u.length != 10) {
          setState(() {
            _busy = false;
            _err = _isAr
                ? 'أدخل الرقم الموحّد للسجل التجاري (10 أرقام).'
                : 'Enter unified commercial registration number (10 digits).';
          });
          _unifiedCrFocus.requestFocus();
          return;
        }
        if (!_commercialVerified || _commercialSnapshot == null) {
          setState(() {
            _busy = false;
            _err = _isAr
                ? 'يجب الضغط على «استعلام السجل التجاري» والتأكد أن السجل ساري.'
                : 'Run commercial registry lookup and ensure the registry is active.';
          });
          _unifiedCrFocus.requestFocus();
          return;
        }
        if (_commercialSnapshot!['valid_for_active'] != true) {
          setState(() {
            _busy = false;
            _err = _isAr
                ? 'السجل التجاري غير ساري — لا يمكن إنشاء الحساب.'
                : 'Commercial registry is not active — cannot create account.';
          });
          return;
        }
      }

      if (!isValidUnifiedNationalNumberDigits(unifiedNatDigits)) {
        setState(() {
          _busy = false;
          _err = _isAr
              ? 'الرقم الوطني الموحّد مطلوب: 10 أرقام تبدأ بـ 700 (يمكن كتابة ن700…).'
              : 'Unified national no. required: 10 digits starting with 700.';
        });
        _unifiedNatFocus.requestFocus();
        return;
      }
    }

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

    if (emailContainsArabicScript(email)) {
      setState(() {
        _busy = false;
        _err = _isAr
            ? 'البريد الإلكتروني لا يقبل أحرفًا عربية.'
            : 'Email cannot contain Arabic characters.';
      });
      _emailFocus.requestFocus();
      return;
    }

    if (!_isValidEmail(email)) {
      setState(() {
        _busy = false;
        _err = _isAr ? 'أدخل بريدًا إلكترونيًا صحيحًا.' : 'Enter a valid email.';
      });
      _emailFocus.requestFocus();
      return;
    }

    final suggested = suggestEmailDomainFix(email);
    if (suggested != null && suggested != email) {
      setState(() {
        _busy = false;
        _err = _isAr
            ? 'هل تقصد: $suggested ؟ صحّح النطاق بعد @ ثم أعد المحاولة.'
            : 'Did you mean: $suggested ? Fix the domain after @ and try again.';
      });
      _emailFocus.requestFocus();
      return;
    }

    if (!_isValidPhoneLocal05(phoneLocal) || phoneE164 == null) {
      setState(() {
        _busy = false;
        _err = _isAr
            ? 'أدخل رقم جوال سعودي 10 أرقام يبدأ بـ 05.'
            : 'Enter a Saudi phone: 10 digits starting with 05.';
      });
      _phoneFocus.requestFocus();
      return;
    }

    final parts = _partsFromFourFields();
    final assembledName = (parts['full4'] ?? '').trim();
    if (_name1Ctrl.text.trim().isEmpty ||
        _name2Ctrl.text.trim().isEmpty ||
        _name3Ctrl.text.trim().isEmpty ||
        _name4Ctrl.text.trim().isEmpty ||
        assembledName.isEmpty) {
      setState(() {
        _busy = false;
        _err = _isAr
            ? 'أدخل الاسم الرباعي في الأربعة حقول (الأول، الثاني، الثالث، الأخير).'
            : 'Enter all four name parts.';
      });
      _name1Focus.requestFocus();
      return;
    }

    if (p1.isEmpty || p2.isEmpty) {
      setState(() {
        _busy = false;
        _err = _isAr ? 'الرجاء إدخال كلمة المرور مرتين.' : 'Enter password twice.';
      });
      _p1Focus.requestFocus();
      return;
    }

    if (p1 != p2) {
      setState(() {
        _busy = false;
        _err = _isAr ? 'كلمتا المرور غير متطابقتين.' : 'Passwords do not match.';
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

    if (_pendingSignaturePng == null || _pendingSignaturePng!.isEmpty) {
      setState(() {
        _busy = false;
        _err = _isAr
            ? 'أضف توقيعك: فعّل اللوحة ثم ارسم و«حفظ التوقيع»، أو ارفع صورة (PNG/JPG).'
            : 'Add your signature: enable the pad, draw and Save, or upload PNG/JPG.';
      });
      return;
    }

    try {
      final username = nid;
      final sb = Supabase.instance.client;

      final usernameTaken = await _usernameExists(username);
      if (usernameTaken == null) {
        setState(() {
          _busy = false;
          _err = _isAr
              ? 'تعذّر الاتصال بالخادم للتحقق من الهوية. تحقق من الشبكة أو أعد المحاولة لاحقًا.'
              : 'Could not verify your ID with the server. Check your connection and try again.';
        });
        return;
      }
      if (usernameTaken) {
        setState(() {
          _busy = false;
          _err = _isAr
              ? 'هذه الهوية/الإقامة مسجلة مسبقًا.'
              : 'This ID/Iqama is already registered.';
        });
        return;
      }

      if (_isProfessionalAccount) {
        final unifiedTaken = await _unifiedNationalTaken(unifiedNatDigits);
        if (unifiedTaken == null) {
          setState(() {
            _busy = false;
            _err = _isAr
                ? 'تعذّر الاتصال بالخادم للتحقق من الرقم الموحّد. تحقق من الشبكة ثم أعد المحاولة.'
                : 'Could not verify the unified national number. Check your connection and try again.';
          });
          _unifiedNatFocus.requestFocus();
          return;
        }
        if (unifiedTaken) {
          setState(() {
            _busy = false;
            _err = _isAr
                ? 'الرقم الوطني الموحّد مسجّل مسبقًا.'
                : 'This unified national number is already registered.';
          });
          _unifiedNatFocus.requestFocus();
          return;
        }
      }

      final phoneTaken = await _phoneExistsE164(phoneE164);
      if (phoneTaken == null) {
        setState(() {
          _busy = false;
          _err = _isAr
              ? 'تعذّر الاتصال بالخادم للتحقق من الجوال. تحقق من الشبكة ثم أعد المحاولة.'
              : 'Could not verify your phone with the server. Check your connection and try again.';
        });
        return;
      }
      if (phoneTaken) {
        setState(() {
          _busy = false;
          _err = _isAr
              ? 'رقم الجوال مسجل مسبقًا.'
              : 'This phone number is already registered.';
        });
        return;
      }

      final locale = await _loadLocale();

      Map<String, String?>? enParts;
      if (_isAr) {
        final fullAr = parts['full4'] ?? assembledName;
        final enFull =
            await NameTranslationService.arabicFullNameToEnglish(fullAr);
        if (enFull != null && enFull.isNotEmpty) {
          try {
            enParts = _splitEnglishFullNameToParts(enFull);
          } catch (_) {
            enParts = _fallbackEnglishNameParts(enFull);
          }
        }
      }

      final profileParams = <String, dynamic>{
        'p_username': username,
        'p_email': email,
        'p_phone': phoneE164,
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
        'account_type': _accountType,
        'verification_status': 'none',
        'fal_license': _isProfessionalAccount ? falLicense : null,
        'fal_start_date': _isProfessionalAccount
            ? _falStartDate?.toIso8601String().split('T').first
            : null,
        'fal_end_date': _isProfessionalAccount
            ? _falEndDate?.toIso8601String().split('T').first
            : null,
        'office_name': _isProfessionalAccount
            ? (_needsUnifiedCommercialReg
                ? (((_commercialSnapshot?['entity_name_ar'] ?? '')
                        .toString()
                        .trim()
                        .isNotEmpty)
                    ? _commercialSnapshot!['entity_name_ar'].toString().trim()
                    : (_falOwnerName ?? assembledName))
                : (_falOwnerName ?? assembledName))
            : null,
        if (_needsUnifiedCommercialReg) ...{
          'unified_commercial_reg_no': _normalizeDigits(_unifiedCrCtrl.text)
              .replaceAll(RegExp(r'[^0-9]'), ''),
          'commercial_reg_snapshot': _commercialSnapshot,
          'commercial_reg_no': _commercialSnapshot?['commercial_reg_no']
              ?.toString(),
        },
      };

      if (_isAr) {
        profileParams.addAll({
          'p_full_name_ar':
              parts['full4'] ?? parts['fullRaw'] ?? assembledName,
          'p_first_name_ar': parts['first'],
          'p_second_name_ar': parts['second'],
          'p_third_name_ar': parts['third'],
          'p_fourth_name_ar': parts['fourth'],
        });
        if (enParts != null) {
          profileParams.addAll({
            'p_full_name_en':
                enParts['full4'] ?? enParts['fullRaw'],
            'p_first_name_en': enParts['first'],
            'p_second_name_en': enParts['second'],
            'p_third_name_en': enParts['third'],
            'p_fourth_name_en': enParts['fourth'],
          });
        }
      } else {
        profileParams.addAll({
          'p_full_name_en':
              parts['full4'] ?? parts['fullRaw'] ?? assembledName,
          'p_first_name_en': parts['first'],
          'p_second_name_en': parts['second'],
          'p_third_name_en': parts['third'],
          'p_fourth_name_en': parts['fourth'],
        });
      }

      final signUpRes = await sb.auth.signUp(
        email: email,
        password: p1,
        data: {
          'username': username,
          'phone': phoneE164,
          'account_type': _accountType,
          'locale': locale,
          'full_name': parts['fullRaw'] ?? assembledName,
          'fal_license': _isProfessionalAccount ? falLicense : null,
          'fal_start_date': _isProfessionalAccount
              ? _falStartDate?.toIso8601String().split('T').first
              : null,
          'fal_end_date': _isProfessionalAccount
              ? _falEndDate?.toIso8601String().split('T').first
              : null,
          'fal_owner_name': _isProfessionalAccount ? _falOwnerName : null,
          'fal_status': _isProfessionalAccount ? _falStatus : null,
          if (_needsUnifiedCommercialReg)
            'unified_commercial_reg_no': _normalizeDigits(_unifiedCrCtrl.text)
                .replaceAll(RegExp(r'[^0-9]'), ''),
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
        print('SIGNUP user id: ${user.id}');
        print('SIGNUP session: ${signUpRes.session != null}');
      }

      if (signUpRes.session != null) {
        try {
          await ProfileComplianceService.clearPendingSignupSignaturePref();
          await sb.rpc('upsert_my_profile', params: profileParams);
          if (_isProfessionalAccount &&
              isValidUnifiedNationalNumberDigits(unifiedNatDigits)) {
            try {
              await sb.rpc(
                'signup_set_unified_national',
                params: {
                  'p_user_id': user.id,
                  'p_digits': unifiedNatDigits,
                },
              );
            } catch (_) {}
          }
          if (_pendingSignaturePng != null &&
              _pendingSignaturePng!.isNotEmpty) {
            try {
              await ProfileComplianceService.uploadSignatureRasterBytes(
                sb,
                _pendingSignaturePng!,
              );
            } catch (_) {}
          }
          await _clearPendingProfile();
        } catch (_) {
          await _savePendingProfile(profileParams);
          await _persistPendingSignupSignatureIfNeeded();
        }
      } else {
        await _savePendingProfile(profileParams);
        await _persistPendingSignupSignatureIfNeeded();
      }

      if (!mounted) return;
      setState(() => _busy = false);

      final successMsg = signUpRes.session != null
          ? (_isAr
              ? 'تم إنشاء الحساب وحفظ البيانات.'
              : 'Account created and profile saved.')
          : (_isAr
              ? 'تم إنشاء الحساب. افتح البريد لتأكيده ثم سجّل الدخول.'
              : 'Account created. Confirm email then sign in.');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(successMsg),
          duration: const Duration(seconds: 3),
        ),
      );

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(AppConfig.prefGuestModeKey, false);
        await prefs.setString(AppConfig.prefEntryModeKey, 'user');
      } catch (_) {}

      await Future<void>.delayed(const Duration(milliseconds: 450));

      if (!mounted) return;
      setState(_clearAllFields);

      try {
        await sb.auth.signOut();
      } catch (_) {}

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
    } on AuthException catch (e) {
      setState(() {
        _busy = false;
        _err = _isAr
            ? 'خطأ في إنشاء الحساب: ${e.message}'
            : 'Sign up error: ${e.message}';
      });
    } on PostgrestException catch (e) {
      setState(() {
        _busy = false;
        final code = (e.code ?? '').toString();
        final isRecursion = e.message.contains('42P17') ||
            e.message.toLowerCase().contains('infinite recursion');
        _err = _isAr
            ? (isRecursion
                ? 'تعارض في صلاحيات قاعدة البيانات (RLS). نفّذ في Supabase → SQL Editor بالترتيب:\n1) supabase/sql/20260422_users_profiles_rls_consolidated_fix.sql\n2) supabase/sql/20260420_in_app_notifications_drop_duplicate_select_policy.sql\n3) إن استمر 500: supabase/sql/20260427_users_profiles_rls_helper_row_security_off.sql\n\n(اختياري للتسجيل) 20260416_signup_rls_safe_checks.sql\n\nالتفاصيل: $code ${e.message}'
                : 'خطأ من الخادم ($code). إن وُجد ملف SQL جديد للتسجيل نفّذه من مجلد supabase/sql.\n${e.message}')
            : (isRecursion
                ? 'Database RLS recursion. In Supabase SQL editor run:\n1) supabase/sql/20260422_users_profiles_rls_consolidated_fix.sql\n2) supabase/sql/20260420_in_app_notifications_drop_duplicate_select_policy.sql\n3) If still 500: supabase/sql/20260427_users_profiles_rls_helper_row_security_off.sql\n\n(Optional signup) 20260416_signup_rls_safe_checks.sql\n\n$code ${e.message}'
                : 'Server error ($code).\n${e.message}');
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _err = _isAr ? 'حدث خطأ غير متوقع: $e' : 'Unexpected error: $e';
      });
    }
  }

  double _hintFontSize(BuildContext context) {
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
        overflow: TextOverflow.ellipsis,
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
              maxLines: 5,
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
            child: const Icon(
              Icons.person_add_alt_1_rounded,
              color: _bankColor,
              size: 22,
            ),
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
                  _isProfessionalAccount
                      ? (_isAr
                          ? 'التحقق من رخصة فال أولًا للحسابات المهنية'
                          : 'Verify FAL license first for professional accounts')
                      : (_isAr ? 'بيانات إلزامية' : 'Required information'),
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

  Widget _fieldAccountType() {
    return DropdownButtonFormField<String>(
      value: _accountType,
      decoration: _dec(
        context,
        hint: _isAr ? 'نوع الحساب' : 'Account type',
        icon: Icons.badge_outlined,
      ),
      items: [
        DropdownMenuItem(
          value: 'individual_seller',
          child: Text(_isAr ? 'فرد / مالك' : 'Individual / Owner'),
        ),
        DropdownMenuItem(
          value: 'marketer',
          child: Text(_isAr ? 'مسوّق عقاري' : 'Marketer'),
        ),
        DropdownMenuItem(
          value: 'office',
          child: Text(_isAr ? 'مكتب عقاري' : 'Real-estate office'),
        ),
        DropdownMenuItem(
          value: 'company',
          child: Text(_isAr ? 'شركة عقارية' : 'Real-estate company'),
        ),
        DropdownMenuItem(
          value: 'institution',
          child: Text(_isAr ? 'مؤسسة عقارية' : 'Real-estate institution'),
        ),
      ],
      onChanged: _busy
          ? null
          : (v) {
              if (v == null || v == _accountType) return;
              setState(() {
                _accountType = v;
                _err = null;
                _ok = null;
                _emailFromRegulatorSnapshot = null;

                _falVerified = false;
                _falOwnerName = null;
                _falStartDate = null;
                _falEndDate = null;
                _falStatus = null;
                _commercialVerified = false;
                _commercialSnapshot = null;
                _unifiedCrCtrl.clear();

                if (!_isProfessionalAccount) {
                  _falLicenseCtrl.clear();
                } else {
                  _clearQuadNameFields();
                }
              });

              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                if (_isProfessionalAccount) {
                  _falLicenseFocus.requestFocus();
                } else {
                  _nidFocus.requestFocus();
                }
              });
            },
    );
  }

  Widget _fieldFalLicense() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _falLicenseCtrl,
          focusNode: _falLicenseFocus,
          enabled: !_busy && !_verifyingFal,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹]')),
            LengthLimitingTextInputFormatter(10),
          ],
          decoration: _dec(
            context,
            hint: _isAr
                ? 'رقم رخصة فال (10 أرقام)'
                : 'FAL license number (10 digits)',
            icon: Icons.verified_user_outlined,
          ),
          onFieldSubmitted: (_) => _verifyFalLicense(),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 50,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _bankColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: (_busy || _verifyingFal)
                ? null
                : _verifyFalLicense,
            icon: _verifyingFal
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: AppLogoLoading(compact: true, size: 20),
                  )
                : const Icon(Icons.travel_explore_rounded),
            label: Text(
              _verifyingFal
                  ? (_isAr ? 'جاري التحقق...' : 'Verifying...')
                  : (_isAr ? 'تحقق من رخصة فال' : 'Verify FAL license'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        if (_falOwnerName != null ||
            _falStatus != null ||
            _falStartDate != null ||
            _falEndDate != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color:
                  _isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0F1425),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _fieldBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((_falOwnerName ?? '').trim().isNotEmpty)
                  Text(
                    '${_isAr ? 'الاسم' : 'Name'}: ${_falOwnerName!.trim()}',
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                if ((_falStatus ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${_isAr ? 'الحالة' : 'Status'}: ${_falStatus!.trim()}',
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (_falStartDate != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${_isAr ? 'البداية' : 'Start'}: '
                    '${_falStartDate!.year}-${_falStartDate!.month.toString().padLeft(2, '0')}-${_falStartDate!.day.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (_falEndDate != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${_isAr ? 'النهاية' : 'End'}: '
                    '${_falEndDate!.year}-${_falEndDate!.month.toString().padLeft(2, '0')}-${_falEndDate!.day.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: _isFalStillValid(_falEndDate)
                          ? _textPrimary
                          : Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _fieldUnifiedCommercialReg() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _isAr
              ? 'السجل التجاري الموحّد (وزارة التجارة)'
              : 'Unified commercial registration (MoC)',
          style: TextStyle(
            color: _textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _unifiedCrCtrl,
          focusNode: _unifiedCrFocus,
          enabled: !_busy && !_commercialBusy && _falVerified,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹]')),
            LengthLimitingTextInputFormatter(10),
          ],
          decoration: _dec(
            context,
            hint: _isAr
                ? 'رقم السجل في وزارة التجارة (10 أرقام) — ليس الرقم الوطني الموحّد'
                : 'MoC registry number (10 digits) — not the unified national no.',
            icon: Icons.apartment_outlined,
          ),
          onFieldSubmitted: (_) => _runCommercialLookup(),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 50,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _bankColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: (_busy || _commercialBusy || !_falVerified)
                ? null
                : _runCommercialLookup,
            icon: _commercialBusy
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: AppLogoLoading(compact: true, size: 20),
                  )
                : const Icon(Icons.business_outlined),
            label: Text(
              _commercialBusy
                  ? (_isAr ? 'جاري الاستعلام...' : 'Looking up…')
                  : (_isAr
                      ? 'استعلام السجل التجاري (وزارة التجارة)'
                      : 'Lookup commercial registry (MoC)'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        if (_commercialSnapshot != null &&
            (_commercialSnapshot!['registry_status_ar'] ?? '')
                .toString()
                .trim()
                .isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color:
                  _isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0F1425),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _fieldBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_isAr ? 'حالة السجل' : 'Registry status'}: '
                  '${_commercialSnapshot!['registry_status_ar']}',
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if ((_commercialSnapshot!['commercial_reg_no'] ?? '')
                    .toString()
                    .trim()
                    .isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${_isAr ? 'رقم السجل' : 'CR no.'}: '
                    '${_commercialSnapshot!['commercial_reg_no']}',
                    style: TextStyle(
                      color: _textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _fieldNationalId() {
    return TextFormField(
      controller: _nidCtrl,
      focusNode: _nidFocus,
      enabled: !_busy,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹]')),
        LengthLimitingTextInputFormatter(10),
      ],
      decoration: _dec(
        context,
        hint: _isAr ? 'رقم الهوية / الإقامة' : 'National ID / Iqama',
        icon: Icons.credit_card_outlined,
      ),
      onFieldSubmitted: (_) {
        if (_isProfessionalAccount) {
          _unifiedNatFocus.requestFocus();
        } else {
          _phoneFocus.requestFocus();
        }
      },
    );
  }

  Widget _fieldUnifiedNationalNumber() {
    return TextFormField(
      controller: _unifiedNatCtrl,
      focusNode: _unifiedNatFocus,
      enabled: !_busy,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.next,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹\u0646]')),
        LengthLimitingTextInputFormatter(11),
      ],
      decoration: _dec(
        context,
        hint: _isAr
            ? 'الرقم الوطني الموحّد (ن700… أو 700…)'
            : 'Unified national no. (700…)',
        icon: Icons.numbers_rounded,
      ),
      onFieldSubmitted: (_) => _phoneFocus.requestFocus(),
    );
  }

  Widget _fieldPhone() {
    return TextFormField(
      controller: _phoneCtrl,
      focusNode: _phoneFocus,
      enabled: !_busy,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.next,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹]')),
        LengthLimitingTextInputFormatter(10),
      ],
      decoration: _dec(
        context,
        hint: _isAr ? 'رقم الجوال (05xxxxxxxx)' : 'Phone number (05xxxxxxxx)',
        icon: Icons.phone_iphone_outlined,
      ),
      onFieldSubmitted: (_) => _emailFocus.requestFocus(),
    );
  }

  /// اقتراحات النطاق مدمجة مع الحقل (طبقة فوق الحقل)؛ تظهر عند وجود @.
  Widget _fieldEmailWithInlineAutocomplete() {
    final borderColor = _fieldBorder;
    return RawAutocomplete<String>(
      textEditingController: _emailCtrl,
      focusNode: _emailFocus,
      displayStringForOption: (s) => s,
      optionsBuilder: (TextEditingValue te) {
        if (_blockEmailDomainAutocomplete()) {
          return const Iterable<String>.empty();
        }
        final t = te.text;
        final at = t.indexOf('@');
        if (at < 0) return const Iterable<String>.empty();
        final local = t.substring(0, at);
        final domainTyped = at < t.length - 1 ? t.substring(at + 1) : '';
        if (local.trim().isEmpty) return const Iterable<String>.empty();
        return EmailDomainCatalog.completionSuggestions(
          localPart: local,
          domainTyped: domainTyped,
          maxItems: 28,
        );
      },
      onSelected: (option) {
        final o = option.trim().toLowerCase();
        _emailCtrl.text = o;
        _emailCtrl.selection = TextSelection.collapsed(offset: o.length);
      },
      fieldViewBuilder:
          (context, textEditingController, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: textEditingController,
          focusNode: focusNode,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: _dec(
            context,
            hint: _isAr ? 'البريد الإلكتروني' : 'Email address',
            icon: Icons.alternate_email_rounded,
          ),
          onFieldSubmitted: (_) {
            onFieldSubmitted();
            _name1Focus.requestFocus();
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final opts = options.toList(growable: false);
        if (opts.isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: AlignmentDirectional.topStart,
          child: Material(
            elevation: 10,
            shadowColor: Colors.black38,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            color: _fieldFill,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: opts.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: borderColor.withValues(alpha: 0.45),
                ),
                itemBuilder: (ctx, i) {
                  final opt = opts[i];
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: Text(
                      opt,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    leading:
                        Icon(Icons.alternate_email_rounded, color: _bankColor, size: 22),
                    onTap: () => onSelected(opt),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _fieldQuadName() {
    final lockName = _isProfessionalAccount &&
        _falVerified &&
        (!_needsUnifiedCommercialReg || _commercialVerified);

    final title = _isAr ? 'الاسم الرباعي (كما في الهوية)' : 'Full legal name (4 parts)';
    final subtitle = _isAr
        ? 'الأول، الثاني، الثالث، والأخير — يُستخدم في العقود والوثائق الرسمية.'
        : 'First, second, third, and family name — used on contracts and official documents.';

    TextFormField field({
      required TextEditingController controller,
      required FocusNode focus,
      required FocusNode nextFocus,
      required String hint,
      TextInputAction action = TextInputAction.next,
    }) {
      return TextFormField(
        controller: controller,
        focusNode: focus,
        enabled: !_busy && !lockName,
        textInputAction: action,
        decoration: _dec(
          context,
          hint: hint,
          icon: Icons.person_outline_rounded,
        ),
        onFieldSubmitted: (_) {
          if (action == TextInputAction.done) {
            _p1Focus.requestFocus();
          } else {
            nextFocus.requestFocus();
          }
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.badge_outlined, size: 22, color: _bankColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: _textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
            height: 1.4,
            color: _textSecondary,
          ),
        ),
        if (lockName) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _bankColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _bankColor.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 18, color: _bankColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isAr
                        ? 'الاسم مُستخرج من بيانات الهيئة ولا يُعدّل هنا.'
                        : 'Name is locked from regulator data and cannot be edited here.',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: _textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: field(
                controller: _name1Ctrl,
                focus: _name1Focus,
                nextFocus: _name2Focus,
                hint: _isAr ? 'الاسم الأول' : 'First name',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: field(
                controller: _name2Ctrl,
                focus: _name2Focus,
                nextFocus: _name3Focus,
                hint: _isAr ? 'الاسم الثاني' : 'Second name',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: field(
                controller: _name3Ctrl,
                focus: _name3Focus,
                nextFocus: _name4Focus,
                hint: _isAr ? 'الاسم الثالث' : 'Third name',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: field(
                controller: _name4Ctrl,
                focus: _name4Focus,
                nextFocus: _p1Focus,
                hint: _isAr ? 'الاسم الأخير' : 'Last name',
                action: TextInputAction.done,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _armSignupSignaturePad() {
    if (_busy) return;
    setState(() {
      _signupSigPadArmed = true;
      _signupSigCtrl.disabled = false;
      _signupSigErr = null;
    });
  }

  void _disarmSignupSignaturePad() {
    if (_busy) return;
    setState(() {
      _signupSigPadArmed = false;
      _signupSigCtrl.disabled = true;
    });
  }

  void _clearSignupPadOnly() {
    if (_busy || _signupSigBusy) return;
    _signupSigCtrl.clear();
    setState(() => _signupSigErr = null);
  }

  void _undoSignupStroke() {
    if (_busy || _signupSigBusy || !_signupSigPadArmed) return;
    if (!_signupSigCtrl.canUndo) return;
    _signupSigCtrl.undo();
    setState(() {});
  }

  void _redoSignupStroke() {
    if (_busy || _signupSigBusy || !_signupSigPadArmed) return;
    if (!_signupSigCtrl.canRedo) return;
    _signupSigCtrl.redo();
    setState(() {});
  }

  void _removeSavedSignupSignature() {
    if (_busy || _signupSigBusy) return;
    _signupSigCtrl.clear();
    setState(() {
      _pendingSignaturePng = null;
      _signupSigErr = null;
      _signupSigPadArmed = false;
      _signupSigCtrl.disabled = true;
    });
  }

  Future<void> _confirmDrawnSignupSignature() async {
    if (_signupSigCtrl.isEmpty) {
      setState(() {
        _signupSigErr = _isAr
            ? 'ارسم توقيعك داخل المربع أولًا.'
            : 'Draw your signature in the box first.';
      });
      return;
    }
    setState(() {
      _signupSigBusy = true;
      _signupSigErr = null;
    });
    try {
      final bytes = await _signupSigCtrl.toPngBytes();
      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          setState(() {
            _signupSigBusy = false;
            _signupSigErr = _isAr
                ? 'تعذر تصدير التوقيع.'
                : 'Could not export signature.';
          });
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _pendingSignaturePng = bytes;
        _signupSigBusy = false;
        _signupSigPadArmed = false;
        _signupSigCtrl.disabled = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _signupSigBusy = false;
          _signupSigErr = '$e';
        });
      }
    }
  }

  Future<void> _pickSignupSignatureFile() async {
    final t = AppLocalizations.of(context);
    if (t != null &&
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      final ok = await RuntimePermissionHelper.ensurePhotos(context, t: t);
      if (!ok || !mounted) return;
    }
    setState(() {
      _signupSigBusy = true;
      _signupSigErr = null;
    });
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg'],
    );
    if (!mounted) return;
    if (result == null || result.files.isEmpty) {
      setState(() => _signupSigBusy = false);
      return;
    }
    final b = result.files.first.bytes;
    if (b == null || b.isEmpty) {
      setState(() {
        _signupSigBusy = false;
        _signupSigErr =
            _isAr ? 'لا توجد بيانات للملف.' : 'No file data.';
      });
      return;
    }
    _signupSigCtrl.clear();
    setState(() {
      _pendingSignaturePng = b;
      _signupSigBusy = false;
      _signupSigPadArmed = false;
      _signupSigCtrl.disabled = true;
    });
  }

  Widget _signupSignatureBlock() {
    const borderInk = Color.fromARGB(
      180,
      kSignatureInkR,
      kSignatureInkG,
      kSignatureInkB,
    );
    final dividerColor = _fieldBorder;
    final mutedPadBg =
        _isLight ? const Color(0xFFF8FAFC) : const Color(0xFF151A28);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.draw_rounded, size: 22, color: _bankColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _isAr ? 'التوقيع الإلكتروني' : 'Electronic signature',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _textPrimary,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _isAr
              ? 'يُحفظ في ملفك ويُستخدم في العقود والمعاملات. فعِّل اللوحة فقط أثناء الرسم لتجنّب خطوطٍ بالخطأ أثناء التمرير.'
              : 'Stored on your profile for contracts and workflows. Enable the pad only while drawing to avoid stray strokes when scrolling.',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: _textSecondary,
            fontSize: 12.8,
            height: 1.4,
          ),
        ),
        if (_signupSigErr != null) ...[
          const SizedBox(height: 8),
          Text(
            _signupSigErr!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (!_signupSigPadArmed)
          FilledButton.tonalIcon(
            onPressed: (_busy || _signupSigBusy) ? null : _armSignupSignaturePad,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              foregroundColor: _bankColor,
            ),
            icon: const Icon(Icons.gesture_rounded, size: 22),
            label: Text(
              _isAr ? 'تفعيل لوحة التوقيع' : 'Enable signature pad',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: (_busy || _signupSigBusy) ? null : _disarmSignupSignaturePad,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              foregroundColor: _textPrimary,
              side: BorderSide(color: dividerColor),
            ),
            icon: Icon(Icons.swipe_vertical_rounded, color: _bankColor, size: 20),
            label: Text(
              _isAr ? 'انتهيت — تفعيل التمرير في الصفحة' : 'Done — resume page scroll',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: _textPrimary,
                fontSize: 13,
              ),
            ),
          ),
        const SizedBox(height: 12),
        AspectRatio(
          aspectRatio: 1.35,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _signupSigPadArmed ? Colors.white : mutedPadBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _signupSigPadArmed ? borderInk : dividerColor,
                width: _signupSigPadArmed ? 2 : 1.2,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  IgnorePointer(
                    ignoring: !_signupSigPadArmed,
                    child: Signature(
                      key: const ValueKey<String>('signup_sig_pad'),
                      controller: _signupSigCtrl,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  if (!_signupSigPadArmed)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _isAr
                                  ? 'مرّر الصفحة بحرية.\nاضغط «تفعيل لوحة التوقيع» للرسم.'
                                  : 'Scroll the page freely.\nTap «Enable signature pad» to draw.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                height: 1.45,
                                color: _textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              onPressed: (_busy || _signupSigBusy || !_signupSigPadArmed)
                  ? null
                  : _undoSignupStroke,
              icon: Icon(Icons.undo_rounded, size: 20, color: _bankColor),
              label: Text(_isAr ? 'تراجع' : 'Undo'),
            ),
            TextButton.icon(
              onPressed: (_busy ||
                      _signupSigBusy ||
                      !_signupSigPadArmed ||
                      !_signupSigCtrl.canRedo)
                  ? null
                  : _redoSignupStroke,
              icon: Icon(Icons.redo_rounded, size: 20, color: _bankColor),
              label: Text(_isAr ? 'إعادة' : 'Redo'),
            ),
            TextButton.icon(
              onPressed: (_busy || _signupSigBusy || !_signupSigPadArmed)
                  ? null
                  : _clearSignupPadOnly,
              icon: Icon(Icons.format_clear_rounded, size: 20, color: _iconColor),
              label: Text(_isAr ? 'مسح اللوحة' : 'Clear pad'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _bankColor),
              onPressed: (_busy || _signupSigBusy || !_signupSigPadArmed)
                  ? null
                  : _confirmDrawnSignupSignature,
              icon: _signupSigBusy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: AppLogoLoading(compact: true, size: 16),
                    )
                  : const Icon(Icons.save_rounded, size: 20),
              label: Text(
                _signupSigBusy
                    ? (_isAr ? 'جاري الحفظ…' : 'Saving…')
                    : (_isAr ? 'حفظ التوقيع' : 'Save signature'),
              ),
            ),
            OutlinedButton.icon(
              onPressed: (_busy || _signupSigBusy) ? null : _pickSignupSignatureFile,
              icon: const Icon(Icons.upload_file_rounded, size: 20),
              label: Text(_isAr ? 'رفع صورة' : 'Upload image'),
            ),
          ],
        ),
        if (_pendingSignaturePng != null && _pendingSignaturePng!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _isLight ? const Color(0xFFF0FDF4) : const Color(0xFF0F1F17),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isLight
                    ? const Color(0xFFBBF7D0)
                    : const Color(0xFF166534).withValues(alpha: 0.45),
                width: 1.2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.verified_rounded,
                      color: _isLight
                          ? const Color(0xFF15803D)
                          : const Color(0xFF4ADE80),
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isAr
                            ? 'جاهز للرفع: عند «إنشاء الحساب» يُخزَّن التوقيع في التخزين الآمن ويُربَط بعمود ملفك لاستخدامه لاحقاً في العقود.'
                            : 'Ready to upload: on «Create account» your signature is stored securely and linked to your profile for contracts and workflows.',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _isLight
                              ? const Color(0xFF14532D)
                              : const Color(0xFFBBF7D0),
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Align(
                  alignment:
                      _isAr ? Alignment.centerRight : Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: (_busy || _signupSigBusy)
                        ? null
                        : _removeSavedSignupSignature,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: Theme.of(context).colorScheme.error,
                      size: 20,
                    ),
                    label: Text(
                      _isAr ? 'إزالة التوقيع المحفوظ' : 'Remove saved signature',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _fieldPassword1() {
    return TextFormField(
      controller: _p1,
      focusNode: _p1Focus,
      enabled: !_busy,
      obscureText: _obscure1,
      enableSuggestions: false,
      autocorrect: false,
      inputFormatters: passwordArabicGuardFormatters(
        onArabicScriptBlocked: _schedulePasswordArabicDialog,
      ),
      textInputAction: TextInputAction.next,
      decoration: _dec(
        context,
        hint: _isAr ? 'كلمة المرور' : 'Password',
        icon: Icons.lock_outline_rounded,
        suffix: IconButton(
          onPressed: () => setState(() => _obscure1 = !_obscure1),
          icon: Icon(
            _obscure1 ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            color: _iconColor,
          ),
        ),
      ),
      onFieldSubmitted: (_) => _p2Focus.requestFocus(),
    );
  }

  Widget _fieldPassword2() {
    return TextFormField(
      controller: _p2,
      focusNode: _p2Focus,
      enabled: !_busy,
      obscureText: _obscure2,
      enableSuggestions: false,
      autocorrect: false,
      inputFormatters: passwordArabicGuardFormatters(
        onArabicScriptBlocked: _schedulePasswordArabicDialog,
      ),
      textInputAction: TextInputAction.done,
      decoration: _dec(
        context,
        hint: _isAr ? 'تأكيد كلمة المرور' : 'Confirm password',
        icon: Icons.lock_person_outlined,
        suffix: IconButton(
          onPressed: () => setState(() => _obscure2 = !_obscure2),
          icon: Icon(
            _obscure2 ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            color: _iconColor,
          ),
        ),
      ),
      onFieldSubmitted: (_) {
        if (!_busy &&
            !_verifyingFal &&
            !(_isProfessionalAccount && !_showProfessionalDetails)) {
          _createAccount();
        }
      },
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
          _isProfessionalAccount
              ? (_showProfessionalDetails
                  ? (_needsUnifiedCommercialReg && !_commercialVerified
                      ? (_isAr
                          ? 'بعد التحقق من فال: أدخل الرقم الموحّد للسجل واستعلام وزارة التجارة.'
                          : 'After FAL: enter unified CR number and run Ministry of Commerce lookup.')
                      : (_isAr
                          ? 'أكمل رقم الهوية والبريد وكلمة المرور.'
                          : 'Complete national ID, email, and password.'))
                  : (_isAr
                      ? 'للحسابات المهنية: تحقق من رخصة فال عبر صفحة الهيئة أولًا.'
                      : 'Professional accounts: verify FAL via the official REGA page first.'))
              : (_isAr
                  ? 'أدخل بياناتك لتسجيل الحساب.'
                  : 'Enter your details to create your account.'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: _textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 18),
        _fieldAccountType(),
        const SizedBox(height: 12),
        if (_isProfessionalAccount) ...[
          _fieldFalLicense(),
          if (_falVerified && _needsUnifiedCommercialReg) ...[
            const SizedBox(height: 12),
            _fieldUnifiedCommercialReg(),
          ],
          if (_showProfessionalDetails) ...[
            const SizedBox(height: 12),
            _fieldNationalId(),
            const SizedBox(height: 12),
            _fieldUnifiedNationalNumber(),
            const SizedBox(height: 12),
            _fieldPhone(),
            const SizedBox(height: 12),
            _fieldEmailWithInlineAutocomplete(),
            const SizedBox(height: 12),
            _fieldQuadName(),
            const SizedBox(height: 12),
            _fieldPassword1(),
            const SizedBox(height: 12),
            _fieldPassword2(),
            const SizedBox(height: 16),
            _signupSignatureBlock(),
          ],
        ] else ...[
          _fieldNationalId(),
          const SizedBox(height: 12),
          _fieldPhone(),
          const SizedBox(height: 12),
          _fieldEmailWithInlineAutocomplete(),
          const SizedBox(height: 12),
          _fieldQuadName(),
          const SizedBox(height: 12),
          _fieldPassword1(),
          const SizedBox(height: 12),
          _fieldPassword2(),
          const SizedBox(height: 16),
          _signupSignatureBlock(),
        ],
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
            onPressed: (_busy ||
                    _verifyingFal ||
                    (_isProfessionalAccount && !_showProfessionalDetails))
                ? null
                : _createAccount,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _busy
                  ? Row(
                      key: const ValueKey('busy'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: AppLogoLoading(compact: true, size: 20),
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
            onPressed: _busy
                ? null
                : () {
                    setState(_clearAllFields);
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/login',
                      (r) => false,
                    );
                  },
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
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}