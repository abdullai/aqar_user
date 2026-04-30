import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/input/saudi_input_formatters.dart';
import '../services/legacy_data_quality_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/field_group_frame.dart';

class LegacyDataQualityGateScreen extends StatefulWidget {
  const LegacyDataQualityGateScreen({
    super.key,
    required this.lang,
    required this.onDone,
  });

  final String lang;
  final VoidCallback onDone;

  @override
  State<LegacyDataQualityGateScreen> createState() =>
      _LegacyDataQualityGateScreenState();
}

class _LegacyDataQualityGateScreenState
    extends State<LegacyDataQualityGateScreen> {
  late final LegacyDataQualityService _svc;
  final _profileArCtrl = TextEditingController();
  final _profileEnCtrl = TextEditingController();
  final _propertyCtrls = <String, Map<String, TextEditingController>>{};
  final _requestCtrls = <String, Map<String, TextEditingController>>{};

  Map<String, dynamic>? _profileIssue;
  List<Map<String, dynamic>> _propertyIssues = const [];
  List<Map<String, dynamic>> _requestIssues = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  @override
  void initState() {
    super.initState();
    _svc = LegacyDataQualityService(Supabase.instance.client);
    _load();
  }

  @override
  void dispose() {
    _profileArCtrl.dispose();
    _profileEnCtrl.dispose();
    for (final group in _propertyCtrls.values) {
      for (final c in group.values) {
        c.dispose();
      }
    }
    for (final group in _requestCtrls.values) {
      for (final c in group.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final profile = await _svc.currentUserProfileIssue();
    final properties = await _svc.currentUserPropertyIssues();
    final requests = await _svc.currentUserListingRequestIssues();
    if (!mounted) return;
    _profileIssue = profile;
    _propertyIssues = properties;
    _requestIssues = requests;
    _profileArCtrl.text = _s(profile?['full_name_ar'] ?? profile?['full_name']);
    _profileEnCtrl.text = _s(profile?['full_name_en']);
    _syncPropertyControllers(properties);
    _syncRequestControllers(requests);
    setState(() => _loading = false);
  }

  void _syncPropertyControllers(List<Map<String, dynamic>> rows) {
    final liveIds =
        rows.map((r) => _s(r['id'])).where((id) => id.isNotEmpty).toSet();
    final stale =
        _propertyCtrls.keys.where((id) => !liveIds.contains(id)).toList();
    for (final id in stale) {
      final group = _propertyCtrls.remove(id);
      if (group != null) {
        for (final c in group.values) {
          c.dispose();
        }
      }
    }
    for (final r in rows) {
      final id = _s(r['id']);
      if (id.isEmpty || _propertyCtrls.containsKey(id)) continue;
      _propertyCtrls[id] = {
        'title': TextEditingController(text: _s(r['title'])),
        'city': TextEditingController(text: _s(r['city'])),
        'price': TextEditingController(text: _s(r['price'])),
        'area': TextEditingController(text: _s(r['area'])),
      };
    }
  }

  void _syncRequestControllers(List<Map<String, dynamic>> rows) {
    final liveIds =
        rows.map((r) => _s(r['id'])).where((id) => id.isNotEmpty).toSet();
    final stale =
        _requestCtrls.keys.where((id) => !liveIds.contains(id)).toList();
    for (final id in stale) {
      final group = _requestCtrls.remove(id);
      if (group != null) {
        for (final c in group.values) {
          c.dispose();
        }
      }
    }
    for (final r in rows) {
      final id = _s(r['id']);
      if (id.isEmpty || _requestCtrls.containsKey(id)) continue;
      final price = _s(r['price']).isNotEmpty
          ? _s(r['price'])
          : (_s(r['request_price']).isNotEmpty
              ? _s(r['request_price'])
              : _s(r['preview_price']));
      _requestCtrls[id] = {
        'title': TextEditingController(text: _s(r['title'])),
        'city': TextEditingController(text: _s(r['city'])),
        'price': TextEditingController(text: price),
      };
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_profileIssue != null) {
        await _svc.saveProfileNames(
          fullNameAr: _profileArCtrl.text,
          fullNameEn: _profileEnCtrl.text,
        );
      }
      for (final row in _propertyIssues) {
        final id = _s(row['id']);
        final c = _propertyCtrls[id];
        if (id.isEmpty || c == null) continue;
        await _svc.savePropertyCardData(
          propertyId: id,
          title: c['title']!.text,
          city: c['city']!.text,
          price: c['price']!.text,
          area: c['area']!.text,
        );
      }
      for (final row in _requestIssues) {
        final id = _s(row['id']);
        final c = _requestCtrls[id];
        if (id.isEmpty || c == null) continue;
        await _svc.saveListingRequestData(
          requestId: id,
          title: c['title']!.text,
          city: c['city']!.text,
          price: c['price']!.text,
        );
      }
      final stillHasIssues = await _svc.hasCurrentUserRepairIssues();
      if (!mounted) return;
      if (!stillHasIssues) {
        widget.onDone();
        return;
      }
      await _load();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _isAr
            ? 'ما زالت توجد بيانات ناقصة أو غير صحيحة. راجع الحقول المعلمة ثم احفظ مرة أخرى.'
            : 'Some data is still missing or invalid. Review the fields and save again.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _friendlyError(e);
      });
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('invalid_arabic_name')) {
      return _isAr
          ? 'اكتب الاسم العربي بحروف عربية وليس أرقاماً.'
          : 'Enter the Arabic name using Arabic letters.';
    }
    if (s.contains('invalid_english_name')) {
      return _isAr
          ? 'اكتب الاسم الإنجليزي بحروف إنجليزية وليس عربياً أو أرقاماً.'
          : 'Enter the English name using Latin letters.';
    }
    if (s.contains('EDIT_LIMIT_REACHED')) {
      return _isAr
          ? 'أحد العقارات بلغ حد التعديلات. يحتاج إصلاحاً إدارياً من لوحة قاعدة البيانات.'
          : 'One property reached its edit limit and needs admin repair.';
    }
    if (s.contains('invalid_request_data')) {
      return _isAr
          ? 'راجع بيانات طلب التسويق: العنوان والمدينة والسعر مطلوبة.'
          : 'Review request data: title, city, and price are required.';
    }
    return _isAr ? 'تعذر حفظ البيانات: $s' : 'Could not save data: $s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
              _isAr ? 'استكمال البيانات الناقصة' : 'Complete missing data'),
        ),
        body: _loading
            ? const Center(child: AppLogoLoading())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    _isAr
                        ? 'وجدنا بيانات قديمة ناقصة أو غير مطابقة. عدّل الحقول ثم احفظ ليتم تحديث قاعدة البيانات.'
                        : 'We found old missing or invalid data. Update the fields and save to repair the database.',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, height: 1.4),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: cs.error)),
                  ],
                  if (_profileIssue != null) ...[
                    const SizedBox(height: 18),
                    _buildProfileSection(),
                  ],
                  if (_propertyIssues.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    ..._propertyIssues.map(_buildPropertySection),
                  ],
                  if (_requestIssues.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    ..._requestIssues.map(_buildRequestSection),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_isAr
                        ? 'حفظ وتحديث قاعدة البيانات'
                        : 'Save and update'),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildProfileSection() {
    return FieldGroupFrame(
      title: _isAr ? 'بيانات الحساب' : 'Profile data',
      subtitle: _isAr
          ? 'هذه الحقول تُحدّث users_profiles للحساب الحالي.'
          : 'These fields update users_profiles for the current account.',
      child: Column(
        children: [
          TextField(
            controller: _profileArCtrl,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: _isAr ? 'الاسم العربي الكامل' : 'Full Arabic name',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _profileEnCtrl,
            textDirection: TextDirection.ltr,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: _isAr ? 'الاسم الإنجليزي الكامل' : 'Full English name',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPropertySection(Map<String, dynamic> row) {
    final id = _s(row['id']);
    final c = _propertyCtrls[id]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: FieldGroupFrame(
        title: _isAr ? 'عقار ناقص البيانات' : 'Property missing data',
        subtitle: id,
        child: Column(
          children: [
            TextField(
              controller: c['title'],
              decoration: InputDecoration(
                labelText: _isAr ? 'عنوان الإعلان' : 'Listing title',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: c['city'],
              decoration: InputDecoration(
                labelText: _isAr ? 'المدينة' : 'City',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: c['price'],
              keyboardType: TextInputType.number,
              inputFormatters: latinDecimalNumberFormatters(),
              decoration: InputDecoration(
                labelText: _isAr ? 'السعر' : 'Price',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: c['area'],
              keyboardType: TextInputType.number,
              inputFormatters: latinDecimalNumberFormatters(),
              decoration: InputDecoration(
                labelText: _isAr ? 'المساحة' : 'Area',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestSection(Map<String, dynamic> row) {
    final id = _s(row['id']);
    final c = _requestCtrls[id]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: FieldGroupFrame(
        title:
            _isAr ? 'طلب تسويق ناقص البيانات' : 'Listing request missing data',
        subtitle: id,
        child: Column(
          children: [
            TextField(
              controller: c['title'],
              decoration: InputDecoration(
                labelText: _isAr ? 'عنوان الطلب' : 'Request title',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: c['city'],
              decoration: InputDecoration(
                labelText: _isAr ? 'المدينة' : 'City',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: c['price'],
              keyboardType: TextInputType.number,
              inputFormatters: latinDecimalNumberFormatters(),
              decoration: InputDecoration(
                labelText: _isAr ? 'السعر/قيمة الطلب' : 'Price/request value',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
