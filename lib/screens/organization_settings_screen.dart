import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../main.dart' show langNotifier;
import '../services/org_team_service.dart';
import '../services/subscription_service.dart';
import '../widgets/app_logo_loading.dart';

/// إعدادات المنشأة للمالك (تعديل بيانات + تجديد رخصة العرض + مقاعد).
class OrganizationSettingsScreen extends StatefulWidget {
  const OrganizationSettingsScreen({
    super.key,
    this.embedAppBar = false,
  });

  /// عند `true`: بدون [AppBar] داخلي — تعتمد على الشريط العلوي
  /// للشاشة الأم (لتفادي ظهور سهمَي رجوع داخل لوحة «إدارتي» والاشتراكات).
  final bool embedAppBar;

  @override
  State<OrganizationSettingsScreen> createState() =>
      _OrganizationSettingsScreenState();
}

class _OrganizationSettingsScreenState extends State<OrganizationSettingsScreen> {
  final _svc = OrgTeamService(Supabase.instance.client);
  late final _sub = SubscriptionService(Supabase.instance.client);

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
  Map<String, dynamic>? _profile;
  bool _orgSubscriptionInactive = false;

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
      final sub = await _sub.getCurrentSubscription(organizationId: id);
      final end = DateTime.tryParse('${sub?['end_date']}');
      final st = '${sub?['status'] ?? ''}';
      final inactive = sub == null ||
          st != 'active' ||
          (end != null && end.isBefore(DateTime.now()));
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
        _profile = p;
      }
      if (!mounted) return;
      setState(() => _orgSubscriptionInactive = inactive);
    } else {
      _orgSubscriptionInactive = false;
    }
    if (!mounted) return;
    setState(() => _loading = false);
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
          SnackBar(content: Text('${res['error'] ?? 'Error'}')),
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

  Future<void> _renew() async {
    final t = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    final r = await _svc.renewFalLicense();
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['ok'] == true) {
      final c = '${r['fal_public_code'] ?? ''}';
      await Clipboard.setData(ClipboardData(text: c));
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(t.orgSetupFalLine(c))),
      );
      await _load();
    }
  }

  Future<void> _buySeats() async {
    final t = AppLocalizations.of(context)!;
    // اقرأ سعر العضو الإضافي بخصم 50% من الباقة الحالية.
    final info = await _sub.getSeatUnitPriceInfo();
    if (!mounted) return;
    if (info['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isAr
              ? 'لا يمكن قراءة سعر المقعد — هل لديك اشتراك فعّال؟'
              : 'Cannot read seat price — do you have an active subscription?'),
        ),
      );
      return;
    }
    final seatPriceNum = info['seat_unit_price_sar'];
    final seatPrice = (seatPriceNum is num)
        ? seatPriceNum.toDouble()
        : double.tryParse('$seatPriceNum') ?? 0;
    final remaining = int.tryParse('${info['remaining_slots_in_plan']}') ?? 0;
    final disc = int.tryParse('${info['team_member_discount_percent']}') ?? 50;

    final ctrl = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.orgBuySeats),
        content: StatefulBuilder(
          builder: (ctx2, setS) {
            final n = int.tryParse(ctrl.text.trim()) ?? 0;
            final total = (n > 0 ? n : 0) * seatPrice;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isAr
                      ? 'سعر العضو الإضافي: ${seatPrice.toStringAsFixed(0)} ر.س (خصم $disc٪ تلقائي)'
                      : 'Seat price: ${seatPrice.toStringAsFixed(0)} SAR (auto $disc% discount)',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  _isAr
                      ? 'المتبقي من حد الفريق في الباقة الحالية: $remaining'
                      : 'Remaining slots in current plan: $remaining',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                AqarTextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: _isAr ? 'العدد' : 'Count',
                  ),
                  onChanged: (_) => setS(() {}),
                ),
                const SizedBox(height: 10),
                Text(
                  _isAr
                      ? 'الإجمالي المتوقّع: ${total.toStringAsFixed(0)} ر.س'
                      : 'Total: ${total.toStringAsFixed(0)} SAR',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_isAr ? 'تأكيد الشراء' : 'Confirm'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final n = int.tryParse(ctrl.text.trim()) ?? 0;
    ctrl.dispose();
    if (n <= 0) return;
    setState(() => _saving = true);
    final r = await _sub.purchaseExtraSeatsPriced(extraSeats: n);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          r['ok'] == true
              ? (_isAr
                  ? 'تم تحديث المقاعد · المبلغ: ${r['total_charged_sar']} ر.س'
                  : 'Seats updated · Total: ${r['total_charged_sar']} SAR')
              : '${r['error']}',
        ),
      ),
    );
    if (r['ok'] == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final mc = int.tryParse('${_profile?['member_count']}') ?? 0;
    final lim = int.tryParse('${_profile?['seat_limit']}') ?? 1;

    return Scaffold(
      appBar: widget.embedAppBar
          ? null
          : AppBar(
              automaticallyImplyLeading: false,
              title: Text(t.orgSettingsTitle),
            ),
      body: _loading
          ? const Center(child: AppLogoLoading())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_orgSubscriptionInactive) ...[
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Theme.of(context).colorScheme.onErrorContainer,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                t.subscriptionsOrgSubscriptionExpired,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  LinearProgressIndicator(
                    value: lim > 0 ? mc / lim : null,
                  ),
                  Text('$mc / $lim', textAlign: TextAlign.end),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    onPressed: (_saving || _orgSubscriptionInactive) ? null : _renew,
                    child: Text(t.orgRenewFal),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: _saving ? null : _buySeats,
                    child: Text(t.orgBuySeats),
                  ),
                  const SizedBox(height: 24),
                  AqarTextField(
                    controller: _nameAr,
                    decoration: const InputDecoration(labelText: 'Name (AR)'),
                  ),
                  const SizedBox(height: 8),
                  AqarTextField(
                    controller: _nameEn,
                    decoration: const InputDecoration(labelText: 'Name (EN)'),
                  ),
                  const SizedBox(height: 8),
                  AqarTextField(
                    controller: _descAr,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Description (AR)'),
                  ),
                  const SizedBox(height: 8),
                  AqarTextField(
                    controller: _descEn,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Description (EN)'),
                  ),
                  const SizedBox(height: 8),
                  AqarTextField(
                    controller: _addrAr,
                    decoration: const InputDecoration(labelText: 'Address (AR)'),
                  ),
                  const SizedBox(height: 8),
                  AqarTextField(
                    controller: _addrEn,
                    decoration: const InputDecoration(labelText: 'Address (EN)'),
                  ),
                  const SizedBox(height: 8),
                  AqarTextField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 8),
                  AqarTextField(
                    controller: _phone,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                  const SizedBox(height: 8),
                  AqarTextField(
                    controller: _logoUrl,
                    decoration: const InputDecoration(labelText: 'Logo URL'),
                  ),
                  const SizedBox(height: 8),
                  AqarTextField(
                    controller: _coverUrl,
                    decoration: const InputDecoration(labelText: 'Cover URL'),
                  ),
                  const SizedBox(height: 24),
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
