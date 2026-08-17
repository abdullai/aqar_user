// نصوص سياسات المنصة (ملخصات تشغيلية) — تُستبدل بنصوص معتمدة عند الترخيص النهائي.

enum PlatformPolicyDoc {
  termsOfUse,
  privacy,
  intellectualProperty,
  cookies,
}

abstract final class PlatformPolicyCopy {
  static String title(PlatformPolicyDoc d, bool ar) {
    switch (d) {
      case PlatformPolicyDoc.termsOfUse:
        return ar ? 'شروط استخدام المنصة' : 'Platform terms of use';
      case PlatformPolicyDoc.privacy:
        return ar ? 'سياسة الخصوصية' : 'Privacy policy';
      case PlatformPolicyDoc.intellectualProperty:
        return ar ? 'حقوق الملكية الفكرية' : 'Intellectual property';
      case PlatformPolicyDoc.cookies:
        return ar ? 'سياسة الكوكيز والتخزين المحلي' : 'Cookies & local storage';
    }
  }

  static String body(PlatformPolicyDoc d, bool ar) {
    switch (d) {
      case PlatformPolicyDoc.termsOfUse:
        return ar ? _termsAr : _termsEn;
      case PlatformPolicyDoc.privacy:
        return ar ? _privacyAr : _privacyEn;
      case PlatformPolicyDoc.intellectualProperty:
        return ar ? _ipAr : _ipEn;
      case PlatformPolicyDoc.cookies:
        return ar ? _cookiesAr : _cookiesEn;
    }
  }

  static const _termsAr =
      'منصة «مؤسسة موثوق لاين العقارية» الإلكترونية مخصّصة وفق التعريف النظامي للأنشطة المساندة للتسويق والإعلان العقاري (بما في ذلك الوساطة العقارية ضمن السجل التجاري ونشاط ISIC 682010 حيث ينطبق). '
      'يلتزم المستخدم بتقديم معلومات صحيحة، وعدم الإخلال بالأنظمة المعمول بها في المملكة العربية السعودية، وعدم استخدام المنصة لأغراض احتيالية أو مضللة. '
      'يُحظر انتحال اسم منشأة أو منصة أخرى أو استخدام أسماء مضللة. يحق لمشغّل المنصة تعليق الحساب أو تقييد الخدمات عند مخالفة الشروط أو طلب الجهات المختصة. '
      'للتفاصيل الكاملة والنسخ المعتمدة يُرفق مع ملف الترخيص نسخ محدّثة من هذه الوثائق.';

  static const _termsEn =
      'The «Mawthuq Line Real Estate Establishment» electronic platform is intended for real-estate marketing and brokerage-related activities under applicable Saudi regulations (including commercial registration activity and ISIC 682010 where applicable). '
      'Users must provide accurate information, comply with Saudi laws, and must not use the platform for fraud or misleading practices. Misleading names or impersonation of another platform or establishment are prohibited. '
      'The operator may suspend or restrict access for violations or competent-authority requests. Certified legal copies accompany the licensing file.';

  static const _privacyAr =
      'تُعالج البيانات الشخصية وفق أنظمة حماية البيانات الشخصية في المملكة العربية السعودية وبما يلزم لتشغيل المنصة (الحساب، التحقق، الإعلانات، الرسائل، والسجلات الفنية). '
      'لا يُشارك محتوى تعريفي حساس مع أطراف ثالثة إلا بموجب نص تشغيلي أو طلب نظامي. يمكن للمستخدم طلب تصحيحاً أو حذفاً وفق السياسة الداخلية وآلية الشكاوى. '
      'يُنصح بمراجعة إعدادات الجهاز والمتصفح للأذونات (الموقع اختياري لتحسين الاستكشاف).';

  static const _privacyEn =
      'Personal data is processed in line with Saudi PDPL requirements and what is necessary to operate the platform (accounting, verification, listings, messaging, and technical logs). '
      'Sensitive identifying content is not shared with third parties except under operational/legal grounds. Users may request correction or deletion per internal policy and the complaints channel. '
      'Review device/browser permissions (location is optional for discovery features).';

  static const _ipAr =
      'العلامات والشعارات والواجهات والمحتوى البرمجي للمنصة محمية بموجب حقوق الملكية الفكرية لمشغّل المنصة أو المرخّص له. '
      'يُمنع نسخ أو إعادة توزيع مكونات المنصة أو استخراج قواعد البيانات بطرق تخالف الترخيص. المحتوى الذي يرفعه المستخدمون يبقى ملكاً لهم مع منح المنصة ترخيصاً تشغيلياً لعرضه وربطه بالخدمات.';

  static const _ipEn =
      'Branding, UI, and software of the platform are protected as the operator’s or licensee’s intellectual property. '
      'Copying, redistribution, or systematic extraction contrary to license terms is prohibited. User-uploaded content remains owned by users with a limited license to the operator to display and link to services.';

  static const _cookiesAr =
      'تستخدم المنصة ملفات تعريف ارتباط وتخزيناً محلياً ضرورياً للجلسة والأمان واللغة والتفضيلات، ولن تُعطّل هذه الوظائف دون التأثير على تسجيل الدخول أو الحماية. '
      'يمكن للمستخدم مسح بيانات الموقع من المتصفح؛ قد يُطلب إعادة التحقق أو تسجيل الدخول. لا تُستخدم الكوكيز لإعلانات طرف ثالث داخل التطبيق ما لم يُعلَن لاحقاً ويُفعَّل خيار صريح.';

  static const _cookiesEn =
      'The platform uses cookies and local storage necessary for sessions, security, language, and preferences; disabling them may require re-authentication. '
      'Clearing site data in the browser may reset device binding and login proof flags. Third‑party ad cookies are not used in-app unless explicitly announced and opted in.';
}

abstract final class RegulatoryOperatorChecklistCopy {
  static String full(bool ar) => ar ? _checkAr : _checkEn;

  static const _checkAr =
      'قائمة تحضيرية لمشغّل المنصة العقارية الإلكترونية (للمراجعة مع مستشار نظامي):\n\n'
      '1) سجل تجاري ساري يتضمن نشاط الوساطة العقارية والرمز 682010 حيث ينطبق.\n'
      '2) نشر: سياسة الملكية الفكرية، وشروط الخصوصية، وشروط الاستخدام داخل المنصة (مفعّل في الإعدادات).\n'
      '3) شهادة التوثيق من المركز السعودي للأعمال وربطها إلكترونياً عند توفر الرابط الرسمي.\n'
      '4) وثائق ملكية المنصة: DNS من الاستضافة، سجل النطاق Domain، شهادة SSL تظهر النطاق.\n'
      '5) وصف المنصة بما يطابق تعريف «التسويق للإعلان العقاري» في طلب الترخيص.\n'
      '6) المدير المسؤول: اجتياز دورات الوساطة والتسويق العقاري والتسويق الإلكتروني، والأهلية النظامية.\n'
      '7) قناة شكاوى فعّالة (بريد/صفحة) وآلية معالجة موثّقة.\n'
      '8) ربط النفاذ الوطني لدخول المعلنين — يتطلب تكاملاً رسمياً ويُفعَّل من الخلفية عند اعتماد البيانات.\n'
      '9) ربط الهيئة العامة للعقار — تكامل برمجي واعتمادات من الجهة.\n'
      '10) سداد الرسوم الحكومية واستكمال الطلب في بوابة الهيئة.\n\n'
      'هذا الملخص لا يغني عن مراجعة النماذج الرسمية الصادرة عن الهيئة العامة للعقار.';

  static const _checkEn =
      'Operator preparation checklist (review with legal counsel):\n\n'
      '1) Valid commercial registration including brokerage activity / ISIC 682010 where applicable.\n'
      '2) Publish: IP policy, privacy policy, and terms of use inside the app (Settings → Compliance).\n'
      '3) Saudi Business Center certification and electronic linkage when official endpoints are available.\n'
      '4) Platform ownership evidence: hosting DNS screenshot, domain WHOIS, SSL certificate showing the domain.\n'
      '5) Platform description aligned with the licensed definition (real-estate advertising marketing).\n'
      '6) Responsible manager: mandated training completion and eligibility requirements.\n'
      '7) Complaints channel with documented handling workflow.\n'
      '8) Nafath for advertiser login — requires approved government integration.\n'
      '9) REGA electronic linkage — requires approved APIs/contracts.\n'
      '10) Government fee payment and final submission in the official portal.\n\n'
      'This summary does not replace official REGA forms.';
}
