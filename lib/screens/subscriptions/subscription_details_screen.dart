import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/branding/app_branding.dart';
import '../../l10n/app_localizations.dart';
import '../../services/individual_market_offer_service.dart';
import '../../services/subscription_lifecycle_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/app_logo_loading.dart';
import '../../widgets/subscription/subscription_ui_helpers.dart';
import '../../widgets/subscription_cancellation_dialog.dart';

/// تفاصيل الاشتراك الحالي (شخصي أو منشأة) — مع:
///   • تشغيل/إيقاف الدفع التلقائي (يَمنح خصم 5٪ على الفواتير القادمة).
///   • زر إلغاء الاشتراك مع حوار الأسباب وعرض الاستبقاء (5٪ لمرّة).
///   • مؤشّر تاريخ الانتهاء وحالة الاشتراك.
///   • إحصائيات استهلاك الباقة (عروض السوق + طلبات الإعلان).
class SubscriptionDetailsScreen extends StatefulWidget {
  const SubscriptionDetailsScreen({
    super.key,
    required this.lang,
    required this.accountType,
    this.organizationId,
  });

  final String lang;
  final String accountType;
  final String? organizationId;

  @override
  State<SubscriptionDetailsScreen> createState() =>
      _SubscriptionDetailsScreenState();
}

class _SubscriptionDetailsScreenState extends State<SubscriptionDetailsScreen> {
  final _svc = SubscriptionService(Supabase.instance.client);
  final _lifecycle = SubscriptionLifecycleService();
  final _offers = IndividualMarketOfferService(Supabase.instance.client);
  bool _loading = true;
  bool _autoPayBusy = false;
  Map<String, dynamic>? _row;
  IndividualMarketOfferAllowance? _offerAllowance;
  Map<String, dynamic>? _listingAllowance;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _svc.getCurrentSubscription(
      organizationId: widget.organizationId,
    );
    final offers = await _offers.currentAllowance(
      accountType: widget.accountType,
      organizationId: widget.organizationId,
    );
    final listings = await _svc.fetchListingRequestsAllowance(
      organizationId: widget.organizationId,
    );
    if (!mounted) return;
    setState(() {
      _row = r;
      _offerAllowance = offers;
      _listingAllowance = listings;
      _loading = false;
    });
  }

  String _statusLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'active':
        return _isAr ? 'نشط' : 'Active';
      case 'cancelled':
        return _isAr ? 'ملغى (حتى نهاية المدة)' : 'Cancelled (until period end)';
      case 'pending':
        return _isAr ? 'قيد المعالجة' : 'Pending';
      case 'expired':
        return _isAr ? 'منتهٍ' : 'Expired';
      case 'trial':
        return _isAr ? 'تجريبي' : 'Trial';
      default:
        return raw.isEmpty ? (_isAr ? '—' : '—') : raw;
    }
  }

  Future<void> _toggleAutoPay(bool desired) async {
    final id = (_row?['id'] ?? '').toString();
    if (id.isEmpty) return;
    setState(() => _autoPayBusy = true);
    final res = await _lifecycle.setAutoPay(
      subscriptionId: id,
      enabled: desired,
    );
    if (!mounted) return;
    setState(() => _autoPayBusy = false);
    if (!res.ok) {
      final err = res.error ?? '';
      if (err.contains('penalty_required') || err == 'penalty_required') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isAr
                  ? 'لإيقاف التجديد التلقائي قبل نهاية الفترة يلزم دفع رسوم تكميلية (فرق خصم 10٪). تواصل مع الدعم أو ادفع من «الاشتراكات والمدفوعات».'
                  : 'Disabling auto-renew before period end requires a 10% penalty payment. Pay via Subscriptions or contact support.',
            ),
            duration: const Duration(seconds: 6),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAr
                ? 'تعذّر تحديث الدفع التلقائي: ${res.error ?? '—'}'
                : 'Could not update auto-pay: ${res.error ?? '—'}',
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          desired
              ? (_isAr
                  ? 'تم تفعيل الدفع التلقائي.'
                  : 'Auto-pay enabled.')
              : (_isAr
                  ? 'تم إيقاف الدفع التلقائي.'
                  : 'Auto-pay disabled.'),
        ),
      ),
    );
    await _load();
  }

  Future<void> _openCancelFlow() async {
    final id = (_row?['id'] ?? '').toString();
    if (id.isEmpty) return;
    Map<String, dynamic> plan = {};
    if (_row!['plan'] is Map) {
      plan = Map<String, dynamic>.from(_row!['plan'] as Map);
    } else if (_row!['subscription_plans'] is Map) {
      plan = Map<String, dynamic>.from(_row!['subscription_plans'] as Map);
    }
    final res = await showSubscriptionCancellationDialog(
      context,
      subscriptionId: id,
      planNameAr: AppBranding.planNameFromRow(plan, isAr: true),
      planNameEn: AppBranding.planNameFromRow(plan, isAr: false),
      isAr: _isAr,
      service: _lifecycle,
    );
    if (!mounted || res == null) return;
    final msg = _isAr ? res.messageAr : res.messageEn;
    if (msg.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
    await _load();
  }

  Widget _usageMeter({
    required String title,
    required int used,
    required int max,
    required bool unlimited,
    required ColorScheme cs,
  }) {
    final rem = unlimited ? null : (max - used).clamp(0, max);
    final pct = unlimited || max <= 0 ? 0.0 : (used / max).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: SubscriptionUiHelpers.denseLabel(context)),
          const SizedBox(height: 6),
          if (!unlimited) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 10,
                backgroundColor: cs.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            unlimited
                ? (_isAr
                    ? 'مستخدم: $used · غير محدود'
                    : 'Used: $used · Unlimited')
                : (_isAr
                    ? 'مستخدم: $used · المتبقي: $rem · الحد: $max'
                    : 'Used: $used · Remaining: $rem · Limit: $max'),
            style: SubscriptionUiHelpers.denseBody(context).copyWith(
              color: cs.onSurfaceVariant,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const Center(child: AppLogoLoading());
    }
    if (_row == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            t.subscriptionsNoSubscription,
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }
    Map<String, dynamic> plan = {};
    if (_row!['plan'] is Map) {
      plan = Map<String, dynamic>.from(_row!['plan'] as Map);
    } else if (_row!['subscription_plans'] is Map) {
      plan = Map<String, dynamic>.from(_row!['subscription_plans'] as Map);
    }
    final name = AppBranding.planNameFromRow(plan, isAr: _isAr);
    final status = _statusLabel('${_row!['status'] ?? ''}');
    final autoPayEnabled = _row!['auto_pay_enabled'] == true;
    final cancelRequestedAt = _row!['cancellation_requested_at'];
    final cancelEffectiveAt = _row!['cancellation_effective_at'];
    final retentionUsedAt = _row!['retention_discount_used_at'];
    final offers = _offerAllowance;
    final listings = _listingAllowance;

    String fmtTs(dynamic v) {
      if (v == null) return '';
      try {
        final d = DateTime.parse('$v').toLocal();
        return DateFormat('yyyy-MM-dd HH:mm').format(d);
      } catch (_) {
        return '$v';
      }
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          SubscriptionUiHelpers.section(
            context: context,
            title: name,
            children: [
              SubscriptionUiHelpers.tableRow(
                context: context,
                label: t.subscriptionsStatus,
                value: status,
              ),
              SubscriptionUiHelpers.tableRow(
                context: context,
                label: _isAr ? 'دورة الفوترة' : 'Billing cycle',
                value: SubscriptionUiHelpers.billingCycleStatusLine(
                  isAr: _isAr,
                  row: _row,
                ),
                emphasize: true,
              ),
              if (cancelEffectiveAt != null)
                SubscriptionUiHelpers.tableRow(
                  context: context,
                  label: _isAr ? 'آخر يوم فعّال' : 'Last active day',
                  value: fmtTs(cancelEffectiveAt),
                ),
            ],
          ),
          SubscriptionUiHelpers.section(
            context: context,
            title: t.subscriptionsUsageTitle,
            children: [
              if (offers != null && offers.ok)
                _usageMeter(
                  title: _isAr ? 'عروض السوق' : 'Market offers',
                  used: offers.used,
                  max: offers.max,
                  unlimited: offers.max >= 999999,
                  cs: cs,
                ),
              if (listings != null && listings['ok'] == true)
                _usageMeter(
                  title: _isAr ? 'طلبات الإعلان' : 'Listing requests',
                  used: int.tryParse('${listings['total_used'] ?? 0}') ?? 0,
                  max: (listings['unlimited'] == true)
                      ? 999999
                      : (int.tryParse('${listings['total_max'] ?? 0}') ?? 0),
                  unlimited: listings['unlimited'] == true,
                  cs: cs,
                ),
              if ((offers == null || !offers.ok) &&
                  (listings == null || listings['ok'] != true))
                Text(
                  _isAr ? 'لا تتوفر بيانات استهلاك بعد.' : 'No usage data yet.',
                  style: SubscriptionUiHelpers.denseBody(context),
                ),
            ],
          ),
          if (SubscriptionUiHelpers.isRecurringSubscription(_row)) ...[
            _autoPayCard(cs, autoPayEnabled),
            const SizedBox(height: 8),
            _cancelCard(
              cs,
              cancelRequestedAt: cancelRequestedAt,
              retentionUsedAt: retentionUsedAt,
            ),
          ],
        ],
      ),
    );
  }

  Widget _autoPayCard(ColorScheme cs, bool enabled) {
    return SubscriptionUiHelpers.section(
      context: context,
      title: _isAr ? 'الدفع التلقائي · خصم 10٪' : 'Auto-pay · 10% off',
      children: [
        Row(
          children: [
            Icon(Icons.bolt_outlined, color: cs.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _isAr
                    ? 'يُطبَّق خصم إضافي على الفواتير القادمة عند التفعيل.'
                    : 'Extra discount applies to upcoming bills when enabled.',
                style: SubscriptionUiHelpers.denseBody(context),
              ),
            ),
            Switch(
              value: enabled,
              onChanged: _autoPayBusy ? null : (v) => _toggleAutoPay(v),
            ),
          ],
        ),
      ],
    );
  }

  Widget _cancelCard(
    ColorScheme cs, {
    dynamic cancelRequestedAt,
    dynamic retentionUsedAt,
  }) {
    final cancelled = (_row?['status'] ?? '').toString().toLowerCase() ==
        'cancelled';
    final hasRequest = cancelRequestedAt != null;
    final canCancel = SubscriptionUiHelpers.showCancelSubscriptionButton(
      row: _row,
    );
    return SubscriptionUiHelpers.section(
      context: context,
      title: _isAr ? 'إلغاء الاشتراك' : 'Cancel subscription',
      children: [
        if (retentionUsedAt != null)
          Text(
            _isAr
                ? 'تم استخدام خصم الاستبقاء سابقاً.'
                : 'Retention discount has already been used.',
            style: SubscriptionUiHelpers.denseBody(context).copyWith(
              color: cs.tertiary,
              fontSize: 12.5,
            ),
          ),
        if (!canCancel && (cancelled || hasRequest))
          Text(
            cancelled
                ? (_isAr
                    ? 'تم إلغاء الاشتراك — تبقى المزايا حتى نهاية الفترة المدفوعة.'
                    : 'Subscription cancelled — access remains until period end.')
                : (_isAr
                    ? 'طلب الإلغاء قيد المعالجة.'
                    : 'Cancellation request is pending.'),
            style: SubscriptionUiHelpers.denseBody(context),
          ),
        if (canCancel) ...[
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: _openCancelFlow,
              icon: const Icon(Icons.flag_outlined, size: 18),
              label: Text(_isAr ? 'بدء الإلغاء' : 'Start cancellation'),
              style: OutlinedButton.styleFrom(foregroundColor: cs.error),
            ),
          ),
        ],
      ],
    );
  }
}
