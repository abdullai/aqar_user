import 'dart:async';

import 'package:flutter/material.dart';
import 'package:aqar_user/core/gestures/app_keyboard_popups.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/subscription/subscription_gate_helper.dart';
import '../../core/payment/platform_fee_catalog.dart';
import '../../core/utils/app_money.dart';
import '../../core/utils/date_helper.dart';
import '../../services/instant_market_request_payment_service.dart';
import '../../widgets/app_logo_loading.dart';

/// مدفوعات المالك/المستخدم العام — الطلب الفوري (سعر الكتالوج).
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
  double _catalogPrice = 0;
  final Set<String> _selectedHistoryIds = <String>{};
  bool _selectionMode = false;

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
        _svc.catalogAmountSar(),
      ]);
      if (!mounted) return;
      setState(() {
        _available = results[0] as Map<String, dynamic>;
        _history = results[1] as List<Map<String, dynamic>>;
        _catalogPrice = results[2] as double;
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
    return DateHelper.fmtCivilDateTime(dt, isAr: _isAr);
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
    final hasCredit = _available?['ok'] == true &&
        (_available?['credit_id'] ?? '').toString().isNotEmpty;
    if (hasCredit) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAr
                ? 'لديك رصيد فوري غير مستخدم. استخدمه عند النشر أو استردّه قبل شراء رصيد جديد.'
                : 'You already have unused instant credit. Use it at publish or refund it before buying another.',
          ),
        ),
      );
      return;
    }
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
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isAr ? 'استرداد الرصيد' : 'Refund credit'),
        content: Text(
          _isAr
              ? 'سيتم استرداد ${PlatformFeeCatalog.of(context).instantPhrase(isAr: true)} إلى وسيلة الدفع الأصلية. يمكنك شراء رصيد جديد لاحقاً.'
              : '${PlatformFeeCatalog.of(context).instantPhrase(isAr: false)} will be refunded to your original payment method. You can buy a new credit later.',
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

  void _toggleHistorySelection(String id) {
    setState(() {
      if (!_selectedHistoryIds.add(id)) {
        _selectedHistoryIds.remove(id);
      }
      _selectionMode = _selectedHistoryIds.isNotEmpty;
    });
  }

  Future<void> _hideSelectedHistory() async {
    if (_busy || _selectedHistoryIds.isEmpty) return;
    final selected = Set<String>.from(_selectedHistoryIds);
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isAr ? 'حذف من السجل' : 'Remove from history'),
        content: Text(
          _isAr
              ? 'سيتم إخفاء العمليات المحددة من السجل فقط. لن تُحذف الفاتورة أو بيانات الدفع.'
              : 'Selected entries will be hidden from this history only. Invoices and payment data remain محفوظًا.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_isAr ? 'حذف من السجل' : 'Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      for (final id in selected) {
        final result = await _svc.hideCredit(id);
        if (result['ok'] != true) {
          throw StateError('${result['error'] ?? 'hide_failed'}');
        }
      }
      if (!mounted) return;
      setState(() {
        _selectedHistoryIds.clear();
        _selectionMode = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAr
                ? 'تم حذف العمليات من السجل.'
                : 'Entries removed from history.',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_isAr ? 'تعذر التنفيذ' : 'Action failed'}: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _hideHistoryEntry(String id) async {
    if (!_selectedHistoryIds.contains(id)) {
      _selectedHistoryIds.add(id);
    }
    await _hideSelectedHistory();
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
                  ? '• إضافة إعلان وطلب عقاري عادي مجانيان. إتمام الصفقات على طلبات السوق يُحسب من حصة باقة الصفقات، وتظهر الإضافات عند نفاد الحصة.\n'
                      '• الطلب «فوري» فقط: ${PlatformFeeCatalog.of(context, listen: true).instantPhrase(isAr: true)} — أسبوع أولوية في منطقتك و72 ساعة في باقي المناطق.\n'
                      '• الرصيد غير المستخدم يُسترد؛ المُلغى قبل النشر يعود للمحفظة.'
                  : '• Adding a listing and a standard home request are free. Completing market deals uses your plan quota; deal top-ups are available when it runs out.\n'
                      '• Instant priority only: ${PlatformFeeCatalog.of(context, listen: true).instantPhrase(isAr: false)} — 1 week in your region, 72h elsewhere.\n'
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
              onPressed: (_busy || hasCredit) ? null : _buyInstant,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bolt_rounded),
              label: Text(
                hasCredit
                    ? (_isAr
                        ? 'رصيد فوري جاهز — استخدمه عند النشر أو استردّه أدناه'
                        : 'Instant credit ready — use it at publish or refund below')
                    : (_isAr
                        ? 'شراء طلب فوري — ${AppMoney.formatWithCurrencyCode(_catalogPrice, isAr: true)}'
                        : 'Buy instant request — ${AppMoney.formatWithCurrencyCode(_catalogPrice, isAr: false)}'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            if (hasCredit) ...[
              const SizedBox(height: 8),
              Text(
                _isAr
                    ? 'ختم الرصيد: ${_creditSeal(_available)} — لا يُشترى رصيد ثانٍ قبل الاستخدام أو الاسترداد (عدالة للدفع).'
                    : 'Credit seal: ${_creditSeal(_available)} — a second unused credit cannot be bought (fair billing).',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _creditSeal(Map<String, dynamic>? row) {
    final id = '${row?['credit_id'] ?? row?['id'] ?? ''}'.replaceAll('-', '');
    if (id.length < 6) return '—';
    return id.substring(id.length - 6).toUpperCase();
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
              _isAr
                  ? 'أرصدة قابلة للاستخدام أو الاسترداد'
                  : 'Credits you can use or refund',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            ...availableRows.map((r) {
              final id = '${r['id']}';
              return Card(
                child: ListTile(
                  leading:
                      const Icon(Icons.bolt_rounded, color: Color(0xFFDC2626)),
                  title: AppMoneyLine(
                    amount:
                        (r['amount_sar'] as num?)?.toDouble() ?? _catalogPrice,
                    currencyCode: 'SAR',
                    isAr: _isAr,
                    maxFractionDigits: 2,
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
          if (_selectionMode) ...[
            const SizedBox(height: 8),
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: ListTile(
                leading: const Icon(Icons.select_all),
                title: Text(
                  _isAr
                      ? 'تم تحديد ${_selectedHistoryIds.length} عملية'
                      : '${_selectedHistoryIds.length} entries selected',
                ),
                trailing: IconButton(
                  tooltip: _isAr ? 'حذف من السجل' : 'Remove from history',
                  onPressed: _busy ? null : _hideSelectedHistory,
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ),
          ],
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
              final id = '${r['id'] ?? ''}';
              final selected = _selectedHistoryIds.contains(id);
              final amount = (r['amount_sar'] as num?)?.toDouble();
              final show =
                  (amount != null && amount > 0) ? amount : _catalogPrice;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: _selectionMode
                      ? Checkbox(
                          value: selected,
                          onChanged:
                              _busy ? null : (_) => _toggleHistorySelection(id),
                        )
                      : Icon(
                          status == 'pending_payment'
                              ? Icons.hourglass_top_outlined
                              : Icons.bolt_rounded,
                        ),
                  title: Text(
                    _statusLabel(status),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(_fmtDate(r['created_at'])),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (show > 0)
                        AppMoneyLine(
                          amount: show,
                          currencyCode: 'SAR',
                          isAr: _isAr,
                          maxFractionDigits: 2,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        )
                      else
                        const Text('—'),
                      PopupMenuButton<String>(
                        enabled: !_busy,
                        onSelected: (_) => unawaited(_hideHistoryEntry(id)),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'archive',
                            child: Text(_isAr ? 'أرشفة' : 'Archive'),
                          ),
                          PopupMenuItem(
                            value: 'remove',
                            child: Text(_isAr ? 'حذف من السجل' : 'Remove'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  onLongPress: () => _toggleHistorySelection(id),
                  onTap:
                      _selectionMode ? () => _toggleHistorySelection(id) : null,
                ),
              );
            }),
        ],
      ),
    );
  }
}
