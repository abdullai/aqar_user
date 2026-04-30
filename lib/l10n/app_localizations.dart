import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Motawoq Real Estate'**
  String get appTitle;

  /// No description provided for @welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get welcomeTitle;

  /// No description provided for @welcomeTrustedAqar.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Motawoq Real Estate'**
  String get welcomeTrustedAqar;

  /// No description provided for @signInToContinue.
  ///
  /// In en, this message translates to:
  /// **'Sign in to continue'**
  String get signInToContinue;

  /// No description provided for @userSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get userSignIn;

  /// No description provided for @allFieldsRequired.
  ///
  /// In en, this message translates to:
  /// **'Please fill in all fields'**
  String get allFieldsRequired;

  /// No description provided for @usernameMustBe10Digits.
  ///
  /// In en, this message translates to:
  /// **'Username must be 10 digits'**
  String get usernameMustBe10Digits;

  /// No description provided for @passwordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password is too short'**
  String get passwordTooShort;

  /// No description provided for @invalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Invalid credentials'**
  String get invalidCredentials;

  /// No description provided for @rememberMe.
  ///
  /// In en, this message translates to:
  /// **'Remind me'**
  String get rememberMe;

  /// No description provided for @quickLogin.
  ///
  /// In en, this message translates to:
  /// **'Quick login'**
  String get quickLogin;

  /// No description provided for @quickLoginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock with device PIN, fingerprint, or Face ID if you enabled it in Settings.'**
  String get quickLoginSubtitle;

  /// No description provided for @forgotUsernameOrPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot username or password?'**
  String get forgotUsernameOrPassword;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get theme;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageArabic.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get languageArabic;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @settingsAppearanceLanguageSection.
  ///
  /// In en, this message translates to:
  /// **'Appearance & language'**
  String get settingsAppearanceLanguageSection;

  /// No description provided for @settingsAppearanceHubSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Language, dark mode, and accent in one place.'**
  String get settingsAppearanceHubSubtitle;

  /// No description provided for @settingsHapticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Haptic feedback'**
  String get settingsHapticsTitle;

  /// No description provided for @settingsHapticsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Light vibration on some interactions (mobile only).'**
  String get settingsHapticsSubtitle;

  /// No description provided for @settingsDarkModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use dark colors across the app'**
  String get settingsDarkModeSubtitle;

  /// No description provided for @settingsInAppNotificationSoundTitle.
  ///
  /// In en, this message translates to:
  /// **'In-app alert sound'**
  String get settingsInAppNotificationSoundTitle;

  /// No description provided for @settingsInAppNotificationSoundSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Web: in-app chime from app assets. Phone/tablet: short system feedback (haptic + system sound) so it does not fight your notification channel ringtones. Foreground FCM stays silent; background uses system notifications. OTP codes: web plays the app chime plus a banner; phone uses the OTP notification channel (your system sound/vibration).'**
  String get settingsInAppNotificationSoundSubtitle;

  /// No description provided for @settingsChatMessageSoundTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat message sound'**
  String get settingsChatMessageSoundTitle;

  /// No description provided for @settingsChatMessageSoundSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Web: in-app chime from assets. Phone/tablet: light haptic + system click (no bundled WAV). Separate from in-app banner alerts and from push notification sounds.'**
  String get settingsChatMessageSoundSubtitle;

  /// No description provided for @legalTermsCoachTitle.
  ///
  /// In en, this message translates to:
  /// **'Terms & privacy'**
  String get legalTermsCoachTitle;

  /// No description provided for @legalTermsCoachBody.
  ///
  /// In en, this message translates to:
  /// **'You can review the terms and privacy policy anytime in Settings. Acceptance may still be required at sign-in.'**
  String get legalTermsCoachBody;

  /// No description provided for @legalTermsCoachOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get legalTermsCoachOk;

  /// No description provided for @fieldGroupCredentialsTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign-in details'**
  String get fieldGroupCredentialsTitle;

  /// No description provided for @fieldGroupCredentialsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your distinguished number and password'**
  String get fieldGroupCredentialsSubtitle;

  /// No description provided for @fieldGroupOtpTitle.
  ///
  /// In en, this message translates to:
  /// **'Verification code'**
  String get fieldGroupOtpTitle;

  /// No description provided for @fieldGroupOtpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the digits sent to you'**
  String get fieldGroupOtpSubtitle;

  /// No description provided for @fieldGroupGateTitle.
  ///
  /// In en, this message translates to:
  /// **'How do you want to continue?'**
  String get fieldGroupGateTitle;

  /// No description provided for @fieldGroupVerificationFalTitle.
  ///
  /// In en, this message translates to:
  /// **'Broker license & contact'**
  String get fieldGroupVerificationFalTitle;

  /// No description provided for @fieldGroupVerificationFalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'FAL verification and broker details for this request.'**
  String get fieldGroupVerificationFalSubtitle;

  /// No description provided for @fieldGroupVerificationOrgTitle.
  ///
  /// In en, this message translates to:
  /// **'Organization & commercial register'**
  String get fieldGroupVerificationOrgTitle;

  /// No description provided for @fieldGroupVerificationOrgSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Office name and unified CR where applicable.'**
  String get fieldGroupVerificationOrgSubtitle;

  /// No description provided for @fieldGroupVerificationOptionalLicenseTitle.
  ///
  /// In en, this message translates to:
  /// **'License reference'**
  String get fieldGroupVerificationOptionalLicenseTitle;

  /// No description provided for @fieldGroupVerificationOptionalLicenseSubtitle.
  ///
  /// In en, this message translates to:
  /// **'If you have a license number, enter it here.'**
  String get fieldGroupVerificationOptionalLicenseSubtitle;

  /// No description provided for @fieldGroupVerificationMoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Team & notes'**
  String get fieldGroupVerificationMoreTitle;

  /// No description provided for @fieldGroupVerificationMoreSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Optional team join code and a message for reviewers.'**
  String get fieldGroupVerificationMoreSubtitle;

  /// No description provided for @fieldGroupVerificationDocumentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get fieldGroupVerificationDocumentsTitle;

  /// No description provided for @fieldGroupVerificationDocumentsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Upload PDF or image files for verification.'**
  String get fieldGroupVerificationDocumentsSubtitle;

  /// No description provided for @fieldGroupFalRenewalTitle.
  ///
  /// In en, this message translates to:
  /// **'License renewal'**
  String get fieldGroupFalRenewalTitle;

  /// No description provided for @fieldGroupFalRenewalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your FAL number to verify with REGA.'**
  String get fieldGroupFalRenewalSubtitle;

  /// No description provided for @fieldGroupListingRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Listing request'**
  String get fieldGroupListingRequestTitle;

  /// No description provided for @fieldGroupListingRequestSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Property title, city, and map coordinates.'**
  String get fieldGroupListingRequestSubtitle;

  /// No description provided for @fieldGroupListingRequestSubmit.
  ///
  /// In en, this message translates to:
  /// **'Send request'**
  String get fieldGroupListingRequestSubmit;

  /// No description provided for @listingRequestFieldTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Property title'**
  String get listingRequestFieldTitleLabel;

  /// No description provided for @listingRequestFieldCityLabel.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get listingRequestFieldCityLabel;

  /// No description provided for @listingRequestFieldLatLabel.
  ///
  /// In en, this message translates to:
  /// **'Latitude'**
  String get listingRequestFieldLatLabel;

  /// No description provided for @listingRequestFieldLngLabel.
  ///
  /// In en, this message translates to:
  /// **'Longitude'**
  String get listingRequestFieldLngLabel;

  /// No description provided for @mapPickerHuaweiNoGmsBanner.
  ///
  /// In en, this message translates to:
  /// **'Google Maps may not load on some Huawei/Honor devices without Google services. Use search or confirm coordinates manually.'**
  String get mapPickerHuaweiNoGmsBanner;

  /// No description provided for @mapPickerMapLoadStalledBanner.
  ///
  /// In en, this message translates to:
  /// **'The map is slow or did not finish loading. Use city search, type latitude/longitude, or open Google Maps externally.'**
  String get mapPickerMapLoadStalledBanner;

  /// No description provided for @mapPickerOpenExternalMaps.
  ///
  /// In en, this message translates to:
  /// **'Open in Maps'**
  String get mapPickerOpenExternalMaps;

  /// No description provided for @welcomeDashboardBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Motawoq Real Estate'**
  String get welcomeDashboardBannerTitle;

  /// No description provided for @welcomeDashboardBannerBody.
  ///
  /// In en, this message translates to:
  /// **'Browse listings on Home, manage your ads under My Ads, and open Settings at the top. You can turn off alert sounds in Settings.'**
  String get welcomeDashboardBannerBody;

  /// No description provided for @welcomeDashboardBannerButton.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get welcomeDashboardBannerButton;

  /// No description provided for @usernameHint10Digits.
  ///
  /// In en, this message translates to:
  /// **'Distinguished number (10 digits)'**
  String get usernameHint10Digits;

  /// No description provided for @loginUsernameFieldHelper.
  ///
  /// In en, this message translates to:
  /// **'ID/Iqama, FAL license, or unified national no. 700… (10 digits)'**
  String get loginUsernameFieldHelper;

  /// No description provided for @loginIdentifierFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'National ID, unified CR, or FAL license — 10 digits'**
  String get loginIdentifierFieldLabel;

  /// No description provided for @loginPasswordFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get loginPasswordFieldLabel;

  /// No description provided for @loginPasswordFieldShortLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get loginPasswordFieldShortLabel;

  /// No description provided for @passwordHint.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordHint;

  /// No description provided for @passwordArabicKeyboardHint.
  ///
  /// In en, this message translates to:
  /// **'Use English letters or numbers for your password. Switch keyboard layout if needed.'**
  String get passwordArabicKeyboardHint;

  /// No description provided for @rightPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Your gateway to documented property'**
  String get rightPanelTitle;

  /// No description provided for @rightPanelSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Verify licences, message securely, and follow listings in one experience aligned with Mawthuq.'**
  String get rightPanelSubtitle;

  /// No description provided for @noEnabledAds.
  ///
  /// In en, this message translates to:
  /// **'No enabled ads right now'**
  String get noEnabledAds;

  /// No description provided for @accountLockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Account locked'**
  String get accountLockedTitle;

  /// No description provided for @accountLockedBody.
  ///
  /// In en, this message translates to:
  /// **'Your account is locked due to multiple attempts. Use recovery.'**
  String get accountLockedBody;

  /// No description provided for @recover.
  ///
  /// In en, this message translates to:
  /// **'Recover'**
  String get recover;

  /// No description provided for @verifyTitle.
  ///
  /// In en, this message translates to:
  /// **'Verification'**
  String get verifyTitle;

  /// No description provided for @otpTitle.
  ///
  /// In en, this message translates to:
  /// **'Verification'**
  String get otpTitle;

  /// No description provided for @verifySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the verification code'**
  String get verifySubtitle;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @securityAlert.
  ///
  /// In en, this message translates to:
  /// **'Security alert'**
  String get securityAlert;

  /// No description provided for @verifyTimeout.
  ///
  /// In en, this message translates to:
  /// **'Verification timed out'**
  String get verifyTimeout;

  /// No description provided for @invalidCode.
  ///
  /// In en, this message translates to:
  /// **'Invalid verification code'**
  String get invalidCode;

  /// No description provided for @accountLocked.
  ///
  /// In en, this message translates to:
  /// **'Account locked'**
  String get accountLocked;

  /// No description provided for @notificationDefaultTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification'**
  String get notificationDefaultTitle;

  /// No description provided for @listingStagesTitle.
  ///
  /// In en, this message translates to:
  /// **'Listing stages'**
  String get listingStagesTitle;

  /// No description provided for @marketingStagesTitle.
  ///
  /// In en, this message translates to:
  /// **'Marketing stages'**
  String get marketingStagesTitle;

  /// No description provided for @marketingStepInvite.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get marketingStepInvite;

  /// No description provided for @marketingStepOffer.
  ///
  /// In en, this message translates to:
  /// **'Offer'**
  String get marketingStepOffer;

  /// No description provided for @marketingStepContract.
  ///
  /// In en, this message translates to:
  /// **'Contract'**
  String get marketingStepContract;

  /// No description provided for @marketingStepPermit.
  ///
  /// In en, this message translates to:
  /// **'Permit'**
  String get marketingStepPermit;

  /// No description provided for @marketingStepPublish.
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get marketingStepPublish;

  /// No description provided for @ownerOfferRejectionReason.
  ///
  /// In en, this message translates to:
  /// **'Offer rejection/counter reason: {reason}'**
  String ownerOfferRejectionReason(Object reason);

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// No description provided for @noNewNotifications.
  ///
  /// In en, this message translates to:
  /// **'No new notifications'**
  String get noNewNotifications;

  /// No description provided for @closeLabel.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeLabel;

  /// No description provided for @retryLabel.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryLabel;

  /// No description provided for @offlineNoInternetTitle.
  ///
  /// In en, this message translates to:
  /// **'No internet connection'**
  String get offlineNoInternetTitle;

  /// No description provided for @offlineNoInternetBody.
  ///
  /// In en, this message translates to:
  /// **'The app cannot start without internet. Enable internet then retry.'**
  String get offlineNoInternetBody;

  /// No description provided for @loginRequiredDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Login required'**
  String get loginRequiredDialogTitle;

  /// No description provided for @loginRequiredDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'You need to log in to access this feature. Would you like to log in now?'**
  String get loginRequiredDialogMessage;

  /// No description provided for @laterLabel.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get laterLabel;

  /// No description provided for @loginToManageListingsBody.
  ///
  /// In en, this message translates to:
  /// **'Log in to manage your listings'**
  String get loginToManageListingsBody;

  /// No description provided for @preparingMarketingTabsTitle.
  ///
  /// In en, this message translates to:
  /// **'Preparing marketing tabs'**
  String get preparingMarketingTabsTitle;

  /// No description provided for @preparingListingsTabsTitle.
  ///
  /// In en, this message translates to:
  /// **'Preparing listings tabs'**
  String get preparingListingsTabsTitle;

  /// No description provided for @ifContinuesTapRetry.
  ///
  /// In en, this message translates to:
  /// **'If this continues, tap retry.'**
  String get ifContinuesTapRetry;

  /// No description provided for @myAdsOwnerTabWaitingMediator.
  ///
  /// In en, this message translates to:
  /// **'🤝 Awaiting marketers'**
  String get myAdsOwnerTabWaitingMediator;

  /// No description provided for @myAdsOwnerTabAwaitContract.
  ///
  /// In en, this message translates to:
  /// **'📝 Contracting'**
  String get myAdsOwnerTabAwaitContract;

  /// No description provided for @myAdsOwnerTabPublishedHome.
  ///
  /// In en, this message translates to:
  /// **'🏡 Published'**
  String get myAdsOwnerTabPublishedHome;

  /// No description provided for @myAdsEmptyWaitingMediator.
  ///
  /// In en, this message translates to:
  /// **'No listings awaiting marketers'**
  String get myAdsEmptyWaitingMediator;

  /// No description provided for @myAdsEmptyAwaitContract.
  ///
  /// In en, this message translates to:
  /// **'No listings in contracting'**
  String get myAdsEmptyAwaitContract;

  /// No description provided for @myAdsEmptyPublishedHome.
  ///
  /// In en, this message translates to:
  /// **'No published listings'**
  String get myAdsEmptyPublishedHome;

  /// No description provided for @marketerTabInvites.
  ///
  /// In en, this message translates to:
  /// **'🏢 Real estate market'**
  String get marketerTabInvites;

  /// No description provided for @marketerTabAwaitingOwner.
  ///
  /// In en, this message translates to:
  /// **'⏳ Awaiting owner · contracting'**
  String get marketerTabAwaitingOwner;

  /// No description provided for @marketerTabMyOffers.
  ///
  /// In en, this message translates to:
  /// **'💼 Offers'**
  String get marketerTabMyOffers;

  /// No description provided for @marketerTabContracts.
  ///
  /// In en, this message translates to:
  /// **'📄 Contracts'**
  String get marketerTabContracts;

  /// No description provided for @marketerTabPermits.
  ///
  /// In en, this message translates to:
  /// **'✅ Permits'**
  String get marketerTabPermits;

  /// No description provided for @marketerTabPublished.
  ///
  /// In en, this message translates to:
  /// **'🚀 Published'**
  String get marketerTabPublished;

  /// No description provided for @marketerEmptyInvites.
  ///
  /// In en, this message translates to:
  /// **'Nothing in the market yet'**
  String get marketerEmptyInvites;

  /// No description provided for @marketerBtnPropertyListingDetails.
  ///
  /// In en, this message translates to:
  /// **'Listing details'**
  String get marketerBtnPropertyListingDetails;

  /// No description provided for @ownerBtnRealEstateOffers.
  ///
  /// In en, this message translates to:
  /// **'Real estate offers'**
  String get ownerBtnRealEstateOffers;

  /// No description provided for @marketerEmptyOffers.
  ///
  /// In en, this message translates to:
  /// **'No offers'**
  String get marketerEmptyOffers;

  /// No description provided for @marketerEmptyContracts.
  ///
  /// In en, this message translates to:
  /// **'No contracts'**
  String get marketerEmptyContracts;

  /// No description provided for @marketerEmptyPermits.
  ///
  /// In en, this message translates to:
  /// **'No permits'**
  String get marketerEmptyPermits;

  /// No description provided for @marketerEmptyPublished.
  ///
  /// In en, this message translates to:
  /// **'No published'**
  String get marketerEmptyPublished;

  /// No description provided for @listingsControlHubTitle.
  ///
  /// In en, this message translates to:
  /// **'Listings Control Hub'**
  String get listingsControlHubTitle;

  /// No description provided for @marketerFullScenarioGuideTooltip.
  ///
  /// In en, this message translates to:
  /// **'Full path: invite → owner decision → contract → REGA permit → publish — and notifications'**
  String get marketerFullScenarioGuideTooltip;

  /// No description provided for @marketerFullScenarioSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Professional marketing path'**
  String get marketerFullScenarioSheetTitle;

  /// No description provided for @marketerFullScenarioOpenInbox.
  ///
  /// In en, this message translates to:
  /// **'Open notification inbox'**
  String get marketerFullScenarioOpenInbox;

  /// No description provided for @marketerFullScenarioUnderstood.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get marketerFullScenarioUnderstood;

  /// No description provided for @ownerFullScenarioGuideTooltip.
  ///
  /// In en, this message translates to:
  /// **'Owner path: offers → contract → REGA permit → publish — and notifications'**
  String get ownerFullScenarioGuideTooltip;

  /// No description provided for @ownerFullScenarioSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Your listing marketing path'**
  String get ownerFullScenarioSheetTitle;

  /// No description provided for @scenarioOpenRequestStatusButton.
  ///
  /// In en, this message translates to:
  /// **'Open request status'**
  String get scenarioOpenRequestStatusButton;

  /// No description provided for @workflowGuideDialogButton.
  ///
  /// In en, this message translates to:
  /// **'Full workflow guide'**
  String get workflowGuideDialogButton;

  /// No description provided for @workflowGuideSheetIntro.
  ///
  /// In en, this message translates to:
  /// **'Follow the numbered steps. Your notifications link to each stage so nothing is missed.'**
  String get workflowGuideSheetIntro;

  /// No description provided for @listingRequestStatusWorkflowTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open the step-by-step guide for this request'**
  String get listingRequestStatusWorkflowTooltip;

  /// No description provided for @workflowGuideHubSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tip: tap the route icon next to the title for the full step-by-step path and notification shortcuts.'**
  String get workflowGuideHubSubtitle;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navMyAds.
  ///
  /// In en, this message translates to:
  /// **'My page'**
  String get navMyAds;

  /// No description provided for @navFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get navFavorites;

  /// No description provided for @navAdd.
  ///
  /// In en, this message translates to:
  /// **'Post ad'**
  String get navAdd;

  /// No description provided for @navMyDesk.
  ///
  /// In en, this message translates to:
  /// **'My desk'**
  String get navMyDesk;

  /// No description provided for @navMyDeskPipelineBadgeTooltip.
  ///
  /// In en, this message translates to:
  /// **'My desk: stats, team, and work management based on your account type.'**
  String get navMyDeskPipelineBadgeTooltip;

  /// No description provided for @navCart.
  ///
  /// In en, this message translates to:
  /// **'My deals'**
  String get navCart;

  /// No description provided for @navReservations.
  ///
  /// In en, this message translates to:
  /// **'Reserved properties'**
  String get navReservations;

  /// No description provided for @navChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get navChat;

  /// No description provided for @navMySubmissions.
  ///
  /// In en, this message translates to:
  /// **'Requests/Listings'**
  String get navMySubmissions;

  /// No description provided for @navSupport.
  ///
  /// In en, this message translates to:
  /// **'Technical support'**
  String get navSupport;

  /// No description provided for @communicationHubTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications & chats'**
  String get communicationHubTitle;

  /// No description provided for @communicationHubNotificationsTab.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get communicationHubNotificationsTab;

  /// No description provided for @communicationHubChatsTab.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get communicationHubChatsTab;

  /// No description provided for @openChatInboxButton.
  ///
  /// In en, this message translates to:
  /// **'Open chat inbox'**
  String get openChatInboxButton;

  /// No description provided for @communicationHubChatsHint.
  ///
  /// In en, this message translates to:
  /// **'All conversation types (property, reservation, market request, support…) are handled in the chat inbox.'**
  String get communicationHubChatsHint;

  /// No description provided for @supportHubTechnicalTab.
  ///
  /// In en, this message translates to:
  /// **'Help center'**
  String get supportHubTechnicalTab;

  /// No description provided for @supportHubAdminTab.
  ///
  /// In en, this message translates to:
  /// **'Administration'**
  String get supportHubAdminTab;

  /// No description provided for @supportHubTicketsTab.
  ///
  /// In en, this message translates to:
  /// **'Tickets'**
  String get supportHubTicketsTab;

  /// No description provided for @supportHubAdminSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon: contact administration and official requests.'**
  String get supportHubAdminSoon;

  /// No description provided for @supportHubTicketsSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon: create and track support tickets with administration.'**
  String get supportHubTicketsSoon;

  /// No description provided for @settingsSupportMovedHint.
  ///
  /// In en, this message translates to:
  /// **'Technical support and admin contact are now in the bottom Technical support tab.'**
  String get settingsSupportMovedHint;

  /// No description provided for @mySubmissionsSectionListings.
  ///
  /// In en, this message translates to:
  /// **'My listings'**
  String get mySubmissionsSectionListings;

  /// No description provided for @mySubmissionsSectionRequests.
  ///
  /// In en, this message translates to:
  /// **'Market requests'**
  String get mySubmissionsSectionRequests;

  /// No description provided for @mySubmissionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'You have no published listings or market requests yet.'**
  String get mySubmissionsEmpty;

  /// No description provided for @cartMarketOffersSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Offers on my requests'**
  String get cartMarketOffersSectionTitle;

  /// No description provided for @cartMarketOffersEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'When someone submits an offer on your market request, it appears here for follow-up.'**
  String get cartMarketOffersEmptyHint;

  /// No description provided for @marketPropertySubmitSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Thank you, partner'**
  String get marketPropertySubmitSuccessTitle;

  /// No description provided for @marketPropertySubmitSuccessBody.
  ///
  /// In en, this message translates to:
  /// **'Your property request was submitted successfully. It will appear to interested parties according to our policies. You can track it under «Requests/Listings».'**
  String get marketPropertySubmitSuccessBody;

  /// No description provided for @marketPropertySubmitGoHome.
  ///
  /// In en, this message translates to:
  /// **'Back to Home'**
  String get marketPropertySubmitGoHome;

  /// No description provided for @marketPropertySubmitAnother.
  ///
  /// In en, this message translates to:
  /// **'Another property request'**
  String get marketPropertySubmitAnother;

  /// No description provided for @supportLabel.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get supportLabel;

  /// No description provided for @logoutLabel.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logoutLabel;

  /// No description provided for @settingsLabel.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsLabel;

  /// No description provided for @loginNowLabel.
  ///
  /// In en, this message translates to:
  /// **'Login Now'**
  String get loginNowLabel;

  /// No description provided for @noInternetConnectionTitle.
  ///
  /// In en, this message translates to:
  /// **'No Internet Connection'**
  String get noInternetConnectionTitle;

  /// No description provided for @ensureInternetThenRetry.
  ///
  /// In en, this message translates to:
  /// **'Make sure you are online, then retry.'**
  String get ensureInternetThenRetry;

  /// No description provided for @offlineGlobalOverlayHint.
  ///
  /// In en, this message translates to:
  /// **'Your session stays on this device. When the connection returns, the app will detect it automatically — or tap Retry. You will not be sent back to login unless you sign out.'**
  String get offlineGlobalOverlayHint;

  /// No description provided for @refreshLabel.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refreshLabel;

  /// No description provided for @failedToLoadAds.
  ///
  /// In en, this message translates to:
  /// **'Failed to load ads'**
  String get failedToLoadAds;

  /// No description provided for @failedToLoadCart.
  ///
  /// In en, this message translates to:
  /// **'Failed to load your deals'**
  String get failedToLoadCart;

  /// No description provided for @failedToLoadReservations.
  ///
  /// In en, this message translates to:
  /// **'Failed to load reservations'**
  String get failedToLoadReservations;

  /// No description provided for @changePasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get changePasswordTitle;

  /// No description provided for @currentPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get currentPasswordLabel;

  /// No description provided for @newPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get newPasswordLabel;

  /// No description provided for @confirmNewPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm new password'**
  String get confirmNewPasswordLabel;

  /// No description provided for @savePassword.
  ///
  /// In en, this message translates to:
  /// **'Update password'**
  String get savePassword;

  /// No description provided for @passwordChangedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Password updated successfully'**
  String get passwordChangedSuccess;

  /// No description provided for @changePasswordFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not change password'**
  String get changePasswordFailed;

  /// No description provided for @wrongCurrentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current password is incorrect'**
  String get wrongCurrentPassword;

  /// No description provided for @profileChangePhoto.
  ///
  /// In en, this message translates to:
  /// **'Change profile photo'**
  String get profileChangePhoto;

  /// No description provided for @profilePhotoUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get profilePhotoUploading;

  /// No description provided for @profilePhotoUpdated.
  ///
  /// In en, this message translates to:
  /// **'Profile photo updated'**
  String get profilePhotoUpdated;

  /// No description provided for @profilePhotoFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update photo'**
  String get profilePhotoFailed;

  /// No description provided for @fullNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get fullNameLabel;

  /// No description provided for @accountCategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Account category'**
  String get accountCategoryLabel;

  /// No description provided for @permissionRoleLabel.
  ///
  /// In en, this message translates to:
  /// **'Role / permission'**
  String get permissionRoleLabel;

  /// No description provided for @changeQuickPin.
  ///
  /// In en, this message translates to:
  /// **'Change quick PIN'**
  String get changeQuickPin;

  /// No description provided for @newPinLabel.
  ///
  /// In en, this message translates to:
  /// **'New PIN (6 digits)'**
  String get newPinLabel;

  /// No description provided for @confirmPinLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm PIN'**
  String get confirmPinLabel;

  /// No description provided for @pinUpdated.
  ///
  /// In en, this message translates to:
  /// **'PIN updated'**
  String get pinUpdated;

  /// No description provided for @pinMismatch.
  ///
  /// In en, this message translates to:
  /// **'PINs do not match'**
  String get pinMismatch;

  /// No description provided for @biometricNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Biometrics are not available on this device'**
  String get biometricNotAvailable;

  /// No description provided for @fastLoginAfterLoginHint.
  ///
  /// In en, this message translates to:
  /// **'After signing in, enable quick login in Settings (mobile only).'**
  String get fastLoginAfterLoginHint;

  /// No description provided for @fastLoginOfferTitle.
  ///
  /// In en, this message translates to:
  /// **'Faster sign-in next time?'**
  String get fastLoginOfferTitle;

  /// No description provided for @fastLoginOfferBody.
  ///
  /// In en, this message translates to:
  /// **'Enable a quick PIN or biometrics (if your device supports it). You can change this anytime in Settings.'**
  String get fastLoginOfferBody;

  /// No description provided for @fastLoginOfferOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get fastLoginOfferOpenSettings;

  /// No description provided for @fastLoginOfferBiometric.
  ///
  /// In en, this message translates to:
  /// **'Use biometrics'**
  String get fastLoginOfferBiometric;

  /// No description provided for @fastLoginOfferNotNow.
  ///
  /// In en, this message translates to:
  /// **'No thanks'**
  String get fastLoginOfferNotNow;

  /// No description provided for @fastLoginOfferRemindLater.
  ///
  /// In en, this message translates to:
  /// **'Remind me later'**
  String get fastLoginOfferRemindLater;

  /// No description provided for @legalTermsTitle.
  ///
  /// In en, this message translates to:
  /// **'Terms and conditions'**
  String get legalTermsTitle;

  /// No description provided for @legalAccept.
  ///
  /// In en, this message translates to:
  /// **'I agree'**
  String get legalAccept;

  /// No description provided for @legalDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get legalDecline;

  /// No description provided for @legalDeclineTitle.
  ///
  /// In en, this message translates to:
  /// **'Cannot continue'**
  String get legalDeclineTitle;

  /// No description provided for @legalDeclineBody.
  ///
  /// In en, this message translates to:
  /// **'You must accept the terms to use the app.'**
  String get legalDeclineBody;

  /// No description provided for @legalTermsFallbackBody.
  ///
  /// In en, this message translates to:
  /// **'Terms and privacy text could not be loaded from the server. By continuing you agree to use Motawoq Real Estate in accordance with applicable laws in the Kingdom of Saudi Arabia, including personal data protection rules where they apply, to provide accurate information, and to use listings and messaging responsibly. For the full text, contact support or try again later.'**
  String get legalTermsFallbackBody;

  /// No description provided for @permissionsGateTitle.
  ///
  /// In en, this message translates to:
  /// **'Before we start'**
  String get permissionsGateTitle;

  /// No description provided for @permissionsGateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We ask for permissions in a standard order: notifications (chat and updates), location (map and nearby accuracy), then photos and camera (listing images). You can skip now and enable later from Settings or when the app prompts you.'**
  String get permissionsGateSubtitle;

  /// No description provided for @permissionsGateWebSubtitle.
  ///
  /// In en, this message translates to:
  /// **'On the web, your browser will request notifications and location when needed. Location improves maps and nearby sorting; gallery and camera use the browser or file picker.'**
  String get permissionsGateWebSubtitle;

  /// No description provided for @permissionsGateContinueAllow.
  ///
  /// In en, this message translates to:
  /// **'Continue & allow'**
  String get permissionsGateContinueAllow;

  /// No description provided for @permissionsGateNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get permissionsGateNotNow;

  /// No description provided for @permissionsGateOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get permissionsGateOpenSettings;

  /// No description provided for @permissionsGateNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get permissionsGateNotificationsTitle;

  /// No description provided for @permissionsGateNotificationsDesc.
  ///
  /// In en, this message translates to:
  /// **'Alerts for chat, bookings, and listing activity.'**
  String get permissionsGateNotificationsDesc;

  /// No description provided for @permissionsGateLocationTitle.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get permissionsGateLocationTitle;

  /// No description provided for @permissionsGateLocationDesc.
  ///
  /// In en, this message translates to:
  /// **'Pick property locations on the map and improve nearby accuracy.'**
  String get permissionsGateLocationDesc;

  /// No description provided for @permissionsGatePhotosTitle.
  ///
  /// In en, this message translates to:
  /// **'Photos / gallery'**
  String get permissionsGatePhotosTitle;

  /// No description provided for @permissionsGatePhotosDesc.
  ///
  /// In en, this message translates to:
  /// **'Attach images to listings and uploads.'**
  String get permissionsGatePhotosDesc;

  /// No description provided for @permissionsGateCameraTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get permissionsGateCameraTitle;

  /// No description provided for @permissionsGateCameraDesc.
  ///
  /// In en, this message translates to:
  /// **'Take photos for listings directly.'**
  String get permissionsGateCameraDesc;

  /// No description provided for @permissionsGateDesktopNote.
  ///
  /// In en, this message translates to:
  /// **'On desktop, images are usually chosen from files; mobile-style gallery permissions may not appear.'**
  String get permissionsGateDesktopNote;

  /// No description provided for @permissionRationalePhotosTitle.
  ///
  /// In en, this message translates to:
  /// **'Photos access needed'**
  String get permissionRationalePhotosTitle;

  /// No description provided for @permissionRationalePhotosBody.
  ///
  /// In en, this message translates to:
  /// **'Photo access is turned off. Open system settings to allow gallery access, then try again.'**
  String get permissionRationalePhotosBody;

  /// No description provided for @permissionRationaleCameraTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera access needed'**
  String get permissionRationaleCameraTitle;

  /// No description provided for @permissionRationaleCameraBody.
  ///
  /// In en, this message translates to:
  /// **'Camera access is turned off. Open system settings to allow the camera, then try again.'**
  String get permissionRationaleCameraBody;

  /// No description provided for @permissionRationaleNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications off'**
  String get permissionRationaleNotificationsTitle;

  /// No description provided for @permissionRationaleNotificationsBody.
  ///
  /// In en, this message translates to:
  /// **'Notifications are disabled for this app. Turn them on in system settings to receive alerts.'**
  String get permissionRationaleNotificationsBody;

  /// No description provided for @permissionRationaleLocationTitle.
  ///
  /// In en, this message translates to:
  /// **'Location access needed'**
  String get permissionRationaleLocationTitle;

  /// No description provided for @permissionRationaleLocationBody.
  ///
  /// In en, this message translates to:
  /// **'Location is off or denied. Open system settings to allow location, then use “My location” again.'**
  String get permissionRationaleLocationBody;

  /// No description provided for @deviceLimitTitle.
  ///
  /// In en, this message translates to:
  /// **'Device limit'**
  String get deviceLimitTitle;

  /// No description provided for @deviceLimitBody.
  ///
  /// In en, this message translates to:
  /// **'This account already has two registered devices. Remove one from Settings (or ask your organization owner) before signing in here.'**
  String get deviceLimitBody;

  /// No description provided for @orgMandatoryPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'For security, you must set a new password before continuing (use the temporary password you were given as the current password).'**
  String get orgMandatoryPasswordHint;

  /// No description provided for @orgTeamManagement.
  ///
  /// In en, this message translates to:
  /// **'Team management'**
  String get orgTeamManagement;

  /// No description provided for @orgMonitoring.
  ///
  /// In en, this message translates to:
  /// **'My desk — team monitoring'**
  String get orgMonitoring;

  /// No description provided for @orgInviteMember.
  ///
  /// In en, this message translates to:
  /// **'Invite team member'**
  String get orgInviteMember;

  /// No description provided for @orgNationalIdHint.
  ///
  /// In en, this message translates to:
  /// **'Unique Business ID (700…) — tap field to copy'**
  String get orgNationalIdHint;

  /// No description provided for @orgTempPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Temporary password (min 8 characters)'**
  String get orgTempPasswordHint;

  /// No description provided for @orgPermissionsJsonHint.
  ///
  /// In en, this message translates to:
  /// **'Permissions (JSON object, optional)'**
  String get orgPermissionsJsonHint;

  /// No description provided for @orgSeatUsage.
  ///
  /// In en, this message translates to:
  /// **'Seats: {used} / {limit}'**
  String orgSeatUsage(int used, int limit);

  /// No description provided for @orgInviteSend.
  ///
  /// In en, this message translates to:
  /// **'Create member'**
  String get orgInviteSend;

  /// No description provided for @orgInviteSuccess.
  ///
  /// In en, this message translates to:
  /// **'Member created or linked successfully'**
  String get orgInviteSuccess;

  /// No description provided for @orgInviteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not invite member'**
  String get orgInviteFailed;

  /// No description provided for @orgMembersTitle.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get orgMembersTitle;

  /// No description provided for @orgActivityTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get orgActivityTitle;

  /// No description provided for @orgDevicesTitle.
  ///
  /// In en, this message translates to:
  /// **'Trusted devices'**
  String get orgDevicesTitle;

  /// No description provided for @orgNoOrg.
  ///
  /// In en, this message translates to:
  /// **'No organization record'**
  String get orgNoOrg;

  /// No description provided for @orgOwnerOnly.
  ///
  /// In en, this message translates to:
  /// **'Only the organization owner can open this'**
  String get orgOwnerOnly;

  /// No description provided for @orgRemoveDevice.
  ///
  /// In en, this message translates to:
  /// **'Revoke device'**
  String get orgRemoveDevice;

  /// No description provided for @orgDeviceRevoked.
  ///
  /// In en, this message translates to:
  /// **'Device revoked'**
  String get orgDeviceRevoked;

  /// No description provided for @orgStatsLogins.
  ///
  /// In en, this message translates to:
  /// **'Logins (sample)'**
  String get orgStatsLogins;

  /// No description provided for @orgStatsListings.
  ///
  /// In en, this message translates to:
  /// **'Listing actions (sample)'**
  String get orgStatsListings;

  /// No description provided for @orgMonitorRoleOwner.
  ///
  /// In en, this message translates to:
  /// **'You see the full team activity log (organization owner).'**
  String get orgMonitorRoleOwner;

  /// No description provided for @orgMonitorRoleMember.
  ///
  /// In en, this message translates to:
  /// **'You see only actions performed with your account.'**
  String get orgMonitorRoleMember;

  /// No description provided for @orgMonitorChartDaily.
  ///
  /// In en, this message translates to:
  /// **'Events per day (last 14 days)'**
  String get orgMonitorChartDaily;

  /// No description provided for @orgMonitorChartActions.
  ///
  /// In en, this message translates to:
  /// **'Most frequent actions'**
  String get orgMonitorChartActions;

  /// No description provided for @orgMonitorChartMembers.
  ///
  /// In en, this message translates to:
  /// **'Events by team member'**
  String get orgMonitorChartMembers;

  /// No description provided for @orgMonitorEngagementNote.
  ///
  /// In en, this message translates to:
  /// **'Engagement scores are derived from logged actions in the app (not external ratings).'**
  String get orgMonitorEngagementNote;

  /// No description provided for @orgMonitorEmptyCharts.
  ///
  /// In en, this message translates to:
  /// **'Not enough activity yet for charts.'**
  String get orgMonitorEmptyCharts;

  /// No description provided for @orgMonitorTotalEvents.
  ///
  /// In en, this message translates to:
  /// **'Total events'**
  String get orgMonitorTotalEvents;

  /// No description provided for @orgMonitorEngagementScore.
  ///
  /// In en, this message translates to:
  /// **'Engagement (estimated)'**
  String get orgMonitorEngagementScore;

  /// No description provided for @postAuthChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking account…'**
  String get postAuthChecking;

  /// No description provided for @loginIdentifierFieldHint.
  ///
  /// In en, this message translates to:
  /// **'ID/Iqama, FAL license, or unified national no. 700… (10 digits)'**
  String get loginIdentifierFieldHint;

  /// No description provided for @loginEnterIdentifierFirst.
  ///
  /// In en, this message translates to:
  /// **'Enter 10 digits: ID, Iqama, or FAL license number.'**
  String get loginEnterIdentifierFirst;

  /// No description provided for @loginNoAccountLinkedIdentifier.
  ///
  /// In en, this message translates to:
  /// **'No account is linked to this number.'**
  String get loginNoAccountLinkedIdentifier;

  /// No description provided for @loginIdentifierMustBe10.
  ///
  /// In en, this message translates to:
  /// **'Enter exactly 10 digits.'**
  String get loginIdentifierMustBe10;

  /// No description provided for @verScreenTitleMarketer.
  ///
  /// In en, this message translates to:
  /// **'Marketer verification request'**
  String get verScreenTitleMarketer;

  /// No description provided for @verScreenTitleOffice.
  ///
  /// In en, this message translates to:
  /// **'Real estate office verification'**
  String get verScreenTitleOffice;

  /// No description provided for @verScreenTitleInstitution.
  ///
  /// In en, this message translates to:
  /// **'Real estate institution verification'**
  String get verScreenTitleInstitution;

  /// No description provided for @verScreenTitleCompany.
  ///
  /// In en, this message translates to:
  /// **'Real estate company verification'**
  String get verScreenTitleCompany;

  /// No description provided for @verFalLicenseLabel.
  ///
  /// In en, this message translates to:
  /// **'FAL license number'**
  String get verFalLicenseLabel;

  /// No description provided for @verFalLicenseHint.
  ///
  /// In en, this message translates to:
  /// **'Official 10-digit FAL license from REGA.'**
  String get verFalLicenseHint;

  /// No description provided for @verFalLookupButton.
  ///
  /// In en, this message translates to:
  /// **'Verify license (REGA)'**
  String get verFalLookupButton;

  /// No description provided for @verFalLookupBusy.
  ///
  /// In en, this message translates to:
  /// **'Looking up…'**
  String get verFalLookupBusy;

  /// No description provided for @verBrokerEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get verBrokerEmailLabel;

  /// No description provided for @verBrokerEmailHint.
  ///
  /// In en, this message translates to:
  /// **'Contact email used for verification.'**
  String get verBrokerEmailHint;

  /// No description provided for @verBrokerNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Broker name'**
  String get verBrokerNameLabel;

  /// No description provided for @verBrokerNameHint.
  ///
  /// In en, this message translates to:
  /// **'As on the license (Arabic only in this field).'**
  String get verBrokerNameHint;

  /// No description provided for @verBrokerPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'Mobile number (Western digits).'**
  String get verBrokerPhoneHint;

  /// No description provided for @verPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get verPhoneLabel;

  /// No description provided for @verCityLabel.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get verCityLabel;

  /// No description provided for @verCityHint.
  ///
  /// In en, this message translates to:
  /// **'Arabic only.'**
  String get verCityHint;

  /// No description provided for @verDistrictLabel.
  ///
  /// In en, this message translates to:
  /// **'District'**
  String get verDistrictLabel;

  /// No description provided for @verDistrictHint.
  ///
  /// In en, this message translates to:
  /// **'Arabic only.'**
  String get verDistrictHint;

  /// No description provided for @verRegionLabel.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get verRegionLabel;

  /// No description provided for @verRegionHint.
  ///
  /// In en, this message translates to:
  /// **'Arabic only.'**
  String get verRegionHint;

  /// No description provided for @verLicenseTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'License type'**
  String get verLicenseTypeLabel;

  /// No description provided for @verLicenseStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'License status'**
  String get verLicenseStatusLabel;

  /// No description provided for @verOfficeNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Entity name'**
  String get verOfficeNameLabel;

  /// No description provided for @verOfficeNameHint.
  ///
  /// In en, this message translates to:
  /// **'Official name as on the registry or license.'**
  String get verOfficeNameHint;

  /// No description provided for @verCrLabel.
  ///
  /// In en, this message translates to:
  /// **'Commercial registration (CR)'**
  String get verCrLabel;

  /// No description provided for @verCrHint.
  ///
  /// In en, this message translates to:
  /// **'Digits as shown on documents.'**
  String get verCrHint;

  /// No description provided for @verUnifiedCrLabel.
  ///
  /// In en, this message translates to:
  /// **'Unified CR number (10 digits)'**
  String get verUnifiedCrLabel;

  /// No description provided for @verUnifiedCrHint.
  ///
  /// In en, this message translates to:
  /// **'Unified commercial registration from MC (often starts with 700…).'**
  String get verUnifiedCrHint;

  /// No description provided for @verMcLookupButton.
  ///
  /// In en, this message translates to:
  /// **'Lookup CR (Ministry of Commerce)'**
  String get verMcLookupButton;

  /// No description provided for @verMcRegistryNotActive.
  ///
  /// In en, this message translates to:
  /// **'This commercial registration is not active (e.g. struck off). You cannot continue.'**
  String get verMcRegistryNotActive;

  /// No description provided for @verMcLookupSuccess.
  ///
  /// In en, this message translates to:
  /// **'Commercial registry data loaded.'**
  String get verMcLookupSuccess;

  /// No description provided for @verMcPleaseLookup.
  ///
  /// In en, this message translates to:
  /// **'Enter the 10-digit unified CR and tap lookup before submitting.'**
  String get verMcPleaseLookup;

  /// No description provided for @verFalDataLoadedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'License data loaded. Review the fields and complete the form.'**
  String get verFalDataLoadedSnackbar;

  /// No description provided for @verTeamSwitchTitle.
  ///
  /// In en, this message translates to:
  /// **'Are you part of a real estate organization team?'**
  String get verTeamSwitchTitle;

  /// No description provided for @verTeamSwitchSubtitle.
  ///
  /// In en, this message translates to:
  /// **'If yes, enter the confidential 10-digit code from your organization manager.'**
  String get verTeamSwitchSubtitle;

  /// No description provided for @verTeamCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Team join code (10 digits).'**
  String get verTeamCodeHint;

  /// No description provided for @verTeamPendingNote.
  ///
  /// In en, this message translates to:
  /// **'After submit, your manager will approve and assign permissions.'**
  String get verTeamPendingNote;

  /// No description provided for @verNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Optional notes for reviewers.'**
  String get verNoteHint;

  /// No description provided for @badgeVerifiedShort.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get badgeVerifiedShort;

  /// No description provided for @latinCharsNotAllowedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'English letters are not allowed in this field.'**
  String get latinCharsNotAllowedSnackbar;

  /// No description provided for @falRenewalTitle.
  ///
  /// In en, this message translates to:
  /// **'Renew FAL license'**
  String get falRenewalTitle;

  /// No description provided for @falRenewalBody.
  ///
  /// In en, this message translates to:
  /// **'Your FAL license has expired or must be updated. Enter the new license number and tap verify to refresh data from REGA.'**
  String get falRenewalBody;

  /// No description provided for @falRenewalSubmit.
  ///
  /// In en, this message translates to:
  /// **'Verify and update'**
  String get falRenewalSubmit;

  /// No description provided for @falRenewalExpired.
  ///
  /// In en, this message translates to:
  /// **'This license is expired.'**
  String get falRenewalExpired;

  /// No description provided for @falRenewalInvalid.
  ///
  /// In en, this message translates to:
  /// **'Could not verify the license.'**
  String get falRenewalInvalid;

  /// No description provided for @falExpiryBannerWeek.
  ///
  /// In en, this message translates to:
  /// **'Reminder: your FAL license expires within a week — renew to avoid account suspension.'**
  String get falExpiryBannerWeek;

  /// No description provided for @profileSignatureTitle.
  ///
  /// In en, this message translates to:
  /// **'Complete signature'**
  String get profileSignatureTitle;

  /// No description provided for @profileSignatureBody.
  ///
  /// In en, this message translates to:
  /// **'Upload a clear signature image (PNG or JPG) on a light background.'**
  String get profileSignatureBody;

  /// No description provided for @profileSignaturePick.
  ///
  /// In en, this message translates to:
  /// **'Choose signature image'**
  String get profileSignaturePick;

  /// No description provided for @profileSignatureNoBytes.
  ///
  /// In en, this message translates to:
  /// **'Could not read the file.'**
  String get profileSignatureNoBytes;

  /// No description provided for @profileSignatureTabDraw.
  ///
  /// In en, this message translates to:
  /// **'Draw'**
  String get profileSignatureTabDraw;

  /// No description provided for @profileSignatureTabUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload image'**
  String get profileSignatureTabUpload;

  /// No description provided for @profileSignatureDrawHint.
  ///
  /// In en, this message translates to:
  /// **'Sign inside the box with your finger or stylus. It is saved as an image for contracts.'**
  String get profileSignatureDrawHint;

  /// No description provided for @profileSignatureClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get profileSignatureClear;

  /// No description provided for @profileSignatureSaveDraw.
  ///
  /// In en, this message translates to:
  /// **'Save signature'**
  String get profileSignatureSaveDraw;

  /// No description provided for @profileSignatureEmpty.
  ///
  /// In en, this message translates to:
  /// **'Draw your signature in the box first.'**
  String get profileSignatureEmpty;

  /// No description provided for @profileRevisionGateTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile update required'**
  String get profileRevisionGateTitle;

  /// No description provided for @profileRevisionGateBody.
  ///
  /// In en, this message translates to:
  /// **'This app version needs you to confirm you have reviewed your profile information. Tap confirm to continue.'**
  String get profileRevisionGateBody;

  /// No description provided for @profileRevisionGateConfirm.
  ///
  /// In en, this message translates to:
  /// **'I have reviewed — continue'**
  String get profileRevisionGateConfirm;

  /// No description provided for @settingsPublicMemberIdSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your 10-digit public ID (offices and teams)'**
  String get settingsPublicMemberIdSubtitle;

  /// No description provided for @onboardingWelcomeTitleApp.
  ///
  /// In en, this message translates to:
  /// **'Motawoq Real Estate app'**
  String get onboardingWelcomeTitleApp;

  /// No description provided for @onboardingWelcomeTitleWeb.
  ///
  /// In en, this message translates to:
  /// **'Motawoq Real Estate online platform'**
  String get onboardingWelcomeTitleWeb;

  /// No description provided for @onboardingWelcomeBodyApp.
  ///
  /// In en, this message translates to:
  /// **'We’re glad you’re here. Whether you work independently, run an office, a company, or an institution, our team is here to serve you and keep your experience smooth—your needs come first. Enjoy exploring.'**
  String get onboardingWelcomeBodyApp;

  /// No description provided for @onboardingWelcomeBodyWeb.
  ///
  /// In en, this message translates to:
  /// **'We’re glad you’re here on the Motawoq Real Estate online platform. Whether you work independently, run an office, a company, or an institution, our team is here to serve you and keep your experience smooth—your needs come first. Enjoy exploring.'**
  String get onboardingWelcomeBodyWeb;

  /// No description provided for @onboardingHomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get onboardingHomeTitle;

  /// No description provided for @onboardingHomeBody.
  ///
  /// In en, this message translates to:
  /// **'Browse listings and use the filters at the top (city, type, purpose). Tap any card to open full details.'**
  String get onboardingHomeBody;

  /// No description provided for @onboardingMyAdsTitle.
  ///
  /// In en, this message translates to:
  /// **'My page'**
  String get onboardingMyAdsTitle;

  /// No description provided for @onboardingMyAdsBodyMarketing.
  ///
  /// In en, this message translates to:
  /// **'Your listings, marketing requests, offers, and contracts—in one place, aligned with your marketing role.'**
  String get onboardingMyAdsBodyMarketing;

  /// No description provided for @onboardingMyAdsBodyOwner.
  ///
  /// In en, this message translates to:
  /// **'Manage your listings and requests as a property owner from this tab.'**
  String get onboardingMyAdsBodyOwner;

  /// No description provided for @onboardingFavoritesTitle.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get onboardingFavoritesTitle;

  /// No description provided for @onboardingFavoritesBody.
  ///
  /// In en, this message translates to:
  /// **'Save listings you care about and come back to them anytime from this tab.'**
  String get onboardingFavoritesBody;

  /// No description provided for @onboardingMySubmissionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Requests/Listings'**
  String get onboardingMySubmissionsTitle;

  /// No description provided for @onboardingMySubmissionsBody.
  ///
  /// In en, this message translates to:
  /// **'Your property listings and market requests you submitted appear as cards, similar to Home — open them from the Requests/Listings tab.'**
  String get onboardingMySubmissionsBody;

  /// No description provided for @onboardingCartTitle.
  ///
  /// In en, this message translates to:
  /// **'My deals'**
  String get onboardingCartTitle;

  /// No description provided for @onboardingCartBody.
  ///
  /// In en, this message translates to:
  /// **'Review properties you added to My deals before you continue.'**
  String get onboardingCartBody;

  /// No description provided for @onboardingChatTitle.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get onboardingChatTitle;

  /// No description provided for @onboardingChatBody.
  ///
  /// In en, this message translates to:
  /// **'Reach the people involved in your deals from your chat inbox.'**
  String get onboardingChatBody;

  /// No description provided for @onboardingSupportTitle.
  ///
  /// In en, this message translates to:
  /// **'Technical support'**
  String get onboardingSupportTitle;

  /// No description provided for @onboardingSupportBody.
  ///
  /// In en, this message translates to:
  /// **'Help center, and soon administration contact and tickets. Open chats from the bell icon or from here.'**
  String get onboardingSupportBody;

  /// No description provided for @onboardingMyDeskTitle.
  ///
  /// In en, this message translates to:
  /// **'My desk'**
  String get onboardingMyDeskTitle;

  /// No description provided for @onboardingMyDeskBodyMarketing.
  ///
  /// In en, this message translates to:
  /// **'Your organization or team workspace—approvals and tasks from the My desk icon in the top app bar.'**
  String get onboardingMyDeskBodyMarketing;

  /// No description provided for @onboardingMyDeskBodyOwnerIndividual.
  ///
  /// In en, this message translates to:
  /// **'Your personal workspace as an owner—manage listings and tasks from the My desk icon in the top app bar.'**
  String get onboardingMyDeskBodyOwnerIndividual;

  /// No description provided for @onboardingMyDeskBodyOrgMember.
  ///
  /// In en, this message translates to:
  /// **'Your organization workspace—follow tasks according to your permissions from the My desk icon in the top app bar.'**
  String get onboardingMyDeskBodyOrgMember;

  /// No description provided for @onboardingStepCounter.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String onboardingStepCounter(int current, int total);

  /// No description provided for @onboardingNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// No description provided for @onboardingPrevious.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get onboardingPrevious;

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// No description provided for @onboardingClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get onboardingClose;

  /// No description provided for @onboardingFinish.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get onboardingFinish;

  /// No description provided for @settingsAccentTitle.
  ///
  /// In en, this message translates to:
  /// **'Accent color'**
  String get settingsAccentTitle;

  /// No description provided for @settingsAccentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Five preset colors for light and dark theme. Applies to primary actions and accent frames (cards, dialogs, fields)—surfaces stay neutral.'**
  String get settingsAccentSubtitle;

  /// No description provided for @accentColorDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose accent color'**
  String get accentColorDialogTitle;

  /// No description provided for @accentColorDialogBody.
  ///
  /// In en, this message translates to:
  /// **'Pick a color that fits you. Language, dark mode, and accent are together under Settings → Appearance & language.'**
  String get accentColorDialogBody;

  /// No description provided for @accentColorLater.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get accentColorLater;

  /// No description provided for @accentColorSkipKeepsDefault.
  ///
  /// In en, this message translates to:
  /// **'If you skip or close this dialog, your current accent stays unchanged.'**
  String get accentColorSkipKeepsDefault;

  /// No description provided for @marketInsightsTitle.
  ///
  /// In en, this message translates to:
  /// **'Market insights'**
  String get marketInsightsTitle;

  /// No description provided for @settingsMarketInsightsCardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Leaderboards, listing stats, and organization activity—same as the chart icon on the home screen. Background refresh about every 2 hours.'**
  String get settingsMarketInsightsCardSubtitle;

  /// No description provided for @onboardingMarketInsightsBody.
  ///
  /// In en, this message translates to:
  /// **'Tap the insights icon at the top of the screen for market stats, leaderboards for individuals and marketers, and top organizations. Numbers update about every two hours—pull down on that screen to refresh now.'**
  String get onboardingMarketInsightsBody;

  /// No description provided for @marketInsightsRefreshHint.
  ///
  /// In en, this message translates to:
  /// **'Numbers refresh in the background about every 2 hours; pull down on any tab for an instant update.'**
  String get marketInsightsRefreshHint;

  /// No description provided for @marketInsightsPublishedTotal.
  ///
  /// In en, this message translates to:
  /// **'Published listings'**
  String get marketInsightsPublishedTotal;

  /// No description provided for @marketInsightsKpiTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get marketInsightsKpiTotal;

  /// No description provided for @marketInsightsNew7d.
  ///
  /// In en, this message translates to:
  /// **'New (7 days)'**
  String get marketInsightsNew7d;

  /// No description provided for @marketInsightsNew30d.
  ///
  /// In en, this message translates to:
  /// **'New (30 days)'**
  String get marketInsightsNew30d;

  /// No description provided for @marketInsightsFeatured.
  ///
  /// In en, this message translates to:
  /// **'Featured'**
  String get marketInsightsFeatured;

  /// No description provided for @marketInsightsByAccountType.
  ///
  /// In en, this message translates to:
  /// **'By account type'**
  String get marketInsightsByAccountType;

  /// No description provided for @marketInsightsByPropertyType.
  ///
  /// In en, this message translates to:
  /// **'By property type'**
  String get marketInsightsByPropertyType;

  /// No description provided for @marketInsightsListingRequests.
  ///
  /// In en, this message translates to:
  /// **'Marketing requests'**
  String get marketInsightsListingRequests;

  /// No description provided for @marketInsightsOrgsRegistered.
  ///
  /// In en, this message translates to:
  /// **'Offices / institutions / companies'**
  String get marketInsightsOrgsRegistered;

  /// No description provided for @marketInsightsTopOrgs.
  ///
  /// In en, this message translates to:
  /// **'Top organizations by listings'**
  String get marketInsightsTopOrgs;

  /// No description provided for @marketInsightsLeaderboard.
  ///
  /// In en, this message translates to:
  /// **'Leaderboard'**
  String get marketInsightsLeaderboard;

  /// No description provided for @marketInsightsLeaderboardIndividuals.
  ///
  /// In en, this message translates to:
  /// **'Individuals'**
  String get marketInsightsLeaderboardIndividuals;

  /// No description provided for @marketInsightsLeaderboardMarketers.
  ///
  /// In en, this message translates to:
  /// **'Marketers & orgs'**
  String get marketInsightsLeaderboardMarketers;

  /// No description provided for @marketInsightsFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get marketInsightsFilterAll;

  /// No description provided for @marketInsightsRank.
  ///
  /// In en, this message translates to:
  /// **'Rank'**
  String get marketInsightsRank;

  /// No description provided for @marketInsightsListingsShort.
  ///
  /// In en, this message translates to:
  /// **'listings'**
  String get marketInsightsListingsShort;

  /// No description provided for @marketInsightsYourSnapshot.
  ///
  /// In en, this message translates to:
  /// **'Your position'**
  String get marketInsightsYourSnapshot;

  /// No description provided for @marketInsightsCompetitiveHint.
  ///
  /// In en, this message translates to:
  /// **'Publish quality listings and climb the leaderboard—healthy competition helps everyone find better deals.'**
  String get marketInsightsCompetitiveHint;

  /// No description provided for @marketInsightsLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load market insights. Check your connection or ensure the server migration is applied.'**
  String get marketInsightsLoadError;

  /// No description provided for @marketInsightsRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get marketInsightsRetry;

  /// No description provided for @marketInsightsLastUpdated.
  ///
  /// In en, this message translates to:
  /// **'Last updated: {time}'**
  String marketInsightsLastUpdated(String time);

  /// No description provided for @marketInsightsYourRankGlobal.
  ///
  /// In en, this message translates to:
  /// **'Your overall rank: {rank}'**
  String marketInsightsYourRankGlobal(String rank);

  /// No description provided for @marketInsightsYourListings.
  ///
  /// In en, this message translates to:
  /// **'Your published listings: {count}'**
  String marketInsightsYourListings(int count);

  /// No description provided for @marketInsightsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No data yet.'**
  String get marketInsightsEmpty;

  /// No description provided for @marketInsightsTabOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get marketInsightsTabOverview;

  /// No description provided for @marketInsightsTabAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Breakdown'**
  String get marketInsightsTabAnalytics;

  /// No description provided for @marketInsightsTabCommunity.
  ///
  /// In en, this message translates to:
  /// **'Leaderboards'**
  String get marketInsightsTabCommunity;

  /// No description provided for @marketInsightsShareSummary.
  ///
  /// In en, this message translates to:
  /// **'Share summary'**
  String get marketInsightsShareSummary;

  /// No description provided for @marketInsightsCopySummary.
  ///
  /// In en, this message translates to:
  /// **'Copy summary'**
  String get marketInsightsCopySummary;

  /// No description provided for @marketInsightsCopied.
  ///
  /// In en, this message translates to:
  /// **'Summary copied'**
  String get marketInsightsCopied;

  /// No description provided for @marketInsightsGuestHint.
  ///
  /// In en, this message translates to:
  /// **'Sign in to see your rank and listing count alongside everyone else.'**
  String get marketInsightsGuestHint;

  /// No description provided for @marketInsightsSignInToSeeRank.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get marketInsightsSignInToSeeRank;

  /// No description provided for @securityInactivityTitle.
  ///
  /// In en, this message translates to:
  /// **'Inactivity detected'**
  String get securityInactivityTitle;

  /// No description provided for @securityInactivityTime.
  ///
  /// In en, this message translates to:
  /// **'Time: {time}'**
  String securityInactivityTime(String time);

  /// No description provided for @securityInactivityBodyLock.
  ///
  /// In en, this message translates to:
  /// **'Continue? If you do not respond in {seconds} seconds you will be asked to unlock the app (PIN or device biometrics).'**
  String securityInactivityBodyLock(int seconds);

  /// No description provided for @securityInactivityBodySignOut.
  ///
  /// In en, this message translates to:
  /// **'Continue? If you do not respond in {seconds} seconds you will be signed out.'**
  String securityInactivityBodySignOut(int seconds);

  /// No description provided for @securityContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get securityContinue;

  /// No description provided for @securitySignOutFromPrompt.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get securitySignOutFromPrompt;

  /// No description provided for @securitySessionSupersededTitle.
  ///
  /// In en, this message translates to:
  /// **'Session notice'**
  String get securitySessionSupersededTitle;

  /// No description provided for @securitySessionSupersededBody.
  ///
  /// In en, this message translates to:
  /// **'Your account was signed in from another browser or device. This session will close for your security.'**
  String get securitySessionSupersededBody;

  /// No description provided for @securitySessionSupersededBodyDetail.
  ///
  /// In en, this message translates to:
  /// **'Signed in from another device (Location: {city}, Device: {device}). You were signed out for security.'**
  String securitySessionSupersededBodyDetail(String city, String device);

  /// No description provided for @securitySessionContinueHere.
  ///
  /// In en, this message translates to:
  /// **'Keep using this device'**
  String get securitySessionContinueHere;

  /// No description provided for @securitySessionSignOutThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Sign out here'**
  String get securitySessionSignOutThisDevice;

  /// No description provided for @securitySessionSupersededChooseHint.
  ///
  /// In en, this message translates to:
  /// **'• Keep using this device: makes this session active again and signs out other open sessions.\n• Sign out here: closes this session on this device only (the other session stays signed in).'**
  String get securitySessionSupersededChooseHint;

  /// No description provided for @securityDeviceLimitMessage.
  ///
  /// In en, this message translates to:
  /// **'Sorry, sign-in is not possible. You have reached the maximum number of devices (2). Manage your devices to continue.'**
  String get securityDeviceLimitMessage;

  /// No description provided for @securityInactivityLockMessage.
  ///
  /// In en, this message translates to:
  /// **'Session locked due to inactivity. Please authenticate again.'**
  String get securityInactivityLockMessage;

  /// No description provided for @securityDeviceManagementTitle.
  ///
  /// In en, this message translates to:
  /// **'Device management'**
  String get securityDeviceManagementTitle;

  /// No description provided for @securityDeviceOtpHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the verification code sent to your registered phone.'**
  String get securityDeviceOtpHint;

  /// No description provided for @securityDeviceRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove device'**
  String get securityDeviceRemoveConfirm;

  /// No description provided for @securityClearOtherDevices.
  ///
  /// In en, this message translates to:
  /// **'Clear other devices'**
  String get securityClearOtherDevices;

  /// No description provided for @securityRetryContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue after update'**
  String get securityRetryContinue;

  /// No description provided for @securityOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get securityOk;

  /// No description provided for @settingsSectionRegisteredDevices.
  ///
  /// In en, this message translates to:
  /// **'Registered devices'**
  String get settingsSectionRegisteredDevices;

  /// No description provided for @settingsSectionSessionHistory.
  ///
  /// In en, this message translates to:
  /// **'Sign-in history'**
  String get settingsSectionSessionHistory;

  /// No description provided for @settingsDevicesFooterHint.
  ///
  /// In en, this message translates to:
  /// **'Shows this app, web, and other clients when your project records sessions on the server.'**
  String get settingsDevicesFooterHint;

  /// No description provided for @settingsSessionKindWeb.
  ///
  /// In en, this message translates to:
  /// **'Web'**
  String get settingsSessionKindWeb;

  /// No description provided for @settingsSessionKindApp.
  ///
  /// In en, this message translates to:
  /// **'Mobile app'**
  String get settingsSessionKindApp;

  /// No description provided for @settingsSessionKindUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown client'**
  String get settingsSessionKindUnknown;

  /// No description provided for @marketInsightsDistinctPublishers.
  ///
  /// In en, this message translates to:
  /// **'Distinct publishers'**
  String get marketInsightsDistinctPublishers;

  /// No description provided for @marketInsightsRegisteredProfiles.
  ///
  /// In en, this message translates to:
  /// **'Registered profiles'**
  String get marketInsightsRegisteredProfiles;

  /// No description provided for @settingsTextScaleTitle.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get settingsTextScaleTitle;

  /// No description provided for @settingsTextScaleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Adjusts text across the app. Combines with your system accessibility size, then stays within safe limits to reduce broken layouts.'**
  String get settingsTextScaleSubtitle;

  /// No description provided for @settingsTextScaleReset.
  ///
  /// In en, this message translates to:
  /// **'Reset to default'**
  String get settingsTextScaleReset;

  /// No description provided for @settingsTextScalePercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String settingsTextScalePercent(int percent);

  /// No description provided for @orgJoinPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Join request pending'**
  String get orgJoinPendingTitle;

  /// No description provided for @orgJoinPendingBody.
  ///
  /// In en, this message translates to:
  /// **'Your request to join {orgLabel} is still under review. The manager will approve or decline it. After approval, tap refresh below to continue.'**
  String orgJoinPendingBody(String orgLabel);

  /// No description provided for @orgJoinPendingRecheck.
  ///
  /// In en, this message translates to:
  /// **'Refresh status'**
  String get orgJoinPendingRecheck;

  /// No description provided for @orgKindOffice.
  ///
  /// In en, this message translates to:
  /// **'real estate office'**
  String get orgKindOffice;

  /// No description provided for @orgKindInstitution.
  ///
  /// In en, this message translates to:
  /// **'institution'**
  String get orgKindInstitution;

  /// No description provided for @orgKindCompany.
  ///
  /// In en, this message translates to:
  /// **'real estate company'**
  String get orgKindCompany;

  /// No description provided for @orgKindGeneric.
  ///
  /// In en, this message translates to:
  /// **'the organization'**
  String get orgKindGeneric;

  /// No description provided for @deskTabMonitoring.
  ///
  /// In en, this message translates to:
  /// **'Monitor'**
  String get deskTabMonitoring;

  /// No description provided for @deskTabTeamChat.
  ///
  /// In en, this message translates to:
  /// **'Team chat'**
  String get deskTabTeamChat;

  /// No description provided for @deskTabTeam.
  ///
  /// In en, this message translates to:
  /// **'Team'**
  String get deskTabTeam;

  /// No description provided for @deskTabJoinRequests.
  ///
  /// In en, this message translates to:
  /// **'Join requests'**
  String get deskTabJoinRequests;

  /// No description provided for @deskTabInsights.
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get deskTabInsights;

  /// No description provided for @settingsDistinguishedNumberSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your distinguished number (10 digits starting with 700 when applicable)'**
  String get settingsDistinguishedNumberSubtitle;

  /// No description provided for @settingsRevealDistinguishedNumber.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get settingsRevealDistinguishedNumber;

  /// No description provided for @settingsHideDistinguishedNumber.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get settingsHideDistinguishedNumber;

  /// No description provided for @settingsCopyDistinguishedNumber.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get settingsCopyDistinguishedNumber;

  /// No description provided for @settingsEditDistinguishedNumber.
  ///
  /// In en, this message translates to:
  /// **'Update number'**
  String get settingsEditDistinguishedNumber;

  /// No description provided for @settingsLastSeenPrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Hide my last seen in chat'**
  String get settingsLastSeenPrivacyTitle;

  /// No description provided for @settingsLastSeenPrivacySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Others will not see when you were last active in chat (you can still appear online while using the app).'**
  String get settingsLastSeenPrivacySubtitle;

  /// No description provided for @sensitiveActionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get sensitiveActionConfirm;

  /// No description provided for @sensitiveActionCancel.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get sensitiveActionCancel;

  /// No description provided for @chatKindDirect.
  ///
  /// In en, this message translates to:
  /// **'Team message'**
  String get chatKindDirect;

  /// No description provided for @chatListKindDirect.
  ///
  /// In en, this message translates to:
  /// **'Team'**
  String get chatListKindDirect;

  /// No description provided for @globalPresenceOnlineTooltip.
  ///
  /// In en, this message translates to:
  /// **'You appear online while the app is open'**
  String get globalPresenceOnlineTooltip;

  /// No description provided for @orgJoinApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get orgJoinApprove;

  /// No description provided for @orgJoinReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get orgJoinReject;

  /// No description provided for @orgJoinApprovedToast.
  ///
  /// In en, this message translates to:
  /// **'Member approved'**
  String get orgJoinApprovedToast;

  /// No description provided for @orgJoinRejectedToast.
  ///
  /// In en, this message translates to:
  /// **'Request declined'**
  String get orgJoinRejectedToast;

  /// No description provided for @orgJoinActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update request'**
  String get orgJoinActionFailed;

  /// No description provided for @orgJoinNoPending.
  ///
  /// In en, this message translates to:
  /// **'No pending join requests'**
  String get orgJoinNoPending;

  /// No description provided for @listingPublicActionsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get listingPublicActionsTooltip;

  /// No description provided for @listingPublicShareLink.
  ///
  /// In en, this message translates to:
  /// **'Share link'**
  String get listingPublicShareLink;

  /// No description provided for @listingPublicCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get listingPublicCopyLink;

  /// No description provided for @listingPublicToggleBest.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get listingPublicToggleBest;

  /// No description provided for @listingPublicShowOnHome.
  ///
  /// In en, this message translates to:
  /// **'Show on home feed'**
  String get listingPublicShowOnHome;

  /// No description provided for @listingPublicWithdrawPendingReport.
  ///
  /// In en, this message translates to:
  /// **'Withdraw pending report'**
  String get listingPublicWithdrawPendingReport;

  /// No description provided for @listingPublicHideFromHome.
  ///
  /// In en, this message translates to:
  /// **'Hide from home'**
  String get listingPublicHideFromHome;

  /// No description provided for @listingPublicReport.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get listingPublicReport;

  /// No description provided for @listingReportGateHourlyBlock.
  ///
  /// In en, this message translates to:
  /// **'You exceeded the hourly report limit. Reports affect others’ rights — please wait before filing another.'**
  String get listingReportGateHourlyBlock;

  /// No description provided for @listingReportGateDailyBlock.
  ///
  /// In en, this message translates to:
  /// **'You exceeded the daily report limit. Contact support if you have an exceptional case.'**
  String get listingReportGateDailyBlock;

  /// No description provided for @listingReportGateSternWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning: repeated reports without good cause may trigger a review. Listings involve real people’s rights — use reports responsibly.'**
  String get listingReportGateSternWarning;

  /// No description provided for @listingReportCannotSubmitGeneric.
  ///
  /// In en, this message translates to:
  /// **'You cannot submit a report right now.'**
  String get listingReportCannotSubmitGeneric;

  /// No description provided for @listingReportImportantNoticeTitle.
  ///
  /// In en, this message translates to:
  /// **'Important notice'**
  String get listingReportImportantNoticeTitle;

  /// No description provided for @listingReportContinueToReport.
  ///
  /// In en, this message translates to:
  /// **'Continue to report'**
  String get listingReportContinueToReport;

  /// No description provided for @listingReportDialogCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get listingReportDialogCancel;

  /// No description provided for @listingReportPropertySheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Report listing'**
  String get listingReportPropertySheetTitle;

  /// No description provided for @listingReportPropertySheetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The listing is hidden from your home feed; the assigned marketer is notified for admin review.'**
  String get listingReportPropertySheetSubtitle;

  /// No description provided for @listingReportRequestSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Report request'**
  String get listingReportRequestSheetTitle;

  /// No description provided for @listingReportRequestSheetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The request is hidden from your home feed for admin review.'**
  String get listingReportRequestSheetSubtitle;

  /// No description provided for @listingReportPickAtLeastOneReason.
  ///
  /// In en, this message translates to:
  /// **'Pick at least one reason'**
  String get listingReportPickAtLeastOneReason;

  /// No description provided for @listingReportOtherDetailsRequired.
  ///
  /// In en, this message translates to:
  /// **'Please add details for «Other»'**
  String get listingReportOtherDetailsRequired;

  /// No description provided for @listingReportSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit report'**
  String get listingReportSubmit;

  /// No description provided for @listingReportDetailsLabel.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get listingReportDetailsLabel;

  /// No description provided for @listingReportDuplicateOpen.
  ///
  /// In en, this message translates to:
  /// **'You already have an open report on this listing. Withdraw it or wait for review before filing again.'**
  String get listingReportDuplicateOpen;

  /// No description provided for @listingReportReasonMisleading.
  ///
  /// In en, this message translates to:
  /// **'Misleading or inaccurate property information'**
  String get listingReportReasonMisleading;

  /// No description provided for @listingReportReasonDuplicateSpam.
  ///
  /// In en, this message translates to:
  /// **'Duplicate listing, spam, or scam-like content'**
  String get listingReportReasonDuplicateSpam;

  /// No description provided for @listingReportReasonWrongPrice.
  ///
  /// In en, this message translates to:
  /// **'Price or terms do not match reality'**
  String get listingReportReasonWrongPrice;

  /// No description provided for @listingReportReasonImpersonation.
  ///
  /// In en, this message translates to:
  /// **'Impersonation or unauthorized marketing entity'**
  String get listingReportReasonImpersonation;

  /// No description provided for @listingReportReasonLicenseMismatch.
  ///
  /// In en, this message translates to:
  /// **'REGA ad license mismatch or missing'**
  String get listingReportReasonLicenseMismatch;

  /// No description provided for @listingReportReasonHarassment.
  ///
  /// In en, this message translates to:
  /// **'Inappropriate behavior after contact'**
  String get listingReportReasonHarassment;

  /// No description provided for @listingReportReasonOther.
  ///
  /// In en, this message translates to:
  /// **'Other (add details)'**
  String get listingReportReasonOther;

  /// No description provided for @inAppNotifListingReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Report on your listing'**
  String get inAppNotifListingReportTitle;

  /// No description provided for @inAppNotifListingReportBody.
  ///
  /// In en, this message translates to:
  /// **'A user filed a report. The listing stays visible to others until admin review.'**
  String get inAppNotifListingReportBody;

  /// No description provided for @inAppNotifListingReportEscalatedTitle.
  ///
  /// In en, this message translates to:
  /// **'Urgent: multiple reports on your listing'**
  String get inAppNotifListingReportEscalatedTitle;

  /// No description provided for @inAppNotifListingReportEscalatedBody.
  ///
  /// In en, this message translates to:
  /// **'Multiple distinct users reported this listing. It is temporarily hidden from the home feed pending admin review.'**
  String get inAppNotifListingReportEscalatedBody;

  /// No description provided for @inAppNotifListingReportOwnerEscalatedTitle.
  ///
  /// In en, this message translates to:
  /// **'Notice: listing reports escalated'**
  String get inAppNotifListingReportOwnerEscalatedTitle;

  /// No description provided for @inAppNotifListingReportOwnerEscalatedBody.
  ///
  /// In en, this message translates to:
  /// **'Your listing is temporarily hidden from the home feed due to multiple distinct user reports. Admin review is in progress.'**
  String get inAppNotifListingReportOwnerEscalatedBody;

  /// No description provided for @dashboardToastListingHiddenFromHome.
  ///
  /// In en, this message translates to:
  /// **'Hidden from home — open «Hidden» to view.'**
  String get dashboardToastListingHiddenFromHome;

  /// No description provided for @dashboardToastListingShownOnHomeAgain.
  ///
  /// In en, this message translates to:
  /// **'Listing shows on home again.'**
  String get dashboardToastListingShownOnHomeAgain;

  /// No description provided for @dashboardToastListingReportWithdrawn.
  ///
  /// In en, this message translates to:
  /// **'Pending report withdrawn.'**
  String get dashboardToastListingReportWithdrawn;

  /// No description provided for @dashboardToastMarketRequestHiddenFromHome.
  ///
  /// In en, this message translates to:
  /// **'Request hidden from home.'**
  String get dashboardToastMarketRequestHiddenFromHome;

  /// No description provided for @dashboardToastMarketRequestShownOnHomeAgain.
  ///
  /// In en, this message translates to:
  /// **'Request shows on home again.'**
  String get dashboardToastMarketRequestShownOnHomeAgain;

  /// No description provided for @propertyDetailsReportWithdrawnSnack.
  ///
  /// In en, this message translates to:
  /// **'Pending report withdrawn.'**
  String get propertyDetailsReportWithdrawnSnack;

  /// No description provided for @propertyDetailsHiddenFromYourHomeSnack.
  ///
  /// In en, this message translates to:
  /// **'Hidden from your home feed.'**
  String get propertyDetailsHiddenFromYourHomeSnack;

  /// No description provided for @propertyDetailsShownOnHomeAgainSnack.
  ///
  /// In en, this message translates to:
  /// **'Shown on home again.'**
  String get propertyDetailsShownOnHomeAgainSnack;

  /// No description provided for @settingsReportsActivityTitle.
  ///
  /// In en, this message translates to:
  /// **'Reports (on this device)'**
  String get settingsReportsActivityTitle;

  /// No description provided for @settingsReportsActivitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Listing reports: {listingCount} · Requests: {requestCount} · Events last 30 days: {events30}'**
  String settingsReportsActivitySubtitle(
      int listingCount, int requestCount, int events30);

  /// No description provided for @marketRequestUrgencyTitle.
  ///
  /// In en, this message translates to:
  /// **'Request urgency'**
  String get marketRequestUrgencyTitle;

  /// No description provided for @marketRequestUrgencyHint.
  ///
  /// In en, this message translates to:
  /// **'How time-sensitive is this request? Higher urgency is surfaced sooner on the home feed.'**
  String get marketRequestUrgencyHint;

  /// No description provided for @marketRequestPriorityFlexible.
  ///
  /// In en, this message translates to:
  /// **'Flexible timeline'**
  String get marketRequestPriorityFlexible;

  /// No description provided for @marketRequestPriorityStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get marketRequestPriorityStandard;

  /// No description provided for @marketRequestPriorityPriority.
  ///
  /// In en, this message translates to:
  /// **'High priority'**
  String get marketRequestPriorityPriority;

  /// No description provided for @marketRequestPriorityUrgent.
  ///
  /// In en, this message translates to:
  /// **'Urgent'**
  String get marketRequestPriorityUrgent;

  /// No description provided for @marketRequestPriorityImmediate.
  ///
  /// In en, this message translates to:
  /// **'Immediate'**
  String get marketRequestPriorityImmediate;

  /// No description provided for @inboxSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search notifications…'**
  String get inboxSearchHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
