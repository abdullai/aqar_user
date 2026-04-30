import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/input/saudi_input_formatters.dart';
import '../core/utils/users_profiles_safe_select.dart';
import '../screens/rega_ad_license_import_page.dart';
import '../services/fal_license_service.dart';
import 'app_logo_loading.dart';

String _digitsOnly(String? s) => (s ?? '').replaceAll(RegExp(r'\D'), '');

/// قبل إضافة إعلان من حساب مسوّق/منشأة: التحقق من رقم ترخيص الإعلان ومطابقة رقم فال مع الملف.
Future<Map<String, dynamic>?> showRegaAdLicenseGate({
  required BuildContext context,
  required bool isAr,
  required SupabaseClient sb,
}) async {
  return showModalBottomSheet<Map<String, dynamic>?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    isDismissible: true,
    enableDrag: true,
    builder: (ctx) => _RegaAdLicenseGateBody(
      isAr: isAr,
      sb: sb,
    ),
  );
}

class _RegaAdLicenseGateBody extends StatefulWidget {
  final bool isAr;
  final SupabaseClient sb;

  const _RegaAdLicenseGateBody({
    required this.isAr,
    required this.sb,
  });

  @override
  State<_RegaAdLicenseGateBody> createState() => _RegaAdLicenseGateBodyState();
}

class _RegaAdLicenseGateBodyState extends State<_RegaAdLicenseGateBody> {
  final _adLicenseCtrl = TextEditingController();
  final _pasteCtrl = TextEditingController();
  Map<String, dynamic>? _importedMap;
  bool _loading = true;
  bool _submitting = false;
  String? _profileLicense;
  String? _err;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _adLicenseCtrl.dispose();
    _pasteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final uid = widget.sb.auth.currentUser?.id;
      if (uid == null || uid.isEmpty) {
        setState(() {
          _profileLicense = null;
          _loading = false;
          _err = widget.isAr ? 'يجب تسجيل الدخول' : 'You must be signed in';
        });
        return;
      }
      final row = await UsersProfilesSafeSelect.fetchProfileById(
        widget.sb,
        uid,
        columnAttempts: const [
          'user_id',
        ],
      );
      final lic = (row?['license_no'] ?? '').toString().trim();
      setState(() {
        _profileLicense = lic.isEmpty ? null : lic;
        _loading = false;
        if (_profileLicense == null) {
          _err = widget.isAr
              ? 'لا يوجد رقم رخصة فال محفوظ في ملفك. أكمل بيانات الترخيص أولاً.'
              : 'No FAL license on file. Complete your license first.';
        }
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _err = e.toString();
      });
    }
  }

  Future<void> _openImport() async {
    final m = kIsWeb
        ? await showRegaElanImportWebDialog(context, isAr: widget.isAr)
        : await Navigator.of(context).push<Map<String, dynamic>?>(
            MaterialPageRoute<Map<String, dynamic>?>(
              builder: (_) => RegaAdLicenseImportPage(isAr: widget.isAr),
            ),
          );
    if (!mounted) return;
    if (m == null || m.isEmpty) return;
    setState(() {
      _importedMap = Map<String, dynamic>.from(m);
      final ad = (m['rega_ad_license_number'] ?? '').toString().trim();
      if (ad.isNotEmpty) _adLicenseCtrl.text = ad;
    });
  }

  Future<void> _continue() async {
    if (_profileLicense == null) return;
    final profDig = _digitsOnly(_profileLicense);
    if (profDig.length != 10) {
      setState(() {
        _err = widget.isAr
            ? 'رقم فال في ملفك غير مكتمل (10 أرقام). حدّث الملف.'
            : 'Your FAL license must be 10 digits.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _err = null;
    });

    try {
      final pasted = _pasteCtrl.text.trim();
      final parsed = <String, dynamic>{};
      if (_importedMap != null) {
        parsed.addAll(_importedMap!);
      }
      if (pasted.isNotEmpty) {
        parsed.addAll(
          RegaAdLicenseImportPage.parsePayloadFromPastedPageText(pasted),
        );
      }

      final falFromParse =
          (parsed['fal_broker_license_number'] ?? '').toString().trim();
      final falDig = _digitsOnly(falFromParse.isNotEmpty ? falFromParse : null);

      if (falDig.isEmpty) {
        setState(() {
          _submitting = false;
          _err = widget.isAr
              ? 'لم يُستخرج رقم فال من النص. الصق نص صفحة «تفاصيل ترخيص الإعلان» من منصة الهيئة، أو استخدم «استيراد من المنصة».'
              : 'FAL number not found. Paste the REGA details page text or use import.';
        });
        return;
      }

      if (falDig != profDig) {
        setState(() {
          _submitting = false;
          _err = widget.isAr
              ? 'رقم فال في ترخيص الإعلان ($falDig) لا يطابق رقم فال في ملفك ($profDig).'
              : 'FAL on the ad license ($falDig) does not match your profile FAL ($profDig).';
        });
        return;
      }

      final falSvc = FalLicenseService(widget.sb);
      final v = await falSvc.verify(profDig);
      if (!v.valid) {
        setState(() {
          _submitting = false;
          _err = widget.isAr
              ? 'تعذر التحقق من رخصة فال: ${v.errorMessage ?? v.status}'
              : 'FAL verification failed: ${v.errorMessage ?? v.status}';
        });
        return;
      }

      final adTyped = _digitsOnly(_adLicenseCtrl.text.trim());
      final adParsed = _digitsOnly(
        (parsed['rega_ad_license_number'] ?? '').toString(),
      );
      if (adParsed.isEmpty) {
        setState(() {
          _submitting = false;
          _err = widget.isAr
              ? 'لم يُستخرج رقم ترخيص الإعلان. أعد لصق النص أو الاستيراد.'
              : 'Ad license number missing in pasted data.';
        });
        return;
      }

      if (adTyped.isNotEmpty && adTyped != adParsed) {
        setState(() {
          _submitting = false;
          _err = widget.isAr
              ? 'رقم ترخيص الإعلان المدخل لا يطابق المستخرج من النص.'
              : 'Typed ad license does not match pasted details.';
        });
        return;
      }

      final out = Map<String, dynamic>.from(parsed);
      out['rega_ad_license_number'] = adParsed;
      out['fal_broker_license_number'] = falDig;
      out['source'] = 'rega_gate_v1';

      if (!mounted) return;
      setState(() => _submitting = false);

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(
            widget.isAr ? 'تم التحقق' : 'Verified',
          ),
          content: Text(
            widget.isAr
                ? 'شكراً لك. تم التحقق من رخصة الإعلان لدى الجهات الحكومية والمعنية. سيتم نقل البيانات إلى نموذج إضافة الإعلان فوراً.'
                : 'Thank you. Your ad license was verified with the relevant authorities. Data will be transferred to the listing form.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(widget.isAr ? 'إكمال' : 'Continue'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop(out);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _err = widget.isAr
              ? 'حدث خطأ أثناء التحقق: $e'
              : 'Verification error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;

    if (_loading) {
      return Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
        child: const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return PopScope(
      canPop: !_submitting && !_loading,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              bottom: 20 + bottom,
              top: 8,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.isAr
                        ? 'ترخيص الإعلان (الهيئة العامة للعقار)'
                        : 'REGA ad license',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.isAr
                        ? 'لا يُفتح متصفح خارجي. يمكنك استيراد صفحة التفاصيل داخل التطبيق أو لصق نص الصفحة. يجب أن يطابق رقم فال في الترخيص رقم فال المحفوظ في ملفك.'
                        : 'No external browser. Import the details page in-app or paste page text. FAL on the license must match your profile.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                  if (_err != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _err!,
                      style: TextStyle(
                        color: cs.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: _adLicenseCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: latinDigitsOnlyFormatters(maxLength: 10),
                    decoration: InputDecoration(
                      labelText: widget.isAr
                          ? 'رقم ترخيص الإعلان (10 أرقام)'
                          : 'Ad license no. (10 digits)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pasteCtrl,
                    minLines: 4,
                    maxLines: 10,
                    decoration: InputDecoration(
                      alignLabelWithHint: true,
                      labelText: widget.isAr
                          ? 'الصق هنا نص صفحة تفاصيل ترخيص الإعلان من الهيئة'
                          : 'Paste REGA Elan details page text',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _submitting ? null : _openImport,
                    icon: const Icon(Icons.shield_outlined),
                    label: Text(
                      widget.isAr
                          ? 'استيراد من بوابة الهيئة (داخل التطبيق)'
                          : 'Import from REGA (in-app)',
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: (_submitting || _profileLicense == null)
                        ? null
                        : _continue,
                    child: Text(
                      widget.isAr ? 'متابعة إلى إضافة الإعلان' : 'Continue',
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_submitting)
            Positioned.fill(
              child: AbsorbPointer(
                child: Material(
                  color: Colors.black.withOpacity(0.55),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const AppLogoLoading(),
                          const SizedBox(height: 20),
                          Text(
                            widget.isAr
                                ? 'الرجاء الانتظار… جاري التأكد من رخصة الإعلان لدى الجهات الحكومية والمعنية.'
                                : 'Please wait… Verifying your ad license with the competent authorities.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
