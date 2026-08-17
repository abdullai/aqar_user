import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/input/saudi_input_formatters.dart';
import '../l10n/app_localizations.dart';
import '../services/fal_license_service.dart';
import '../services/profile_compliance_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/field_group_frame.dart';

/// يظهر عند انتهاء رخصة فال أو تجميد الامتثال — زر واحد يعيد الاستعلام من REGA.
class FalRenewalGateScreen extends StatefulWidget {
  const FalRenewalGateScreen({
    super.key,
    required this.lang,
    required this.onRenewed,
  });

  final String lang;
  final VoidCallback onRenewed;

  @override
  State<FalRenewalGateScreen> createState() => _FalRenewalGateScreenState();
}

class _FalRenewalGateScreenState extends State<FalRenewalGateScreen> {
  final _fal = TextEditingController();
  bool _busy = false;
  String? _err;
  final _falSvc = FalLicenseService(Supabase.instance.client);

  @override
  void dispose() {
    _fal.dispose();
    super.dispose();
  }

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  Future<void> _lookupAndSave() async {
    final t = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _err = null;
    });
    final res = await _falSvc.verify(_fal.text);
    if (!mounted) return;
    if (!res.valid || res.isExpired) {
      setState(() {
        _busy = false;
        _err = res.isExpired
            ? (t?.falRenewalExpired ?? 'الرخصة منتهية.')
            : (res.errorMessage ??
                t?.falRenewalInvalid ??
                'تعذر التحقق من الرخصة.');
      });
      return;
    }
    DateTime? exp;
    if (res.endDateIso != null && res.endDateIso!.isNotEmpty) {
      exp = DateTime.tryParse(res.endDateIso!);
    }
    try {
      await ProfileComplianceService.applyFalRenewal(
        sb: Supabase.instance.client,
        licenseDigits: _fal.text.replaceAll(RegExp(r'\D'), ''),
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
    } catch (e) {
      setState(() {
        _busy = false;
        _err = '$e';
      });
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onRenewed();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t?.falRenewalTitle ?? 'تجديد رخصة فال'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(
            children: [
              Text(
                t?.falRenewalBody ??
                    'انتهت صلاحية رخصة فال أو يتطلب الحساب تحديثها. أدخل الرقم واضغط تحقق.',
                style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4),
              ),
              const SizedBox(height: 20),
              FieldGroupFrame(
                title: t?.fieldGroupFalRenewalTitle,
                subtitle: t?.fieldGroupFalRenewalSubtitle,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AqarTextField(
                      controller: _fal,
                      keyboardType: TextInputType.number,
                      maxLength: 10,
                      inputFormatters: [
                        ArabicDigitsToLatinFormatter(),
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: t?.verFalLicenseLabel,
                        hintText: t?.verFalLicenseHint,
                        counterText: '',
                      ),
                    ),
                    if (_err != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _err!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: _busy ? null : _lookupAndSave,
                        child: _busy
                            ? const AppLogoLoading(compact: true, size: 28)
                            : Text(t?.falRenewalSubmit ?? 'تحقق وتحديث'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
