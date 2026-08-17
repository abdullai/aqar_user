import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';

import '../core/utils/app_money.dart';
import '../services/subscription_lifecycle_service.dart';

/// حوار شامل لإلغاء الاشتراك:
///   1) عرض الأسباب لاختيار سبب واحد + ملاحظة اختيارية.
///   2) محاولة الاستبقاء بخصم 5% لمرة واحدة (إن كان مؤهلاً).
///   3) تأكيد الإلغاء — يبقى الاشتراك حتى نهاية المدة المدفوعة.
///
/// يعيد:
///   • `null` إذا أغلق المستخدم الحوار دون قرار.
///   • [CancellationConfirmation] عند الانتهاء (مع علامة تم الإلغاء/الاستبقاء).
Future<CancellationConfirmation?> showSubscriptionCancellationDialog(
  BuildContext context, {
  required String subscriptionId,
  required String planNameAr,
  required String planNameEn,
  required bool isAr,
  SubscriptionLifecycleService? service,
}) async {
  final svc = service ?? SubscriptionLifecycleService();
  final reasons = await svc.loadReasons();

  if (!context.mounted) return null;

  return showDialog<CancellationConfirmation>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _SubscriptionCancellationDialog(
      subscriptionId: subscriptionId,
      planNameAr: planNameAr,
      planNameEn: planNameEn,
      isAr: isAr,
      reasons: reasons,
      service: svc,
    ),
  );
}

class _SubscriptionCancellationDialog extends StatefulWidget {
  final String subscriptionId;
  final String planNameAr;
  final String planNameEn;
  final bool isAr;
  final List<CancellationReason> reasons;
  final SubscriptionLifecycleService service;

  const _SubscriptionCancellationDialog({
    required this.subscriptionId,
    required this.planNameAr,
    required this.planNameEn,
    required this.isAr,
    required this.reasons,
    required this.service,
  });

  @override
  State<_SubscriptionCancellationDialog> createState() =>
      _SubscriptionCancellationDialogState();
}

enum _CancelStep { pickReason, retentionOffer, confirming }

class _SubscriptionCancellationDialogState
    extends State<_SubscriptionCancellationDialog> {
  _CancelStep _step = _CancelStep.pickReason;
  String? _reasonCode;
  final TextEditingController _noteCtrl = TextEditingController();
  CancellationOffer? _offer;
  bool _busy = false;
  String? _error;

  bool get _isAr => widget.isAr;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitReason() async {
    if (_reasonCode == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final offer = await widget.service.requestCancellation(
      subscriptionId: widget.subscriptionId,
      reasonCode: _reasonCode!,
      reasonNote: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!offer.ok) {
      setState(() {
        _error = offer.error ?? 'unknown_error';
      });
      return;
    }
    setState(() {
      _offer = offer;
      _step = offer.retentionAvailable
          ? _CancelStep.retentionOffer
          : _CancelStep.confirming;
    });
    if (!offer.retentionAvailable) {
      await _confirm(acceptRetention: false);
    }
  }

  Future<void> _confirm({required bool acceptRetention}) async {
    final reqId = _offer?.requestId;
    if (reqId == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = true;
      _step = _CancelStep.confirming;
      _error = null;
    });
    final res = await widget.service.confirmCancellation(
      requestId: reqId,
      acceptRetention: acceptRetention,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      setState(() => _error = res.error ?? 'unknown_error');
      return;
    }
    Navigator.of(context).pop(res);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final planName = _isAr ? widget.planNameAr : widget.planNameEn;

    return AlertDialog(
      backgroundColor: cs.surface,
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          Icon(Icons.support_agent_outlined, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isAr
                  ? 'إلغاء الاشتراك — $planName'
                  : 'Cancel subscription — $planName',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(child: _buildBody(context)),
      ),
      actions: _buildActions(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_step) {
      case _CancelStep.pickReason:
        return _buildPickReason(context);
      case _CancelStep.retentionOffer:
        return _buildRetention(context);
      case _CancelStep.confirming:
        return _busy
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            : _buildErrorBlock();
    }
  }

  Widget _buildPickReason(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isAr
              ? 'نأسف لرغبتك بالإلغاء — لمساعدة الدعم الفني في إيجاد حلٍّ مناسب، اختَر السبب الأقرب لحالتك:'
              : "We're sorry to see you go — please pick the reason closest to your case so support can help:",
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
        ),
        const SizedBox(height: 12),
        for (final r in widget.reasons)
          RadioListTile<String>(
            value: r.code,
            groupValue: _reasonCode,
            onChanged: _busy
                ? null
                : (v) {
                    setState(() => _reasonCode = v);
                  },
            title: Text(
              r.label(isAr: _isAr),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        const SizedBox(height: 8),
        AqarTextField(
          controller: _noteCtrl,
          minLines: 2,
          maxLines: 4,
          enabled: !_busy,
          decoration: InputDecoration(
            labelText: _isAr ? 'ملاحظة (اختياري)' : 'Note (optional)',
            hintText: _isAr
                ? 'أخبرنا بأي تفصيل يساعدنا في تحسين الخدمة.'
                : 'Tell us anything that helps us improve.',
            border: const OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _isAr ? 'تعذّر إرسال الطلب: $_error' : 'Could not submit: $_error',
            style: TextStyle(
              color: cs.error,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRetention(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final percent = _offer?.retentionDiscountPercent ?? 5;
    final amountSample = AppMoney.formatWithCurrencyCode(
      ((100 - percent) / 100.0) * 100, // عرضي تقريبي
      isAr: _isAr,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.card_giftcard_outlined, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    _isAr
                        ? 'هديّة استبقاء — خصم ${percent.toStringAsFixed(0)}٪'
                        : 'Stay-with-us bonus — ${percent.toStringAsFixed(0)}% off',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: cs.primary,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _isAr
                    ? (_offer?.retentionMessageAr ?? '')
                    : (_offer?.retentionMessageEn ?? ''),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                _isAr
                    ? 'مثال: من 100 $amountSample → بعد الخصم'
                    : 'Example: 100 → after discount',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _isAr ? (_offer?.noteAr ?? '') : (_offer?.noteEn ?? ''),
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBlock() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        _isAr ? 'تعذّر إكمال الطلب: $_error' : 'Could not complete: $_error',
        style: TextStyle(color: cs.error, fontWeight: FontWeight.w700),
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    switch (_step) {
      case _CancelStep.pickReason:
        return [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(_isAr ? 'تراجع' : 'Back'),
          ),
          FilledButton.icon(
            onPressed: (_busy || _reasonCode == null) ? null : _submitReason,
            icon: const Icon(Icons.arrow_forward_outlined),
            label: Text(_isAr ? 'متابعة' : 'Continue'),
          ),
        ];
      case _CancelStep.retentionOffer:
        return [
          OutlinedButton(
            onPressed:
                _busy ? null : () => _confirm(acceptRetention: false),
            child: Text(_isAr ? 'إكمال الإلغاء' : 'Continue cancelling'),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : () => _confirm(acceptRetention: true),
            icon: const Icon(Icons.favorite_outline),
            label: Text(
              _isAr ? 'أبقَى مع خصم 5٪' : 'Stay with 5% off',
            ),
          ),
        ];
      case _CancelStep.confirming:
        return [
          if (!_busy)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(_isAr ? 'إغلاق' : 'Close'),
            ),
        ];
    }
  }
}
