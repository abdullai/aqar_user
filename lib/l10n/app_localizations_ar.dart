// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'تطبيق موثوق العقاري';

  @override
  String get welcomeTitle => 'مرحباً بك';

  @override
  String get welcomeTrustedAqar => 'مرحباً بك في موثوق العقاري';

  @override
  String get signInToContinue => 'سجّل الدخول للمتابعة';

  @override
  String get userSignIn => 'تسجيل الدخول';

  @override
  String get allFieldsRequired => 'يرجى تعبئة جميع الحقول';

  @override
  String get usernameMustBe10Digits => 'اسم المستخدم يجب أن يكون 10 أرقام';

  @override
  String get passwordTooShort => 'كلمة المرور قصيرة جداً';

  @override
  String get invalidCredentials => 'بيانات الدخول غير صحيحة';

  @override
  String get rememberMe => 'ذكرني';

  @override
  String get quickLogin => 'دخول سريع';

  @override
  String get quickLoginSubtitle =>
      'افتح القفل برمز الجهاز أو البصمة أو الوجه إن فعّلت ذلك من الإعدادات.';

  @override
  String get forgotUsernameOrPassword => 'نسيت اسم المستخدم أو كلمة المرور؟';

  @override
  String get theme => 'المظهر';

  @override
  String get themeLight => 'فاتح';

  @override
  String get themeDark => 'داكن';

  @override
  String get themeSystem => 'حسب النظام';

  @override
  String get language => 'اللغة';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageEnglish => 'English';

  @override
  String get settings => 'الإعدادات';

  @override
  String get settingsAppearanceLanguageSection => 'المظهر واللغة';

  @override
  String get settingsAppearanceHubSubtitle =>
      'اللغة والمظهر الداكن ولون التمييز — من مكان واحد.';

  @override
  String get settingsHapticsTitle => 'الاهتزاز';

  @override
  String get settingsHapticsSubtitle =>
      'اهتزاز خفيف عند التفاعل مع بعض العناصر (الجوال فقط).';

  @override
  String get settingsDarkModeSubtitle => 'تفعيل الألوان الداكنة في التطبيق';

  @override
  String get settingsInAppNotificationSoundTitle => 'صوت تنبيه الإشعارات';

  @override
  String get settingsInAppNotificationSoundSubtitle =>
      'الويب: نغمة من أصول التطبيق. الهاتف/اللوحي: اهتزاز وصوت نظام قصير حتى لا يتصادم مع نغمات قنوات الإشعارات التي تضبطها. FCM في المقدمة بلا صوت؛ في الخلفية عبر إشعارات النظام. رمز التحقق: الويب ينطق نغمة الأصول مع شريط عائم؛ الجوال عبر قناة OTP (نغمة/اهتزاز النظام).';

  @override
  String get settingsChatMessageSoundTitle => 'صوت رسائل المحادثة';

  @override
  String get settingsChatMessageSoundSubtitle =>
      'الويب: نغمة من الأصول. الهاتف/اللوحي: اهتزاز خفيف ونقرة نظام (بدون ملف WAV). منفصلة عن شريط الإشعارات الداخلي وأصوات الدفع.';

  @override
  String get legalTermsCoachTitle => 'الشروط والخصوصية';

  @override
  String get legalTermsCoachBody =>
      'يمكنك مراجعة الشروط وسياسة الخصوصية من الإعدادات في أي وقت. قد يُطلب القبول عند تسجيل الدخول.';

  @override
  String get legalTermsCoachOk => 'حسناً';

  @override
  String get fieldGroupCredentialsTitle => 'بيانات الدخول';

  @override
  String get fieldGroupCredentialsSubtitle => 'رقمك المميز وكلمة المرور';

  @override
  String get fieldGroupOtpTitle => 'رمز التحقق';

  @override
  String get fieldGroupOtpSubtitle => 'أدخل الأرقام المرسلة إليك';

  @override
  String get fieldGroupGateTitle => 'كيف تريد المتابعة؟';

  @override
  String get fieldGroupVerificationFalTitle => 'رخصة الوساطة وبيانات التواصل';

  @override
  String get fieldGroupVerificationFalSubtitle =>
      'التحقق من فال وتفاصيل الوسيط لهذا الطلب.';

  @override
  String get fieldGroupVerificationOrgTitle => 'المنشأة والسجل التجاري';

  @override
  String get fieldGroupVerificationOrgSubtitle =>
      'اسم المكتب والسجل التجاري الموحّد عند الحاجة.';

  @override
  String get fieldGroupVerificationOptionalLicenseTitle => 'مرجع الترخيص';

  @override
  String get fieldGroupVerificationOptionalLicenseSubtitle =>
      'إن وُجد رقم ترخيص أدخله هنا.';

  @override
  String get fieldGroupVerificationMoreTitle => 'الفريق والملاحظات';

  @override
  String get fieldGroupVerificationMoreSubtitle =>
      'رمز انضمام فريق (اختياري) ورسالة للمراجعين.';

  @override
  String get fieldGroupVerificationDocumentsTitle => 'المستندات';

  @override
  String get fieldGroupVerificationDocumentsSubtitle =>
      'ارفع ملفات PDF أو صور للتحقق.';

  @override
  String get fieldGroupFalRenewalTitle => 'تجديد الرخصة';

  @override
  String get fieldGroupFalRenewalSubtitle => 'أدخل رقم فال للتحقق عبر الهيئة.';

  @override
  String get fieldGroupListingRequestTitle => 'طلب تسويق عقار';

  @override
  String get fieldGroupListingRequestSubtitle =>
      'عنوان العقار والمدينة وإحداثيات الخريطة.';

  @override
  String get fieldGroupListingRequestSubmit => 'إرسال الطلب';

  @override
  String get listingRequestFieldTitleLabel => 'عنوان العقار';

  @override
  String get listingRequestFieldCityLabel => 'المدينة';

  @override
  String get listingRequestFieldLatLabel => 'خط العرض';

  @override
  String get listingRequestFieldLngLabel => 'خط الطول';

  @override
  String get mapPickerHuaweiNoGmsBanner =>
      'قد لا تُحمّل خرائط Google على بعض أجهزة هواوي/هونر بدون خدمات Google. استخدم البحث أو اعتماد الإحداثيات يدوياً.';

  @override
  String get mapPickerMapLoadStalledBanner =>
      'الخريطة بطيئة أو لم تكتمل. استخدم البحث بالمدينة، أو أدخل خطي الطول/العرض، أو افتح خرائط Google خارج التطبيق.';

  @override
  String get mapPickerOpenExternalMaps => 'فتح في تطبيق الخرائط';

  @override
  String get welcomeDashboardBannerTitle => 'مرحباً بك في موثوق العقاري';

  @override
  String get welcomeDashboardBannerBody =>
      'تصفّح العقارات من الرئيسية، وإعلاناتك من «صفحتي»، والإعدادات من الأعلى. يمكنك إيقاف صوت التنبيهات من الإعدادات.';

  @override
  String get welcomeDashboardBannerButton => 'حسناً';

  @override
  String get usernameHint10Digits => 'الرقم المميز (10 أرقام)';

  @override
  String get loginUsernameFieldHelper =>
      'هوية/إقامة، رخصة فال، أو الرقم الوطني الموحّد 700… (10 أرقام)';

  @override
  String get loginIdentifierFieldLabel =>
      'الهوية أو السجل الموحّد أو رخصة فال — 10 أرقام';

  @override
  String get loginPasswordFieldLabel => 'أدخل كلمة المرور';

  @override
  String get loginPasswordFieldShortLabel => 'كلمة المرور';

  @override
  String get passwordHint => 'كلمة المرور';

  @override
  String get passwordArabicKeyboardHint =>
      'يُفضّل إدخال كلمة المرور بالإنجليزية أو الأرقام. غيّر لغة لوحة المفاتيح إن لزم.';

  @override
  String get rightPanelTitle => 'بوابتك للعقار الموثّق';

  @override
  String get rightPanelSubtitle =>
      'تحقّق من الرخص، تواصل بأمان، وتابع العروض في تجربة واحدة متماسكة مع هوية موثوق.';

  @override
  String get noEnabledAds => 'لا توجد إعلانات مفعلة حالياً';

  @override
  String get accountLockedTitle => 'تم قفل الحساب';

  @override
  String get accountLockedBody =>
      'تم قفل الحساب بسبب محاولات دخول متعددة. استخدم الاستعادة.';

  @override
  String get recover => 'استعادة';

  @override
  String get verifyTitle => 'التحقق';

  @override
  String get otpTitle => 'التحقق';

  @override
  String get verifySubtitle => 'أدخل رمز التحقق';

  @override
  String get confirm => 'تأكيد';

  @override
  String get clear => 'مسح';

  @override
  String get securityAlert => 'تنبيه أمني';

  @override
  String get verifyTimeout => 'انتهت مدة التحقق';

  @override
  String get invalidCode => 'رمز التحقق غير صحيح';

  @override
  String get accountLocked => 'تم قفل الحساب';

  @override
  String get notificationDefaultTitle => 'إشعار';

  @override
  String get listingStagesTitle => 'مراحل الإعلان';

  @override
  String get marketingStagesTitle => 'مراحل التسويق';

  @override
  String get marketingStepInvite => 'دعوة';

  @override
  String get marketingStepOffer => 'عرض';

  @override
  String get marketingStepContract => 'عقد';

  @override
  String get marketingStepPermit => 'تصريح';

  @override
  String get marketingStepPublish => 'نشر';

  @override
  String ownerOfferRejectionReason(Object reason) {
    return 'سبب إعادة/رفض العرض: $reason';
  }

  @override
  String get notificationsTitle => 'الإشعارات';

  @override
  String get noNewNotifications => 'لا توجد إشعارات جديدة';

  @override
  String get closeLabel => 'إغلاق';

  @override
  String get retryLabel => 'إعادة المحاولة';

  @override
  String get offlineNoInternetTitle => 'لا يوجد اتصال بالإنترنت';

  @override
  String get offlineNoInternetBody =>
      'لن يبدأ التطبيق بدون إنترنت. فعّل الإنترنت ثم أعد المحاولة.';

  @override
  String get loginRequiredDialogTitle => 'تسجيل الدخول';

  @override
  String get loginRequiredDialogMessage =>
      'يجب تسجيل الدخول للوصول إلى هذه الميزة. هل تريد تسجيل الدخول الآن؟';

  @override
  String get laterLabel => 'لاحقاً';

  @override
  String get loginToManageListingsBody => 'سجّل الدخول لإدارة إعلاناتك';

  @override
  String get preparingMarketingTabsTitle => 'جارٍ تجهيز تبويبات التسويق';

  @override
  String get preparingListingsTabsTitle => 'جارٍ تجهيز تبويبات الإعلانات';

  @override
  String get ifContinuesTapRetry => 'إذا استمر ذلك، اضغط إعادة المحاولة.';

  @override
  String get myAdsOwnerTabWaitingMediator => '🤝 بانتظار المسوّقين';

  @override
  String get myAdsOwnerTabAwaitContract => '📝 التعاقد';

  @override
  String get myAdsOwnerTabPublishedHome => '🏡 منشور في الرئيسية';

  @override
  String get myAdsEmptyWaitingMediator => 'لا توجد إعلانات بانتظار مسوّقين';

  @override
  String get myAdsEmptyAwaitContract => 'لا توجد إعلانات في مرحلة التعاقد';

  @override
  String get myAdsEmptyPublishedHome => 'لا توجد إعلانات منشورة';

  @override
  String get marketerTabInvites => '🏢 السوق العقاري';

  @override
  String get marketerTabAwaitingOwner => '⏳ بانتظار موافقة المالك · التعاقد';

  @override
  String get marketerTabMyOffers => '💼 عروضي';

  @override
  String get marketerTabContracts => '📄 العقود';

  @override
  String get marketerTabPermits => '✅ التصاريح';

  @override
  String get marketerTabPublished => '🚀 المنشور';

  @override
  String get marketerEmptyInvites => 'لا طلبات تسويق ظاهرة في السوق حالياً';

  @override
  String get marketerBtnPropertyListingDetails => 'تفاصيل الإعلان العقاري';

  @override
  String get ownerBtnRealEstateOffers => 'العروض العقارية';

  @override
  String get marketerEmptyOffers => 'لا توجد عروض';

  @override
  String get marketerEmptyContracts => 'لا توجد عقود';

  @override
  String get marketerEmptyPermits => 'لا توجد تصاريح';

  @override
  String get marketerEmptyPublished => 'لا توجد إعلانات منشورة';

  @override
  String get listingsControlHubTitle => 'لوحة إدارة الإعلانات';

  @override
  String get marketerFullScenarioGuideTooltip =>
      'المسار الكامل: دعوة → قرار المالك → عقد → تصريح REGA → نشر — والإشعارات';

  @override
  String get marketerFullScenarioSheetTitle => 'مسار التسويق الاحترافي';

  @override
  String get marketerFullScenarioOpenInbox => 'فتح صندوق الإشعارات';

  @override
  String get marketerFullScenarioUnderstood => 'حسناً';

  @override
  String get ownerFullScenarioGuideTooltip =>
      'مسار المعلن: العروض → العقد → تصريح REGA → نشر — والإشعارات';

  @override
  String get ownerFullScenarioSheetTitle => 'مسار إعلانك في التسويق';

  @override
  String get scenarioOpenRequestStatusButton => 'فتح حالة الطلب';

  @override
  String get workflowGuideDialogButton => 'شرح المسار الكامل';

  @override
  String get workflowGuideSheetIntro =>
      'اتبع الخطوات المرقّمة. الإشعارات تربطك بكل مرحلة حتى لا يفوتك شيء.';

  @override
  String get listingRequestStatusWorkflowTooltip =>
      'فتح دليل المسار خطوة بخطوة لهذا الطلب';

  @override
  String get workflowGuideHubSubtitle =>
      'تلميح: اضغط أيقونة المسار بجانب العنوان لعرض الخطوات كاملة واختصارات الإشعارات.';

  @override
  String get navHome => 'الرئيسية';

  @override
  String get navMyAds => 'صفحتي';

  @override
  String get navFavorites => 'المفضلة';

  @override
  String get navAdd => 'إضافة إعلان';

  @override
  String get navMyDesk => 'إدارتي';

  @override
  String get navMyDeskPipelineBadgeTooltip =>
      'إدارتي: لوحة الإحصاءات والفريق وإدارة العمل حسب نوع الحساب.';

  @override
  String get navCart => 'صفقاتي';

  @override
  String get navReservations => 'العقارات المحجوزة';

  @override
  String get navChat => 'الدردشة';

  @override
  String get navMySubmissions => 'طلباتي/إعلاناتي';

  @override
  String get navSupport => 'الدعم الفني';

  @override
  String get communicationHubTitle => 'الإشعارات والمحادثات';

  @override
  String get communicationHubNotificationsTab => 'الإشعارات';

  @override
  String get communicationHubChatsTab => 'المحادثات';

  @override
  String get openChatInboxButton => 'فتح صندوق المحادثات';

  @override
  String get communicationHubChatsHint =>
      'جميع أنواع المحادثة (عقار، حجز، طلب سوق، دعم…) تُدار من صندوق المحادثات.';

  @override
  String get supportHubTechnicalTab => 'الدعم الفني';

  @override
  String get supportHubAdminTab => 'الإدارة';

  @override
  String get supportHubTicketsTab => 'التذاكر';

  @override
  String get supportHubAdminSoon =>
      'قريباً: التواصل مع الإدارة وربط الطلبات الرسمية.';

  @override
  String get supportHubTicketsSoon =>
      'قريباً: رفع وتتبع تذاكر الدعم والمتابعة مع الإدارة.';

  @override
  String get settingsSupportMovedHint =>
      'الدعم الفني والتواصل مع الإدارة أصبح في تبويب «الدعم الفني» بالأسفل.';

  @override
  String get mySubmissionsSectionListings => 'إعلاناتي';

  @override
  String get mySubmissionsSectionRequests => 'طلبات عقارية';

  @override
  String get mySubmissionsEmpty =>
      'لا توجد إعلانات أو طلبات سوق منشورة منك بعد.';

  @override
  String get cartMarketOffersSectionTitle => 'عروض على طلباتي';

  @override
  String get cartMarketOffersEmptyHint =>
      'عندما يقدّم أحدهم عرضاً على طلبك العقاري يظهر هنا للمتابعة.';

  @override
  String get marketPropertySubmitSuccessTitle => 'شكراً لك شريكنا العقاري';

  @override
  String get marketPropertySubmitSuccessBody =>
      'تم تقديم طلبك العقاري بنجاح. يظهر للمهتمين وفق السياسات المعتمدة، ويمكنك متابعته من تبويب «طلباتي/إعلاناتي».';

  @override
  String get marketPropertySubmitGoHome => 'العودة للرئيسية';

  @override
  String get marketPropertySubmitAnother => 'طلب عقاري آخر';

  @override
  String get supportLabel => 'الدعم الفني';

  @override
  String get logoutLabel => 'تسجيل خروج';

  @override
  String get settingsLabel => 'الإعدادات';

  @override
  String get loginNowLabel => 'تسجيل الدخول الآن';

  @override
  String get noInternetConnectionTitle => 'لا يوجد اتصال بالإنترنت';

  @override
  String get ensureInternetThenRetry =>
      'تأكد من اتصال الإنترنت ثم أعد المحاولة.';

  @override
  String get offlineGlobalOverlayHint =>
      'جلسة تسجيل الدخول تبقى على هذا الجهاز. عند عودة الاتصال يكتشف التطبيق ذلك تلقائياً — أو اضغط إعادة المحاولة. لن يُعاد توجيهك لتسجيل الدخول ما لم تخرج بنفسك.';

  @override
  String get refreshLabel => 'تحديث';

  @override
  String get failedToLoadAds => 'تعذر تحميل الإعلانات';

  @override
  String get failedToLoadCart => 'تعذر تحميل صفقاتك';

  @override
  String get failedToLoadReservations => 'تعذر تحميل الحجوزات';

  @override
  String get changePasswordTitle => 'تغيير كلمة المرور';

  @override
  String get currentPasswordLabel => 'كلمة المرور الحالية';

  @override
  String get newPasswordLabel => 'كلمة المرور الجديدة';

  @override
  String get confirmNewPasswordLabel => 'تأكيد كلمة المرور الجديدة';

  @override
  String get savePassword => 'تحديث كلمة المرور';

  @override
  String get passwordChangedSuccess => 'تم تحديث كلمة المرور بنجاح';

  @override
  String get changePasswordFailed => 'تعذر تغيير كلمة المرور';

  @override
  String get wrongCurrentPassword => 'كلمة المرور الحالية غير صحيحة';

  @override
  String get profileChangePhoto => 'تغيير الصورة الشخصية';

  @override
  String get profilePhotoUploading => 'جاري الرفع…';

  @override
  String get profilePhotoUpdated => 'تم تحديث الصورة';

  @override
  String get profilePhotoFailed => 'تعذر تحديث الصورة';

  @override
  String get fullNameLabel => 'الاسم الكامل';

  @override
  String get accountCategoryLabel => 'نوع الحساب';

  @override
  String get permissionRoleLabel => 'الصلاحية / الدور';

  @override
  String get changeQuickPin => 'تغيير رمز الدخول السريع';

  @override
  String get newPinLabel => 'رمز جديد (6 أرقام)';

  @override
  String get confirmPinLabel => 'تأكيد الرمز';

  @override
  String get pinUpdated => 'تم تحديث الرمز';

  @override
  String get pinMismatch => 'الرمزان غير متطابقين';

  @override
  String get biometricNotAvailable => 'البصمة غير متاحة على هذا الجهاز';

  @override
  String get fastLoginAfterLoginHint =>
      'بعد تسجيل الدخول يمكنك تفعيل الدخول السريع من الإعدادات (للجوال فقط).';

  @override
  String get fastLoginOfferTitle => 'تسجيل دخول أسرع لاحقاً؟';

  @override
  String get fastLoginOfferBody =>
      'يمكنك تفعيل رمز PIN سريع أو البصمة/الوجه إن وفره جهازك. يمكنك تغيير ذلك لاحقاً من الإعدادات.';

  @override
  String get fastLoginOfferOpenSettings => 'فتح الإعدادات';

  @override
  String get fastLoginOfferBiometric => 'تفعيل البصمة أو الوجه';

  @override
  String get fastLoginOfferNotNow => 'لا، شكراً';

  @override
  String get fastLoginOfferRemindLater => 'ذكرني لاحقاً';

  @override
  String get legalTermsTitle => 'الشروط والأحكام';

  @override
  String get legalAccept => 'أوافق';

  @override
  String get legalDecline => 'أرفض';

  @override
  String get legalDeclineTitle => 'لا يمكن المتابعة';

  @override
  String get legalDeclineBody => 'يجب الموافقة على الشروط لاستخدام التطبيق.';

  @override
  String get legalTermsFallbackBody =>
      'تعذر تحميل نص الشروط والخصوصية من الخادم. بمتابعتك فإنك توافق على استخدام «موثوق العقاري» وفق الأنظمة المعمول بها في المملكة العربية السعودية بما في ذلك قواعد حماية البيانات الشخصية حيث تنطبق، وتقديم معلومات صحيحة، واستخدام الإعلانات والمراسلة بمسؤولية. للاطلاع على النص الكامل تواصل مع الدعم أو أعد المحاولة لاحقاً.';

  @override
  String get permissionsGateTitle => 'قبل أن نبدأ';

  @override
  String get permissionsGateSubtitle =>
      'نطلب الأذونات بترتيب شائع: الإشعارات (الدردشة والتحديثات)، ثم الموقع (الخريطة والدقة)، ثم الصور والكاميرا (صور الإعلانات). يمكنك التخطي الآن والتفعيل لاحقاً من الإعدادات أو عندما يطلبها التطبيق.';

  @override
  String get permissionsGateWebSubtitle =>
      'على الويب يطلب المتصفح إذن الإشعارات والموقع عند الحاجة. السماح بالموقع يفعّل دقة الخريطة والأقرب لك، والمعرض والكاميرا تتم عبر المتصفح أو اختيار ملفات.';

  @override
  String get permissionsGateContinueAllow => 'متابعة والسماح';

  @override
  String get permissionsGateNotNow => 'ليس الآن';

  @override
  String get permissionsGateOpenSettings => 'فتح الإعدادات';

  @override
  String get permissionsGateNotificationsTitle => 'الإشعارات';

  @override
  String get permissionsGateNotificationsDesc =>
      'تنبيهات الدردشة والحجوزات ونشاط الإعلانات.';

  @override
  String get permissionsGateLocationTitle => 'الموقع';

  @override
  String get permissionsGateLocationDesc =>
      'تحديد مواقع العقارات على الخريطة وتحسين الدقة القريبة.';

  @override
  String get permissionsGatePhotosTitle => 'الصور / المعرض';

  @override
  String get permissionsGatePhotosDesc => 'إرفاق صور للإعلانات والمرفقات.';

  @override
  String get permissionsGateCameraTitle => 'الكاميرا';

  @override
  String get permissionsGateCameraDesc => 'التقاط صور للإعلان مباشرة.';

  @override
  String get permissionsGateDesktopNote =>
      'على الكمبيوتر غالباً تُختار الصور من الملفات؛ قد لا تظهر أذونات معرض كالجوال.';

  @override
  String get permissionRationalePhotosTitle => 'يلزم إذن الصور';

  @override
  String get permissionRationalePhotosBody =>
      'الوصول للصور معطّل. افتح إعدادات النظام واسمح بالمعرض ثم أعد المحاولة.';

  @override
  String get permissionRationaleCameraTitle => 'يلزم إذن الكاميرا';

  @override
  String get permissionRationaleCameraBody =>
      'الكاميرا معطّلة. افتح إعدادات النظام واسمح بالكاميرا ثم أعد المحاولة.';

  @override
  String get permissionRationaleNotificationsTitle => 'الإشعارات متوقفة';

  @override
  String get permissionRationaleNotificationsBody =>
      'الإشعارات غير مفعّلة لهذا التطبيق. فعّلها من إعدادات النظام لتصلك التنبيهات.';

  @override
  String get permissionRationaleLocationTitle => 'يلزم إذن الموقع';

  @override
  String get permissionRationaleLocationBody =>
      'الموقع معطّل أو مرفوض. افتح إعدادات النظام واسمح بالموقع ثم أعد استخدام «موقعي».';

  @override
  String get deviceLimitTitle => 'حد الأجهزة';

  @override
  String get deviceLimitBody =>
      'هذا الحساب لديه جهازان مسجّلان بالفعل. احذف أحد الجهازين من الإعدادات (أو اطلب من مدير المؤسسة) قبل الدخول من هنا.';

  @override
  String get orgMandatoryPasswordHint =>
      'لأسباب أمنية يجب تعيين كلمة مرور جديدة قبل المتابعة (استخدم كلمة المرور المؤقتة المعطاة لك ككلمة المرور الحالية).';

  @override
  String get orgTeamManagement => 'إدارة الفريق';

  @override
  String get orgMonitoring => 'إدارتي — مراقبة الفريق';

  @override
  String get orgInviteMember => 'دعوة عضو فريق';

  @override
  String get orgNationalIdHint => 'الرقم المميز للمنشأة (700…) — انقر للنسخ';

  @override
  String get orgTempPasswordHint => 'كلمة مرور مؤقتة (8 أحرف على الأقل)';

  @override
  String get orgPermissionsJsonHint => 'صلاحيات (كائن JSON، اختياري)';

  @override
  String orgSeatUsage(int used, int limit) {
    return 'المقاعد: $used / $limit';
  }

  @override
  String get orgInviteSend => 'إنشاء العضو';

  @override
  String get orgInviteSuccess => 'تم إنشاء أو ربط العضو بنجاح';

  @override
  String get orgInviteFailed => 'تعذر دعوة العضو';

  @override
  String get orgMembersTitle => 'الأعضاء';

  @override
  String get orgActivityTitle => 'آخر النشاطات';

  @override
  String get orgDevicesTitle => 'الأجهزة الموثوقة';

  @override
  String get orgNoOrg => 'لا يوجد سجل مؤسسة';

  @override
  String get orgOwnerOnly => 'فقط صاحب المؤسسة يمكنه فتح هذه الشاشة';

  @override
  String get orgRemoveDevice => 'إلغاء الجهاز';

  @override
  String get orgDeviceRevoked => 'تم إلغاء الجهاز';

  @override
  String get orgStatsLogins => 'تسجيلات الدخول (عينة)';

  @override
  String get orgStatsListings => 'إجراءات الإعلانات (عينة)';

  @override
  String get orgMonitorRoleOwner =>
      'تعرض لك سجل نشاط الفريق كاملاً (مالك المؤسسة).';

  @override
  String get orgMonitorRoleMember => 'تعرض لك فقط الإجراءات التي تمت بحسابك.';

  @override
  String get orgMonitorChartDaily => 'الأحداث يومياً (آخر 14 يوماً)';

  @override
  String get orgMonitorChartActions => 'أكثر الإجراءات تكراراً';

  @override
  String get orgMonitorChartMembers => 'الأحداث حسب عضو الفريق';

  @override
  String get orgMonitorEngagementNote =>
      'مؤشرات النشاط مبنية على الأحداث المسجّلة في التطبيق (وليست تقييمات خارجية).';

  @override
  String get orgMonitorEmptyCharts => 'لا يوجد نشاط كافٍ بعد لعرض الرسوم.';

  @override
  String get orgMonitorTotalEvents => 'إجمالي الأحداث';

  @override
  String get orgMonitorEngagementScore => 'النشاط (تقديري)';

  @override
  String get postAuthChecking => 'جاري التحقق من الحساب…';

  @override
  String get loginIdentifierFieldHint =>
      'هوية/إقامة، رخصة فال، أو الرقم الوطني الموحّد 700… (10 أرقام)';

  @override
  String get loginEnterIdentifierFirst =>
      'أدخل 10 أرقام: هوية/إقامة أو رقم رخصة فال.';

  @override
  String get loginNoAccountLinkedIdentifier => 'لا يوجد حساب مرتبط بهذا الرقم.';

  @override
  String get loginIdentifierMustBe10 => 'يجب إدخال 10 أرقام بالضبط.';

  @override
  String get verScreenTitleMarketer => 'طلب توثيق مسوّق عقاري';

  @override
  String get verScreenTitleOffice => 'طلب توثيق مكتب عقاري';

  @override
  String get verScreenTitleInstitution => 'طلب توثيق مؤسسة عقارية';

  @override
  String get verScreenTitleCompany => 'طلب توثيق شركة عقارية';

  @override
  String get verFalLicenseLabel => 'رقم رخصة فال';

  @override
  String get verFalLicenseHint =>
      'رقم فال الرسمي من منصة الهيئة العامة للعقار (10 أرقام).';

  @override
  String get verFalLookupButton => 'استعلام عن الرخصة (REGA)';

  @override
  String get verFalLookupBusy => 'جاري الاستعلام…';

  @override
  String get verBrokerEmailLabel => 'البريد الإلكتروني';

  @override
  String get verBrokerEmailHint => 'بريد التواصل معك (يُستخدم في التوثيق).';

  @override
  String get verBrokerNameLabel => 'اسم الوسيط';

  @override
  String get verBrokerNameHint => 'كما في الرخصة (عربي فقط في هذا الحقل).';

  @override
  String get verBrokerPhoneHint => 'جوال التواصل (أرقام إنجليزية).';

  @override
  String get verPhoneLabel => 'رقم الجوال';

  @override
  String get verCityLabel => 'المدينة';

  @override
  String get verCityHint => 'عربي فقط.';

  @override
  String get verDistrictLabel => 'الحي';

  @override
  String get verDistrictHint => 'عربي فقط.';

  @override
  String get verRegionLabel => 'المنطقة';

  @override
  String get verRegionHint => 'عربي فقط.';

  @override
  String get verLicenseTypeLabel => 'نوع الرخصة';

  @override
  String get verLicenseStatusLabel => 'حالة الرخصة';

  @override
  String get verOfficeNameLabel => 'اسم المنشأة';

  @override
  String get verOfficeNameHint => 'الاسم الرسمي كما في السجل أو الترخيص.';

  @override
  String get verCrLabel => 'السجل التجاري';

  @override
  String get verCrHint => 'أرقام السجل الظاهرة في الوثائق.';

  @override
  String get verUnifiedCrLabel => 'السجل التجاري الموحّد (10 أرقام)';

  @override
  String get verUnifiedCrHint =>
      'رقم السجل الموحّد من وزارة التجارة (مثال يبدأ بـ 700…).';

  @override
  String get verMcLookupButton => 'استعلام بيانات السجل (وزارة التجارة)';

  @override
  String get verMcRegistryNotActive =>
      'السجل التجاري غير ساري (مثلاً مشطوب) — لا يمكن المتابعة به.';

  @override
  String get verMcLookupSuccess => 'تم جلب بيانات السجل التجاري.';

  @override
  String get verMcPleaseLookup =>
      'أدخل الرقم الموحّد (10 أرقام) واضغط استعلام السجل قبل الإرسال.';

  @override
  String get verFalDataLoadedSnackbar =>
      'تم جلب بيانات الرخصة. راجع الحقول وأكمل المطلوب.';

  @override
  String get verTeamSwitchTitle => 'هل أنت ضمن فريق عمل منشأة عقارية؟';

  @override
  String get verTeamSwitchSubtitle =>
      'إن نعم، أدخل الرمز السري المكوّن من 10 أرقام الذي يعطيك إياه مدير المنشأة.';

  @override
  String get verTeamCodeHint => 'رمز انضمام فريق العمل (10 أرقام).';

  @override
  String get verTeamPendingNote =>
      'بعد الإرسال يصل طلبك للمدير للموافقة ومنح الصلاحيات.';

  @override
  String get verNoteHint => 'أي ملاحظات إضافية للمراجعة (اختياري).';

  @override
  String get badgeVerifiedShort => 'موثق';

  @override
  String get latinCharsNotAllowedSnackbar =>
      'هذا الحقل لا يقبل أحرفاً إنجليزية.';

  @override
  String get falRenewalTitle => 'تجديد رخصة فال';

  @override
  String get falRenewalBody =>
      'انتهت صلاحية رخصة فال أو يجب تحديثها. أدخل رقم الرخصة الجديد واضغط «تحقق وتحديث» لجلب البيانات من REGA.';

  @override
  String get falRenewalSubmit => 'تحقق وتحديث';

  @override
  String get falRenewalExpired => 'هذه الرخصة منتهية.';

  @override
  String get falRenewalInvalid => 'تعذر التحقق من الرخصة.';

  @override
  String get falExpiryBannerWeek =>
      'تنبيه: رخصة فال تنتهي خلال أسبوع أو أقل — جدّدها لتفادي إيقاف الحساب.';

  @override
  String get profileSignatureTitle => 'إكمال التوقيع';

  @override
  String get profileSignatureBody =>
      'يرجى رفع صورة توقيعك (PNG أو JPG) بخط واضح وخلفية فاتحة.';

  @override
  String get profileSignaturePick => 'اختيار صورة التوقيع';

  @override
  String get profileSignatureNoBytes => 'تعذر قراءة الملف.';

  @override
  String get profileSignatureTabDraw => 'رسم التوقيع';

  @override
  String get profileSignatureTabUpload => 'رفع صورة';

  @override
  String get profileSignatureDrawHint =>
      'وقع داخل المربع بإصبعك أو القلم. يُحفظ كصورة للاستخدام في العقود.';

  @override
  String get profileSignatureClear => 'مسح';

  @override
  String get profileSignatureSaveDraw => 'حفظ التوقيع';

  @override
  String get profileSignatureEmpty => 'ارسم توقيعك داخل المربع أولاً.';

  @override
  String get profileRevisionGateTitle => 'مراجعة بيانات مطلوبة';

  @override
  String get profileRevisionGateBody =>
      'يتطلب إصدار التطبيق الحالي تأكيدك لمراجعة بيانات ملفك. اضغط «متابعة» بعد المراجعة.';

  @override
  String get profileRevisionGateConfirm => 'راجعت بياناتي — متابعة';

  @override
  String get settingsPublicMemberIdSubtitle =>
      'رقمك العمومي (10 أرقام) — المكاتب والفرق';

  @override
  String get onboardingWelcomeTitleApp => 'تطبيق موثوق العقاري';

  @override
  String get onboardingWelcomeTitleWeb => 'منصة موثوق العقاري الإلكترونية';

  @override
  String get onboardingWelcomeBodyApp =>
      'يسعدنا وجودك معنا. سواء كنت تعمل بشكل مستقل، أو تمثّل مكتباً، أو شركة، أو مؤسسة، ففريقنا في خدمتك ليجعل تجربتك سلسة ويضع اهتمامك في المقدمة. نتمنى لك استكشافاً مريحاً.';

  @override
  String get onboardingWelcomeBodyWeb =>
      'يسعدنا وجودك على منصة موثوق العقاري الإلكترونية. سواء كنت تعمل بشكل مستقل، أو تمثّل مكتباً، أو شركة، أو مؤسسة، ففريقنا في خدمتك ليجعل تجربتك سلسة ويضع اهتمامك في المقدمة. نتمنى لك استكشافاً مريحاً.';

  @override
  String get onboardingHomeTitle => 'الرئيسية';

  @override
  String get onboardingHomeBody =>
      'تصفّح الإعلانات واستخدم الفلاتر أعلى الشاشة (المدينة، النوع، الغرض). اضغط أي بطاقة لعرض التفاصيل الكاملة.';

  @override
  String get onboardingMyAdsTitle => 'صفحتي';

  @override
  String get onboardingMyAdsBodyMarketing =>
      'إعلاناتك وطلبات التسويق والعروض والعقود—منظّمة هنا وفق دورك كمسوّق أو منشأة.';

  @override
  String get onboardingMyAdsBodyOwner =>
      'أدر إعلاناتك وطلباتك كمالك عقار من هذا التبويب.';

  @override
  String get onboardingFavoritesTitle => 'المفضلة';

  @override
  String get onboardingFavoritesBody =>
      'احفظ الإعلانات التي تهمّك وارجع إليها متى شئت من هذا القسم.';

  @override
  String get onboardingMySubmissionsTitle => 'طلباتي/إعلاناتي';

  @override
  String get onboardingMySubmissionsBody =>
      'إعلاناتك العقارية وطلبات السوق التي قدّمتها تظهر كبطاقات مثل الرئيسية — افتحها من تبويب «طلباتي/إعلاناتي».';

  @override
  String get onboardingCartTitle => 'صفقاتي';

  @override
  String get onboardingCartBody =>
      'راجع العقارات التي أضفتها إلى «صفقاتي» قبل المتابعة أو الإتمام.';

  @override
  String get onboardingChatTitle => 'الدردشة';

  @override
  String get onboardingChatBody =>
      'تواصل مع الأطراف المرتبطة بصفقاتك من صندوق محادثاتك.';

  @override
  String get onboardingSupportTitle => 'الدعم الفني';

  @override
  String get onboardingSupportBody =>
      'مركز المساعدة، وقريباً التواصل مع الإدارة وتذاكر المتابعة. المحادثات تُفتح من أيقونة الجرس أو من هنا.';

  @override
  String get onboardingMyDeskTitle => 'إدارتي';

  @override
  String get onboardingMyDeskBodyMarketing =>
      'لوحة منشأتك أو فريق التسويق—المتابعة والموافقات من أيقونة «إدارتي» أعلى الشاشة.';

  @override
  String get onboardingMyDeskBodyOwnerIndividual =>
      'مساحة عملك كمالك فردي—إدارة إعلاناتك ومهامك من أيقونة «إدارتي» أعلى الشاشة.';

  @override
  String get onboardingMyDeskBodyOrgMember =>
      'لوحة منشأتك أو فريقك—متابعة المهام حسب صلاحياتك من أيقونة «إدارتي» أعلى الشاشة.';

  @override
  String onboardingStepCounter(int current, int total) {
    return 'الخطوة $current من $total';
  }

  @override
  String get onboardingNext => 'التالي';

  @override
  String get onboardingPrevious => 'السابق';

  @override
  String get onboardingSkip => 'تخطي';

  @override
  String get onboardingClose => 'إغلاق';

  @override
  String get onboardingFinish => 'حسناً';

  @override
  String get settingsAccentTitle => 'لون التمييز';

  @override
  String get settingsAccentSubtitle =>
      'خمسة ألوان جاهزة للوضعين الفاتح والداكن. يُطبَّق على الإجراءات الرئيسية وإطار التمييز (البطاقات، الحوارات، الحقول)—الأسطح تبقى محايدة.';

  @override
  String get accentColorDialogTitle => 'اختر لون التمييز';

  @override
  String get accentColorDialogBody =>
      'اختر لوناً يناسبك. اللغة والمظهر الداكن ولون التمييز في مكان واحد: الإعدادات ← المظهر واللغة.';

  @override
  String get accentColorLater => 'ليس الآن';

  @override
  String get accentColorSkipKeepsDefault =>
      'إذا تخطّيتَ أو أغلقتَ الحوار دون اختيار، يبقى لون التمييز كما هو دون تغيير.';

  @override
  String get marketInsightsTitle => 'تحليل السوق';

  @override
  String get settingsMarketInsightsCardSubtitle =>
      'لوحة المتقدّمين وإحصاءات الإعلانات والنشاط—نفس أيقونة الرسم في الشريط السفلي أو أعلى الشاشة. تحديث تلقائي في الخلفية حوالي كل ساعتين.';

  @override
  String get onboardingMarketInsightsBody =>
      'اضغط أيقونة التحليل أعلى الشاشة لعرض إحصاءات السوق، ترتيب الأفراد والمسوّقين والمؤسسات، وأعلى المنشآت. تُحدَّث الأرقام حوالي كل ساعتين—اسحب للأسفل داخل الشاشة لتحديث فوري.';

  @override
  String get marketInsightsRefreshHint =>
      'تُحدَّث الأرقام في الخلفية حوالي كل ساعتين؛ اسحب لأسفل في أي تبويب لتحديث فوري.';

  @override
  String get marketInsightsPublishedTotal => 'الإعلانات المعروضة';

  @override
  String get marketInsightsKpiTotal => 'الإجمالي';

  @override
  String get marketInsightsNew7d => 'جديد خلال 7 أيام';

  @override
  String get marketInsightsNew30d => 'جديد خلال 30 يوماً';

  @override
  String get marketInsightsFeatured => 'مميز';

  @override
  String get marketInsightsByAccountType => 'حسب نوع الحساب';

  @override
  String get marketInsightsByPropertyType => 'حسب نوع العقار';

  @override
  String get marketInsightsListingRequests => 'طلبات التسويق';

  @override
  String get marketInsightsOrgsRegistered => 'مكاتب / مؤسسات / شركات مسجّلة';

  @override
  String get marketInsightsTopOrgs => 'أعلى مؤسسات بإعلانات';

  @override
  String get marketInsightsLeaderboard => 'لوحة المتقدّمين';

  @override
  String get marketInsightsLeaderboardIndividuals => 'الأفراد';

  @override
  String get marketInsightsLeaderboardMarketers => 'المسوّقون والمؤسسات';

  @override
  String get marketInsightsFilterAll => 'الكل';

  @override
  String get marketInsightsRank => 'الترتيب';

  @override
  String get marketInsightsListingsShort => 'إعلانات';

  @override
  String get marketInsightsYourSnapshot => 'موقعك';

  @override
  String get marketInsightsCompetitiveHint =>
      'انشر إعلانات جيدة وتقدّم في الترتيب—تنافس بنّاء يخدم الجميع.';

  @override
  String get marketInsightsLoadError =>
      'تعذّر تحميل تحليل السوق. تحقق من الاتصال أو أن ترحيل الخادم مُنفَّذ.';

  @override
  String get marketInsightsRetry => 'إعادة المحاولة';

  @override
  String marketInsightsLastUpdated(String time) {
    return 'آخر تحديث: $time';
  }

  @override
  String marketInsightsYourRankGlobal(String rank) {
    return 'ترتيبك العام: $rank';
  }

  @override
  String marketInsightsYourListings(int count) {
    return 'إعلاناتك المنشورة: $count';
  }

  @override
  String get marketInsightsEmpty => 'لا توجد بيانات بعد.';

  @override
  String get marketInsightsTabOverview => 'نظرة عامة';

  @override
  String get marketInsightsTabAnalytics => 'التفصيل';

  @override
  String get marketInsightsTabCommunity => 'الترتيب';

  @override
  String get marketInsightsShareSummary => 'مشاركة الملخص';

  @override
  String get marketInsightsCopySummary => 'نسخ الملخص';

  @override
  String get marketInsightsCopied => 'تم نسخ الملخص';

  @override
  String get marketInsightsGuestHint =>
      'سجّل الدخول لعرض ترتيبك وعدد إعلاناتك بجانب بقية المستخدمين.';

  @override
  String get marketInsightsSignInToSeeRank => 'تسجيل الدخول';

  @override
  String get securityInactivityTitle => 'تم اكتشاف عدم نشاط';

  @override
  String securityInactivityTime(String time) {
    return 'الوقت: $time';
  }

  @override
  String securityInactivityBodyLock(int seconds) {
    return 'هل تريد الاستمرار؟ إن لم تختر خلال $seconds ثانية سيُطلب منك فتح قفل التطبيق (رمز PIN أو البصمة على الجهاز إن وُجدت).';
  }

  @override
  String securityInactivityBodySignOut(int seconds) {
    return 'هل تريد الاستمرار؟ إن لم تختر خلال $seconds ثانية سيتم تسجيل خروجك.';
  }

  @override
  String get securityContinue => 'استمرار';

  @override
  String get securitySignOutFromPrompt => 'تسجيل الخروج';

  @override
  String get securitySessionSupersededTitle => 'تنبيه جلسة';

  @override
  String get securitySessionSupersededBody =>
      'تم تسجيل الدخول إلى حسابك من متصفح أو جهاز آخر؛ تُغلق هذه الجلسة لأمانك.';

  @override
  String securitySessionSupersededBodyDetail(String city, String device) {
    return 'تم الدخول من جهاز آخر (الموقع: $city، الجهاز: $device). تم تسجيل خروجك للأمان.';
  }

  @override
  String get securitySessionContinueHere => 'الاستمرار على هذا الجهاز';

  @override
  String get securitySessionSignOutThisDevice => 'تسجيل الخروج من هنا';

  @override
  String get securitySessionSupersededChooseHint =>
      '• الاستمرار على هذا الجهاز: تجعل هذه الجلسة هي النشطة وتُسجّل خروج الحساب من الأجهزة/المتصفحات الأخرى المفتوحة.\n• تسجيل الخروج من هنا: يُغلق الحساب على هذا الجهاز فقط وتبقى الجلسة الأخرى نشطة.';

  @override
  String get securityDeviceLimitMessage =>
      'عذراً، لا يمكن تسجيل الدخول. لقد وصلت للحد الأقصى من الأجهزة (2). يرجى إدارة أجهزتك للمتابعة.';

  @override
  String get securityInactivityLockMessage =>
      'تم قفل الجلسة لعدم النشاط. يرجى إعادة المصادقة.';

  @override
  String get securityDeviceManagementTitle => 'إدارة الأجهزة';

  @override
  String get securityDeviceOtpHint => 'أدخل رمز التحقق المرسل لهاتفك المسجّل.';

  @override
  String get securityDeviceRemoveConfirm => 'إزالة الجهاز';

  @override
  String get securityClearOtherDevices => 'مسح الأجهزة الأخرى';

  @override
  String get securityRetryContinue => 'متابعة بعد التحديث';

  @override
  String get securityOk => 'حسناً';

  @override
  String get settingsSectionRegisteredDevices => 'الأجهزة المسجّلة';

  @override
  String get settingsSectionSessionHistory => 'سجل تسجيل الدخول';

  @override
  String get settingsDevicesFooterHint =>
      'يظهر تطبيق الويب والجوال والعملاء الآخرون عندما يسجّل الخادم الجلسات في المشروع.';

  @override
  String get settingsSessionKindWeb => 'ويب';

  @override
  String get settingsSessionKindApp => 'تطبيق جوّال';

  @override
  String get settingsSessionKindUnknown => 'عميل غير معروف';

  @override
  String get marketInsightsDistinctPublishers => 'ناشرون مختلفون (إعلانات)';

  @override
  String get marketInsightsRegisteredProfiles => 'ملفات مستخدمين مسجّلة';

  @override
  String get settingsTextScaleTitle => 'حجم الخط';

  @override
  String get settingsTextScaleSubtitle =>
      'يضبط حجم النص في التطبيق. يُدمَج مع حجم إمكانية الوصول في النظام ثم يُقيَّد ضمن حدود آمنة لتقليل كسر التخطيط.';

  @override
  String get settingsTextScaleReset => 'الافتراضي';

  @override
  String settingsTextScalePercent(int percent) {
    return '$percent٪';
  }

  @override
  String get orgJoinPendingTitle => 'طلب الانضمام قيد المراجعة';

  @override
  String orgJoinPendingBody(String orgLabel) {
    return 'لم تُوافَق بعد على طلب انضمامك إلى $orgLabel. سيتخذ مدير المكتب أو المؤسسة أو الشركة العقارية القرار، وستصلك إشعار عند الموافقة أو الرفض. بعد الموافقة اضغط «تحديث الحالة» للمتابعة.';
  }

  @override
  String get orgJoinPendingRecheck => 'تحديث الحالة';

  @override
  String get orgKindOffice => 'مكتب عقاري';

  @override
  String get orgKindInstitution => 'مؤسسة';

  @override
  String get orgKindCompany => 'شركة عقارية';

  @override
  String get orgKindGeneric => 'المؤسسة';

  @override
  String get deskTabMonitoring => 'المراقبة';

  @override
  String get deskTabTeamChat => 'دردشة الفريق';

  @override
  String get deskTabTeam => 'الفريق';

  @override
  String get deskTabJoinRequests => 'طلبات الانضمام';

  @override
  String get deskTabInsights => 'إحصائيات';

  @override
  String get settingsDistinguishedNumberSubtitle =>
      'رقمك المميز (10 أرقام، غالباً يبدأ بـ 700)';

  @override
  String get settingsRevealDistinguishedNumber => 'إظهار';

  @override
  String get settingsHideDistinguishedNumber => 'إخفاء';

  @override
  String get settingsCopyDistinguishedNumber => 'نسخ';

  @override
  String get settingsEditDistinguishedNumber => 'تحديث الرقم';

  @override
  String get settingsLastSeenPrivacyTitle => 'إخفاء آخر ظهور في الدردشة';

  @override
  String get settingsLastSeenPrivacySubtitle =>
      'لن يرى الآخرون وقت آخر نشاط لك في الدردشة (قد يظهر أنك متصل أثناء استخدام التطبيق).';

  @override
  String get sensitiveActionConfirm => 'تأكيد';

  @override
  String get sensitiveActionCancel => 'تراجع';

  @override
  String get chatKindDirect => 'رسالة فريق';

  @override
  String get chatListKindDirect => 'فريق';

  @override
  String get globalPresenceOnlineTooltip => 'تظهر متصلاً أثناء فتح التطبيق';

  @override
  String get orgJoinApprove => 'موافقة';

  @override
  String get orgJoinReject => 'رفض';

  @override
  String get orgJoinApprovedToast => 'تمت الموافقة على العضو';

  @override
  String get orgJoinRejectedToast => 'تم رفض الطلب';

  @override
  String get orgJoinActionFailed => 'تعذر تنفيذ الطلب';

  @override
  String get orgJoinNoPending => 'لا توجد طلبات انضمام معلّقة';

  @override
  String get listingPublicActionsTooltip => 'خيارات';

  @override
  String get listingPublicShareLink => 'مشاركة الرابط';

  @override
  String get listingPublicCopyLink => 'نسخ الرابط';

  @override
  String get listingPublicToggleBest => 'الأفضل';

  @override
  String get listingPublicShowOnHome => 'إظهار في الرئيسية';

  @override
  String get listingPublicWithdrawPendingReport => 'سحب البلاغ المعلّق';

  @override
  String get listingPublicHideFromHome => 'إخفاء من الرئيسية';

  @override
  String get listingPublicReport => 'إبلاغ';

  @override
  String get listingReportGateHourlyBlock =>
      'تجاوزت الحدّ المسموح للبلاغات خلال ساعة. البلاغات تؤثر على حقوق المعلنين والمسوّقين — يرجى الانتظار قبل إرسال بلاغ جديد.';

  @override
  String get listingReportGateDailyBlock =>
      'تجاوزت الحدّ اليومي للبلاغات. إن كان لديك أسباب استثنائية تواصل مع الدعم.';

  @override
  String get listingReportGateSternWarning =>
      'تنبيه: الإبلاغ المتكرر دون مسوّغ قد يعرّض حسابك للمراجعة. الإعلانات مرتبطة بحقوق أشخاص حقيقيين — استخدم البلاغ بحكمة وأمانة.';

  @override
  String get listingReportCannotSubmitGeneric => 'لا يمكن إرسال بلاغ الآن.';

  @override
  String get listingReportImportantNoticeTitle => 'تنبيه مهم';

  @override
  String get listingReportContinueToReport => 'متابعة البلاغ';

  @override
  String get listingReportDialogCancel => 'إلغاء';

  @override
  String get listingReportPropertySheetTitle => 'إبلاغ عن الإعلان';

  @override
  String get listingReportPropertySheetSubtitle =>
      'يُخفى الإعلان من رئيسيتك ويُرسل تنبيه للمسوّق المسؤول حتى تتابع الإدارة.';

  @override
  String get listingReportRequestSheetTitle => 'إبلاغ عن الطلب';

  @override
  String get listingReportRequestSheetSubtitle =>
      'يُخفى الطلب من رئيسيتك. يمكن للإدارة مراجعة البلاغ لاحقاً.';

  @override
  String get listingReportPickAtLeastOneReason => 'اختر سبباً واحداً على الأقل';

  @override
  String get listingReportOtherDetailsRequired => 'اكتب تفاصيل «سبب آخر»';

  @override
  String get listingReportSubmit => 'إرسال البلاغ';

  @override
  String get listingReportDetailsLabel => 'التفاصيل';

  @override
  String get listingReportDuplicateOpen =>
      'لديك بلاغ مفتوح على هذا الإعلان. اسحب البلاغ السابق أو انتظر مراجعته قبل إرسال بلاغ جديد.';

  @override
  String get listingReportReasonMisleading =>
      'معلومات مضللة أو غير دقيقة عن العقار';

  @override
  String get listingReportReasonDuplicateSpam =>
      'إعلان مكرر / محتوى مزعج أو احتيالي';

  @override
  String get listingReportReasonWrongPrice => 'السعر أو الشروط لا تطابق الواقع';

  @override
  String get listingReportReasonImpersonation =>
      'انتحال صفة أو جهة تسويق غير مخولة';

  @override
  String get listingReportReasonLicenseMismatch =>
      'عدم مطابقة رخصة الإعلان (هيئة العقار)';

  @override
  String get listingReportReasonHarassment => 'سلوك غير لائق بعد التواصل';

  @override
  String get listingReportReasonOther => 'سبب آخر (اكتب تفاصيلك)';

  @override
  String get inAppNotifListingReportTitle => 'بلاغ على إعلانك';

  @override
  String get inAppNotifListingReportBody =>
      'قام مستخدم بتقديم بلاغ. الإعلان يبقى ظاهراً للجمهور حتى تُكمل الإدارة المراجعة.';

  @override
  String get inAppNotifListingReportEscalatedTitle =>
      'عاجل: بلاغات متعددة على إعلانك';

  @override
  String get inAppNotifListingReportEscalatedBody =>
      'بلاغات من عدة مستخدمين مختلفين. وُقف ظهور الإعلان في الرئيسية مؤقتاً ريثما تراجع الإدارة.';

  @override
  String get inAppNotifListingReportOwnerEscalatedTitle =>
      'تنبيه: تصعيد بلاغات على إعلانك';

  @override
  String get inAppNotifListingReportOwnerEscalatedBody =>
      'وُقف ظهور الإعلان في الرئيسية مؤقتاً بسبب بلاغات متعددة من مستخدمين مختلفين. الإدارة تراجع القضية.';

  @override
  String get dashboardToastListingHiddenFromHome =>
      'أُخفيت من الرئيسية — تفعيل «المخفية» لعرضها.';

  @override
  String get dashboardToastListingShownOnHomeAgain =>
      'عاد الإعلان إلى الرئيسية.';

  @override
  String get dashboardToastListingReportWithdrawn => 'سُحب البلاغ المعلّق.';

  @override
  String get dashboardToastMarketRequestHiddenFromHome =>
      'أُخفِي الطلب من الرئيسية.';

  @override
  String get dashboardToastMarketRequestShownOnHomeAgain =>
      'عاد الطلب إلى الرئيسية.';

  @override
  String get propertyDetailsReportWithdrawnSnack => 'سُحب البلاغ المعلّق.';

  @override
  String get propertyDetailsHiddenFromYourHomeSnack => 'أُخفِي من رئيسيتك.';

  @override
  String get propertyDetailsShownOnHomeAgainSnack => 'أُعيد للرئيسية.';

  @override
  String get settingsReportsActivityTitle => 'نشاط البلاغات (على الجهاز)';

  @override
  String settingsReportsActivitySubtitle(
      int listingCount, int requestCount, int events30) {
    return 'إجمالي بلاغات إعلانات: $listingCount · طلبات: $requestCount · أحداث آخر ٣٠ يومًا: $events30';
  }

  @override
  String get marketRequestUrgencyTitle => 'درجة الإلحاح';

  @override
  String get marketRequestUrgencyHint =>
      'مدى استعجال الطلب؟ الدرجة الأعلى تظهر أوّلاً في خليط الرئيسية.';

  @override
  String get marketRequestPriorityFlexible => 'مرن';

  @override
  String get marketRequestPriorityStandard => 'عادي';

  @override
  String get marketRequestPriorityPriority => 'ذو أولوية';

  @override
  String get marketRequestPriorityUrgent => 'مستعجل';

  @override
  String get marketRequestPriorityImmediate => 'طلب فوري';

  @override
  String get inboxSearchHint => 'بحث في الإشعارات…';
}
