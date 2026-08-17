import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/input/input_normalizers.dart';
import '../core/utils/compound_display_name.dart';
import '../core/utils/profile_greeting_from_row.dart';
import '../services/account_completion_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/field_group_frame.dart';

/// استكمال الحقول الناقصة — الرقم الوطني الموحّد، واسم الظهور إن كان المعرّف رقمياً، والجوال إن نقص.
class MandatoryDataCompletionScreen extends StatefulWidget {
  final String lang;
  final VoidCallback onDone;

  const MandatoryDataCompletionScreen({
    super.key,
    required this.lang,
    required this.onDone,
  });

  @override
  State<MandatoryDataCompletionScreen> createState() =>
      _MandatoryDataCompletionScreenState();
}

class _MandatoryDataCompletionScreenState
    extends State<MandatoryDataCompletionScreen> {
  static const Color _bankColor = Color(0xFF0F766E);

  final _nationalCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _busy = false;
  String? _err;
  Map<String, dynamic>? _row;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  bool get _needName =>
      AccountCompletionService.needsDisplayNameCompletion(_row, isAr: _isAr);

  bool get _needPhone {
    final ph = digitsOnly(
      normalizeAsciiDigits((_row?['phone'] ?? '').toString()),
    );
    return ph.length < 10;
  }

  bool get _needNational =>
      AccountCompletionService.needsUnifiedNationalCompletion(_row);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await AccountCompletionService.loadRow(Supabase.instance.client);
    if (!mounted) return;
    final existingName =
        ProfileGreetingFromRow.displayName(r ?? const {}, isAr: _isAr)?.trim() ??
            '';
    final un = (r?['username'] ?? '').toString().trim();
    final seedName =
        CompoundDisplayName.looksLikeNumericUsername(existingName) ||
                existingName == un
            ? ''
            : existingName;
    final ph = digitsOnly(
      normalizeAsciiDigits((r?['phone'] ?? '').toString()),
    );
    setState(() {
      _row = r;
      if (seedName.isNotEmpty) _nameCtrl.text = seedName;
      if (ph.length >= 10) _phoneCtrl.text = ph;
      final unn = digitsOnly(
        normalizeAsciiDigits(
          (r?['unified_national_number'] ?? '').toString(),
        ),
      );
      if (isValidUnifiedNationalNumberDigits(unn)) {
        _nationalCtrl.text = unn;
      }
    });
  }

  @override
  void dispose() {
    _nationalCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final sb = Supabase.instance.client;
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
      if (_needPhone) {
        await AccountCompletionService.savePhone(
          sb: sb,
          phoneRaw: _phoneCtrl.text,
        );
      }
      if (_needNational) {
        await AccountCompletionService.saveUnifiedNational(
          sb: sb,
          tenDigits700: _nationalCtrl.text,
        );
      }
      if (!mounted) return;
      widget.onDone();
    } catch (e) {
      if (!mounted) return;
      final code = e.toString();
      setState(() {
        _busy = false;
        if (code.contains('invalid_name')) {
          _err = _isAr
              ? 'أدخل اسم ظهور نصّي (وليس أرقاماً فقط).'
              : 'Enter a text display name (not digits only).';
        } else if (code.contains('invalid_phone')) {
          _err = _isAr
              ? 'رقم الجوال غير صالح (10 أرقام على الأقل).'
              : 'Phone number is invalid (at least 10 digits).';
        } else if (code.contains('invalid_unified') || _needNational) {
          _err = _isAr
              ? 'الرقم الوطني الموحّد يجب أن يكون 10 أرقام تبدأ بـ 700.'
              : 'Unified national number must be 10 digits starting with 700.';
        } else {
          _err = _isAr ? 'تعذر الحفظ. أعد المحاولة.' : 'Could not save. Try again.';
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_err!)),
        );
      }
    }
  }

  Widget _roField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          AqarTextField(
            controller: TextEditingController(text: value),
            readOnly: true,
            decoration: const InputDecoration(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final un = _row == null
        ? ''
        : digitsOnly(
            normalizeAsciiDigits(
              (_row!['username'] ?? '').toString(),
            ),
          );
    final lic = _row == null
        ? ''
        : digitsOnly(
            normalizeAsciiDigits(
              (_row!['license_no'] ?? '').toString(),
            ),
          );
    final displayHint = _row == null
        ? ''
        : (ProfileGreetingFromRow.displayName(_row!, isAr: _isAr) ?? '');

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isAr ? 'استكمال البيانات' : 'Complete your profile',
          ),
        ),
        body: _row == null
            ? const Center(child: AppLogoLoading())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    _isAr
                        ? 'أكمل الحقول الناقصة أدناه للمتابعة. الحقول المكتملة تظهر للقراءة فقط.'
                        : 'Complete the missing fields below to continue. Completed fields are read-only.',
                    style: const TextStyle(height: 1.35, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  if (displayHint.isNotEmpty &&
                      !CompoundDisplayName.looksLikeNumericUsername(displayHint) &&
                      !_needName)
                    _roField(
                      _isAr ? 'اسم الظهور المستعار' : 'Display alias',
                      CompoundDisplayName.normalize(displayHint),
                    ),
                  if (!_needPhone &&
                      digitsOnly(
                            normalizeAsciiDigits(
                              (_row?['phone'] ?? '').toString(),
                            ),
                          ).length >=
                          10)
                    _roField(
                      _isAr ? 'الجوال الأساسي (ثابت)' : 'Primary phone (locked)',
                      digitsOnly(
                        normalizeAsciiDigits((_row?['phone'] ?? '').toString()),
                      ),
                    ),
                  if (un.length == 10)
                    _roField(
                      _isAr ? 'اسم المستخدم (الهوية)' : 'Username (ID)',
                      un,
                    ),
                  if (lic.length >= 8)
                    _roField(
                      _isAr ? 'رخصة فال المسجّلة' : 'FAL license on file',
                      lic,
                    ),
                  if (_needName) ...[
                    FieldGroupFrame(
                      title: _isAr ? 'اسم الظهور المستعار' : 'Display alias',
                      subtitle: _isAr
                          ? 'للظهور على البطاقات عند اختيار المستعار. الاسم/الصفة المعتمدة تُستكمل من الإعدادات إن نقصت.'
                          : 'Used on cards when alias is selected. Official name is completed in Settings if missing.',
                      child: AqarTextField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          hintText: _isAr
                              ? 'مثال: اسم مختصر للظهور'
                              : 'e.g. short public alias',
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_needPhone) ...[
                    FieldGroupFrame(
                      title: _isAr ? 'الجوال الأساسي' : 'Primary phone',
                      subtitle: _isAr
                          ? 'يُسجّل مرة واحدة ويصبح ثابتاً — للإضافي استخدم الإعدادات لاحقاً'
                          : 'Saved once then locked — use Settings later for an extra phone',
                      child: AqarTextField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9٠-٩۰-۹+]'),
                          ),
                          LengthLimitingTextInputFormatter(16),
                        ],
                        decoration: InputDecoration(
                          hintText: _isAr ? '05xxxxxxxx' : '05xxxxxxxx',
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_needNational)
                    FieldGroupFrame(
                      title: _isAr
                          ? 'الرقم الوطني الموحّد'
                          : 'Unified national number',
                      subtitle: _isAr
                          ? 'عشرة أرقام تبدأ بـ 700 (ليس رقم السجل التجاري)'
                          : '10 digits starting with 700 (not commercial registry)',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AqarTextField(
                            controller: _nationalCtrl,
                            keyboardType: TextInputType.text,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9٠-٩۰-۹\u0646]'),
                              ),
                              LengthLimitingTextInputFormatter(13),
                            ],
                            decoration: InputDecoration(
                              hintText: _isAr
                                  ? 'مثال: ن7001234567 أو 7001234567'
                                  : 'e.g. 7001234567',
                            ),
                          ),
                          if (_err != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _err!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (!_needNational && !_needName && !_needPhone) ...[
                    Text(
                      _isAr
                          ? 'لا توجد حقول ناقصة في هذه الشاشة. اضغط متابعة.'
                          : 'Nothing missing on this screen. Tap continue.',
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _bankColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _busy ? null : _save,
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _isAr ? 'حفظ ومتابعة' : 'Save & continue',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
