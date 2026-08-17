import 'dart:async';
import 'dart:html' as html;

class Moyasar3dsResult {
  const Moyasar3dsResult({
    required this.status,
    this.message = '',
    this.paymentId = '',
  });

  final String status;
  final String message;
  final String paymentId;
}

/// يفتح رابط 3DS في نافذة منبثقة وينتظر postMessage من [moyasar-3ds-return.html].
Future<Moyasar3dsResult> runMoyasarWeb3ds(String transactionUrl) async {
  final completer = Completer<Moyasar3dsResult>();
  Timer? pollTimer;
  StreamSubscription<html.MessageEvent>? sub;

  void finish(Moyasar3dsResult r) {
    if (completer.isCompleted) return;
    pollTimer?.cancel();
    sub?.cancel();
    completer.complete(r);
  }

  void onMessage(html.MessageEvent event) {
    try {
      final raw = event.data;
      final map = _coerceMessageMap(raw);
      if (map == null) return;
      if (map['type'] != 'moyasar-3ds-return') return;

      final status = '${map['status'] ?? ''}'.trim();
      final paymentId =
          '${map['paymentId'] ?? map['payment_id'] ?? map['id'] ?? ''}'.trim();
      final message = '${map['message'] ?? map['error'] ?? ''}'.trim();

      try {
        final existing = html.window.open('', 'moyasar3ds');
        existing.close();
      } catch (_) {}

      finish(
        Moyasar3dsResult(
          status: status.isNotEmpty ? status : 'return',
          message: message,
          paymentId: paymentId,
        ),
      );
    } catch (_) {}
  }

  sub = html.window.onMessage.listen(onMessage);

  final popup = html.window.open(
    transactionUrl,
    'moyasar3ds',
    'popup=yes,width=480,height=720,scrollbars=yes,resizable=yes',
  );

  // ignore: unnecessary_null_comparison — dart:html types differ on some SDKs
  if (popup == null) {
    sub.cancel();
    html.window.location.href = transactionUrl;
    return const Moyasar3dsResult(
      status: 'redirected',
      message: 'popup_blocked',
    );
  }

  pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
    try {
      if (popup.closed == true) {
        finish(
          const Moyasar3dsResult(
            status: 'closed',
            message: 'window_closed',
          ),
        );
      }
    } catch (_) {}
  });

  return completer.future.timeout(
    const Duration(minutes: 8),
    onTimeout: () {
      finish(
        const Moyasar3dsResult(
          status: 'timeout',
          message: '3ds_timeout',
        ),
      );
      return const Moyasar3dsResult(
        status: 'timeout',
        message: '3ds_timeout',
      );
    },
  );
}

/// عند العودة من 3DS في نفس التبويب (?moyasar_payment= / ?moyasar_status=).
void listenMoyasarReturnOnPageLoad(void Function(Moyasar3dsResult) onResult) {
  try {
    final uri = Uri.parse(html.window.location.href);
    final paymentId = uri.queryParameters['moyasar_payment']?.trim() ?? '';
    final status = uri.queryParameters['moyasar_status']?.trim() ?? '';
    if (paymentId.isEmpty && status.isEmpty) return;

    onResult(
      Moyasar3dsResult(
        status: paymentId.isNotEmpty
            ? 'paid'
            : (status.isNotEmpty ? status : 'return'),
        paymentId: paymentId,
      ),
    );

    final qp = Map<String, String>.from(uri.queryParameters)
      ..remove('moyasar_payment')
      ..remove('moyasar_status');
    final clean = uri.replace(queryParameters: qp);
    html.window.history.replaceState(null, '', clean.toString());
  } catch (_) {}
}

Map<String, dynamic>? _coerceMessageMap(Object? raw) {
  if (raw is Map) {
    return Map<String, dynamic>.from(raw);
  }
  return null;
}
