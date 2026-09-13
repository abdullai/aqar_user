/// تعليقات جاهزة بلا أرقام — سريعة ولا تكشف تواصلاً خارج المنصة.
abstract final class ShortsCannedComments {
  static List<String> forItem({
    required bool isAr,
    required bool isProperty,
    required bool isRent,
  }) {
    if (isAr) {
      if (isProperty) {
        return [
          if (isRent) 'الإيجار مناسب لي' else 'السعر ضمن ميزانيتي',
          'أرغب في معاينة العقار',
          'الموقع مناسب',
          'أحتاج تفاصيل إضافية',
          'واجهات العقار أعجبتني',
          if (isRent) 'ما مدة عقد الإيجار؟' else 'هل السعر قابل للتفاوض؟',
          'أفكر جدياً في هذا الإعلان',
        ];
      }
      return [
        'أستطيع تقديم عرض مناسب',
        'الطلب واضح ومناسب',
        'لدي عقار يطابق المواصفات',
        'الميزانية معقولة',
        'أتواصل عبر العرض داخل التطبيق',
      ];
    }
    if (isProperty) {
      return [
        if (isRent) 'The rent works for me' else 'The price is in my range',
        'I would like a viewing',
        'The location looks right',
        'I need a few more details',
        'The photos look great',
        if (isRent) 'What is the lease term?' else 'Is the price negotiable?',
        'I am seriously considering this',
      ];
    }
    return [
      'I can submit a matching offer',
      'The request is clear',
      'I have a property that fits',
      'The budget looks reasonable',
      'I will reply via in-app offer',
    ];
  }
}
