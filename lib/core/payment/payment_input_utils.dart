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

/// اسم حامل البطاقة: لاتيني كبير فوراً — بلا حروف عربية/فارسية.
class CardHolderLatinUppercaseFormatter extends TextInputFormatter {
  const CardHolderLatinUppercaseFormatter();

  static final _allowed = RegExp(r'[^A-Z. \-]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final stripped = stripArabicOrPersianScript(newValue.text);
    var t = stripped.toUpperCase().replaceAll(_allowed, '');
    t = t.replaceAll(RegExp(r' {2,}'), ' ');
    final rawCaret = newValue.selection.baseOffset;
    final caret = rawCaret < 0
        ? 0
        : (rawCaret > newValue.text.length ? newValue.text.length : rawCaret);
    var before = stripArabicOrPersianScript(newValue.text.substring(0, caret))
        .toUpperCase()
        .replaceAll(_allowed, '');
    before = before.replaceAll(RegExp(r' {2,}'), ' ');
    final offset = before.length > t.length ? t.length : before.length;
    return TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

/// هل تاريخ MM / YY أو YYYY منتهٍ؟ القيم الناقصة لا تُعد منتهية.
bool isCardExpiryInPast(String month, String year) {
  final mm = int.tryParse(month.trim()) ?? 0;
  var yy = int.tryParse(year.trim()) ?? 0;
  if (yy <= 0 || mm < 1 || mm > 12) return false;
  if (yy < 100) yy += 2000;
  final endOfMonth = DateTime(yy, mm + 1, 0, 23, 59, 59);
  return DateTime.now().isAfter(endOfMonth);
}

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

/// رقم بطاقة: أرقام لاتينية، مجموعات من 4، بدون قلب المؤشر في RTL.
class CardPanFormatter extends TextInputFormatter {
  const CardPanFormatter({this.maxDigits = 19});

  final int maxDigits;

  static String grouped(String digits) {
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  static int _offsetForDigitCount(String grouped, int digitCount) {
    if (digitCount <= 0) return 0;
    var seen = 0;
    for (var i = 0; i < grouped.length; i++) {
      if (grouped[i] == ' ') continue;
      seen++;
      if (seen >= digitCount) return i + 1;
    }
    return grouped.length;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = normalizeWesternDigits(newValue.text);
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length > maxDigits) digits = digits.substring(0, maxDigits);
    final groupedText = grouped(digits);

    final caret = newValue.selection.baseOffset.clamp(0, newValue.text.length);
    final before = normalizeWesternDigits(newValue.text.substring(0, caret))
        .replaceAll(RegExp(r'\D'), '');
    var digitCaret = before.length;
    if (digitCaret > digits.length) digitCaret = digits.length;

    final offset = _offsetForDigitCount(groupedText, digitCaret);
    return TextEditingValue(
      text: groupedText,
      selection: TextSelection.collapsed(offset: offset),
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

    if (digits.length == 1) {
      final first = int.tryParse(digits) ?? 0;
      if (first > 1) digits = '0$digits';
    }
    if (digits.length >= 2) {
      var mm = int.tryParse(digits.substring(0, 2)) ?? 0;
      if (mm > 12) mm = 12;
      if (mm < 1) mm = 1;
      digits = mm.toString().padLeft(2, '0') + digits.substring(2);
    }

    final mm = digits.length >= 2 ? digits.substring(0, 2) : digits;
    var out = mm;
    if (digits.length > 2) {
      out = '$mm/${digits.substring(2)}';
    } else if (digits.length == 2) {
      out = '$mm/';
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
