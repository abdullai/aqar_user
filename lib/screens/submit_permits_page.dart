import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/permissions/runtime_permission_helper.dart';
import '../l10n/app_localizations.dart';
import '../main.dart' show suspendAutoLock;
import '../services/marketing_flow_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/field_group_frame.dart';
import '../widgets/government_in_app_web_page.dart';

/// رفع بيانات ترخيص الإعلان (REGA) + QR إلزامي — يُخزَّن في payload للـ RPC submit_permits.
class SubmitPermitsPage extends StatefulWidget {
  final String requestId;
  final String lang;

  const SubmitPermitsPage({
    super.key,
    required this.requestId,
    this.lang = 'ar',
  });

  @override
  State<SubmitPermitsPage> createState() => _SubmitPermitsPageState();
}

class _SubmitPermitsPageState extends State<SubmitPermitsPage> {
  final _licenseNo = TextEditingController();
  final _issueDate = TextEditingController();
  final _expiryDate = TextEditingController();
  final _falLicense = TextEditingController();
  final _deedDocNo = TextEditingController();
  final _notes = TextEditingController();
  final _marketerEntity = TextEditingController();
  final _marketerBrandImageUrl = TextEditingController();

  bool _saving = false;
  bool _showOwnerNameOnListing = true;
  bool _showMarketerBrandOnListing = false;
  bool _listingPrefsLoaded = false;
  Uint8List? _qrBytes;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  String _t(String a, String e) => _isAr ? a : e;

  static const _regaBrokerEntry =
      'https://eservicesredp.rega.gov.sa/auth/queries/Brokerage';

  @override
  void initState() {
    super.initState();
    _loadListingDisplayPrefs();
  }

  Future<void> _loadListingDisplayPrefs() async {
    final flow = MarketingFlowService(Supabase.instance.client);
    final show =
        await flow.propertyShowAdvertiserNameForRequest(widget.requestId);
    if (!mounted) return;
    setState(() {
      _showOwnerNameOnListing = show;
      _listingPrefsLoaded = true;
    });
  }

  @override
  void dispose() {
    _licenseNo.dispose();
    _issueDate.dispose();
    _expiryDate.dispose();
    _falLicense.dispose();
    _deedDocNo.dispose();
    _notes.dispose();
    _marketerEntity.dispose();
    _marketerBrandImageUrl.dispose();
    super.dispose();
  }

  Future<void> _openRega() async {
    final u = Uri.parse(_regaBrokerEntry);
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => GovernmentInAppWebViewPage(
          uri: u,
          title: _t(
            'الهيئة العامة للعقار — استعلامات الوساطة',
            'REGA — brokerage inquiries',
          ),
        ),
      ),
    );
  }

  Future<void> _pickQr() async {
    final t = AppLocalizations.of(context);
    if (t != null && context.mounted) {
      final ok = await RuntimePermissionHelper.ensurePhotos(context, t: t);
      if (!ok || !mounted) return;
    }
    suspendAutoLock.value = true;
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      setState(() {
        _qrBytes = bytes;
      });
    } finally {
      suspendAutoLock.value = false;
    }
  }

  Future<String?> _uploadQr(String uid) async {
    if (_qrBytes == null || _qrBytes!.isEmpty) return null;
    final path = 'listing-permits/${widget.requestId}/${uid}_${const Uuid().v4()}.jpg';
    await Supabase.instance.client.storage.from('property-images').uploadBinary(
          path,
          _qrBytes!,
          fileOptions: const FileOptions(
            upsert: false,
            contentType: 'image/jpeg',
          ),
        );
    return path;
  }

  Future<void> _submit() async {
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (uid.isEmpty) return;

    if (_licenseNo.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('أدخل رقم ترخيص الإعلان', 'Enter ad license number'))),
      );
      return;
    }
    if (_qrBytes == null || _qrBytes!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('أضف صورة رمز الاستجابة السريعة', 'Add QR code image'))),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final qrStoragePath = await _uploadQr(uid);
      final entityName = _marketerEntity.text.trim();
      final payload = <String, dynamic>{
        'rega_ad_license_number': _licenseNo.text.trim(),
        'rega_issue_date': _issueDate.text.trim(),
        'rega_expiry_date': _expiryDate.text.trim(),
        'fal_broker_license_number': _falLicense.text.trim(),
        'deed_or_benefit_doc_number': _deedDocNo.text.trim(),
        'notes': _notes.text.trim(),
        if (entityName.isNotEmpty) 'marketer_entity_display_name': entityName,
        'marketer_show_brand_on_listing': _showMarketerBrandOnListing,
        if (_marketerBrandImageUrl.text.trim().isNotEmpty)
          'marketer_brand_image_url': _marketerBrandImageUrl.text.trim(),
        if (qrStoragePath != null) 'ad_qr_storage_path': qrStoragePath,
        'source': 'app_submit_permits_v1',
      };

      final flow = MarketingFlowService(Supabase.instance.client);
      await flow.createOrUpdateListingPermit(
        requestId: widget.requestId,
        permitNo: _licenseNo.text.trim(),
        authorityName: 'REGA',
        licenseNo: _falLicense.text.trim(),
        notes: _notes.text.trim(),
        payload: payload,
        expiresAt: null,
      );
      await flow.updatePropertyShowAdvertiserNameForRequest(
        requestId: widget.requestId,
        showAdvertiserName: _showOwnerNameOnListing,
      );
      await flow.syncPropertyMarketingLicenseSnapshot(
        requestId: widget.requestId,
        permitPayload: payload,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('تم الإرسال', 'Submitted'))),
      );
      try {
        final req = await Supabase.instance.client
            .from('listing_requests')
            .select('owner_id')
            .eq('id', widget.requestId)
            .maybeSingle();
        final oid = (req?['owner_id'] ?? '').toString().trim();
        if (oid.isNotEmpty) {
          await flow.notifyOwnerPermitPackageSubmitted(
            ownerId: oid,
            requestId: widget.requestId,
          );
        }
      } catch (_) {}
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_t('خطأ', 'Error')}: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_t('إصدار التصاريح / ترخيص الإعلان', 'Permits & ad license')),
        ),
        body: _saving
            ? const Center(child: AppLogoLoading())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    _t(
                      'تُفتح بوابة الهيئة داخل التطبيق فقط. راجع البيانات ثم انسخ الحقول هنا. رمز الاستجابة السريعة إلزامي.',
                      'The authority portal opens inside the app only. Review data, then copy fields here. QR image is required.',
                    ),
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _openRega,
                    icon: const Icon(Icons.account_balance_outlined),
                    label: Text(
                      _t(
                        'بوابة الهيئة (داخل التطبيق)',
                        'REGA portal (in-app)',
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FieldGroupFrame(
                    title: _t('بيانات ترخيص الإعلان', 'Ad license details'),
                    subtitle: _t(
                      'انسخ الحقول من بوابة الهيئة بعد المراجعة.',
                      'Copy fields from the authority portal after review.',
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AqarTextField(
                          controller: _licenseNo,
                          decoration: InputDecoration(
                            labelText:
                                _t('رقم ترخيص الإعلان', 'Ad license number'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        AqarTextField(
                          controller: _issueDate,
                          decoration: InputDecoration(
                            labelText: _t(
                                'تاريخ الإصدار (يوم/شهر/سنة)', 'Issue date'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        AqarTextField(
                          controller: _expiryDate,
                          decoration: InputDecoration(
                            labelText: _t('تاريخ الانتهاء', 'Expiry date'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        AqarTextField(
                          controller: _falLicense,
                          decoration: InputDecoration(
                            labelText: _t(
                                'رقم رخصة فال للوساطة',
                                'FAL brokerage license no.'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        AqarTextField(
                          controller: _deedDocNo,
                          decoration: InputDecoration(
                            labelText: _t(
                                'رقم وثيقة الملكية / المنفعة',
                                'Deed / benefit doc no.'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        AqarTextField(
                          controller: _notes,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText:
                                _t('ملاحظات إضافية', 'Extra notes'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FieldGroupFrame(
                    title: _t('الكيان والعرض على البطاقة', 'Entity & card display'),
                    subtitle: _t(
                      'ما يظهر للمستخدم على بطاقة الإعلان.',
                      'What users see on the listing card.',
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AqarTextField(
                          controller: _marketerEntity,
                          decoration: InputDecoration(
                            labelText: _t(
                              'اسم المكتب / الشركة المسوقة (يظهر على البطاقة)',
                              'Marketer office / company (shown on listing card)',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _showMarketerBrandOnListing,
                          onChanged: _saving
                              ? null
                              : (v) => setState(
                                  () => _showMarketerBrandOnListing = v,
                                ),
                          title: Text(
                            _t(
                              'إظهار شعار المسوق على بطاقة الإعلان المنشور',
                              'Show marketer logo on published listing card',
                            ),
                          ),
                          subtitle: Text(
                            _t(
                              'عند التفعيل، أدخل رابط صورة (https) تظهر بجانب اسم الكيان.',
                              'When enabled, enter an image URL (https) shown next to the entity name.',
                            ),
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (_showMarketerBrandOnListing) ...[
                          const SizedBox(height: 8),
                          AqarTextField(
                            controller: _marketerBrandImageUrl,
                            keyboardType: TextInputType.url,
                            decoration: InputDecoration(
                              labelText: _t(
                                'رابط صورة الشعار (https)',
                                'Brand image URL (https)',
                              ),
                            ),
                          ),
                        ],
                        if (_listingPrefsLoaded) ...[
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _showOwnerNameOnListing,
                            onChanged: _saving
                                ? null
                                : (v) => setState(
                                      () => _showOwnerNameOnListing = v,
                                    ),
                            title: Text(
                              _t(
                                'إظهار اسم المالك على بطاقة الإعلان',
                                'Show owner name on the listing card',
                              ),
                            ),
                            subtitle: Text(
                              _t(
                                'يمكن للمالك لاحقًا طلب الإظهار من إعدادات تعديل إعلانه.',
                                'The owner can later request visibility from listing edit.',
                              ),
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FieldGroupFrame(
                    title: _t('رمز الاستجابة السريعة (QR) *', 'QR code *'),
                    subtitle: _t(
                      'صورة QR إلزامية لإتمام الإرسال.',
                      'QR image is required to submit.',
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _pickQr,
                          icon: const Icon(Icons.qr_code_2),
                          label: Text(_t('اختيار صورة QR', 'Pick QR image')),
                        ),
                        if (_qrBytes != null) ...[
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              _qrBytes!,
                              height: 140,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ],
                        const SizedBox(height: 28),
                        FilledButton.icon(
                          onPressed: _saving ? null : _submit,
                          icon: const Icon(Icons.send),
                          label:
                              Text(_t('إرسال للمراجعة', 'Submit for review')),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0F766E),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
