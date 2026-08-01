import 'package:flutter/services.dart';

/// Normalizes Eastern Arabic-Indic, Arabic-Indic, and Persian digits to Western ASCII 0–9.
String normalizeWesternDigits(String input) {
  const from = '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹';
  const to = '01234567890123456789';
  final buf = StringBuffer();
  for (final ch in input.runes) {
    final c = String.fromCharCode(ch);
    final i = from.indexOf(c);
    buf.write(i >= 0 ? to[i] : c);
  }
  return buf.toString();
}

/// Arabic / Persian script blocks (cardholder names must be Latin on most gateways).
final RegExp arabicOrPersianScript = RegExp(
  r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]',
);

bool containsArabicOrPersianScript(String s) =>
    arabicOrPersianScript.hasMatch(s);

String stripArabicOrPersianScript(String s) =>
    s.replaceAll(arabicOrPersianScript, '');

/// Western digits + optional slash for expiry display.
class WesternDigitNormalizer extends TextInputFormatter {
  const WesternDigitNormalizer();
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final t = normalizeWesternDigits(newValue.text);
    if (t == newValue.text) return newValue;
    return TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length.clamp(0, t.length)),
    );
  }
}

/// Builds `MM/YY` or `MM/YYYY` from digit input; inserts `/` after the month.
class CardExpirySlashFormatter extends TextInputFormatter {
  const CardExpirySlashFormatter();
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalized = normalizeWesternDigits(newValue.text);
    var digits = normalized.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 6) digits = digits.substring(0, 6);

    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final mm = digits.length >= 2 ? digits.substring(0, 2) : digits;
    String out = mm;
    if (digits.length > 2) {
      out = '$mm/${digits.substring(2)}';
    }

    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: out.length),
    );
  }
}

/// ASCII digits only, after digit normalization (for CVV etc.).
class DigitsOnlyFormatter extends TextInputFormatter {
  const DigitsOnlyFormatter(this.maxLen);
  final int maxLen;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final d =
        normalizeWesternDigits(newValue.text).replaceAll(RegExp(r'\D'), '');
    final t = d.length > maxLen ? d.substring(0, maxLen) : d;
    return TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }
}
