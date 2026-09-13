import 'package:web/web.dart' as web;

void stampFocusedOtpField({
  required String autocomplete,
  required int maxLength,
}) {
  try {
    final el = web.document.activeElement;
    if (el == null) return;
    if (el is web.HTMLInputElement) {
      el.autocomplete = autocomplete;
      el.inputMode = 'numeric';
      el.maxLength = maxLength;
      return;
    }
    if (el is web.HTMLTextAreaElement) {
      el.setAttribute('autocomplete', autocomplete);
      el.setAttribute('inputmode', 'numeric');
      el.maxLength = maxLength;
    }
  } catch (_) {}
}
