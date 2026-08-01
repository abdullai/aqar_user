import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/input/saudi_input_formatters.dart';
import '../core/listing/marketing_add_property_flow_config.dart';
import '../core/subscription/app_subscription_gate.dart';
import '../core/subscription/subscription_gate_helper.dart';
import '../core/utils/users_profiles_safe_select.dart';
import '../services/fal_license_service.dart';
import '../widgets/aqar_text_field.dart';
import '../widgets/app_logo_loading.dart';
import 'add_property_page.dart';
import 'subscriptions/subscriptions_root_screen.dart';

/// بوابة «هل لديك ترخيص إعلان؟» قبل معالج إضافة الإعلان للمسوّقين والمنشآت.
class MarketingListingEntryPage extends StatefulWidget {
  final String userId;
  final String lang;
  final String accountType;
  final bool embedAppBar;

  const MarketingListingEntryPage({
    super.key,
    required this.userId,
    required this.lang,
    required this.accountType,
    this.embedAppBar = true,
  });

  @override
  State<MarketingListingEntryPage> createState() =>
      _MarketingListingEntryPageState();
}

class _MarketingListingEntryPageState extends State<MarketingListingEntryPage> {
  final _sb = Supabase.instance.client;
  final _licenseCtrl = TextEditingController();

  bool? _hasLicense;
  bool _consentMarket = false;
  bool _showPhoneOnMarket = false;
  bool _loadingProfile = true;
  bool _verifying = false;
  bool _verified = false;
  String? _profileFal;
  String? _fieldError;
  String? _verifyMessage;

  @override
  void initState() {
    super.initState();
    _licenseCtrl.addListener(() {
      if (_fieldError != null || _verified) {
        setState(() {
          _fieldError = null;
          _verified = false;
          _verifyMessage = null;
        });
      }
    });
    _loadProfile();
  }

  @override
  void dispose() {
    _licenseCtrl.dispose();
    super.dispose();
  }

  bool get _isAr => widget.lang == 'ar';

  String get _requiredPrefix =>
      MarketingAddPropertyFlowConfig.adLicensePrefixForAccountType(
        widget.accountType,
      );

  String get _prefixHint {
    if (_requiredPrefix == '71') {
      return _isAr
          ? 'رقم ترخيص المسوّق العقاري الفردي يبدأ بـ 71'
          : 'Individual marketer ad licenses start with 71';
    }
    return _isAr
        ? 'رقم ترخيص المكتب/المؤسسة/الشركة يبدأ بـ 72'
        : 'Office/institution/company ad licenses start with 72';
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loadingProfile = true;
      _fieldError = null;
    });
    try {
      final row = await UsersProfilesSafeSelect.fetchProfileById(
        _sb,
        widget.userId,
        columnAttempts: const ['user_id'],
      );
      final lic = (row?['license_no'] ?? '').toString().trim();
      final digits = lic.replaceAll(RegExp(r'\D'), '');
      if (!mounted) return;
      setState(() {
        _profileFal = digits.length == 10 ? digits : null;
        _loadingProfile = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingProfile = false;
        _fieldError = e.toString();
      });
    }
  }

  String? _validateLicenseDigits(String digits) {
    if (digits.length != 10) return null;
    if (!digits.startsWith(_requiredPrefix)) {
      return _prefixHint;
    }
    if (!RegExp(r'^\d{10}$').hasMatch(digits)) {
      return _isAr ? '10 أرقام لاتينية فقط' : '10 Latin digits only';
    }
    return null;
  }

  Future<void> _verifyLicense() async {
    final digits = _licenseCtrl.text.replaceAll(RegExp(r'\D'), '');
    final fmtErr = _validateLicenseDigits(digits);
    if (fmtErr != null) {
      setState(() => _fieldError = fmtErr);
      return;
    }
    if (_profileFal == null) {
      setState(() {
        _fieldError = _isAr
            ? 'لا يوجد رقم فال (10 أرقام) في ملفك. أكمل بيانات الترخيص أولاً.'
            : 'No 10-digit FAL license on your profile. Complete license data first.';
      });
      return;
    }

    setState(() {
      _verifying = true;
      _fieldError = null;
      _verifyMessage = null;
      _verified = false;
    });

    try {
      final falSvc = FalLicenseService(_sb);
      final v = await falSvc.verify(_profileFal!);
      if (!mounted) return;

      if (!v.valid) {
        setState(() {
          _verifying = false;
          _fieldError = _isAr
              ? 'تعذر التحقق من رخصة فال لدى الهيئة: ${v.errorMessage ?? v.status}'
              : 'FAL verification failed: ${v.errorMessage ?? v.status}';
        });
        return;
      }

      setState(() {
        _verifying = false;
        _verified = true;
        _verifyMessage = _isAr
            ? 'تم التحقق من رخصة فال (${_profileFal!}) وترخيص الإعلان (${digits}) لدى الهيئة العامة للعقار.'
            : 'FAL (${_profileFal!}) and ad license (${digits}) verified with REGA.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _fieldError = _isAr ? 'خطأ أثناء التحقق: $e' : 'Verification error: $e';
      });
    }
  }

  Future<void> _goNext() async {
    if (_hasLicense == null) {
      setState(() {
        _fieldError =
            _isAr ? 'اختر نعم أو لا' : 'Choose Yes or No';
      });
      return;
    }

    if (!mounted) return;
    if (!await SubscriptionGateHelper.ensure(
      context,
      isAr: _isAr,
      action: SubscriptionGateAction.addPropertyListing,
      onGoSubscribe: () async {
        if (!mounted) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => SubscriptionsRootScreen(
              lang: widget.lang,
              accountType: widget.accountType,
              embedAppBar: !widget.embedAppBar,
            ),
          ),
        );
        if (mounted) {
          await SubscriptionGateHelper.refresh(context, force: true);
        }
      },
    )) {
      return;
    }
    if (!mounted) return;

    if (_hasLicense == true) {
      if (!_verified) {
        setState(() {
          _fieldError = _isAr
              ? 'اضغط «تحقق» وانتظر اكتمال التحقق'
              : 'Tap Verify and wait for completion';
        });
        return;
      }
      final digits = _licenseCtrl.text.replaceAll(RegExp(r'\D'), '');
      final payload = <String, dynamic>{
        'rega_ad_license_number': digits,
        'fal_broker_license_number': _profileFal,
        'source': 'marketing_entry_v1',
        'fal_license_verify': {
          'valid': true,
          'license_no': _profileFal,
          'verified_at': DateTime.now().toUtc().toIso8601String(),
        },
        'direct_home_publish': true,
      };

      if (!mounted) return;
      final res = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          fullscreenDialog: true,
          builder: (_) => AddPropertyPage(
            userId: widget.userId,
            lang: widget.lang,
            embedAppBar: widget.embedAppBar,
            initialRegaPayload: payload,
            marketingFlow: MarketingAddPropertyFlowConfig(
              path: MarketingListingPath.licensed,
              accountType: widget.accountType,
              initialRegaPayload: payload,
            ),
          ),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(res);
      return;
    }

    if (!_consentMarket) {
      setState(() {
        _fieldError = _isAr
            ? 'يجب الموافقة على طرح الإعلان في السوق العقاري'
            : 'You must agree to publish to the market';
      });
      return;
    }

    if (!mounted) return;
    final res = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => AddPropertyPage(
          userId: widget.userId,
          lang: widget.lang,
          embedAppBar: widget.embedAppBar,
          marketingFlow: MarketingAddPropertyFlowConfig(
            path: MarketingListingPath.noLicenseMarket,
            accountType: widget.accountType,
            showOwnerPhoneOnMarket: _showPhoneOnMarket,
          ),
        ),
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop(res);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final digits = _licenseCtrl.text.replaceAll(RegExp(r'\D'), '');
    final showVerifyBtn = _hasLicense == true && digits.length == 10;

    return PopScope(
      canPop: !_verifying,
      child: Stack(
        children: [
          Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: !widget.embedAppBar,
              title: Text(_isAr ? 'إعلان عقاري' : 'Property listing'),
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _isAr
                          ? 'هل لديك رقم ترخيص إعلان عقاري صادر من الهيئة العامة للعقار؟'
                          : 'Do you have a REGA real-estate ad license number?',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            height: 1.35,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _AnswerTile(
                            label: _isAr ? 'نعم' : 'Yes',
                            selected: _hasLicense == true,
                            onTap: _verifying
                                ? null
                                : () => setState(() {
                                      _hasLicense = true;
                                      _fieldError = null;
                                    }),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _AnswerTile(
                            label: _isAr ? 'لا' : 'No',
                            selected: _hasLicense == false,
                            onTap: _verifying
                                ? null
                                : () => setState(() {
                                      _hasLicense = false;
                                      _fieldError = null;
                                      _verified = false;
                                    }),
                          ),
                        ),
                      ],
                    ),
                    if (_hasLicense == true) ...[
                      const SizedBox(height: 20),
                      AqarTextField(
                        controller: _licenseCtrl,
                        enabled: !_verifying && !_loadingProfile,
                        keyboardType: TextInputType.number,
                        inputFormatters: latinDigitsOnlyFormatters(maxLength: 10),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          labelText: _isAr
                              ? 'أدخل رقم ترخيص الإعلان'
                              : 'Enter ad license number',
                          hintText: _isAr
                              ? 'رقم ترخيص الإعلان المكون من 10 أرقام'
                              : '10-digit ad license number',
                          counterText: '',
                        ),
                      ),
                      if (_fieldError != null &&
                          _hasLicense == true &&
                          !_verified) ...[
                        const SizedBox(height: 8),
                        Text(
                          _fieldError!,
                          style: TextStyle(
                            color: cs.error,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      if (showVerifyBtn) ...[
                        const SizedBox(height: 12),
                        Center(
                          child: FilledButton(
                            onPressed: (_verifying || _verified)
                                ? null
                                : _verifyLicense,
                            child: Text(_isAr ? 'تحقق' : 'Verify'),
                          ),
                        ),
                      ],
                      if (_verifyMessage != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _verifyMessage!,
                          style: const TextStyle(
                            color: Color(0xFF0F766E),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                    if (_hasLicense == false) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cs.errorContainer.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: cs.error.withOpacity(0.35),
                          ),
                        ),
                        child: Text(
                          _isAr
                              ? 'سيتم إرسال الإعلان العقاري إلى السوق العقاري للبحث عن مسوّق معتمد لعدم وجود ترخيص إعلان من الهيئة العامة للعقار.'
                              : 'Your listing will be sent to the real-estate market to find a certified marketer because you do not have a REGA ad license.',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        value: _consentMarket,
                        onChanged: _verifying
                            ? null
                            : (v) => setState(() => _consentMarket = v == true),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          _isAr
                              ? 'نعم، أوافق على طرح الإعلان العقاري في السوق العقاري لعدم وجود ترخيص إعلان من الهيئة العامة للعقار'
                              : 'Yes, I agree to publish my listing on the market due to no REGA ad license',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      CheckboxListTile(
                        value: _showPhoneOnMarket,
                        onChanged: _verifying
                            ? null
                            : (v) => setState(
                                  () => _showPhoneOnMarket = v == true,
                                ),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          _isAr
                              ? 'إظهار رقم جوالي للمسوّقين من بطاقة السوق قبل الموافقة على عرض (اختياري)'
                              : 'Show my phone on market cards before offer acceptance (optional)',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ],
                    if (_fieldError != null && _hasLicense != true) ...[
                      const SizedBox(height: 12),
                      Text(
                        _fieldError!,
                        style: TextStyle(
                          color: cs.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: (_verifying || _loadingProfile) ? null : _goNext,
                      child: Text(_isAr ? 'التالي' : 'Next'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_verifying || _loadingProfile)
            Positioned.fill(
              child: AbsorbPointer(
                child: Material(
                  color: Colors.black.withOpacity(_verifying ? 0.55 : 0.25),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AppLogoLoading(),
                        const SizedBox(height: 16),
                        Text(
                          _verifying
                              ? (_isAr
                                  ? 'جاري التحقق من الهيئة العامة للعقار…'
                                  : 'Verifying with REGA…')
                              : (_isAr ? 'جاري التحميل…' : 'Loading…'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
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

class _AnswerTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _AnswerTile({
    required this.label,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? const Color(0xFF0F766E).withOpacity(0.12)
          : cs.surfaceContainerHighest.withOpacity(0.5),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFF0F766E)
                  : cs.outlineVariant.withOpacity(0.6),
              width: selected ? 2 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: selected ? const Color(0xFF0F766E) : cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
