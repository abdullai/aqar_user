import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/input/input_normalizers.dart';
import '../core/profile/publisher_identity_prefs.dart';
import '../core/utils/compound_display_name.dart';
import '../core/utils/profile_greeting_from_row.dart';
import '../services/account_completion_service.dart';
import '../services/fal_license_service.dart';
import '../services/profile_compliance_service.dart';
import 'aqar_text_field.dart';
import 'app_logo_loading.dart';
import 'field_group_frame.dart';

/// نافذة منبثقة لاستكمال النواقص وحفظها ثم إعادة الفحص.
class ProfileCompletionSheet extends StatefulWidget {
  const ProfileCompletionSheet({
    super.key,
    required this.lang,
    this.initialRow,
  });

  final String lang;
  final Map<String, dynamic>? initialRow;

  /// يعيد `true` إذا اكتمل الملف بعد الحفظ/الفحص.
  static Future<bool?> show(
    BuildContext context, {
    required String lang,
    Map<String, dynamic>? initialRow,
  }) {
    final isAr = lang.toLowerCase() != 'en';
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final h = MediaQuery.sizeOf(ctx).height;
        return Directionality(
          textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
          child: SizedBox(
            height: h * 0.92,
            child: ProfileCompletionSheet(
              lang: lang,
              initialRow: initialRow,
            ),
          ),
        );
      },
    );
  }

  @override
  State<ProfileCompletionSheet> createState() => _ProfileCompletionSheetState();
}

class _ProfileCompletionSheetState extends State<ProfileCompletionSheet> {
  static const Color _bank = Color(0xFF0F766E);

  final _phoneCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _officialArCtrl = TextEditingController();
  final _officialEnCtrl = TextEditingController();
  final _officeNameCtrl = TextEditingController();
  final _nationalCtrl = TextEditingController();
  final _identityCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();

  Map<String, dynamic>? _row;
  List<String> _missing = const [];
  bool _loading = true;
  bool _saving = false;
  String? _err;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  bool get _needPhone {
    final ph = digitsOnly(
      normalizeAsciiDigits((_row?['phone'] ?? '').toString()),
    );
    return ph.length < 10;
  }

  bool get _needIdentity =>
      AccountCompletionService.needsIdentityUsername(_row);

  bool get _needName =>
      AccountCompletionService.needsDisplayNameCompletion(_row, isAr: true) ||
      AccountCompletionService.needsDisplayNameCompletion(_row, isAr: false);

  bool get _needOfficial =>
      PublisherIdentityPrefs.officialNameNeedsCompletion(_row, isAr: _isAr);

  bool get _needNational =>
      AccountCompletionService.needsUnifiedNationalCompletion(_row);

  bool get _isOrgAccount {
    final at = (_row?['account_type'] ?? '').toString().toLowerCase().trim();
    return const {'office', 'institution', 'company', 'agency'}.contains(at);
  }

  bool get _needLicense {
    final row = _row;
    if (row == null) return false;
    if (!AccountCompletionService.accountTypeNeedsUnifiedNational(
      row['account_type']?.toString(),
    )) {
      return false;
    }
    final lic = (row['license_no'] ?? '').toString().trim();
    if (lic.isEmpty) return true;
    final fal = ProfileComplianceService.evaluateFal(row);
    return fal == FalComplianceLevel.blockedExpired ||
        fal == FalComplianceLevel.warnWeek;
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
    _officialArCtrl.dispose();
    _officialEnCtrl.dispose();
    _officeNameCtrl.dispose();
    _nationalCtrl.dispose();
    _identityCtrl.dispose();
    _licenseCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    final row = widget.initialRow ??
        await AccountCompletionService.loadRow(Supabase.instance.client);
    if (!mounted) return;
    _applyRow(row);
  }

  void _applyRow(Map<String, dynamic>? row) {
    final ph = digitsOnly(
      normalizeAsciiDigits((row?['phone'] ?? '').toString()),
    );
    final existingName =
        ProfileGreetingFromRow.displayName(row ?? const {}, isAr: _isAr)
                ?.trim() ??
            '';
    final un = (row?['username'] ?? '').toString().trim();
    final seedName =
        CompoundDisplayName.looksLikeNumericUsername(existingName) ||
                existingName == un
            ? ''
            : existingName;
    final unn = digitsOnly(
      normalizeAsciiDigits((row?['unified_national_number'] ?? '').toString()),
    );
    final idDigits = digitsOnly(normalizeAsciiDigits(un));
    final lic = digitsOnly(
      normalizeAsciiDigits((row?['license_no'] ?? '').toString()),
    );
    final arFull = CompoundDisplayName.normalize(
      (row?['full_name_ar'] ?? '').toString(),
    );
    final enFull = CompoundDisplayName.normalize(
      (row?['full_name_en'] ?? '').toString(),
    );
    final office = (row?['office_name'] ?? '').toString().trim();

    setState(() {
      _row = row;
      _missing = AccountCompletionService.missingFieldLabels(
        row,
        isAr: _isAr,
      );
      if (ph.length >= 10) {
        _phoneCtrl.text = ph;
      }
      if (seedName.isNotEmpty) _nameCtrl.text = seedName;
      if (isValidUnifiedNationalNumberDigits(unn)) {
        _nationalCtrl.text = unn;
      }
      if (idDigits.length == 10) {
        _identityCtrl.text = idDigits;
      }
      if (lic.isNotEmpty) _licenseCtrl.text = lic;
      if (arFull.isNotEmpty) _officialArCtrl.text = arFull;
      if (enFull.isNotEmpty) _officialEnCtrl.text = enFull;
      if (office.isNotEmpty) _officeNameCtrl.text = office;
      _loading = false;
      _err = null;
    });
  }

  Future<void> _reloadAndMaybeClose() async {
    final row =
        await AccountCompletionService.loadRow(Supabase.instance.client);
    if (!mounted) return;
    _applyRow(row);
    if (_missing.isEmpty) {
      await AccountCompletionService.clearEnrollmentDeferred();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _err = null;
    });
    try {
      final sb = Supabase.instance.client;

      if (_needPhone) {
        await AccountCompletionService.savePhone(
          sb: sb,
          phoneRaw: _phoneCtrl.text,
        );
      }
      if (_needIdentity) {
        await AccountCompletionService.saveIdentityUsername(
          sb: sb,
          tenDigits: _identityCtrl.text,
        );
      }
      if (_needName) {
        final n = _nameCtrl.text.trim();
        if (n.isEmpty || CompoundDisplayName.looksLikeNumericUsername(n)) {
          throw 'invalid_name';
        }
        await AccountCompletionService.saveDisplayName(
          sb: sb,
          displayName: n,
          isAr: _isAr,
        );
      }
      if (_needOfficial) {
        if (_isOrgAccount) {
          final office = _officeNameCtrl.text.trim();
          if (office.isEmpty) throw 'invalid_official';
          final uid = sb.auth.currentUser?.id;
          if (uid == null) throw 'no_session';
          await sb.from('users_profiles').update({
            'office_name': office,
          }).eq('user_id', uid);
        } else {
          final ar = CompoundDisplayName.normalize(_officialArCtrl.text);
          final en = CompoundDisplayName.normalize(_officialEnCtrl.text);
          if (ar.isEmpty || en.isEmpty) throw 'invalid_official';
          await AccountCompletionService.saveOfficialQuadNames(
            sb: sb,
            arParts: ar.split(RegExp(r'\s+')),
            enParts: en.split(RegExp(r'\s+')),
          );
        }
      }
      if (_needNational) {
        await AccountCompletionService.saveUnifiedNational(
          sb: sb,
          tenDigits700: _nationalCtrl.text,
        );
      }
      if (_needLicense) {
        final falSvc = FalLicenseService(sb);
        final res = await falSvc.verify(_licenseCtrl.text);
        if (!res.valid || res.isExpired) {
          throw res.isExpired ? 'fal_expired' : 'invalid_license';
        }
        DateTime? exp;
        if ((res.endDateIso ?? '').isNotEmpty) {
          exp = DateTime.tryParse(res.endDateIso!);
        }
        await ProfileComplianceService.applyFalRenewal(
          sb: sb,
          licenseDigits: digitsOnly(
            normalizeAsciiDigits(_licenseCtrl.text),
          ),
          regaSnapshot: {
            'broker_name': res.brokerName,
            'email': res.email,
            'mobile': res.mobile,
            'end_date': res.endDateIso,
            'license_no': res.licenseNo,
            'source': res.source,
            'renewed_at': DateTime.now().toUtc().toIso8601String(),
          },
          expiresAt: exp,
        );
      }

      if (!mounted) return;
      await _reloadAndMaybeClose();
      if (!mounted) return;
      if (_missing.isNotEmpty) {
        setState(() {
          _saving = false;
          _err = _isAr
              ? 'تم الحفظ. ما زالت هناك نواقص — أكملها ثم احفظ مجدداً.'
              : 'Saved. Some fields are still missing — complete them and save again.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      final code = e.toString();
      setState(() {
        _saving = false;
        if (code.contains('invalid_name')) {
          _err = _isAr
              ? 'أدخل اسم ظهور نصّي (وليس أرقاماً فقط).'
              : 'Enter a text display alias (not digits only).';
        } else if (code.contains('invalid_phone') ||
            code.contains('primary_phone_locked')) {
          _err = _isAr
              ? 'رقم الجوال غير صالح أو مقفل.'
              : 'Phone is invalid or locked.';
        } else if (code.contains('invalid_identity') ||
            code.contains('identity_locked')) {
          _err = _isAr
              ? 'رقم الهوية يجب أن يكون 10 أرقام (أو مقفل إن وُجد).'
              : 'Identity must be 10 digits (or is locked).';
        } else if (code.contains('invalid_official')) {
          _err = _isAr
              ? 'أكمل الاسم/الصفة المعتمدة (عربي وإنجليزي).'
              : 'Complete official name (Arabic and English).';
        } else if (code.contains('invalid_unified')) {
          _err = _isAr
              ? 'الرقم الوطني الموحّد: 10 أرقام تبدأ بـ 700.'
              : 'Unified national number: 10 digits starting with 700.';
        } else if (code.contains('fal_expired')) {
          _err = _isAr
              ? 'رخصة فال منتهية — أدخل رقم رخصة سارية.'
              : 'FAL license expired — enter a valid license.';
        } else if (code.contains('invalid_license')) {
          _err = _isAr
              ? 'تعذر التحقق من رخصة فال. تأكد من الرقم.'
              : 'Could not verify FAL license. Check the number.';
        } else {
          _err = _isAr ? 'تعذر الحفظ. أعد المحاولة.' : 'Could not save. Try again.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _isAr ? 'استكمال البيانات' : 'Complete profile data',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _isAr ? 'إغلاق' : 'Close',
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: AppLogoLoading())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    children: [
                      Text(
                        _isAr
                            ? 'حدّث الحقول الناقصة فقط، ثم احفظ. تُستبدل القيم القديمة تلقائياً ويُعاد الفحص.'
                            : 'Update only missing fields, then save. Old values are replaced and the check runs again.',
                        style: TextStyle(
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      if (_missing.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          _isAr ? 'النواقص' : 'Missing',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _missing
                              .map(
                                (m) => Chip(
                                  avatar: Icon(
                                    Icons.warning_amber_rounded,
                                    size: 18,
                                    color: cs.error,
                                  ),
                                  label: Text(
                                    m,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  side: BorderSide(
                                    color: cs.error.withValues(alpha: 0.35),
                                  ),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (_needPhone) ...[
                        FieldGroupFrame(
                          title: _isAr ? 'رقم الجوال' : 'Phone number',
                          child: AqarTextField(
                            controller: _phoneCtrl,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9٠-٩۰-۹+]'),
                              ),
                              LengthLimitingTextInputFormatter(16),
                            ],
                            decoration: const InputDecoration(
                              hintText: '05xxxxxxxx',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_needIdentity) ...[
                        FieldGroupFrame(
                          title: _isAr
                              ? 'رقم الهوية (المعرّف)'
                              : 'Identity ID (username)',
                          subtitle: _isAr
                              ? '10 أرقام — يُحفظ مرة واحدة إن كان ناقصاً.'
                              : '10 digits — saved once when missing.',
                          child: AqarTextField(
                            controller: _identityCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9٠-٩۰-۹]'),
                              ),
                              LengthLimitingTextInputFormatter(10),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_needName) ...[
                        FieldGroupFrame(
                          title:
                              _isAr ? 'اسم الظهور المستعار' : 'Display alias',
                          child: AqarTextField(
                            controller: _nameCtrl,
                            textCapitalization: TextCapitalization.words,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_needOfficial) ...[
                        if (_isOrgAccount)
                          FieldGroupFrame(
                            title: _isAr ? 'اسم المنشأة' : 'Organization name',
                            child: AqarTextField(
                              controller: _officeNameCtrl,
                            ),
                          )
                        else ...[
                          FieldGroupFrame(
                            title: _isAr
                                ? 'الاسم المعتمد (عربي)'
                                : 'Official name (Arabic)',
                            child: AqarTextField(
                              controller: _officialArCtrl,
                              textCapitalization: TextCapitalization.words,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FieldGroupFrame(
                            title: _isAr
                                ? 'الاسم المعتمد (إنجليزي)'
                                : 'Official name (English)',
                            child: AqarTextField(
                              controller: _officialEnCtrl,
                              textCapitalization: TextCapitalization.words,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                      ],
                      if (_needNational) ...[
                        FieldGroupFrame(
                          title: _isAr
                              ? 'الرقم الوطني الموحّد'
                              : 'Unified national number',
                          subtitle: _isAr
                              ? '10 أرقام تبدأ بـ 700'
                              : '10 digits starting with 700',
                          child: AqarTextField(
                            controller: _nationalCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9٠-٩۰-۹]'),
                              ),
                              LengthLimitingTextInputFormatter(10),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_needLicense) ...[
                        FieldGroupFrame(
                          title: _isAr ? 'رخصة فال' : 'FAL license',
                          subtitle: _isAr
                              ? 'يُتحقق من الرقم ويُحدَّث تاريخ الصلاحية تلقائياً.'
                              : 'Number is verified and expiry is updated automatically.',
                          child: AqarTextField(
                            controller: _licenseCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9٠-٩۰-۹]'),
                              ),
                              LengthLimitingTextInputFormatter(20),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (!_needPhone &&
                          !_needIdentity &&
                          !_needName &&
                          !_needOfficial &&
                          !_needNational &&
                          !_needLicense) ...[
                        Text(
                          _isAr
                              ? 'لا توجد حقول ناقصة قابلة للتعديل هنا.'
                              : 'No editable missing fields here.',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                      if (_err != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _err!,
                          style: TextStyle(
                            color: cs.error,
                            fontWeight: FontWeight.w800,
                            height: 1.35,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _bank,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _isAr ? 'حفظ وإعادة الفحص' : 'Save & recheck',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
