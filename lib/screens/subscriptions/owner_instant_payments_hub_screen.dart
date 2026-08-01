import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/subscription/subscription_gate_helper.dart';
import '../../core/utils/app_money.dart';
import '../../services/instant_market_request_payment_service.dart';
import '../../widgets/app_logo_loading.dart';

/// مدفوعات المالك/المستخدم العام — الطلب الفوري فقط (30 ر.س).
class OwnerInstantPaymentsHubScreen extends StatefulWidget {
  const OwnerInstantPaymentsHubScreen({
    super.key,
    required this.lang,
  });

  final String lang;

  @override
  State<OwnerInstantPaymentsHubScreen> createState() =>
      _OwnerInstantPaymentsHubScreenState();
}

class _OwnerInstantPaymentsHubScreenState
    extends State<OwnerInstantPaymentsHubScreen> {
  final _svc = InstantMarketRequestPaymentService(Supabase.instance.client);

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _available;
  List<Map<String, dynamic>> _history = const [];
  bool _busy = false;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _svc.getAvailableCredit(),
        _svc.listMyCredits(limit: 40),
      ]);
      if (!mounted) return;
      setState(() {
        _available = results[0] as Map<String, dynamic>;
        _history = results[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _fmtDate(dynamic raw) {
    if (raw == null) return '—';
    final dt = raw is DateTime
        ? raw.toLocal()
        : DateTime.tryParse(raw.toString())?.toLocal();
    if (dt == null) return '—';
    return DateFormat.yMMMd(_isAr ? 'ar' : 'en').add_jm().format(dt);
  }

  String _statusLabel(String status) {
    return switch (status) {
      'available' => _isAr ? 'جاهز للاستخدام' : 'Ready to use',
      'consumed' => _isAr ? 'مُستخدم' : 'Used',
      'refunded' => _isAr ? 'مُسترد' : 'Refunded',
      'pending_payment' => _isAr ? 'بانتظار الدفع' : 'Pending payment',
      _ => status,
    };
  }

  Future<void> _buyInstant() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final paid = await SubscriptionGateHelper.payInstantMarketRequest(
        context: context,
        isAr: _isAr,
        lang: widget.lang,
      );
      if (!mounted) return;
      if (paid?.ok == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isAr
                  ? 'تم الدفع — يمكنك استخدام الرصيد عند نشر طلب «فوري».'
                  : 'Paid — use this credit when you publish an Instant request.',
            ),
          ),
        );
        await _load();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refundCredit(String creditId) async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isAr ? 'استرداد الرصيد' : 'Refund credit'),
        content: Text(
          _isAr
              ? 'سيتم استرداد 30 ر.س إلى وسيلة الدفع الأصلية. يمكنك شراء رصيد جديد لاحقاً.'
              : 'SAR 30 will be refunded to your original payment method. You can buy a new credit later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_isAr ? 'استرداد' : 'Refund'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final res = await _svc.refundUnusedCredit(creditId);
      if (!mounted) return;
      if (res['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isAr ? 'تم طلب الاسترداد.' : 'Refund requested.',
            ),
          ),
        );
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${res['error'] ?? 'error'}')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _infoCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _isAr ? 'خدماتك المجانية' : 'Your free services',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _isAr
                  ? '• إعلان عقاري وطلب عقاري وإتمام صفقة على طلبات الآخرين — مجاني.\n'
                    '• الطلب «فوري» فقط: 30 ر.س — أسبوع أولوية في منطقتك و72 ساعة في باقي المناطق.\n'
                    '• الرصيد غير المستخدم يُسترد؛ المُلغى قبل النشر يعود للمحفظة.'
                  : '• Property listing, home request, and completing deals on others\' requests — free.\n'
                    '• Instant priority only: SAR 30 — 1 week in your region, 72h elsewhere.\n'
                    '• Unused credits can be refunded before publish.',
              style: TextStyle(
                height: 1.45,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _availableCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasCredit = _available?['ok'] == true &&
        (_available?['credit_id'] ?? '').toString().isNotEmpty;
    return Card(
      color: cs.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isAr ? 'رصيد الطلب الفوري' : 'Instant request credit',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (hasCredit)
              Text(
                _isAr
                    ? 'لديك رصيد جاهز — اختر «فوري» عند إنشاء الطلب.'
                    : 'You have a ready credit — choose Instant when creating a request.',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              )
            else
              Text(
                _isAr
                    ? 'لا يوجد رصيد جاهز حالياً.'
                    : 'No ready credit at the moment.',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _busy ? null : _buyInstant,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bolt_rounded),
              label: Text(
                _isAr
                    ? 'شراء طلب فوري — ${AppMoney.formatWithCurrencyCode(InstantMarketRequestPaymentService.priceSar, isAr: true)}'
                    : 'Buy instant request — ${AppMoney.formatWithCurrencyCode(InstantMarketRequestPaymentService.priceSar, isAr: false)}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: AppLogoLoading());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(_error!),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _load,
                child: Text(_isAr ? 'إعادة المحاولة' : 'Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final availableRows =
        _history.where((r) => (r['status'] ?? '') == 'available').toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _infoCard(context),
          const SizedBox(height: 12),
          _availableCard(context),
          if (availableRows.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              _isAr ? 'أرصدة قابلة للاستخدام أو الاسترداد' : 'Credits you can use or refund',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            ...availableRows.map((r) {
              final id = '${r['id']}';
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.bolt_rounded, color: Color(0xFFDC2626)),
                  title: Text(
                    AppMoney.formatWithCurrencyCode(
                      (r['amount_sar'] as num?)?.toDouble() ??
                          InstantMarketRequestPaymentService.priceSar,
                      isAr: _isAr,
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    '${_statusLabel('${r['status']}')} · ${_fmtDate(r['activated_at'] ?? r['created_at'])}',
                  ),
                  trailing: TextButton(
                    onPressed: _busy ? null : () => _refundCredit(id),
                    child: Text(_isAr ? 'استرداد' : 'Refund'),
                  ),
                ),
              );
            }),
          ],
          const SizedBox(height: 20),
          Text(
            _isAr ? 'سجل الطلبات الفورية' : 'Instant request history',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          if (_history.isEmpty)
            Text(
              _isAr ? 'لا توجد عمليات بعد.' : 'No transactions yet.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            ..._history.map((r) {
              final status = '${r['status'] ?? ''}';
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(
                    _statusLabel(status),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(_fmtDate(r['created_at'])),
                  trailing: Text(
                    AppMoney.formatWithCurrencyCode(
                      (r['amount_sar'] as num?)?.toDouble() ?? 30,
                      isAr: _isAr,
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
