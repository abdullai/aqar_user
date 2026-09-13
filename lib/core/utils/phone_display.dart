import 'date_helper.dart';

/// عرض أرقام الجوال السعودية دون انقلاب الاتجاه في العربية.
abstract final class PhoneDisplay {
  PhoneDisplay._();

  static String digitsOnly(String raw) => raw.replaceAll(RegExp(r'\D'), '');

  /// رقم سعودي محلي من 10 أرقام يبدأ بـ 05 — بلا مفتاح دولة.
  static String localTenDigits(String raw) {
    var d = digitsOnly(raw);
    if (d.startsWith('00')) d = d.substring(2);
    if (d.startsWith('966') && d.length >= 12) {
      d = '0${d.substring(3)}';
    } else if (d.length == 9 && !d.startsWith('0')) {
      d = '0$d';
    }
    if (d.length > 10) d = d.substring(d.length - 10);
    return d;
  }

  /// عرض الهاتف في الواجهة: 05XXXXXXXX فقط، بلا +966.
  static String forUi(String raw, {required bool isAr}) {
    final local = localTenDigits(raw);
    if (local.isEmpty) return '';
    return DateHelper.ltrIsolate(local);
  }
}
