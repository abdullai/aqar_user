/// تلميح عرض فقط — التحقق النهائي عند الربط ببوابة معتمدة.
String detectCardSchemeFromPan(String panDigits) {
  const from = '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹';
  const to = '01234567890123456789';
  final buf = StringBuffer();
  for (final ch in panDigits.runes) {
    final c = String.fromCharCode(ch);
    final i = from.indexOf(c);
    buf.write(i >= 0 ? to[i] : c);
  }
  final d = buf.toString().replaceAll(RegExp(r'\D'), '');
  if (d.length < 6) return 'unknown';
  const mada6 = <String>{
    '400861', '401607', '405454', '406136', '407197', '407395', '409201',
    '410685', '412565', '417633', '419593', '422817', '422818', '422819',
    '428331', '428671', '431361', '432328', '434107', '439954', '440533',
    '440647', '440795', '445564', '446393', '446404', '446672', '455036',
    '455708', '455836', '457865', '457866', '458456', '462220', '468540',
    '468541', '468542', '468543', '483010', '483011', '483012', '484783',
    '486094', '486095', '486096', '489415', '489416', '492564', '493428',
    '504300', '506968', '508160', '513213', '520058', '521076', '524130',
    '524514', '529415', '531196', '535825', '535989', '536023', '537767',
    '539931', '543085', '543357', '549760', '554180', '557606', '557607',
    '558563', '585265', '588845', '588846', '588847', '588848', '588849',
    '588850', '600829', '601699', '636120', '968201', '968202', '968203',
    '968204', '968205', '968206', '968207', '968208', '968209', '968210',
    '968211',
  };
  final bin6 = d.length >= 6 ? d.substring(0, 6) : '';
  if (mada6.contains(bin6)) return 'mada';
  if (d.startsWith('34') || d.startsWith('37')) return 'amex';
  if (RegExp(r'^5[1-5]').hasMatch(d) || RegExp(r'^2[2-7]\d{2}').hasMatch(d)) {
    return 'mastercard';
  }
  if (d.startsWith('4')) return 'visa';
  if (d.startsWith('62')) return 'unionpay';
  return 'unknown';
}

String cardSchemeDisplayLabel(String scheme, {required bool isAr}) {
  switch (scheme) {
    case 'visa':
      return 'Visa';
    case 'mastercard':
      return 'Mastercard';
    case 'mada':
      return isAr ? 'مدى' : 'mada';
    case 'amex':
      return 'American Express';
    case 'unionpay':
      return 'UnionPay';
    default:
      return '';
  }
}

int cardSchemeMaxPanDigits(String scheme) {
  switch (scheme) {
    case 'amex':
      return 15;
    case 'visa':
      return 19;
    default:
      return 16;
  }
}
