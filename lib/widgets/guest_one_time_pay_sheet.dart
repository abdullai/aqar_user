import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';

import '../core/payment/payment_platform_detector.dart';
import '../services/guest_unlock_service.dart';
import '../services/payment_gateway_mock.dart';
import '../services/payment_service.dart';

/// دفع لمرة واحدة للضيف (تجريبي محلي حتى تفعيل ميسّر) —
/// يضبط [GuestUnlockService] عند النجاح.
Future<bool> showGuestOneTimePaySheet({
  required BuildContext context,
  required bool isAr,
  required String unlockKind,
  required double amountSar,
}) async {
  if (!PaymentService.allowMockGateway) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAr
                ? 'بوابة الدفع غير مفعّلة حالياً. سجّل الدخول أو أنشئ حساباً للمتابعة.'
                : 'Payment is unavailable right now. Sign in or create an account to continue.',
          ),
        ),
      );
    }
    return false;
  }

  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return _GuestPayBody(
        isAr: isAr,
        unlockKind: unlockKind,
        amountSar: amountSar,
      );
    },
  );
  return ok == true;
}

class _GuestPayBody extends StatefulWidget {
  const _GuestPayBody({
    required this.isAr,
    required this.unlockKind,
    required this.amountSar,
  });

  final bool isAr;
  final String unlockKind;
  final double amountSar;

  @override
  State<_GuestPayBody> createState() => _GuestPayBodyState();
}

class _GuestPayBodyState extends State<_GuestPayBody> {
  bool _busy = false;

  bool get _showApple {
    if (PaymentService.useMoyasarLiveFlow) {
      return PaymentPlatformDetector.supportsApplePay();
    }
    // تجريبي: أظهر Apple Pay على iOS/Safari فقط.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) return true;
    return kIsWeb && PaymentPlatformDetector.browser == BrowserType.safari;
  }

  bool get _showMada => true;

  bool get _showCard => true;

  Future<void> _finish(bool success) async {
    if (!success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isAr
                  ? 'تعذّر إتمام الدفع. حاول مرة أخرى.'
                  : 'Payment could not be completed. Please try again.',
            ),
          ),
        );
      }
      return;
    }
    await GuestUnlockService.markPaid(kind: widget.unlockKind);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _payWallet(String kind) async {
    if (_busy) return;
    if (!PaymentService.allowMockGateway) {
      await _finish(false);
      return;
    }
    setState(() => _busy = true);
    final ok = PaymentGatewayMock.mockWalletPay(walletKind: kind);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => _busy = false);
    await _finish(ok);
  }

  Future<void> _payCard() async {
    if (_busy) return;
    if (!PaymentService.allowMockGateway) {
      await _finish(false);
      return;
    }
    setState(() => _busy = true);
    final token = PaymentGatewayMock.issueCardToken(
      cardBin: '424242',
      lastFour: '4242',
      expiryMonth: 12,
      expiryYear: DateTime.now().year + 3,
    );
    final ok = PaymentGatewayMock.mockProcessPayment(
      cardToken: token,
      amountKey:
          'guest_ot_${widget.unlockKind}_${widget.amountSar.toStringAsFixed(0)}',
    );
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    setState(() => _busy = false);
    await _finish(ok);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final amount = widget.amountSar.toStringAsFixed(0);
    final title = widget.isAr ? 'دفع لمرة واحدة' : 'One-time payment';
    final sub = widget.isAr
        ? 'المبلغ $amount ر.س — تجربة محلية على هذا الجهاز حتى تفعيل بوابة الدفع المعتمدة في المملكة.'
        : 'SAR $amount — local trial on this device until the licensed Saudi payment gateway is activated.';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              sub,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 18),
            if (_busy)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              if (_showApple) ...[
                FilledButton.icon(
                  onPressed: () => _payWallet('apple_pay'),
                  icon: const Icon(Icons.apple_rounded),
                  label: const Text('Apple Pay'),
                ),
                const SizedBox(height: 10),
              ],
              if (_showMada) ...[
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF006C35),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _payWallet('mada'),
                  icon: const Icon(Icons.credit_card_rounded),
                  label: Text(widget.isAr ? 'مدى' : 'mada'),
                ),
                const SizedBox(height: 10),
              ],
              if (_showCard)
                OutlinedButton.icon(
                  onPressed: _payCard,
                  icon: const Icon(Icons.payment_rounded),
                  label: Text(
                    widget.isAr ? 'بطاقة مدى أو ائتمان' : 'mada or credit card',
                  ),
                ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: Text(widget.isAr ? 'إلغاء' : 'Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
