import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';

import '../../core/navigation/dashboard_embedded_route.dart';
import '../../l10n/app_localizations.dart';
import '../../services/payment_card_manager.dart';
import '../../services/payment_service.dart';
import '../../widgets/app_logo_loading.dart';
import '../../widgets/aqar_primary_scroll_scope.dart';
import 'add_payment_card_screen.dart';

/// إدارة البطاقات المحفوظة — إضافة، تعديل، حذف، افتراضية.
class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key, required this.lang});

  final String lang;

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  final _cardManager = PaymentCardManager();
  bool _loading = true;
  List<Map<String, dynamic>> _cards = [];

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  bool get _canAddCard =>
      _cards.length < PaymentService.maxSavedCards;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await _cardManager.purgeMockCards();
    final c = await _cardManager.getSavedCards();
    if (!mounted) return;
    setState(() {
      _cards = c;
      _loading = false;
    });
  }

  Future<void> _openAddCard() async {
    if (!_canAddCard) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAr
                ? 'الحد الأقصى ${PaymentService.maxSavedCards} بطاقات — احذف بطاقة لإضافة أخرى.'
                : 'Maximum ${PaymentService.maxSavedCards} cards — delete one to add another.',
          ),
        ),
      );
      return;
    }
    final embedded = DashboardEmbeddedRoute.shouldUseEmbeddedChrome(context);
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        settings: RouteSettings(
          name: embedded
              ? DashboardEmbeddedRoute.subscriptionsAddCard
              : '/subscriptions/add-card',
        ),
        builder: (_) => AddPaymentCardScreen(lang: widget.lang),
      ),
    );
    if (ok == true) await _load();
  }

  Future<void> _editLabel(String id, String? current) async {
    final controller = TextEditingController(text: current ?? '');
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isAr ? 'تعديل اسم البطاقة' : 'Edit card label'),
        content: AqarTextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: InputDecoration(
            hintText: _isAr ? 'مثال: بطاقة العمل' : 'e.g. Work card',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(_isAr ? 'حفظ' : 'Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (label == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final res = await _cardManager.updateCardLabel(id, label);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          res['ok'] == true
              ? (_isAr ? 'تم التحديث' : 'Updated')
              : '${res['error']}',
        ),
      ),
    );
    await _load();
  }

  Future<void> _setDefault(String id) async {
    final messenger = ScaffoldMessenger.of(context);
    final res = await _cardManager.setDefaultCard(id);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          res['ok'] == true
              ? (_isAr ? 'تم التعيين كمفضّلة' : 'Set as preferred')
              : res['error'] == 'card_expired'
                  ? (_isAr
                      ? 'لا يمكن تعيين بطاقة منتهية'
                      : 'Cannot prefer an expired card')
                  : '${res['error']}',
        ),
      ),
    );
    if (res['ok'] == true) await _load();
  }

  Future<void> _deleteCard(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isAr ? 'حذف البطاقة؟' : 'Delete card?'),
        content: Text(
          _isAr
              ? 'سيُحذف السجل نهائياً من حسابك.'
              : 'This card will be permanently removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_isAr ? 'حذف' : 'Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final res = await _cardManager.deleteCard(id);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          res['ok'] == true
              ? AppLocalizations.of(context)!.subscriptionsCardDeleted
              : '${res['error']}',
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const Center(child: AppLogoLoading());
    }

    return AqarPrimaryScrollScope(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              _isAr
                  ? 'بطاقات الدفع (${_cards.length}/${PaymentService.maxSavedCards})'
                  : 'Payment cards (${_cards.length}/${PaymentService.maxSavedCards})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            if (_cards.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.credit_card_off_outlined,
                      size: 48,
                      color: cs.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isAr ? 'لا توجد بطاقات محفوظة' : 'No saved cards',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isAr
                          ? 'أضف بطاقة بنكية أو محفظة للدفع السريع'
                          : 'Add a bank card or wallet for faster checkout',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.outline,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ..._cards.map((c) {
              final id = '${c['id']}';
              final scheme = '${c['card_scheme'] ?? ''}'.toUpperCase();
              final last = '${c['last_four'] ?? ''}';
              final em = int.tryParse('${c['expiry_month']}') ?? 0;
              final ey = int.tryParse('${c['expiry_year']}') ?? 0;
              final exp =
                  '${em.toString().padLeft(2, '0')}/${ey.toString().length > 2 ? ey.toString().substring(2) : ey}';
              final expired = c['is_expired'] == true;
              final isDefault = c['is_default'] == true;
              final label = c['label']?.toString().trim() ?? '';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isDefault ? cs.primary : Colors.transparent,
                    width: isDefault ? 2 : 0,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            scheme == 'MADA'
                                ? Icons.payments_outlined
                                : Icons.credit_card,
                            color: expired ? cs.error : cs.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label.isNotEmpty
                                      ? label
                                      : '$scheme •••• $last',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${_isAr ? 'تنتهي' : 'Expires'}: $exp',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: expired
                                        ? cs.error
                                        : cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isDefault)
                            Chip(
                              label: Text(_isAr ? 'مفضّلة' : 'Preferred'),
                              visualDensity: VisualDensity.compact,
                            ),
                          if (expired)
                            Chip(
                              label: Text(_isAr ? 'منتهية' : 'Expired'),
                              backgroundColor: cs.errorContainer,
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            tooltip: _isAr ? 'تعديل الاسم' : 'Edit label',
                            onPressed: () => _editLabel(id, label),
                          ),
                          if (!isDefault && !expired)
                            IconButton(
                              icon: const Icon(Icons.star_outline, size: 20),
                              tooltip: _isAr ? 'تعيين كمفضّلة' : 'Set preferred',
                              onPressed: () => _setDefault(id),
                            ),
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: cs.error,
                            ),
                            tooltip: t.subscriptionsDelete,
                            onPressed: () => _deleteCard(id),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _canAddCard ? _openAddCard : null,
              icon: const Icon(Icons.add_card_outlined),
              label: Text(
                _isAr ? 'إضافة بطاقة أو طريقة دفع' : 'Add card or payment method',
              ),
            ),
            if (!_canAddCard)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _isAr
                      ? 'وصلت للحد الأقصى (${PaymentService.maxSavedCards} بطاقات). احذف بطاقة لإضافة أخرى.'
                      : 'Card limit reached (${PaymentService.maxSavedCards}). Delete a card to add another.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
