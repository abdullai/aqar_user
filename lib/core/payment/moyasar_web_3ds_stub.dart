/// منصات غير الويب — لا تُستخدم.
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

Future<Moyasar3dsResult> runMoyasarWeb3ds(String transactionUrl) async {
  throw UnsupportedError('runMoyasarWeb3ds is web-only');
}

void listenMoyasarReturnOnPageLoad(void Function(Moyasar3dsResult) onResult) {}
