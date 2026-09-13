import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../main.dart' show langNotifier;
import '../services/org_team_service.dart';
import '../services/photographer_service.dart';
import 'photographer_hub_page.dart';
import 'photographer_join_page.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/app_page_close_button.dart';

/// إعدادات المنشأة: بيانات العرض العام فقط (الاشتراك/فال/المقاعد في تبويب الاشتراكات).
class OrganizationSettingsScreen extends StatefulWidget {
  const OrganizationSettingsScreen({
    super.key,
    this.embedAppBar = false,
  });

  final bool embedAppBar;

  @override
  State<OrganizationSettingsScreen> createState() =>
      _OrganizationSettingsScreenState();
}

class _OrganizationSettingsScreenState extends State<OrganizationSettingsScreen> {
  final _svc = OrgTeamService(Supabase.instance.client);

  final _nameAr = TextEditingController();
  final _nameEn = TextEditingController();
  final _descAr = TextEditingController();
  final _descEn = TextEditingController();
  final _addrAr = TextEditingController();
  final _addrEn = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _logoUrl = TextEditingController();
  final _coverUrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  bool get _isAr => langNotifier.value != 'en';

  @override
  void dispose() {
    _nameAr.dispose();
    _nameEn.dispose();
    _descAr.dispose();
    _descEn.dispose();
    _addrAr.dispose();
    _addrEn.dispose();
    _email.dispose();
    _phone.dispose();
    _logoUrl.dispose();
    _coverUrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await _svc.ensureMyOrgUnit();
    final org = await _svc.orgUnitForOwner();
    final id = org?['id']?.toString();
    if (id != null && id.isNotEmpty) {
      final p = await _svc.publicOrganizationProfile(id);
      if (p != null) {
        _nameAr.text = '${p['display_name_ar'] ?? ''}';
        _nameEn.text = '${p['display_name_en'] ?? ''}';
        _descAr.text = '${p['description_ar'] ?? ''}';
        _descEn.text = '${p['description_en'] ?? ''}';
        _addrAr.text = '${p['address_ar'] ?? ''}';
        _addrEn.text = '${p['address_en'] ?? ''}';
        _email.text = '${p['org_public_email'] ?? ''}';
        _phone.text = '${p['org_public_phone'] ?? ''}';
        _logoUrl.text = '${p['logo_url'] ?? ''}';
        _coverUrl.text = '${p['cover_url'] ?? ''}';
      }
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  int get _completeness {
    final filled = [
      _nameAr,
      _nameEn,
      _descAr,
      _addrAr,
      _email,
      _phone,
    ].where((c) => c.text.trim().isNotEmpty).length;
    return ((filled / 6) * 100).round();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final patch = <String, dynamic>{
      'display_name_ar': _nameAr.text.trim(),
      'display_name_en': _nameEn.text.trim(),
      'description_ar': _descAr.text.trim(),
      'description_en': _descEn.text.trim(),
      'address_ar': _addrAr.text.trim(),
      'address_en': _addrEn.text.trim(),
      'org_public_email': _email.text.trim(),
      'org_public_phone': _phone.text.trim(),
      'logo_url': _logoUrl.text.trim(),
      'cover_url': _coverUrl.text.trim(),
    };
    try {
      final res = await _svc.updateOrgProfile(patch);
      if (!mounted) return;
      if (res['ok'] == false) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${res['error'] ?? (_isAr ? 'تعذر الحفظ' : 'Save failed')}',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isAr ? 'تم الحفظ' : 'Saved')),
        );
        await _load();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _lbl(String ar, String en) => _isAr ? ar : en;

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? helper,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AqarTextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 2,
          alignLabelWithHint: maxLines > 1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final previewName = _isAr
        ? (_nameAr.text.trim().isNotEmpty
            ? _nameAr.text.trim()
            : _nameEn.text.trim())
        : (_nameEn.text.trim().isNotEmpty
            ? _nameEn.text.trim()
            : _nameAr.text.trim());

    return Scaffold(
      appBar: widget.embedAppBar
          ? null
          : AppBar(
              automaticallyImplyLeading: false,
              leading: AppPageCloseButton(isArabic: _isAr),
              title: Text(t.orgSettingsTitle),
            ),
      body: _loading
          ? const Center(child: AppLogoLoading())
          : SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    color: cs.primaryContainer.withValues(alpha: 0.35),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 44,
                            height: 44,
                            child: CircularProgressIndicator(
                              value: _completeness / 100,
                              strokeWidth: 5,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _lbl(
                                    'اكتمال ملف المنشأة $_completeness٪',
                                    'Profile completeness $_completeness%',
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  _lbl(
                                    'الاسم والوصف والعنوان والتواصل تظهر للعملاء.',
                                    'Name, description, address and contact appear to clients.',
                                  ),
                                  style: TextStyle(
                                    color: cs.onSurfaceVariant,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.photo_camera_outlined),
                      title: Text(
                        t.photographerJoinCta,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(t.photographerReviewSla),
                      onTap: () async {
                        PhotographerProfile? p;
                        try {
                          p = await PhotographerService(
                            Supabase.instance.client,
                          ).myProfile();
                        } catch (_) {}
                        if (!context.mounted) return;
                        final lang = langNotifier.value;
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => p != null && p.isVerified
                                ? PhotographerHubPage(lang: lang)
                                : PhotographerJoinPage(lang: lang),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          previewName.isEmpty
                              ? '—'
                              : String.fromCharCodes(previewName.runes.take(1)),
                        ),
                      ),
                      title: Text(
                        previewName.isEmpty
                            ? _lbl('معاينة الاسم العام', 'Public name preview')
                            : previewName,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(
                        _lbl(
                          'هكذا يظهر اسم منشأتك في البطاقات والتواصل.',
                          'This is how your organization name appears on cards.',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _lbl(
                      'تجديد رخصة فال وشراء المقاعد من تبويب «إدارة الاشتراك» وليس من هنا.',
                      'Renew FAL and extra seats from the Subscription tab, not here.',
                    ),
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _field(
                    controller: _nameAr,
                    label: _lbl('اسم المنشأة بالعربية', 'Organization name (Arabic)'),
                    helper: _lbl(
                      'الاسم الرسمي كما يظهر للعملاء في الواجهة العربية.',
                      'Official name shown in the Arabic interface.',
                    ),
                  ),
                  _field(
                    controller: _nameEn,
                    label: _lbl('اسم المنشأة بالإنجليزية', 'Organization name (English)'),
                    helper: _lbl(
                      'يُستخدم عند اختيار العميل للغة الإنجليزية.',
                      'Used when the client chooses English.',
                    ),
                  ),
                  _field(
                    controller: _descAr,
                    label: _lbl('وصف المنشأة بالعربية', 'Description (Arabic)'),
                    helper: _lbl(
                      'نبذة قصيرة عن نشاطكم العقاري.',
                      'A short note about your real-estate work.',
                    ),
                    maxLines: 3,
                  ),
                  _field(
                    controller: _descEn,
                    label: _lbl('وصف المنشأة بالإنجليزية', 'Description (English)'),
                    maxLines: 3,
                  ),
                  _field(
                    controller: _addrAr,
                    label: _lbl('العنوان بالعربية', 'Address (Arabic)'),
                  ),
                  _field(
                    controller: _addrEn,
                    label: _lbl('العنوان بالإنجليزية', 'Address (English)'),
                  ),
                  _field(
                    controller: _email,
                    label: _lbl('البريد الإلكتروني العام', 'Public email'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  _field(
                    controller: _phone,
                    label: _lbl('الجوال العام', 'Public phone'),
                    keyboardType: TextInputType.phone,
                  ),
                  _field(
                    controller: _logoUrl,
                    label: _lbl('رابط الشعار', 'Logo link'),
                    helper: _lbl(
                      'رابط صورة الشعار إن رُفع إلى التخزين.',
                      'Logo image URL if uploaded to storage.',
                    ),
                  ),
                  _field(
                    controller: _coverUrl,
                    label: _lbl('رابط صورة الغلاف', 'Cover image link'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_isAr ? 'حفظ' : 'Save'),
                  ),
                ],
              ),
            ),
    );
  }
}
