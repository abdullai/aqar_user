import 'package:flutter/services.dart';

/// Converts Eastern Arabic digits (٠–٩) and Persian digits to Latin 0–9.
String arabicAndPersianDigitsToLatin(String input) {
  const map = {
    '٠': '0',
    '١': '1',
    '٢': '2',
    '٣': '3',
    '٤': '4',
    '٥': '5',
    '٦': '6',
    '٧': '7',
    '٨': '8',
    '٩': '9',
    '۰': '0',
    '۱': '1',
    '۲': '2',
    '۳': '3',
    '۴': '4',
    '۵': '5',
    '۶': '6',
    '۷': '7',
    '۸': '8',
    '۹': '9',
  };
  final buf = StringBuffer();
  for (final c in input.runes) {
    final s = String.fromCharCode(c);
    buf.write(map[s] ?? s);
  }
  return buf.toString();
}

/// Use on numeric fields (FAL, phone, CR, join code, etc.).
class ArabicDigitsToLatinFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final t = arabicAndPersianDigitsToLatin(newValue.text);
    if (t == newValue.text) return newValue;
    final removed = newValue.text.length - t.length;
    var end = newValue.selection.end - removed;
    end = end.clamp(0, t.length);
    return TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: end),
    );
  }
}

/// أرقام إنجليزية فقط مع قبول لصق/كتابة الأرقام العربية والفارسية.
List<TextInputFormatter> latinDigitsOnlyFormatters({int? maxLength}) {
  return [
    ArabicDigitsToLatinFormatter(),
    FilteringTextInputFormatter.digitsOnly,
    if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
  ];
}

/// رقم عشري إنجليزي؛ يقبل الفاصلة العربية/الإنجليزية ويحوّلها لنقطة عشرية للحفظ.
class LatinDecimalNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var t = arabicAndPersianDigitsToLatin(newValue.text)
        .replaceAll('٫', '.')
        .replaceAll(',', '.')
        .replaceAll('٬', '');
    t = t.replaceAll(RegExp(r'[^0-9.]'), '');
    final dot = t.indexOf('.');
    if (dot >= 0) {
      t = t.substring(0, dot + 1) + t.substring(dot + 1).replaceAll('.', '');
    }
    final end = newValue.selection.end.clamp(0, t.length);
    return TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: end),
    );
  }
}

List<TextInputFormatter> latinDecimalNumberFormatters({int? maxLength}) {
  return [
    LatinDecimalNumberFormatter(),
    if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
  ];
}

/// Blocks Latin letters [A-Za-z]. Digits and Arabic letters allowed.
class BlockLatinLettersFormatter extends TextInputFormatter {
  BlockLatinLettersFormatter(this.onBlocked);

  final VoidCallback onBlocked;

  static final _latin = RegExp(r'[A-Za-z]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!_latin.hasMatch(newValue.text)) return newValue;
    onBlocked();
    final cleaned = newValue.text.replaceAll(_latin, '');
    final sel = newValue.selection.end;
    final adj = sel - (newValue.text.length - cleaned.length);
    final pos = adj.clamp(0, cleaned.length);
    return TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: pos),
    );
  }
}
