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
  /// **'Mawthuq Line Real Estate App'**
  String get appTitle;

  /// No description provided for @welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get welcomeTitle;

  /// No description provided for @welcomeTrustedAqar.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Mawthuq Line Real Estate App'**
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
  /// **'Saved with this account on this device. Not copied to another account after sign-out.'**
  String get settingsDarkModeSubtitle;

  /// No description provided for @settingsThemeModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Follows the device appearance (light/dark), including automatic mode by time or brightness.'**
  String get settingsThemeModeSubtitle;

  /// No description provided for @photographerCaptureWithCamera.
  ///
  /// In en, this message translates to:
  /// **'Capture with camera'**
  String get photographerCaptureWithCamera;

  /// No description provided for @photographerPickFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get photographerPickFromGallery;

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
  /// **'Terms & Conditions'**
  String get legalTermsCoachTitle;

  /// No description provided for @legalTermsCoachBody.
  ///
  /// In en, this message translates to:
  /// **'Review the Terms & Conditions via the link, then check the acknowledgment box to continue. This prompt will not appear again after you confirm.'**
  String get legalTermsCoachBody;

  /// No description provided for @legalTermsCoachOk.
  ///
  /// In en, this message translates to:
  /// **'Acknowledged — continue'**
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
  /// **'Welcome to Mawthuq Line Real Estate'**
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
  /// **'Enter ID / Iqama — 10 digits'**
  String get loginUsernameFieldHelper;

  /// No description provided for @loginIdentifierFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
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
  /// **'✅ Permit issuance'**
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
  /// **'Marketer offers'**
  String get ownerBtnRealEstateOffers;

  /// No description provided for @ownerHubTabWaitingMarketers.
  ///
  /// In en, this message translates to:
  /// **'Awaiting marketers'**
  String get ownerHubTabWaitingMarketers;

  /// No description provided for @ownerHubTabAwaitingApproval.
  ///
  /// In en, this message translates to:
  /// **'Awaiting owner approval'**
  String get ownerHubTabAwaitingApproval;

  /// No description provided for @ownerBtnApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get ownerBtnApprove;

  /// No description provided for @ownerBtnReject.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get ownerBtnReject;

  /// No description provided for @ownerDeclineReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Decline reason'**
  String get ownerDeclineReasonLabel;

  /// No description provided for @ownerDeclineReasonHint.
  ///
  /// In en, this message translates to:
  /// **'This reason is shown to the marketer after you decline.'**
  String get ownerDeclineReasonHint;

  /// No description provided for @ownerDeclineReasonRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a decline reason so the marketer can see it.'**
  String get ownerDeclineReasonRequired;

  /// No description provided for @ownerOfferDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Marketer offer details'**
  String get ownerOfferDetailsTitle;

  /// No description provided for @ownerOfferNoExtraDetails.
  ///
  /// In en, this message translates to:
  /// **'The marketer did not fill extra offer details.'**
  String get ownerOfferNoExtraDetails;

  /// No description provided for @marketerBtnSendOffer.
  ///
  /// In en, this message translates to:
  /// **'Send offer'**
  String get marketerBtnSendOffer;

  /// No description provided for @marketerBtnSubmitOffer.
  ///
  /// In en, this message translates to:
  /// **'Submit offer'**
  String get marketerBtnSubmitOffer;

  /// No description provided for @marketerBtnTrack.
  ///
  /// In en, this message translates to:
  /// **'Track'**
  String get marketerBtnTrack;

  /// No description provided for @marketerBtnIssuePermit.
  ///
  /// In en, this message translates to:
  /// **'Issue permit'**
  String get marketerBtnIssuePermit;

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
  /// **'Notifications, chats, and ads'**
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

  /// No description provided for @communicationHubCampaignsTab.
  ///
  /// In en, this message translates to:
  /// **'Ads & campaigns'**
  String get communicationHubCampaignsTab;

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
  /// **'In-app complaint'**
  String get supportHubAdminTab;

  /// No description provided for @supportHubTicketsTab.
  ///
  /// In en, this message translates to:
  /// **'Tickets'**
  String get supportHubTicketsTab;

  /// No description provided for @supportHubComplaintTab.
  ///
  /// In en, this message translates to:
  /// **'In-app complaint'**
  String get supportHubComplaintTab;

  /// No description provided for @supportHubNeedLogin.
  ///
  /// In en, this message translates to:
  /// **'Log in to access support'**
  String get supportHubNeedLogin;

  /// No description provided for @settingsSupportMovedHint.
  ///
  /// In en, this message translates to:
  /// **'Technical support is on the bottom bar or here. X returns you to the screen you came from without signing you out.'**
  String get settingsSupportMovedHint;

  /// No description provided for @supportCenterTitle.
  ///
  /// In en, this message translates to:
  /// **'Support center'**
  String get supportCenterTitle;

  /// No description provided for @supportCenterIntro.
  ///
  /// In en, this message translates to:
  /// **'Support helps with the app, your account, listings, requests, payments, and subscriptions. Describe what happened clearly, and attach a screenshot if you have one so we can resolve it faster.'**
  String get supportCenterIntro;

  /// No description provided for @supportEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get supportEmailLabel;

  /// No description provided for @supportPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get supportPhoneLabel;

  /// No description provided for @supportCopyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get supportCopyTooltip;

  /// No description provided for @supportWhatsAppTooltip.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp message'**
  String get supportWhatsAppTooltip;

  /// No description provided for @supportEmailCopied.
  ///
  /// In en, this message translates to:
  /// **'Email copied — paste it in your mail app if it did not open.'**
  String get supportEmailCopied;

  /// No description provided for @supportPhoneCopied.
  ///
  /// In en, this message translates to:
  /// **'Support number copied.'**
  String get supportPhoneCopied;

  /// No description provided for @supportHoursLabel.
  ///
  /// In en, this message translates to:
  /// **'Response hours'**
  String get supportHoursLabel;

  /// No description provided for @supportHoursValue.
  ///
  /// In en, this message translates to:
  /// **'Business days — 9 AM to 5 PM (KSA)'**
  String get supportHoursValue;

  /// No description provided for @supportComplaintFormTitle.
  ///
  /// In en, this message translates to:
  /// **'Submit a complaint / suggestion'**
  String get supportComplaintFormTitle;

  /// No description provided for @supportComplaintFormHint.
  ///
  /// In en, this message translates to:
  /// **'Choose the type, write the subject and details, and attach a photo or file if needed. Choosing the type will not close this screen.'**
  String get supportComplaintFormHint;

  /// No description provided for @supportAttachmentsLabel.
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get supportAttachmentsLabel;

  /// No description provided for @supportAttachmentsHint.
  ///
  /// In en, this message translates to:
  /// **'Optional. From files, gallery, or camera depending on your device.'**
  String get supportAttachmentsHint;

  /// No description provided for @supportAttachFile.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get supportAttachFile;

  /// No description provided for @supportAttachGallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get supportAttachGallery;

  /// No description provided for @supportAttachCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get supportAttachCamera;

  /// No description provided for @supportAttachRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get supportAttachRemove;

  /// No description provided for @supportAttachFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not attach the file.'**
  String get supportAttachFailed;

  /// No description provided for @supportSubmitterNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get supportSubmitterNameLabel;

  /// No description provided for @supportSubmitterPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Mobile'**
  String get supportSubmitterPhoneLabel;

  /// No description provided for @supportTicketRefLabel.
  ///
  /// In en, this message translates to:
  /// **'Ticket reference'**
  String get supportTicketRefLabel;

  /// No description provided for @supportTicketConversationSection.
  ///
  /// In en, this message translates to:
  /// **'Conversation'**
  String get supportTicketConversationSection;

  /// No description provided for @supportTicketWelcomeRow.
  ///
  /// In en, this message translates to:
  /// **'Support greeting'**
  String get supportTicketWelcomeRow;

  /// No description provided for @supportTicketMessageAt.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get supportTicketMessageAt;

  /// No description provided for @supportTicketMessageFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get supportTicketMessageFrom;

  /// No description provided for @supportTicketMessageBody.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get supportTicketMessageBody;

  /// No description provided for @supportTicketReplyBy.
  ///
  /// In en, this message translates to:
  /// **'Replied by'**
  String get supportTicketReplyBy;

  /// No description provided for @supportTicketReplyAt.
  ///
  /// In en, this message translates to:
  /// **'Reply time'**
  String get supportTicketReplyAt;

  /// No description provided for @supportTicketReceivedBy.
  ///
  /// In en, this message translates to:
  /// **'Received by'**
  String get supportTicketReceivedBy;

  /// No description provided for @supportTicketReceivedAt.
  ///
  /// In en, this message translates to:
  /// **'Received at'**
  String get supportTicketReceivedAt;

  /// No description provided for @supportTicketEscalateRemaining.
  ///
  /// In en, this message translates to:
  /// **'Escalation available in'**
  String get supportTicketEscalateRemaining;

  /// No description provided for @supportTicketEscalateAvailableAt.
  ///
  /// In en, this message translates to:
  /// **'Escalation available at'**
  String get supportTicketEscalateAvailableAt;

  /// No description provided for @supportTicketCopySnapshot.
  ///
  /// In en, this message translates to:
  /// **'Copy ticket summary'**
  String get supportTicketCopySnapshot;

  /// No description provided for @supportTicketCopied.
  ///
  /// In en, this message translates to:
  /// **'Ticket summary copied.'**
  String get supportTicketCopied;

  /// No description provided for @supportTicketOpenAttachment.
  ///
  /// In en, this message translates to:
  /// **'Open attachment'**
  String get supportTicketOpenAttachment;

  /// No description provided for @supportTicketDownloadAttachment.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get supportTicketDownloadAttachment;

  /// No description provided for @supportTicketNoConversation.
  ///
  /// In en, this message translates to:
  /// **'No messages yet.'**
  String get supportTicketNoConversation;

  /// No description provided for @supportTicketInternalHidden.
  ///
  /// In en, this message translates to:
  /// **'Internal support draft — hidden from the user.'**
  String get supportTicketInternalHidden;

  /// No description provided for @supportSlaCountdownHours.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String supportSlaCountdownHours(int hours, int minutes);

  /// No description provided for @supportComplaintKindLabel.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get supportComplaintKindLabel;

  /// No description provided for @supportComplaintKindComplaint.
  ///
  /// In en, this message translates to:
  /// **'Complaint'**
  String get supportComplaintKindComplaint;

  /// No description provided for @supportComplaintKindSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Suggestion'**
  String get supportComplaintKindSuggestion;

  /// No description provided for @supportComplaintSubjectLabel.
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get supportComplaintSubjectLabel;

  /// No description provided for @supportComplaintDetailsLabel.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get supportComplaintDetailsLabel;

  /// No description provided for @supportComplaintSubjectHint.
  ///
  /// In en, this message translates to:
  /// **'A clear subject, one or more lines'**
  String get supportComplaintSubjectHint;

  /// No description provided for @supportComplaintDetailsHint.
  ///
  /// In en, this message translates to:
  /// **'Describe the issue or suggestion in detail'**
  String get supportComplaintDetailsHint;

  /// No description provided for @supportComplaintChannelLabel.
  ///
  /// In en, this message translates to:
  /// **'Contact method'**
  String get supportComplaintChannelLabel;

  /// No description provided for @supportComplaintChannelWhatsApp.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp'**
  String get supportComplaintChannelWhatsApp;

  /// No description provided for @supportComplaintChannelInApp.
  ///
  /// In en, this message translates to:
  /// **'In-app'**
  String get supportComplaintChannelInApp;

  /// No description provided for @supportComplaintWhatsAppHint.
  ///
  /// In en, this message translates to:
  /// **'The request is saved in the system and WhatsApp opens with support numbers — tap Send in each chat.'**
  String get supportComplaintWhatsAppHint;

  /// No description provided for @supportComplaintSendWhatsApp.
  ///
  /// In en, this message translates to:
  /// **'Send via WhatsApp'**
  String get supportComplaintSendWhatsApp;

  /// No description provided for @supportComplaintSendInApp.
  ///
  /// In en, this message translates to:
  /// **'Send in-app'**
  String get supportComplaintSendInApp;

  /// No description provided for @supportComplaintSubmitFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not submit — try again later.'**
  String get supportComplaintSubmitFailed;

  /// No description provided for @supportComplaintSubmitOk.
  ///
  /// In en, this message translates to:
  /// **'Your request was sent — track it under Tickets.'**
  String get supportComplaintSubmitOk;

  /// No description provided for @supportTicketSubmittedAt.
  ///
  /// In en, this message translates to:
  /// **'Submitted'**
  String get supportTicketSubmittedAt;

  /// No description provided for @supportTicketStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get supportTicketStatusLabel;

  /// No description provided for @supportTicketStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get supportTicketStatusOpen;

  /// No description provided for @supportTicketStatusOpenUnresolved.
  ///
  /// In en, this message translates to:
  /// **'Open — unresolved'**
  String get supportTicketStatusOpenUnresolved;

  /// No description provided for @supportTicketStatusResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get supportTicketStatusResolved;

  /// No description provided for @supportTicketStatusEscalated.
  ///
  /// In en, this message translates to:
  /// **'Escalated'**
  String get supportTicketStatusEscalated;

  /// No description provided for @supportTicketEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tickets yet. Submit a complaint or suggestion from the In-app complaint tab.'**
  String get supportTicketEmpty;

  /// No description provided for @supportTicketReceiptSection.
  ///
  /// In en, this message translates to:
  /// **'Submitted ticket'**
  String get supportTicketReceiptSection;

  /// No description provided for @supportTicketReplySection.
  ///
  /// In en, this message translates to:
  /// **'Support reply'**
  String get supportTicketReplySection;

  /// No description provided for @supportTicketReplyEmpty.
  ///
  /// In en, this message translates to:
  /// **'Support has not replied yet. An automatic receipt is not an admin reply.'**
  String get supportTicketReplyEmpty;

  /// No description provided for @supportTicketAckSection.
  ///
  /// In en, this message translates to:
  /// **'Receipt confirmation'**
  String get supportTicketAckSection;

  /// No description provided for @supportTicketEscalationSection.
  ///
  /// In en, this message translates to:
  /// **'Escalation'**
  String get supportTicketEscalationSection;

  /// No description provided for @supportTicketEscalateCta.
  ///
  /// In en, this message translates to:
  /// **'Escalate'**
  String get supportTicketEscalateCta;

  /// No description provided for @supportTicketResolvedCta.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get supportTicketResolvedCta;

  /// No description provided for @supportTicketUnresolvedCta.
  ///
  /// In en, this message translates to:
  /// **'Not resolved'**
  String get supportTicketUnresolvedCta;

  /// No description provided for @supportTicketEscalateHint.
  ///
  /// In en, this message translates to:
  /// **'Escalation appears 24 hours after submission if the ticket is still unresolved.'**
  String get supportTicketEscalateHint;

  /// No description provided for @supportTicketEscalateReady.
  ///
  /// In en, this message translates to:
  /// **'The 24-hour window has passed and the ticket is still unresolved. You can escalate to administration.'**
  String get supportTicketEscalateReady;

  /// No description provided for @supportTicketUnresolvedLocked.
  ///
  /// In en, this message translates to:
  /// **'“Resolved” and “Not resolved” appear only after administration replies.'**
  String get supportTicketUnresolvedLocked;

  /// No description provided for @supportTicketUnresolvedOk.
  ///
  /// In en, this message translates to:
  /// **'Ticket remains open.'**
  String get supportTicketUnresolvedOk;

  /// No description provided for @supportTicketSlaHours.
  ///
  /// In en, this message translates to:
  /// **'Escalation window: 24 hours from submission.'**
  String get supportTicketSlaHours;

  /// No description provided for @supportTicketRateTitle.
  ///
  /// In en, this message translates to:
  /// **'Rate the resolution'**
  String get supportTicketRateTitle;

  /// No description provided for @supportTicketRateSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get supportTicketRateSkip;

  /// No description provided for @supportTicketRateSend.
  ///
  /// In en, this message translates to:
  /// **'Submit rating'**
  String get supportTicketRateSend;

  /// No description provided for @supportTicketRateNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes (optional)'**
  String get supportTicketRateNotes;

  /// No description provided for @supportTicketResolvedBy.
  ///
  /// In en, this message translates to:
  /// **'Resolved by: {name}'**
  String supportTicketResolvedBy(String name);

  /// No description provided for @supportTicketFollowWhatsApp.
  ///
  /// In en, this message translates to:
  /// **'Follow up on WhatsApp'**
  String get supportTicketFollowWhatsApp;

  /// No description provided for @supportTicketThreadTitle.
  ///
  /// In en, this message translates to:
  /// **'Conversation'**
  String get supportTicketThreadTitle;

  /// No description provided for @supportTicketYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get supportTicketYou;

  /// No description provided for @supportTicketStaff.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get supportTicketStaff;

  /// No description provided for @opsDeskTicketSubmittedAt.
  ///
  /// In en, this message translates to:
  /// **'Submitted at'**
  String get opsDeskTicketSubmittedAt;

  /// No description provided for @opsDeskTicketReplySection.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get opsDeskTicketReplySection;

  /// No description provided for @opsDeskTicketEscalationSection.
  ///
  /// In en, this message translates to:
  /// **'Escalation'**
  String get opsDeskTicketEscalationSection;

  /// No description provided for @opsDeskSlaOverdue.
  ///
  /// In en, this message translates to:
  /// **'Past the 24-hour window — awaiting reply or escalation'**
  String get opsDeskSlaOverdue;

  /// No description provided for @opsDeskSlaWaiting.
  ///
  /// In en, this message translates to:
  /// **'Within the 24-hour window'**
  String get opsDeskSlaWaiting;

  /// No description provided for @opsDeskTicketNoStaffReply.
  ///
  /// In en, this message translates to:
  /// **'No admin reply yet'**
  String get opsDeskTicketNoStaffReply;

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
  /// **'Deals you submitted'**
  String get cartMarketOffersSectionTitle;

  /// No description provided for @cartMarketOffersEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'When someone requests to complete a deal on your listing or request, it appears under Incoming offers.'**
  String get cartMarketOffersEmptyHint;

  /// No description provided for @cartTabIncoming.
  ///
  /// In en, this message translates to:
  /// **'Incoming offers'**
  String get cartTabIncoming;

  /// No description provided for @cartIncomingEmpty.
  ///
  /// In en, this message translates to:
  /// **'No complete-deal offers on your listings or requests yet.'**
  String get cartIncomingEmpty;

  /// No description provided for @cartIncomingSectionRequests.
  ///
  /// In en, this message translates to:
  /// **'On my requests'**
  String get cartIncomingSectionRequests;

  /// No description provided for @cartIncomingSectionListings.
  ///
  /// In en, this message translates to:
  /// **'On my listings'**
  String get cartIncomingSectionListings;

  /// No description provided for @dealFactsRequestedAt.
  ///
  /// In en, this message translates to:
  /// **'Request date & time'**
  String get dealFactsRequestedAt;

  /// No description provided for @dealFactsRemainingMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} minutes left to complete the deal'**
  String dealFactsRemainingMinutes(int minutes);

  /// No description provided for @dealFactsMinutesLeftShort.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String dealFactsMinutesLeftShort(int minutes);

  /// No description provided for @dealFactsAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get dealFactsAddress;

  /// No description provided for @dealFactsApplicantNote.
  ///
  /// In en, this message translates to:
  /// **'Application window details'**
  String get dealFactsApplicantNote;

  /// No description provided for @dealFactsOwnerApprovedAt.
  ///
  /// In en, this message translates to:
  /// **'Owner approval date & time'**
  String get dealFactsOwnerApprovedAt;

  /// No description provided for @dealFactsOwnerParty.
  ///
  /// In en, this message translates to:
  /// **'Listing owner'**
  String get dealFactsOwnerParty;

  /// No description provided for @dealFactsApplicantParty.
  ///
  /// In en, this message translates to:
  /// **'Complete-deal applicant'**
  String get dealFactsApplicantParty;

  /// No description provided for @dealFactsCopySummary.
  ///
  /// In en, this message translates to:
  /// **'Copy transparency summary'**
  String get dealFactsCopySummary;

  /// No description provided for @dealFactsSummaryCopied.
  ///
  /// In en, this message translates to:
  /// **'Transparency summary copied'**
  String get dealFactsSummaryCopied;

  /// No description provided for @dealFactsQueueRank.
  ///
  /// In en, this message translates to:
  /// **'Secret queue: {index} of {max}'**
  String dealFactsQueueRank(int index, int max);

  /// No description provided for @dealFactsSecretUntil72.
  ///
  /// In en, this message translates to:
  /// **'Applicant details are visible to you only. After 72 hours without completion, remaining waiters are re-activated and appear on Home.'**
  String get dealFactsSecretUntil72;

  /// No description provided for @dealIncomingSortOldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest'**
  String get dealIncomingSortOldest;

  /// No description provided for @dealIncomingSortNewest.
  ///
  /// In en, this message translates to:
  /// **'Newest'**
  String get dealIncomingSortNewest;

  /// No description provided for @dealIncomingFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get dealIncomingFilterAll;

  /// No description provided for @dealIncomingFilterWaiting.
  ///
  /// In en, this message translates to:
  /// **'Awaiting you'**
  String get dealIncomingFilterWaiting;

  /// No description provided for @dealIncomingFilterAccepted.
  ///
  /// In en, this message translates to:
  /// **'You accepted'**
  String get dealIncomingFilterAccepted;

  /// No description provided for @cartOutgoingEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'When you submit a complete-deal from Home it appears here.'**
  String get cartOutgoingEmptyHint;

  /// No description provided for @cartApplicantCount.
  ///
  /// In en, this message translates to:
  /// **'{used} of {max}'**
  String cartApplicantCount(int used, int max);

  /// No description provided for @dealWaitingOwnerAccept.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the owner to approve this deal. Messaging appears after approval.'**
  String get dealWaitingOwnerAccept;

  /// No description provided for @dealOwnerAcceptPartner.
  ///
  /// In en, this message translates to:
  /// **'Accept to complete deal'**
  String get dealOwnerAcceptPartner;

  /// No description provided for @dealOwnerAcceptedPartner.
  ///
  /// In en, this message translates to:
  /// **'This partner was selected to complete the deal.'**
  String get dealOwnerAcceptedPartner;

  /// No description provided for @dealStayPendingUntilCancel.
  ///
  /// In en, this message translates to:
  /// **'Another partner was selected. This deal stays pending until you cancel it, or until the sale is completed — then it leaves My deals.'**
  String get dealStayPendingUntilCancel;

  /// No description provided for @dealCompleteWithPartner.
  ///
  /// In en, this message translates to:
  /// **'Complete deal'**
  String get dealCompleteWithPartner;

  /// No description provided for @dealEnterPromptTitle.
  ///
  /// In en, this message translates to:
  /// **'Has this deal been completed?'**
  String get dealEnterPromptTitle;

  /// No description provided for @dealEnterPromptBody.
  ///
  /// In en, this message translates to:
  /// **'The deal «{title}» was accepted. Completion happens outside the app. Confirm if it is finished, or keep it open.'**
  String dealEnterPromptBody(String title);

  /// No description provided for @dealEnterYesDone.
  ///
  /// In en, this message translates to:
  /// **'Yes, it is done'**
  String get dealEnterYesDone;

  /// No description provided for @dealEnterStillOpen.
  ///
  /// In en, this message translates to:
  /// **'Still in progress'**
  String get dealEnterStillOpen;

  /// No description provided for @dealCompleteNoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Completion details'**
  String get dealCompleteNoteTitle;

  /// No description provided for @dealCompleteNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Write a short note about how the deal was completed outside the app (meeting, payment, handover).'**
  String get dealCompleteNoteHint;

  /// No description provided for @dealCompleteNoteFieldHint.
  ///
  /// In en, this message translates to:
  /// **'Short details…'**
  String get dealCompleteNoteFieldHint;

  /// No description provided for @dealCompleteNoteRequired.
  ///
  /// In en, this message translates to:
  /// **'Add a short note before sending.'**
  String get dealCompleteNoteRequired;

  /// No description provided for @dealCompleteSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get dealCompleteSend;

  /// No description provided for @dealCompleteCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get dealCompleteCancel;

  /// No description provided for @dealSlotCapTitle.
  ///
  /// In en, this message translates to:
  /// **'My deals is full'**
  String get dealSlotCapTitle;

  /// No description provided for @dealSlotCapBody.
  ///
  /// In en, this message translates to:
  /// **'You have {used} of {max} active deal cards. Complete, cancel, or remove a deal before adding another.'**
  String dealSlotCapBody(int used, int max);

  /// No description provided for @dealSlotCapOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get dealSlotCapOk;

  /// No description provided for @inventorySlotCapTitle.
  ///
  /// In en, this message translates to:
  /// **'Listings and requests are full'**
  String get inventorySlotCapTitle;

  /// No description provided for @inventorySlotCapBody.
  ///
  /// In en, this message translates to:
  /// **'You have {used} of {max} active listing/request cards. Complete, cancel, or delete some before adding more.'**
  String inventorySlotCapBody(int used, int max);

  /// No description provided for @cartTabActive.
  ///
  /// In en, this message translates to:
  /// **'Open deals'**
  String get cartTabActive;

  /// No description provided for @cartTabCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get cartTabCompleted;

  /// No description provided for @cartActiveCount.
  ///
  /// In en, this message translates to:
  /// **'{used}/{max}'**
  String cartActiveCount(int used, int max);

  /// No description provided for @shortsCommentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get shortsCommentsTitle;

  /// No description provided for @shortsCommentHint.
  ///
  /// In en, this message translates to:
  /// **'Write a comment'**
  String get shortsCommentHint;

  /// No description provided for @shortsCommentEmpty.
  ///
  /// In en, this message translates to:
  /// **'No comments yet'**
  String get shortsCommentEmpty;

  /// No description provided for @shortsCommenterFallback.
  ///
  /// In en, this message translates to:
  /// **'Interested partner'**
  String get shortsCommenterFallback;

  /// No description provided for @shortsCommenterMyDeal.
  ///
  /// In en, this message translates to:
  /// **'My deal'**
  String get shortsCommenterMyDeal;

  /// No description provided for @marketPropertySubmitSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Sent to Home'**
  String get marketPropertySubmitSuccessTitle;

  /// No description provided for @marketPropertySubmitSuccessBody.
  ///
  /// In en, this message translates to:
  /// **'Your request is visible to interested parties on the market. Home refreshes instantly and opens on your new request. You can also track it under Requests/Listings.'**
  String get marketPropertySubmitSuccessBody;

  /// No description provided for @marketPropertySubmitGoHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get marketPropertySubmitGoHome;

  /// No description provided for @marketPropertySubmitAnother.
  ///
  /// In en, this message translates to:
  /// **'Another property request'**
  String get marketPropertySubmitAnother;

  /// No description provided for @listingPublishLiveSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Sent to Home'**
  String get listingPublishLiveSuccessTitle;

  /// No description provided for @listingPublishLiveSuccessBody.
  ///
  /// In en, this message translates to:
  /// **'Your listing is live, verified, and linked to official records. The listing number appears on the card, and Home refreshes instantly to open on it at the top.'**
  String get listingPublishLiveSuccessBody;

  /// No description provided for @listingPublishLiveStatusChip.
  ///
  /// In en, this message translates to:
  /// **'Live on Home'**
  String get listingPublishLiveStatusChip;

  /// No description provided for @listingPublishMarketingSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Marketing request sent'**
  String get listingPublishMarketingSuccessTitle;

  /// No description provided for @listingPublishMarketingSuccessBody.
  ///
  /// In en, this message translates to:
  /// **'Your request will be reviewed and assigned to a licensed marketer. It will not appear on Home until it is approved and linked to the official permit. Track it from Follow request.'**
  String get listingPublishMarketingSuccessBody;

  /// No description provided for @listingPublishMarketingStatusChip.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a marketer'**
  String get listingPublishMarketingStatusChip;

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
  /// **'Terms and privacy text could not be loaded from the server. By continuing you agree to use Mawthuq Line Real Estate Establishment in accordance with applicable laws in the Kingdom of Saudi Arabia, including personal data protection rules where they apply, to provide accurate information, and to use listings and messaging responsibly. For the full text, contact support or try again later.'**
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
  /// **'Enter ID / Iqama number (10 digits)'**
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
  /// **'FAL license number — for offices and real-estate entities'**
  String get settingsPublicMemberIdSubtitle;

  /// No description provided for @onboardingWelcomeTitleApp.
  ///
  /// In en, this message translates to:
  /// **'Mawthuq Line Real Estate App'**
  String get onboardingWelcomeTitleApp;

  /// No description provided for @onboardingWelcomeTitleWeb.
  ///
  /// In en, this message translates to:
  /// **'Mawthuq Line Real Estate Establishment'**
  String get onboardingWelcomeTitleWeb;

  /// No description provided for @onboardingWelcomeBodyApp.
  ///
  /// In en, this message translates to:
  /// **'We’re glad you’re here. Whether you work independently, run an office, a company, or an institution, our team is here to serve you and keep your experience smooth—your needs come first. Enjoy exploring.'**
  String get onboardingWelcomeBodyApp;

  /// No description provided for @onboardingWelcomeBodyWeb.
  ///
  /// In en, this message translates to:
  /// **'We’re glad you’re here on the Mawthuq Line Real Estate Establishment platform. Whether you work independently, run an office, a company, or an institution, our team is here to serve you and keep your experience smooth—your needs come first. Enjoy exploring.'**
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
  /// **'Help center, in-app complaint, and tickets with administration. It opens over every tab; close with X to go back. Open chats from the bell icon or from here.'**
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
  /// **'Primary buttons, navigation, and card/dialog/field frames. Backgrounds and text follow light/dark. This color stays with this account only.'**
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
  /// **'• Keep using this device: stay signed in here and sign out other open sessions.\n• Sign out here: close this device only; the other session stays signed in.'**
  String get securitySessionSupersededChooseHint;

  /// No description provided for @securitySessionFieldKind.
  ///
  /// In en, this message translates to:
  /// **'Sign-in type'**
  String get securitySessionFieldKind;

  /// No description provided for @securitySessionFieldMethod.
  ///
  /// In en, this message translates to:
  /// **'Sign-in method'**
  String get securitySessionFieldMethod;

  /// No description provided for @securitySessionFieldWhen.
  ///
  /// In en, this message translates to:
  /// **'Date and time'**
  String get securitySessionFieldWhen;

  /// No description provided for @securitySessionFieldWhere.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get securitySessionFieldWhere;

  /// No description provided for @securitySessionFieldDevice.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get securitySessionFieldDevice;

  /// No description provided for @securitySessionKindWebWindows.
  ///
  /// In en, this message translates to:
  /// **'Web — Windows browser'**
  String get securitySessionKindWebWindows;

  /// No description provided for @securitySessionKindWebMobile.
  ///
  /// In en, this message translates to:
  /// **'Web — mobile browser'**
  String get securitySessionKindWebMobile;

  /// No description provided for @securitySessionKindWebDesktop.
  ///
  /// In en, this message translates to:
  /// **'Web — desktop browser'**
  String get securitySessionKindWebDesktop;

  /// No description provided for @securitySessionKindApp.
  ///
  /// In en, this message translates to:
  /// **'Device app'**
  String get securitySessionKindApp;

  /// No description provided for @securitySessionMethodPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get securitySessionMethodPassword;

  /// No description provided for @securitySessionMethodPin.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get securitySessionMethodPin;

  /// No description provided for @securitySessionMethodBiometric.
  ///
  /// In en, this message translates to:
  /// **'Biometrics'**
  String get securitySessionMethodBiometric;

  /// No description provided for @securitySessionMethodOtp.
  ///
  /// In en, this message translates to:
  /// **'Verification code'**
  String get securitySessionMethodOtp;

  /// No description provided for @securitySessionMethodOther.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get securitySessionMethodOther;

  /// No description provided for @trackingOfferSentAt.
  ///
  /// In en, this message translates to:
  /// **'Offer sent date'**
  String get trackingOfferSentAt;

  /// No description provided for @trackingOfferSender.
  ///
  /// In en, this message translates to:
  /// **'Offer sender'**
  String get trackingOfferSender;

  /// No description provided for @trackingOfferSenderRole.
  ///
  /// In en, this message translates to:
  /// **'Sender role'**
  String get trackingOfferSenderRole;

  /// No description provided for @trackingOfferRoleOfficial.
  ///
  /// In en, this message translates to:
  /// **'Official registered name'**
  String get trackingOfferRoleOfficial;

  /// No description provided for @trackingOfferRoleDisplay.
  ///
  /// In en, this message translates to:
  /// **'Marketing display name'**
  String get trackingOfferRoleDisplay;

  /// No description provided for @trackingOfferDetails.
  ///
  /// In en, this message translates to:
  /// **'Offer details'**
  String get trackingOfferDetails;

  /// No description provided for @listingCreatedBy.
  ///
  /// In en, this message translates to:
  /// **'Listing created by'**
  String get listingCreatedBy;

  /// No description provided for @listingCreatedByOffice.
  ///
  /// In en, this message translates to:
  /// **'Listing created by real estate office'**
  String get listingCreatedByOffice;

  /// No description provided for @listingCreatedByCompany.
  ///
  /// In en, this message translates to:
  /// **'Listing created by real estate company'**
  String get listingCreatedByCompany;

  /// No description provided for @listingCreatedByInstitution.
  ///
  /// In en, this message translates to:
  /// **'Listing created by real estate establishment'**
  String get listingCreatedByInstitution;

  /// No description provided for @listingCreatedByMarketer.
  ///
  /// In en, this message translates to:
  /// **'Listing created by marketer'**
  String get listingCreatedByMarketer;

  /// No description provided for @listingCreatedByAdvertiser.
  ///
  /// In en, this message translates to:
  /// **'Listing created by advertiser'**
  String get listingCreatedByAdvertiser;

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
  /// **'Enter the 6-digit verification code. In development it arrives in-app (top banner), not by SMS.'**
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

  /// No description provided for @securityDeviceColBrowser.
  ///
  /// In en, this message translates to:
  /// **'Browser / device'**
  String get securityDeviceColBrowser;

  /// No description provided for @securityDeviceColPlatform.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get securityDeviceColPlatform;

  /// No description provided for @securityDeviceColLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get securityDeviceColLocation;

  /// No description provided for @securityDeviceColLastSignIn.
  ///
  /// In en, this message translates to:
  /// **'Last sign-in'**
  String get securityDeviceColLastSignIn;

  /// No description provided for @securityDeviceColRegistered.
  ///
  /// In en, this message translates to:
  /// **'Registered'**
  String get securityDeviceColRegistered;

  /// No description provided for @securityDeviceColStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get securityDeviceColStatus;

  /// No description provided for @securityDeviceStatusCurrent.
  ///
  /// In en, this message translates to:
  /// **'This device'**
  String get securityDeviceStatusCurrent;

  /// No description provided for @securityDeviceUnknownBrowser.
  ///
  /// In en, this message translates to:
  /// **'Unknown device'**
  String get securityDeviceUnknownBrowser;

  /// No description provided for @securityDeviceRemoveAction.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get securityDeviceRemoveAction;

  /// No description provided for @securityDeviceOtpSent.
  ///
  /// In en, this message translates to:
  /// **'Verification code sent'**
  String get securityDeviceOtpSent;

  /// No description provided for @securityDeviceOtpResendWait.
  ///
  /// In en, this message translates to:
  /// **'Wait for the timer before resending'**
  String get securityDeviceOtpResendWait;

  /// No description provided for @otpAttemptsRemaining.
  ///
  /// In en, this message translates to:
  /// **'Attempts left: {count}'**
  String otpAttemptsRemaining(int count);

  /// No description provided for @otpAttemptsThirdNotifyTitle.
  ///
  /// In en, this message translates to:
  /// **'Verification attempt notice'**
  String get otpAttemptsThirdNotifyTitle;

  /// No description provided for @otpAttemptsThirdNotifyBody.
  ///
  /// In en, this message translates to:
  /// **'You entered the code three times. Check remaining attempts or resend a new code.'**
  String get otpAttemptsThirdNotifyBody;

  /// No description provided for @otpAttemptsLocked.
  ///
  /// In en, this message translates to:
  /// **'The three attempts were used. Resend the code.'**
  String get otpAttemptsLocked;

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

  /// No description provided for @settingsSectionAccountHub.
  ///
  /// In en, this message translates to:
  /// **'Account & guided tour'**
  String get settingsSectionAccountHub;

  /// No description provided for @settingsReplayDashboardTourTitle.
  ///
  /// In en, this message translates to:
  /// **'Replay dashboard tour'**
  String get settingsReplayDashboardTourTitle;

  /// No description provided for @settingsReplayDashboardTourSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Walks main tabs again (Home → My page → …). Starts when you return to the dashboard.'**
  String get settingsReplayDashboardTourSubtitle;

  /// No description provided for @settingsReplayDashboardTourSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Tour will start when you go back to the dashboard.'**
  String get settingsReplayDashboardTourSnackbar;

  /// No description provided for @settingsOpenSwitchAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch account'**
  String get settingsOpenSwitchAccountTitle;

  /// No description provided for @settingsOpenSwitchAccountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick another profile you used on this device.'**
  String get settingsOpenSwitchAccountSubtitle;

  /// No description provided for @settingsOpenSessionHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Full session log'**
  String get settingsOpenSessionHistoryTitle;

  /// No description provided for @settingsOpenSessionHistorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open the detailed sign-in history screen.'**
  String get settingsOpenSessionHistorySubtitle;

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
  /// **'Unified national number (10 digits starting with 700) — offices, institutions, and companies'**
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

  /// No description provided for @listingReportReasonFraudFinancial.
  ///
  /// In en, this message translates to:
  /// **'Fraud, extortion, or illegal payment demands'**
  String get listingReportReasonFraudFinancial;

  /// No description provided for @listingReportReasonIllegalContent.
  ///
  /// In en, this message translates to:
  /// **'Illegal content or serious criminal activity'**
  String get listingReportReasonIllegalContent;

  /// No description provided for @listingReportReasonPrivacyViolation.
  ///
  /// In en, this message translates to:
  /// **'Privacy breach or misuse of personal data'**
  String get listingReportReasonPrivacyViolation;

  /// No description provided for @listingReportReasonOther.
  ///
  /// In en, this message translates to:
  /// **'Other (add details)'**
  String get listingReportReasonOther;

  /// No description provided for @listingReportLegalDetailsLabel.
  ///
  /// In en, this message translates to:
  /// **'Legal / factual explanation (required for this selection)'**
  String get listingReportLegalDetailsLabel;

  /// No description provided for @listingReportLegalDetailsRequired.
  ///
  /// In en, this message translates to:
  /// **'Add a clear explanation (at least 30 characters) for the selected reason.'**
  String get listingReportLegalDetailsRequired;

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

  /// No description provided for @registerTitle.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get registerTitle;

  /// No description provided for @registerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose account type, then complete registration.'**
  String get registerSubtitle;

  /// No description provided for @registerAccountTypeHeading.
  ///
  /// In en, this message translates to:
  /// **'Account type'**
  String get registerAccountTypeHeading;

  /// No description provided for @accountKindIndividual.
  ///
  /// In en, this message translates to:
  /// **'Individual user (browse)'**
  String get accountKindIndividual;

  /// No description provided for @accountKindOffice.
  ///
  /// In en, this message translates to:
  /// **'Real estate office (max 3 members)'**
  String get accountKindOffice;

  /// No description provided for @accountKindInstitution.
  ///
  /// In en, this message translates to:
  /// **'Real estate institution (max 6 members)'**
  String get accountKindInstitution;

  /// No description provided for @accountKindCompany.
  ///
  /// In en, this message translates to:
  /// **'Real estate company (max 12 members)'**
  String get accountKindCompany;

  /// No description provided for @registerContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue to registration'**
  String get registerContinue;

  /// No description provided for @accountKindIndependentAdvertiser.
  ///
  /// In en, this message translates to:
  /// **'Independent (individual advertiser)'**
  String get accountKindIndependentAdvertiser;

  /// No description provided for @accountKindMarketer.
  ///
  /// In en, this message translates to:
  /// **'Real estate marketer'**
  String get accountKindMarketer;

  /// No description provided for @registerOrgModeSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Organization setup'**
  String get registerOrgModeSectionTitle;

  /// No description provided for @registerOrgModeCreate.
  ///
  /// In en, this message translates to:
  /// **'Create a new organization (you will be the owner)'**
  String get registerOrgModeCreate;

  /// No description provided for @registerOrgModeJoin.
  ///
  /// In en, this message translates to:
  /// **'Join an existing organization'**
  String get registerOrgModeJoin;

  /// No description provided for @registerInviteCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Organization or invitation code (FAL)'**
  String get registerInviteCodeLabel;

  /// No description provided for @registerInviteCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the code shared by the owner'**
  String get registerInviteCodeHint;

  /// No description provided for @registerLookupOrg.
  ///
  /// In en, this message translates to:
  /// **'Look up organization'**
  String get registerLookupOrg;

  /// No description provided for @registerOrgPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm organization'**
  String get registerOrgPreviewTitle;

  /// No description provided for @registerOrgPreviewFal.
  ///
  /// In en, this message translates to:
  /// **'Display code: {code}'**
  String registerOrgPreviewFal(String code);

  /// No description provided for @registerInviteInvalid.
  ///
  /// In en, this message translates to:
  /// **'Code not found. Check with the owner and try again.'**
  String get registerInviteInvalid;

  /// No description provided for @registerInviteContinueRequiresPreview.
  ///
  /// In en, this message translates to:
  /// **'Look up the organization before continuing.'**
  String get registerInviteContinueRequiresPreview;

  /// No description provided for @registerSignupJoinPendingSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Account created. After you sign in, your join request is sent to the owner for approval.'**
  String get registerSignupJoinPendingSnackbar;

  /// No description provided for @registerPendingJoinIntro.
  ///
  /// In en, this message translates to:
  /// **'Join request submitted from account registration.'**
  String get registerPendingJoinIntro;

  /// No description provided for @registerJoinFlowHint.
  ///
  /// In en, this message translates to:
  /// **'After you complete signup and sign in, a join request is sent to the organization owner for approval.'**
  String get registerJoinFlowHint;

  /// No description provided for @orgBrowseTitle.
  ///
  /// In en, this message translates to:
  /// **'Organizations'**
  String get orgBrowseTitle;

  /// No description provided for @orgBrowseEmpty.
  ///
  /// In en, this message translates to:
  /// **'No organizations yet.'**
  String get orgBrowseEmpty;

  /// No description provided for @orgJoinSubmit.
  ///
  /// In en, this message translates to:
  /// **'Request to join'**
  String get orgJoinSubmit;

  /// No description provided for @orgJoinMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Optional message'**
  String get orgJoinMessageHint;

  /// No description provided for @orgProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Organization'**
  String get orgProfileTitle;

  /// No description provided for @orgMembersCount.
  ///
  /// In en, this message translates to:
  /// **'{count} members'**
  String orgMembersCount(int count);

  /// No description provided for @orgFalBadge.
  ///
  /// In en, this message translates to:
  /// **'FAL {code}'**
  String orgFalBadge(String code);

  /// No description provided for @orgSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Organization created'**
  String get orgSetupTitle;

  /// No description provided for @orgSetupFalLine.
  ///
  /// In en, this message translates to:
  /// **'Public license: {code}'**
  String orgSetupFalLine(String code);

  /// No description provided for @orgSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Organization settings'**
  String get orgSettingsTitle;

  /// No description provided for @orgRenewFal.
  ///
  /// In en, this message translates to:
  /// **'Renew FAL display license'**
  String get orgRenewFal;

  /// No description provided for @orgBuySeats.
  ///
  /// In en, this message translates to:
  /// **'Purchase extra seats'**
  String get orgBuySeats;

  /// No description provided for @orgAssignPermissionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Member permissions'**
  String get orgAssignPermissionsTitle;

  /// No description provided for @permManageTeam.
  ///
  /// In en, this message translates to:
  /// **'Manage team'**
  String get permManageTeam;

  /// No description provided for @permAddProperties.
  ///
  /// In en, this message translates to:
  /// **'Add properties'**
  String get permAddProperties;

  /// No description provided for @permAddAds.
  ///
  /// In en, this message translates to:
  /// **'Add ads only'**
  String get permAddAds;

  /// No description provided for @permViewMarket.
  ///
  /// In en, this message translates to:
  /// **'Market access'**
  String get permViewMarket;

  /// No description provided for @permViewProfile.
  ///
  /// In en, this message translates to:
  /// **'My profile tab'**
  String get permViewProfile;

  /// No description provided for @permAccessChat.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get permAccessChat;

  /// No description provided for @permEditOrgSettings.
  ///
  /// In en, this message translates to:
  /// **'Organization settings'**
  String get permEditOrgSettings;

  /// No description provided for @permViewAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get permViewAnalytics;

  /// No description provided for @orgListingOrgTap.
  ///
  /// In en, this message translates to:
  /// **'Organization'**
  String get orgListingOrgTap;

  /// No description provided for @manageMembersTitle.
  ///
  /// In en, this message translates to:
  /// **'Member management'**
  String get manageMembersTitle;

  /// No description provided for @tabActiveMembers.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get tabActiveMembers;

  /// No description provided for @tabBanned.
  ///
  /// In en, this message translates to:
  /// **'Banned'**
  String get tabBanned;

  /// No description provided for @tabAlumni.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get tabAlumni;

  /// No description provided for @tabLeaveRequests.
  ///
  /// In en, this message translates to:
  /// **'Leave requests'**
  String get tabLeaveRequests;

  /// No description provided for @orgRejectReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Optional reason (shown to applicant)'**
  String get orgRejectReasonHint;

  /// No description provided for @deskTabTeamDashboard.
  ///
  /// In en, this message translates to:
  /// **'Team board'**
  String get deskTabTeamDashboard;

  /// No description provided for @deskTabTeamInventory.
  ///
  /// In en, this message translates to:
  /// **'Team listings & requests'**
  String get deskTabTeamInventory;

  /// No description provided for @deskTabTeamInventoryListings.
  ///
  /// In en, this message translates to:
  /// **'Listings'**
  String get deskTabTeamInventoryListings;

  /// No description provided for @deskTabTeamInventoryMarketingRequests.
  ///
  /// In en, this message translates to:
  /// **'Marketing requests'**
  String get deskTabTeamInventoryMarketingRequests;

  /// No description provided for @deskTabTeamInventoryMarketRequests.
  ///
  /// In en, this message translates to:
  /// **'Market requests'**
  String get deskTabTeamInventoryMarketRequests;

  /// No description provided for @deskTabTeamInventoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No listings or requests for this team yet.'**
  String get deskTabTeamInventoryEmpty;

  /// No description provided for @deskTabTeamInventoryLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load team items. Pull to refresh.'**
  String get deskTabTeamInventoryLoadError;

  /// No description provided for @deskTabTeamInventoryUntitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get deskTabTeamInventoryUntitled;

  /// No description provided for @ownerDeskManageListingsInMyPage.
  ///
  /// In en, this message translates to:
  /// **'Manage your listings and marketing from the «My page» tab in the bottom bar.'**
  String get ownerDeskManageListingsInMyPage;

  /// No description provided for @deskTabRolesPermissions.
  ///
  /// In en, this message translates to:
  /// **'Roles'**
  String get deskTabRolesPermissions;

  /// No description provided for @deskTabTeamAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get deskTabTeamAnalytics;

  /// No description provided for @deskTabReportsDesk.
  ///
  /// In en, this message translates to:
  /// **'Reports & export'**
  String get deskTabReportsDesk;

  /// No description provided for @deskTabAnalyticsReports.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get deskTabAnalyticsReports;

  /// No description provided for @appBarOrgJoinRequestsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Pending join requests'**
  String get appBarOrgJoinRequestsTooltip;

  /// No description provided for @orgTeamDeskTitle.
  ///
  /// In en, this message translates to:
  /// **'My organization'**
  String get orgTeamDeskTitle;

  /// No description provided for @orgStatActiveMembers.
  ///
  /// In en, this message translates to:
  /// **'Active members'**
  String get orgStatActiveMembers;

  /// No description provided for @orgStatPendingJoin.
  ///
  /// In en, this message translates to:
  /// **'Pending requests'**
  String get orgStatPendingJoin;

  /// No description provided for @orgStatOrgListings.
  ///
  /// In en, this message translates to:
  /// **'Team listings'**
  String get orgStatOrgListings;

  /// No description provided for @orgStatOrgAds.
  ///
  /// In en, this message translates to:
  /// **'Team ads'**
  String get orgStatOrgAds;

  /// No description provided for @orgLeaderboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Member leaderboard'**
  String get orgLeaderboardTitle;

  /// No description provided for @orgLeaderboardProps.
  ///
  /// In en, this message translates to:
  /// **'Listings'**
  String get orgLeaderboardProps;

  /// No description provided for @orgLeaderboardAds.
  ///
  /// In en, this message translates to:
  /// **'Ads'**
  String get orgLeaderboardAds;

  /// No description provided for @orgLeaderboardRank.
  ///
  /// In en, this message translates to:
  /// **'Rank'**
  String get orgLeaderboardRank;

  /// No description provided for @orgRolesPickMember.
  ///
  /// In en, this message translates to:
  /// **'Pick a teammate'**
  String get orgRolesPickMember;

  /// No description provided for @orgRolesEditPermissions.
  ///
  /// In en, this message translates to:
  /// **'Edit permissions'**
  String get orgRolesEditPermissions;

  /// No description provided for @orgExportReport.
  ///
  /// In en, this message translates to:
  /// **'Export report'**
  String get orgExportReport;

  /// No description provided for @orgExportCsv.
  ///
  /// In en, this message translates to:
  /// **'Share CSV summary'**
  String get orgExportCsv;

  /// No description provided for @orgAnalyticsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No analytics data yet.'**
  String get orgAnalyticsEmpty;

  /// No description provided for @organalyticsSoldRented.
  ///
  /// In en, this message translates to:
  /// **'Sold / rented (est.)'**
  String get organalyticsSoldRented;

  /// No description provided for @organalyticsScore.
  ///
  /// In en, this message translates to:
  /// **'Score'**
  String get organalyticsScore;

  /// No description provided for @permManageTeamHelp.
  ///
  /// In en, this message translates to:
  /// **'Approve or decline join requests, edit permissions, ban or remove members.'**
  String get permManageTeamHelp;

  /// No description provided for @permAddPropertiesHelp.
  ///
  /// In en, this message translates to:
  /// **'Create and publish new property listings on behalf of the organization.'**
  String get permAddPropertiesHelp;

  /// No description provided for @permAddAdsHelp.
  ///
  /// In en, this message translates to:
  /// **'Create side or promotional ads where your role allows.'**
  String get permAddAdsHelp;

  /// No description provided for @permViewMarketHelp.
  ///
  /// In en, this message translates to:
  /// **'Open the public real-estate market tab.'**
  String get permViewMarketHelp;

  /// No description provided for @permViewProfileHelp.
  ///
  /// In en, this message translates to:
  /// **'Access your personal profile tab inside the app.'**
  String get permViewProfileHelp;

  /// No description provided for @permAccessChatHelp.
  ///
  /// In en, this message translates to:
  /// **'Use internal team chat and direct team messages.'**
  String get permAccessChatHelp;

  /// No description provided for @permEditOrgSettingsHelp.
  ///
  /// In en, this message translates to:
  /// **'Edit organization branding, contacts, and desk settings.'**
  String get permEditOrgSettingsHelp;

  /// No description provided for @permViewAnalyticsHelp.
  ///
  /// In en, this message translates to:
  /// **'View team dashboards, charts, and exports.'**
  String get permViewAnalyticsHelp;

  /// No description provided for @permAddListingRequests.
  ///
  /// In en, this message translates to:
  /// **'Listing requests'**
  String get permAddListingRequests;

  /// No description provided for @permAddListingRequestsHelp.
  ///
  /// In en, this message translates to:
  /// **'Add buy/rent property requests that appear on the home feed.'**
  String get permAddListingRequestsHelp;

  /// No description provided for @permEditProperties.
  ///
  /// In en, this message translates to:
  /// **'Edit properties'**
  String get permEditProperties;

  /// No description provided for @permEditPropertiesHelp.
  ///
  /// In en, this message translates to:
  /// **'Edit or delete any property listing owned by your organization.'**
  String get permEditPropertiesHelp;

  /// No description provided for @permManageSubscription.
  ///
  /// In en, this message translates to:
  /// **'Manage subscription'**
  String get permManageSubscription;

  /// No description provided for @permManageSubscriptionHelp.
  ///
  /// In en, this message translates to:
  /// **'Purchase extra seats, renew the display license, and manage the plan.'**
  String get permManageSubscriptionHelp;

  /// No description provided for @permExportData.
  ///
  /// In en, this message translates to:
  /// **'Export data'**
  String get permExportData;

  /// No description provided for @permExportDataHelp.
  ///
  /// In en, this message translates to:
  /// **'Export team summaries to CSV or share reports from analytics.'**
  String get permExportDataHelp;

  /// No description provided for @permInviteMembers.
  ///
  /// In en, this message translates to:
  /// **'Invite members'**
  String get permInviteMembers;

  /// No description provided for @permInviteMembersHelp.
  ///
  /// In en, this message translates to:
  /// **'Show the invite / FAL code and renew it so teammates can join.'**
  String get permInviteMembersHelp;

  /// No description provided for @permManageChatRooms.
  ///
  /// In en, this message translates to:
  /// **'Manage chat rooms'**
  String get permManageChatRooms;

  /// No description provided for @permManageChatRoomsHelp.
  ///
  /// In en, this message translates to:
  /// **'Create private team chat rooms and assign moderators.'**
  String get permManageChatRoomsHelp;

  /// No description provided for @permViewMemberActivity.
  ///
  /// In en, this message translates to:
  /// **'Member activity'**
  String get permViewMemberActivity;

  /// No description provided for @permViewMemberActivityHelp.
  ///
  /// In en, this message translates to:
  /// **'View the activity log and recent actions by teammates.'**
  String get permViewMemberActivityHelp;

  /// No description provided for @deskTabMemberActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity log'**
  String get deskTabMemberActivity;

  /// No description provided for @orgMemberActivityEmpty.
  ///
  /// In en, this message translates to:
  /// **'No activity recorded yet for this organization.'**
  String get orgMemberActivityEmpty;

  /// No description provided for @orgMemberActivityUnknownAction.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get orgMemberActivityUnknownAction;

  /// No description provided for @orgMemberLastActivity.
  ///
  /// In en, this message translates to:
  /// **'Last activity'**
  String get orgMemberLastActivity;

  /// No description provided for @inviteMembersTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite teammates'**
  String get inviteMembersTitle;

  /// No description provided for @inviteMembersBody.
  ///
  /// In en, this message translates to:
  /// **'Share this code with people joining from registration. It is the same public FAL / invite code for your organization.'**
  String get inviteMembersBody;

  /// No description provided for @inviteMembersShare.
  ///
  /// In en, this message translates to:
  /// **'Share code'**
  String get inviteMembersShare;

  /// No description provided for @inviteMembersRenew.
  ///
  /// In en, this message translates to:
  /// **'Generate new invite code'**
  String get inviteMembersRenew;

  /// No description provided for @inviteMembersRenewHint.
  ///
  /// In en, this message translates to:
  /// **'Generating a new code invalidates the previous one for join-by-code flows.'**
  String get inviteMembersRenewHint;

  /// No description provided for @inviteMembersQrCaption.
  ///
  /// In en, this message translates to:
  /// **'Scan to copy the code on another device.'**
  String get inviteMembersQrCaption;

  /// No description provided for @inviteMembersShareHint.
  ///
  /// In en, this message translates to:
  /// **'Enter this code when choosing “Join an existing organization” in sign-up.'**
  String get inviteMembersShareHint;

  /// No description provided for @reportsDeskServerSyncHint.
  ///
  /// In en, this message translates to:
  /// **'Team and billing figures in these templates will fill automatically once server analytics queries are connected. Export, print, and share work today; full platform operations console will roll out later under project policy.'**
  String get reportsDeskServerSyncHint;

  /// No description provided for @subscriptionsMenuHub.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions & payments'**
  String get subscriptionsMenuHub;

  /// No description provided for @subscriptionsMenuCards.
  ///
  /// In en, this message translates to:
  /// **'My saved cards'**
  String get subscriptionsMenuCards;

  /// No description provided for @subscriptionsMenuHistory.
  ///
  /// In en, this message translates to:
  /// **'Payment history'**
  String get subscriptionsMenuHistory;

  /// No description provided for @subscriptionsMenuPlans.
  ///
  /// In en, this message translates to:
  /// **'Subscription plans'**
  String get subscriptionsMenuPlans;

  /// No description provided for @subscriptionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions & payments'**
  String get subscriptionsTitle;

  /// No description provided for @subscriptionsTabPlans.
  ///
  /// In en, this message translates to:
  /// **'Plans'**
  String get subscriptionsTabPlans;

  /// No description provided for @subscriptionsTabPaymentMethods.
  ///
  /// In en, this message translates to:
  /// **'Payment methods'**
  String get subscriptionsTabPaymentMethods;

  /// No description provided for @subscriptionsTabHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get subscriptionsTabHistory;

  /// No description provided for @subscriptionsTabTeam.
  ///
  /// In en, this message translates to:
  /// **'Team seats'**
  String get subscriptionsTabTeam;

  /// No description provided for @subscriptionsTabUsage.
  ///
  /// In en, this message translates to:
  /// **'Plan usage'**
  String get subscriptionsTabUsage;

  /// No description provided for @subscriptionsTabUpgrade.
  ///
  /// In en, this message translates to:
  /// **'Upgrade plan'**
  String get subscriptionsTabUpgrade;

  /// No description provided for @subscriptionsTabRenewFal.
  ///
  /// In en, this message translates to:
  /// **'Renew FAL license'**
  String get subscriptionsTabRenewFal;

  /// No description provided for @subscriptionsOrgManageTab.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get subscriptionsOrgManageTab;

  /// No description provided for @subscriptionsBadgeExpired.
  ///
  /// In en, this message translates to:
  /// **'Subscription expired or ending soon'**
  String get subscriptionsBadgeExpired;

  /// No description provided for @subscriptionsSar.
  ///
  /// In en, this message translates to:
  /// **'SAR'**
  String get subscriptionsSar;

  /// No description provided for @subscriptionsMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get subscriptionsMonthly;

  /// No description provided for @subscriptionsYearly.
  ///
  /// In en, this message translates to:
  /// **'Yearly (20% off)'**
  String get subscriptionsYearly;

  /// No description provided for @subscriptionsSubscribeNow.
  ///
  /// In en, this message translates to:
  /// **'Subscribe now'**
  String get subscriptionsSubscribeNow;

  /// No description provided for @subscriptionsCurrentPlan.
  ///
  /// In en, this message translates to:
  /// **'Current plan'**
  String get subscriptionsCurrentPlan;

  /// No description provided for @subscriptionsRenewsOn.
  ///
  /// In en, this message translates to:
  /// **'Renews on {date}'**
  String subscriptionsRenewsOn(String date);

  /// No description provided for @subscriptionsExpiredOn.
  ///
  /// In en, this message translates to:
  /// **'Ended on {date}'**
  String subscriptionsExpiredOn(String date);

  /// No description provided for @subscriptionsRenew.
  ///
  /// In en, this message translates to:
  /// **'Renew'**
  String get subscriptionsRenew;

  /// No description provided for @subscriptionsCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel subscription'**
  String get subscriptionsCancel;

  /// No description provided for @subscriptionsUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get subscriptionsUnlimited;

  /// No description provided for @subscriptionsMembers.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get subscriptionsMembers;

  /// No description provided for @subscriptionsProperties.
  ///
  /// In en, this message translates to:
  /// **'Properties'**
  String get subscriptionsProperties;

  /// No description provided for @subscriptionsAdsPerMonth.
  ///
  /// In en, this message translates to:
  /// **'Ads / month'**
  String get subscriptionsAdsPerMonth;

  /// No description provided for @subscriptionsListingRequests.
  ///
  /// In en, this message translates to:
  /// **'Listing requests'**
  String get subscriptionsListingRequests;

  /// No description provided for @subscriptionsFalIncluded.
  ///
  /// In en, this message translates to:
  /// **'FAL license included'**
  String get subscriptionsFalIncluded;

  /// No description provided for @subscriptionsSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get subscriptionsSupport;

  /// No description provided for @subscriptionsAddCard.
  ///
  /// In en, this message translates to:
  /// **'Add payment card'**
  String get subscriptionsAddCard;

  /// No description provided for @subscriptionsCardSaved.
  ///
  /// In en, this message translates to:
  /// **'Card saved'**
  String get subscriptionsCardSaved;

  /// No description provided for @subscriptionsCardDeleted.
  ///
  /// In en, this message translates to:
  /// **'Card removed'**
  String get subscriptionsCardDeleted;

  /// No description provided for @subscriptionsDefaultCard.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get subscriptionsDefaultCard;

  /// No description provided for @subscriptionsSetDefault.
  ///
  /// In en, this message translates to:
  /// **'Set default'**
  String get subscriptionsSetDefault;

  /// No description provided for @subscriptionsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get subscriptionsDelete;

  /// No description provided for @subscriptionsAddCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Add payment card'**
  String get subscriptionsAddCardTitle;

  /// No description provided for @subscriptionsCardNumber.
  ///
  /// In en, this message translates to:
  /// **'Card number'**
  String get subscriptionsCardNumber;

  /// No description provided for @subscriptionsCardHolder.
  ///
  /// In en, this message translates to:
  /// **'Cardholder name'**
  String get subscriptionsCardHolder;

  /// No description provided for @subscriptionsExpiry.
  ///
  /// In en, this message translates to:
  /// **'Expiry (MM/YY or MM/YYYY)'**
  String get subscriptionsExpiry;

  /// No description provided for @subscriptionsCapsLockOn.
  ///
  /// In en, this message translates to:
  /// **'Caps Lock is on — card fields usually expect Latin letters.'**
  String get subscriptionsCapsLockOn;

  /// No description provided for @subscriptionsCardHolderLatinTitle.
  ///
  /// In en, this message translates to:
  /// **'Latin characters only'**
  String get subscriptionsCardHolderLatinTitle;

  /// No description provided for @subscriptionsCardHolderLatinBody.
  ///
  /// In en, this message translates to:
  /// **'Enter the cardholder name in English letters (as printed on the card). Arabic or Persian letters are not accepted for this field.'**
  String get subscriptionsCardHolderLatinBody;

  /// No description provided for @subscriptionsCardHolderLatinOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get subscriptionsCardHolderLatinOk;

  /// No description provided for @subscriptionsMoyasarCardFieldHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the cardholder name in Latin capital letters and Western digits (0–9) exactly as printed on the card.'**
  String get subscriptionsMoyasarCardFieldHint;

  /// No description provided for @subscriptionsCvv.
  ///
  /// In en, this message translates to:
  /// **'CVV'**
  String get subscriptionsCvv;

  /// No description provided for @subscriptionsCardLabel.
  ///
  /// In en, this message translates to:
  /// **'Card label (optional)'**
  String get subscriptionsCardLabel;

  /// No description provided for @subscriptionsSaveCard.
  ///
  /// In en, this message translates to:
  /// **'Save card'**
  String get subscriptionsSaveCard;

  /// No description provided for @subscriptionsFieldRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get subscriptionsFieldRequired;

  /// No description provided for @subscriptionsCheckoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Checkout summary'**
  String get subscriptionsCheckoutTitle;

  /// No description provided for @subscriptionsLegalNote.
  ///
  /// In en, this message translates to:
  /// **'Activating this subscription grants you full and unlimited access to all premium features within the platform throughout the subscription period.'**
  String get subscriptionsLegalNote;

  /// No description provided for @subscriptionsCreditMadaTitle.
  ///
  /// In en, this message translates to:
  /// **'Credit / mada card'**
  String get subscriptionsCreditMadaTitle;

  /// No description provided for @paymentGatewayUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Payments are unavailable right now. Try again later or contact support.'**
  String get paymentGatewayUnavailable;

  /// No description provided for @subscriptionsPay.
  ///
  /// In en, this message translates to:
  /// **'Complete payment'**
  String get subscriptionsPay;

  /// No description provided for @subscriptionsPlanLine.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get subscriptionsPlanLine;

  /// No description provided for @subscriptionsPeriodLine.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get subscriptionsPeriodLine;

  /// No description provided for @subscriptionsOriginalLine.
  ///
  /// In en, this message translates to:
  /// **'Original price'**
  String get subscriptionsOriginalLine;

  /// No description provided for @subscriptionsDiscountLine.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get subscriptionsDiscountLine;

  /// No description provided for @subscriptionsTotalLine.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get subscriptionsTotalLine;

  /// No description provided for @subscriptionsPaymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get subscriptionsPaymentMethod;

  /// No description provided for @subscriptionsPaySavedCard.
  ///
  /// In en, this message translates to:
  /// **'Saved card'**
  String get subscriptionsPaySavedCard;

  /// No description provided for @subscriptionsPayNewCard.
  ///
  /// In en, this message translates to:
  /// **'Credit / mada card'**
  String get subscriptionsPayNewCard;

  /// No description provided for @subscriptionsApplePay.
  ///
  /// In en, this message translates to:
  /// **'Apple Pay'**
  String get subscriptionsApplePay;

  /// No description provided for @subscriptionsMadaPay.
  ///
  /// In en, this message translates to:
  /// **'Mada Pay'**
  String get subscriptionsMadaPay;

  /// No description provided for @subscriptionsPaymentSuccess.
  ///
  /// In en, this message translates to:
  /// **'Payment successful'**
  String get subscriptionsPaymentSuccess;

  /// No description provided for @subscriptionsPaymentFailed.
  ///
  /// In en, this message translates to:
  /// **'Payment failed'**
  String get subscriptionsPaymentFailed;

  /// No description provided for @subscriptionsDownloadInvoice.
  ///
  /// In en, this message translates to:
  /// **'Download invoice'**
  String get subscriptionsDownloadInvoice;

  /// No description provided for @subscriptionsInvoiceSaved.
  ///
  /// In en, this message translates to:
  /// **'Invoice saved'**
  String get subscriptionsInvoiceSaved;

  /// No description provided for @subscriptionsFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get subscriptionsFilterAll;

  /// No description provided for @subscriptionsFilterSuccess.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get subscriptionsFilterSuccess;

  /// No description provided for @subscriptionsFilterPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get subscriptionsFilterPending;

  /// No description provided for @subscriptionsFilterFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get subscriptionsFilterFailed;

  /// No description provided for @subscriptionsSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get subscriptionsSearch;

  /// No description provided for @subscriptionsTxnRef.
  ///
  /// In en, this message translates to:
  /// **'Transaction ref'**
  String get subscriptionsTxnRef;

  /// No description provided for @subscriptionsStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get subscriptionsStatus;

  /// No description provided for @subscriptionsTeamTitle.
  ///
  /// In en, this message translates to:
  /// **'Team & seats'**
  String get subscriptionsTeamTitle;

  /// No description provided for @subscriptionsSeatsUsed.
  ///
  /// In en, this message translates to:
  /// **'Seats used'**
  String get subscriptionsSeatsUsed;

  /// No description provided for @subscriptionsAddMember.
  ///
  /// In en, this message translates to:
  /// **'Add teammate'**
  String get subscriptionsAddMember;

  /// No description provided for @subscriptionsUpgradeHint.
  ///
  /// In en, this message translates to:
  /// **'You reached the seat limit — upgrade your plan.'**
  String get subscriptionsUpgradeHint;

  /// No description provided for @subscriptionsUpgradeCta.
  ///
  /// In en, this message translates to:
  /// **'Upgrade plan'**
  String get subscriptionsUpgradeCta;

  /// No description provided for @subscriptionsUsageTitle.
  ///
  /// In en, this message translates to:
  /// **'Usage'**
  String get subscriptionsUsageTitle;

  /// No description provided for @subscriptionsRenewFalBody.
  ///
  /// In en, this message translates to:
  /// **'FAL display renewal is linked to your active subscription. Open organization settings to renew the public license code.'**
  String get subscriptionsRenewFalBody;

  /// No description provided for @subscriptionsOpenOrgSettings.
  ///
  /// In en, this message translates to:
  /// **'Open organization settings'**
  String get subscriptionsOpenOrgSettings;

  /// No description provided for @subscriptionsDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Current subscription'**
  String get subscriptionsDetailsTitle;

  /// No description provided for @subscriptionsNoSubscription.
  ///
  /// In en, this message translates to:
  /// **'No active subscription'**
  String get subscriptionsNoSubscription;

  /// No description provided for @subscriptionsOrgSubscriptionExpired.
  ///
  /// In en, this message translates to:
  /// **'Organization subscription is inactive. Renew to keep FAL renewal and desk features.'**
  String get subscriptionsOrgSubscriptionExpired;

  /// No description provided for @subscriptionsAuthenticateToPay.
  ///
  /// In en, this message translates to:
  /// **'Confirm with biometrics'**
  String get subscriptionsAuthenticateToPay;

  /// No description provided for @subscriptionsBiometricFailed.
  ///
  /// In en, this message translates to:
  /// **'Biometric authentication failed or cancelled'**
  String get subscriptionsBiometricFailed;

  /// No description provided for @subscriptionsYearlyDiscountNote.
  ///
  /// In en, this message translates to:
  /// **'Yearly billing includes a 20% discount vs monthly.'**
  String get subscriptionsYearlyDiscountNote;

  /// No description provided for @subscriptionsExtraSeats.
  ///
  /// In en, this message translates to:
  /// **'Buy extra seats'**
  String get subscriptionsExtraSeats;

  /// No description provided for @subscriptionsSharePaymentLink.
  ///
  /// In en, this message translates to:
  /// **'Share payment summary'**
  String get subscriptionsSharePaymentLink;

  /// No description provided for @subscriptionsSharePaymentSubject.
  ///
  /// In en, this message translates to:
  /// **'Subscription payment'**
  String get subscriptionsSharePaymentSubject;

  /// No description provided for @subscriptionsCheckoutRefundPolicy.
  ///
  /// In en, this message translates to:
  /// **'By paying, you confirm that the subscription activates for the selected plan and billing period. Subscription fees are not refundable once charged.'**
  String get subscriptionsCheckoutRefundPolicy;

  /// No description provided for @subscriptionsMarketingPaywallTitle.
  ///
  /// In en, this message translates to:
  /// **'Subscription required'**
  String get subscriptionsMarketingPaywallTitle;

  /// No description provided for @subscriptionsMarketingPaywallBody.
  ///
  /// In en, this message translates to:
  /// **'Marketing actions that affect contracts, permits, publishing, or listings require an active subscription. Open plans to subscribe, then you can continue immediately.'**
  String get subscriptionsMarketingPaywallBody;

  /// No description provided for @subscriptionsPaywallExpiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Subscription inactive'**
  String get subscriptionsPaywallExpiredTitle;

  /// No description provided for @subscriptionsPaywallNoAutoRenewBody.
  ///
  /// In en, this message translates to:
  /// **'Your paid subscription period has ended (by date and time). This action is blocked until you subscribe again. Your data remains; you can keep working within free-tier limits after closing this dialog.'**
  String get subscriptionsPaywallNoAutoRenewBody;

  /// No description provided for @subscriptionsPaywallAutoRenewFailBody.
  ///
  /// In en, this message translates to:
  /// **'Automatic renewal could not charge your card (declined or insufficient funds). This action stays blocked until payment succeeds or you renew manually. Update your card or open plans to pay.'**
  String get subscriptionsPaywallAutoRenewFailBody;

  /// No description provided for @subscriptionsPaywallCloseLabel.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get subscriptionsPaywallCloseLabel;

  /// No description provided for @subscriptionsPaywallGoPlans.
  ///
  /// In en, this message translates to:
  /// **'Plans & pay'**
  String get subscriptionsPaywallGoPlans;

  /// No description provided for @subscriptionsCancelEndTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel subscription'**
  String get subscriptionsCancelEndTitle;

  /// No description provided for @subscriptionsCancelEndBody.
  ///
  /// In en, this message translates to:
  /// **'If you cancel, auto-renewal stops. Your benefits stay active until the end of the paid period ({date}).'**
  String subscriptionsCancelEndBody(String date);

  /// No description provided for @subscriptionsContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get subscriptionsContinue;

  /// No description provided for @subscriptionsGoBack.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get subscriptionsGoBack;

  /// No description provided for @subscriptionsRetentionTitle.
  ///
  /// In en, this message translates to:
  /// **'One-time loyalty offer'**
  String get subscriptionsRetentionTitle;

  /// No description provided for @subscriptionsRetentionBody.
  ///
  /// In en, this message translates to:
  /// **'Stay with us: get 20% off your next renewal if you keep your subscription now. This offer is shown only once.'**
  String get subscriptionsRetentionBody;

  /// No description provided for @subscriptionsRetentionStay.
  ///
  /// In en, this message translates to:
  /// **'Keep subscription'**
  String get subscriptionsRetentionStay;

  /// No description provided for @subscriptionsRetentionDecline.
  ///
  /// In en, this message translates to:
  /// **'Continue cancellation'**
  String get subscriptionsRetentionDecline;

  /// No description provided for @subscriptionsChurnTitle.
  ///
  /// In en, this message translates to:
  /// **'Help us improve'**
  String get subscriptionsChurnTitle;

  /// No description provided for @subscriptionsChurnBody.
  ///
  /// In en, this message translates to:
  /// **'What is the main reason you are cancelling? (optional)'**
  String get subscriptionsChurnBody;

  /// No description provided for @subscriptionsChurnSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get subscriptionsChurnSkip;

  /// No description provided for @subscriptionsChurnSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit & cancel'**
  String get subscriptionsChurnSubmit;

  /// No description provided for @subscriptionsChurnReasonPrice.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get subscriptionsChurnReasonPrice;

  /// No description provided for @subscriptionsChurnReasonFeatures.
  ///
  /// In en, this message translates to:
  /// **'Features / limits'**
  String get subscriptionsChurnReasonFeatures;

  /// No description provided for @subscriptionsChurnReasonSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get subscriptionsChurnReasonSupport;

  /// No description provided for @subscriptionsChurnReasonOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get subscriptionsChurnReasonOther;

  /// No description provided for @subscriptionsChurnDetailHint.
  ///
  /// In en, this message translates to:
  /// **'Additional details (optional)'**
  String get subscriptionsChurnDetailHint;

  /// No description provided for @opsDeskDeniedTitle.
  ///
  /// In en, this message translates to:
  /// **'Access denied'**
  String get opsDeskDeniedTitle;

  /// No description provided for @opsDeskDeniedBody.
  ///
  /// In en, this message translates to:
  /// **'This application is reserved for the platform operations team only'**
  String get opsDeskDeniedBody;

  /// No description provided for @opsDeskExit.
  ///
  /// In en, this message translates to:
  /// **'Close the app'**
  String get opsDeskExit;

  /// No description provided for @opsDeskTitle.
  ///
  /// In en, this message translates to:
  /// **'Platform operations desk'**
  String get opsDeskTitle;

  /// No description provided for @opsTabTickets.
  ///
  /// In en, this message translates to:
  /// **'Tickets'**
  String get opsTabTickets;

  /// No description provided for @opsDeskTabReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get opsDeskTabReports;

  /// No description provided for @opsDeskTabUsers.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get opsDeskTabUsers;

  /// No description provided for @opsDeskTabTeam.
  ///
  /// In en, this message translates to:
  /// **'Operations team'**
  String get opsDeskTabTeam;

  /// No description provided for @opsDeskTabLoginAds.
  ///
  /// In en, this message translates to:
  /// **'Login ads'**
  String get opsDeskTabLoginAds;

  /// No description provided for @opsDeskTabBilling.
  ///
  /// In en, this message translates to:
  /// **'Billing'**
  String get opsDeskTabBilling;

  /// No description provided for @opsDeskTabNotices.
  ///
  /// In en, this message translates to:
  /// **'Notices'**
  String get opsDeskTabNotices;

  /// No description provided for @opsDeskRoleAll.
  ///
  /// In en, this message translates to:
  /// **'All my roles'**
  String get opsDeskRoleAll;

  /// No description provided for @opsDeskRoleSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get opsDeskRoleSupport;

  /// No description provided for @opsDeskRoleCompliance.
  ///
  /// In en, this message translates to:
  /// **'Compliance'**
  String get opsDeskRoleCompliance;

  /// No description provided for @opsDeskRoleFinance.
  ///
  /// In en, this message translates to:
  /// **'Finance'**
  String get opsDeskRoleFinance;

  /// No description provided for @opsDeskGrantTooltip.
  ///
  /// In en, this message translates to:
  /// **'Grant operations access'**
  String get opsDeskGrantTooltip;

  /// No description provided for @opsDeskRevoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke access'**
  String get opsDeskRevoke;

  /// No description provided for @opsDeskSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name, national ID / iqama, or phone'**
  String get opsDeskSearchHint;

  /// No description provided for @opsDeskAiDraft.
  ///
  /// In en, this message translates to:
  /// **'AI draft'**
  String get opsDeskAiDraft;

  /// No description provided for @opsDeskSendReply.
  ///
  /// In en, this message translates to:
  /// **'Send reply'**
  String get opsDeskSendReply;

  /// No description provided for @opsDeskReplyHint.
  ///
  /// In en, this message translates to:
  /// **'Reply text (does not charge or ban)'**
  String get opsDeskReplyHint;

  /// No description provided for @opsDeskNoTickets.
  ///
  /// In en, this message translates to:
  /// **'No tickets'**
  String get opsDeskNoTickets;

  /// No description provided for @opsDeskNoReports.
  ///
  /// In en, this message translates to:
  /// **'No open reports'**
  String get opsDeskNoReports;

  /// No description provided for @opsDeskNoUsers.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get opsDeskNoUsers;

  /// No description provided for @opsDeskSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get opsDeskSaved;

  /// No description provided for @opsDeskForbidden.
  ///
  /// In en, this message translates to:
  /// **'Not allowed'**
  String get opsDeskForbidden;

  /// No description provided for @opsDeskOptions.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get opsDeskOptions;

  /// No description provided for @opsDeskAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get opsDeskAccept;

  /// No description provided for @opsDeskDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get opsDeskDismiss;

  /// No description provided for @opsDeskFeeSave.
  ///
  /// In en, this message translates to:
  /// **'Save price'**
  String get opsDeskFeeSave;

  /// No description provided for @opsDeskAdTitleAr.
  ///
  /// In en, this message translates to:
  /// **'Ad title (Arabic)'**
  String get opsDeskAdTitleAr;

  /// No description provided for @opsDeskAdTitleEn.
  ///
  /// In en, this message translates to:
  /// **'Ad title (English)'**
  String get opsDeskAdTitleEn;

  /// No description provided for @opsDeskAdSubAr.
  ///
  /// In en, this message translates to:
  /// **'Ad subtitle (Arabic)'**
  String get opsDeskAdSubAr;

  /// No description provided for @opsDeskAdSubEn.
  ///
  /// In en, this message translates to:
  /// **'Ad subtitle (English)'**
  String get opsDeskAdSubEn;

  /// No description provided for @opsDeskAdImage.
  ///
  /// In en, this message translates to:
  /// **'Image URL'**
  String get opsDeskAdImage;

  /// No description provided for @opsDeskAdLink.
  ///
  /// In en, this message translates to:
  /// **'Destination URL'**
  String get opsDeskAdLink;

  /// No description provided for @opsDeskAdPublish.
  ///
  /// In en, this message translates to:
  /// **'Publish ad'**
  String get opsDeskAdPublish;

  /// No description provided for @opsDeskNoticeUserId.
  ///
  /// In en, this message translates to:
  /// **'Recipient'**
  String get opsDeskNoticeUserId;

  /// No description provided for @opsDeskNoticeTitleAr.
  ///
  /// In en, this message translates to:
  /// **'Notice title (Arabic)'**
  String get opsDeskNoticeTitleAr;

  /// No description provided for @opsDeskNoticeTitleEn.
  ///
  /// In en, this message translates to:
  /// **'Notice title (English)'**
  String get opsDeskNoticeTitleEn;

  /// No description provided for @opsDeskNoticeBodyAr.
  ///
  /// In en, this message translates to:
  /// **'Notice body (Arabic)'**
  String get opsDeskNoticeBodyAr;

  /// No description provided for @opsDeskNoticeBodyEn.
  ///
  /// In en, this message translates to:
  /// **'Notice body (English)'**
  String get opsDeskNoticeBodyEn;

  /// No description provided for @opsDeskNoticeSend.
  ///
  /// In en, this message translates to:
  /// **'Send notice'**
  String get opsDeskNoticeSend;

  /// No description provided for @opsDeskDeniedHello.
  ///
  /// In en, this message translates to:
  /// **'Hello {name}'**
  String opsDeskDeniedHello(String name);

  /// No description provided for @opsDeskDeniedHelloGuest.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get opsDeskDeniedHelloGuest;

  /// No description provided for @opsDeskDeniedPolite.
  ///
  /// In en, this message translates to:
  /// **'We\'re glad you\'re here. The Windows desktop app is reserved for the platform operations team, and your account does not have access. Continue on the web or the mobile app with your marketplace permissions.'**
  String get opsDeskDeniedPolite;

  /// No description provided for @opsDeskOpenWeb.
  ///
  /// In en, this message translates to:
  /// **'Open the platform on the web'**
  String get opsDeskOpenWeb;

  /// No description provided for @opsDeskOpenMobile.
  ///
  /// In en, this message translates to:
  /// **'Open the platform on mobile'**
  String get opsDeskOpenMobile;

  /// No description provided for @opsDeskModeOps.
  ///
  /// In en, this message translates to:
  /// **'Platform operations'**
  String get opsDeskModeOps;

  /// No description provided for @opsDeskModeMarket.
  ///
  /// In en, this message translates to:
  /// **'Marketplace user'**
  String get opsDeskModeMarket;

  /// No description provided for @opsDeskLoginHint.
  ///
  /// In en, this message translates to:
  /// **'Platform operations team sign-in only. Marketplace stays on web and the mobile app.'**
  String get opsDeskLoginHint;

  /// No description provided for @opsDeskUsersHint.
  ///
  /// In en, this message translates to:
  /// **'A marketplace account type (marketer / office / establishment) is not operations-team membership. Add someone to the operations team only from the shield icon after choosing capabilities.'**
  String get opsDeskUsersHint;

  /// No description provided for @opsDeskPreviewBeforePublish.
  ///
  /// In en, this message translates to:
  /// **'Preview before approval'**
  String get opsDeskPreviewBeforePublish;

  /// No description provided for @opsDeskPreviewWhere.
  ///
  /// In en, this message translates to:
  /// **'Where it appears'**
  String get opsDeskPreviewWhere;

  /// No description provided for @opsDeskDraftLive.
  ///
  /// In en, this message translates to:
  /// **'Your edits appear here as the user will see them. Check the placement, then approve.'**
  String get opsDeskDraftLive;

  /// No description provided for @opsDeskApprovePublish.
  ///
  /// In en, this message translates to:
  /// **'Approve & publish'**
  String get opsDeskApprovePublish;

  /// No description provided for @opsDeskNoticePreview.
  ///
  /// In en, this message translates to:
  /// **'Notice preview'**
  String get opsDeskNoticePreview;

  /// No description provided for @opsDeskColName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get opsDeskColName;

  /// No description provided for @opsDeskColType.
  ///
  /// In en, this message translates to:
  /// **'Marketplace type'**
  String get opsDeskColType;

  /// No description provided for @opsDeskColOps.
  ///
  /// In en, this message translates to:
  /// **'Operations team'**
  String get opsDeskColOps;

  /// No description provided for @opsTitleOwnerIndividual.
  ///
  /// In en, this message translates to:
  /// **'Individual owner'**
  String get opsTitleOwnerIndividual;

  /// No description provided for @opsTitleMarketer.
  ///
  /// In en, this message translates to:
  /// **'Real-estate marketer'**
  String get opsTitleMarketer;

  /// No description provided for @opsTitleOffice.
  ///
  /// In en, this message translates to:
  /// **'Real-estate office'**
  String get opsTitleOffice;

  /// No description provided for @opsTitleCompany.
  ///
  /// In en, this message translates to:
  /// **'Real-estate company'**
  String get opsTitleCompany;

  /// No description provided for @opsTitleInstitution.
  ///
  /// In en, this message translates to:
  /// **'Real-estate establishment'**
  String get opsTitleInstitution;

  /// No description provided for @opsTitleAgency.
  ///
  /// In en, this message translates to:
  /// **'Real-estate agency'**
  String get opsTitleAgency;

  /// No description provided for @opsTitleUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get opsTitleUser;

  /// No description provided for @opsDeskTabAudit.
  ///
  /// In en, this message translates to:
  /// **'Audit log'**
  String get opsDeskTabAudit;

  /// No description provided for @opsDeskResolve.
  ///
  /// In en, this message translates to:
  /// **'Close ticket'**
  String get opsDeskResolve;

  /// No description provided for @opsDeskPrint.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get opsDeskPrint;

  /// No description provided for @opsDeskNoAudit.
  ///
  /// In en, this message translates to:
  /// **'No audit rows yet'**
  String get opsDeskNoAudit;

  /// No description provided for @opsDeskPrintTickets.
  ///
  /// In en, this message translates to:
  /// **'Print tickets'**
  String get opsDeskPrintTickets;

  /// No description provided for @opsDeskPrintAudit.
  ///
  /// In en, this message translates to:
  /// **'Print audit'**
  String get opsDeskPrintAudit;

  /// No description provided for @opsDeskRoleDeputy.
  ///
  /// In en, this message translates to:
  /// **'Deputy system manager'**
  String get opsDeskRoleDeputy;

  /// No description provided for @opsDeskRoleAds.
  ///
  /// In en, this message translates to:
  /// **'Ads'**
  String get opsDeskRoleAds;

  /// No description provided for @opsDeskRolePromo.
  ///
  /// In en, this message translates to:
  /// **'Offers & discounts'**
  String get opsDeskRolePromo;

  /// No description provided for @opsDeskRoleBan.
  ///
  /// In en, this message translates to:
  /// **'Ban'**
  String get opsDeskRoleBan;

  /// No description provided for @opsDeskRoleTeam.
  ///
  /// In en, this message translates to:
  /// **'Team notices'**
  String get opsDeskRoleTeam;

  /// No description provided for @opsDeskTabPromos.
  ///
  /// In en, this message translates to:
  /// **'Offers'**
  String get opsDeskTabPromos;

  /// No description provided for @opsDeskTabOpsSettings.
  ///
  /// In en, this message translates to:
  /// **'Operations settings'**
  String get opsDeskTabOpsSettings;

  /// No description provided for @opsDeskAdPlacement.
  ///
  /// In en, this message translates to:
  /// **'Ad placement'**
  String get opsDeskAdPlacement;

  /// No description provided for @opsDeskAdPlaceLogin.
  ///
  /// In en, this message translates to:
  /// **'Large login screens'**
  String get opsDeskAdPlaceLogin;

  /// No description provided for @opsDeskAdPlaceInApp.
  ///
  /// In en, this message translates to:
  /// **'In-app for users'**
  String get opsDeskAdPlaceInApp;

  /// No description provided for @opsDeskAdPlaceTeam.
  ///
  /// In en, this message translates to:
  /// **'Operations team'**
  String get opsDeskAdPlaceTeam;

  /// No description provided for @opsDeskAdPlaceSupport.
  ///
  /// In en, this message translates to:
  /// **'Support cards'**
  String get opsDeskAdPlaceSupport;

  /// No description provided for @opsDeskPromoCode.
  ///
  /// In en, this message translates to:
  /// **'Discount code'**
  String get opsDeskPromoCode;

  /// No description provided for @opsDeskPromoValue.
  ///
  /// In en, this message translates to:
  /// **'Percent or value'**
  String get opsDeskPromoValue;

  /// No description provided for @opsDeskPromoSave.
  ///
  /// In en, this message translates to:
  /// **'Save offer'**
  String get opsDeskPromoSave;

  /// No description provided for @opsDeskBan.
  ///
  /// In en, this message translates to:
  /// **'Ban'**
  String get opsDeskBan;

  /// No description provided for @opsDeskLiftBan.
  ///
  /// In en, this message translates to:
  /// **'Lift ban'**
  String get opsDeskLiftBan;

  /// No description provided for @opsDeskBanReason.
  ///
  /// In en, this message translates to:
  /// **'Ban reason'**
  String get opsDeskBanReason;

  /// No description provided for @opsDeskBroadcastTeam.
  ///
  /// In en, this message translates to:
  /// **'Send to the whole team'**
  String get opsDeskBroadcastTeam;

  /// No description provided for @opsDeskSettingsHint.
  ///
  /// In en, this message translates to:
  /// **'Language and theme for the operations desk — separate from marketplace settings on web and mobile.'**
  String get opsDeskSettingsHint;

  /// No description provided for @opsDeskFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get opsDeskFilterAll;

  /// No description provided for @opsDeskFilterActive.
  ///
  /// In en, this message translates to:
  /// **'Active (7 days)'**
  String get opsDeskFilterActive;

  /// No description provided for @opsDeskFilterInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get opsDeskFilterInactive;

  /// No description provided for @opsDeskFilterIdle.
  ///
  /// In en, this message translates to:
  /// **'Idle (30 days)'**
  String get opsDeskFilterIdle;

  /// No description provided for @opsDeskFilterBanned.
  ///
  /// In en, this message translates to:
  /// **'Banned'**
  String get opsDeskFilterBanned;

  /// No description provided for @opsDeskFilterLocked.
  ///
  /// In en, this message translates to:
  /// **'Locked out of the app'**
  String get opsDeskFilterLocked;

  /// No description provided for @opsDeskFilterPending.
  ///
  /// In en, this message translates to:
  /// **'Pending activation'**
  String get opsDeskFilterPending;

  /// No description provided for @opsDeskFilterStaff.
  ///
  /// In en, this message translates to:
  /// **'Operations team'**
  String get opsDeskFilterStaff;

  /// No description provided for @opsDeskFilterOffice.
  ///
  /// In en, this message translates to:
  /// **'Real-estate office'**
  String get opsDeskFilterOffice;

  /// No description provided for @opsDeskFilterCompany.
  ///
  /// In en, this message translates to:
  /// **'Real-estate company'**
  String get opsDeskFilterCompany;

  /// No description provided for @opsDeskFilterInstitution.
  ///
  /// In en, this message translates to:
  /// **'Real-estate institution'**
  String get opsDeskFilterInstitution;

  /// No description provided for @opsDeskFilterMarketer.
  ///
  /// In en, this message translates to:
  /// **'Marketer'**
  String get opsDeskFilterMarketer;

  /// No description provided for @opsDeskFilterOwner.
  ///
  /// In en, this message translates to:
  /// **'Individual owner'**
  String get opsDeskFilterOwner;

  /// No description provided for @opsDeskAddToTeam.
  ///
  /// In en, this message translates to:
  /// **'Add to operations team'**
  String get opsDeskAddToTeam;

  /// No description provided for @opsDeskOnTeam.
  ///
  /// In en, this message translates to:
  /// **'On the team'**
  String get opsDeskOnTeam;

  /// No description provided for @opsDeskTerminateSessions.
  ///
  /// In en, this message translates to:
  /// **'End login sessions'**
  String get opsDeskTerminateSessions;

  /// No description provided for @opsDeskSendNoticeTo.
  ///
  /// In en, this message translates to:
  /// **'Send a notice to this user — open the Notices tab'**
  String get opsDeskSendNoticeTo;

  /// No description provided for @opsDeskCopyId.
  ///
  /// In en, this message translates to:
  /// **'Copy national ID / iqama'**
  String get opsDeskCopyId;

  /// No description provided for @opsDeskTabIntel.
  ///
  /// In en, this message translates to:
  /// **'Activity & sales'**
  String get opsDeskTabIntel;

  /// No description provided for @opsDeskTabCampaigns.
  ///
  /// In en, this message translates to:
  /// **'Push & in-app campaigns'**
  String get opsDeskTabCampaigns;

  /// No description provided for @opsDeskMostLogins.
  ///
  /// In en, this message translates to:
  /// **'Most logins'**
  String get opsDeskMostLogins;

  /// No description provided for @opsDeskMostSales.
  ///
  /// In en, this message translates to:
  /// **'Most sales'**
  String get opsDeskMostSales;

  /// No description provided for @opsDeskPrintUsers.
  ///
  /// In en, this message translates to:
  /// **'Print users'**
  String get opsDeskPrintUsers;

  /// No description provided for @opsDeskPrintIntel.
  ///
  /// In en, this message translates to:
  /// **'Print activity'**
  String get opsDeskPrintIntel;

  /// No description provided for @opsDeskPrintCampaigns.
  ///
  /// In en, this message translates to:
  /// **'Print campaigns'**
  String get opsDeskPrintCampaigns;

  /// No description provided for @opsDeskCampaignMedia.
  ///
  /// In en, this message translates to:
  /// **'Image or video URL next to the notice'**
  String get opsDeskCampaignMedia;

  /// No description provided for @opsDeskCampaignDeep.
  ///
  /// In en, this message translates to:
  /// **'Destination when opened'**
  String get opsDeskCampaignDeep;

  /// No description provided for @opsDeskCampaignAudience.
  ///
  /// In en, this message translates to:
  /// **'Recipient account type'**
  String get opsDeskCampaignAudience;

  /// No description provided for @opsDeskCampaignAllTypes.
  ///
  /// In en, this message translates to:
  /// **'All account types'**
  String get opsDeskCampaignAllTypes;

  /// No description provided for @opsDeskCampaignSave.
  ///
  /// In en, this message translates to:
  /// **'Schedule campaign'**
  String get opsDeskCampaignSave;

  /// No description provided for @opsDeskCampaignSendNow.
  ///
  /// In en, this message translates to:
  /// **'Send now'**
  String get opsDeskCampaignSendNow;

  /// No description provided for @opsDeskCampaignStarts.
  ///
  /// In en, this message translates to:
  /// **'Send from'**
  String get opsDeskCampaignStarts;

  /// No description provided for @opsDeskCampaignEnds.
  ///
  /// In en, this message translates to:
  /// **'Campaign ends (then expires)'**
  String get opsDeskCampaignEnds;

  /// No description provided for @opsDeskCampaignTarget.
  ///
  /// In en, this message translates to:
  /// **'Name or national ID (optional)'**
  String get opsDeskCampaignTarget;

  /// No description provided for @opsDeskTeamActive.
  ///
  /// In en, this message translates to:
  /// **'Active on the team'**
  String get opsDeskTeamActive;

  /// No description provided for @opsDeskTeamInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive on the team'**
  String get opsDeskTeamInactive;

  /// No description provided for @opsDeskLogins.
  ///
  /// In en, this message translates to:
  /// **'Logins'**
  String get opsDeskLogins;

  /// No description provided for @opsDeskLogouts.
  ///
  /// In en, this message translates to:
  /// **'Logouts'**
  String get opsDeskLogouts;

  /// No description provided for @opsDeskSales.
  ///
  /// In en, this message translates to:
  /// **'Successful sales'**
  String get opsDeskSales;

  /// No description provided for @opsDeskLastLogin.
  ///
  /// In en, this message translates to:
  /// **'Last login'**
  String get opsDeskLastLogin;

  /// No description provided for @opsDeskLastLogout.
  ///
  /// In en, this message translates to:
  /// **'Last logout'**
  String get opsDeskLastLogout;

  /// No description provided for @opsDeskVerification.
  ///
  /// In en, this message translates to:
  /// **'Verification'**
  String get opsDeskVerification;

  /// No description provided for @opsDeskCampaignSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get opsDeskCampaignSent;

  /// No description provided for @opsDeskNoCampaigns.
  ///
  /// In en, this message translates to:
  /// **'No campaigns yet'**
  String get opsDeskNoCampaigns;

  /// No description provided for @opsDeskNoIntel.
  ///
  /// In en, this message translates to:
  /// **'Not enough data yet'**
  String get opsDeskNoIntel;

  /// No description provided for @opsDeskFilterOnline.
  ///
  /// In en, this message translates to:
  /// **'Online now'**
  String get opsDeskFilterOnline;

  /// No description provided for @opsDeskFilterOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get opsDeskFilterOffline;

  /// No description provided for @opsDeskHoursToday.
  ///
  /// In en, this message translates to:
  /// **'Hours today'**
  String get opsDeskHoursToday;

  /// No description provided for @opsDeskHours7d.
  ///
  /// In en, this message translates to:
  /// **'Hours (7 days)'**
  String get opsDeskHours7d;

  /// No description provided for @opsDeskOnlineNow.
  ///
  /// In en, this message translates to:
  /// **'Online now: {count}'**
  String opsDeskOnlineNow(int count);

  /// No description provided for @opsDeskStaffOnline.
  ///
  /// In en, this message translates to:
  /// **'Staff online: {count}'**
  String opsDeskStaffOnline(int count);

  /// No description provided for @opsDeskSubsActive.
  ///
  /// In en, this message translates to:
  /// **'Active subscriptions'**
  String get opsDeskSubsActive;

  /// No description provided for @opsDeskSubsPending.
  ///
  /// In en, this message translates to:
  /// **'Pending subscriptions'**
  String get opsDeskSubsPending;

  /// No description provided for @opsDeskDupGateway.
  ///
  /// In en, this message translates to:
  /// **'Duplicate gateway ids'**
  String get opsDeskDupGateway;

  /// No description provided for @opsDeskPayStuck.
  ///
  /// In en, this message translates to:
  /// **'Payments pending over 1 hour'**
  String get opsDeskPayStuck;

  /// No description provided for @opsDeskCampaignSendAll.
  ///
  /// In en, this message translates to:
  /// **'Send to everyone (batched until done, no 400 cap)'**
  String get opsDeskCampaignSendAll;

  /// No description provided for @opsDeskCampaignIdleNudge.
  ///
  /// In en, this message translates to:
  /// **'Idle reminder only (30+ days) — skips active users'**
  String get opsDeskCampaignIdleNudge;

  /// No description provided for @opsDeskCampaignReceipts.
  ///
  /// In en, this message translates to:
  /// **'Delivery report'**
  String get opsDeskCampaignReceipts;

  /// No description provided for @opsDeskReceiptDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get opsDeskReceiptDelivered;

  /// No description provided for @opsDeskReceiptRead.
  ///
  /// In en, this message translates to:
  /// **'Opened'**
  String get opsDeskReceiptRead;

  /// No description provided for @opsDeskPurged.
  ///
  /// In en, this message translates to:
  /// **'Removed from inboxes'**
  String get opsDeskPurged;

  /// No description provided for @opsDeskIdleHint.
  ///
  /// In en, this message translates to:
  /// **'Normal broadcasts skip anyone idle 90 days. Use the idle reminder to reach them by name or account type.'**
  String get opsDeskIdleHint;

  /// No description provided for @opsDeskWatchHint.
  ///
  /// In en, this message translates to:
  /// **'Subscription and billing anomalies — export and print with finance permission.'**
  String get opsDeskWatchHint;

  /// No description provided for @opsDeskTeamTimeHint.
  ///
  /// In en, this message translates to:
  /// **'Staff attendance from login/logout sessions. Windows idle is 3 minutes then a 1-minute countdown then sign-out, and session duration is recorded.'**
  String get opsDeskTeamTimeHint;

  /// No description provided for @opsDeskWorkHours.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get opsDeskWorkHours;

  /// No description provided for @opsDeskPromoHint.
  ///
  /// In en, this message translates to:
  /// **'Codes may be Arabic, English, numbers, symbols, or a public name. Each signed-in user can use a code once. The discount is calculated on the server for subscriptions, invoices, and one-time payments.'**
  String get opsDeskPromoHint;

  /// No description provided for @opsDeskPromoKind.
  ///
  /// In en, this message translates to:
  /// **'Discount type'**
  String get opsDeskPromoKind;

  /// No description provided for @opsDeskPromoKindPercent.
  ///
  /// In en, this message translates to:
  /// **'Percent off'**
  String get opsDeskPromoKindPercent;

  /// No description provided for @opsDeskPromoKindFixed.
  ///
  /// In en, this message translates to:
  /// **'Fixed amount off (SAR)'**
  String get opsDeskPromoKindFixed;

  /// No description provided for @opsDeskPromoKindTrial.
  ///
  /// In en, this message translates to:
  /// **'Trial days (does not change the price)'**
  String get opsDeskPromoKindTrial;

  /// No description provided for @opsDeskPromoKindBonus.
  ///
  /// In en, this message translates to:
  /// **'First-payment bonus (SAR off)'**
  String get opsDeskPromoKindBonus;

  /// No description provided for @opsDeskPromoShare.
  ///
  /// In en, this message translates to:
  /// **'Share code'**
  String get opsDeskPromoShare;

  /// No description provided for @opsDeskPromoCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get opsDeskPromoCopied;

  /// No description provided for @opsDeskPromoUsed.
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get opsDeskPromoUsed;

  /// No description provided for @opsDeskPromoRedemptions.
  ///
  /// In en, this message translates to:
  /// **'Who used this code'**
  String get opsDeskPromoRedemptions;

  /// No description provided for @opsDeskPromoExport.
  ///
  /// In en, this message translates to:
  /// **'Export who used it'**
  String get opsDeskPromoExport;

  /// No description provided for @opsDeskPromoActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get opsDeskPromoActive;

  /// No description provided for @opsDeskPromoInactive.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get opsDeskPromoInactive;

  /// No description provided for @opsDeskPromoMax.
  ///
  /// In en, this message translates to:
  /// **'Max uses (optional)'**
  String get opsDeskPromoMax;

  /// No description provided for @opsDeskPromoFilterHint.
  ///
  /// In en, this message translates to:
  /// **'Name, national ID, or account type'**
  String get opsDeskPromoFilterHint;

  /// No description provided for @opsDeskGrantPlan.
  ///
  /// In en, this message translates to:
  /// **'Grant a plan'**
  String get opsDeskGrantPlan;

  /// No description provided for @opsDeskGrantPlanHint.
  ///
  /// In en, this message translates to:
  /// **'Pick the plan that matches this account type, then the period. Individual owners stay on the free tier and pay catalog fees instead. Staff without a plan can still use a discount code or pay from marketplace mode.'**
  String get opsDeskGrantPlanHint;

  /// No description provided for @opsDeskGrantMonths.
  ///
  /// In en, this message translates to:
  /// **'Grant period'**
  String get opsDeskGrantMonths;

  /// No description provided for @opsDeskGrantMonth1.
  ///
  /// In en, this message translates to:
  /// **'1 month'**
  String get opsDeskGrantMonth1;

  /// No description provided for @opsDeskGrantMonth3.
  ///
  /// In en, this message translates to:
  /// **'3 months'**
  String get opsDeskGrantMonth3;

  /// No description provided for @opsDeskGrantMonth6.
  ///
  /// In en, this message translates to:
  /// **'6 months'**
  String get opsDeskGrantMonth6;

  /// No description provided for @opsDeskGrantMonth12.
  ///
  /// In en, this message translates to:
  /// **'12 months'**
  String get opsDeskGrantMonth12;

  /// No description provided for @opsDeskGrantFreeTier.
  ///
  /// In en, this message translates to:
  /// **'This account type has no paid plan — free marketplace access plus one-time catalog fees.'**
  String get opsDeskGrantFreeTier;

  /// No description provided for @opsDeskGrantConfirm.
  ///
  /// In en, this message translates to:
  /// **'Activate plan'**
  String get opsDeskGrantConfirm;

  /// No description provided for @opsDeskGrantOk.
  ///
  /// In en, this message translates to:
  /// **'Plan activated until the granted period ends.'**
  String get opsDeskGrantOk;

  /// No description provided for @checkoutPromoCode.
  ///
  /// In en, this message translates to:
  /// **'Discount code'**
  String get checkoutPromoCode;

  /// No description provided for @checkoutPromoApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get checkoutPromoApply;

  /// No description provided for @checkoutPromoApplied.
  ///
  /// In en, this message translates to:
  /// **'Discount applied'**
  String get checkoutPromoApplied;

  /// No description provided for @checkoutPromoRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove code'**
  String get checkoutPromoRemove;

  /// No description provided for @checkoutPromoZero.
  ///
  /// In en, this message translates to:
  /// **'This code brings the amount to zero. Ask finance to grant the plan instead of paying.'**
  String get checkoutPromoZero;

  /// No description provided for @promoErrInvalid.
  ///
  /// In en, this message translates to:
  /// **'This discount code is not valid.'**
  String get promoErrInvalid;

  /// No description provided for @promoErrUsed.
  ///
  /// In en, this message translates to:
  /// **'You have already used this code.'**
  String get promoErrUsed;

  /// No description provided for @promoErrExpired.
  ///
  /// In en, this message translates to:
  /// **'This discount code has expired.'**
  String get promoErrExpired;

  /// No description provided for @promoErrSoldOut.
  ///
  /// In en, this message translates to:
  /// **'This discount code has reached its use limit.'**
  String get promoErrSoldOut;

  /// No description provided for @promoErrAudience.
  ///
  /// In en, this message translates to:
  /// **'This code is not for your account type.'**
  String get promoErrAudience;

  /// No description provided for @promoErrNotStarted.
  ///
  /// In en, this message translates to:
  /// **'This discount code is not active yet.'**
  String get promoErrNotStarted;

  /// No description provided for @promoErrActiveSub.
  ///
  /// In en, this message translates to:
  /// **'You already have an active plan — this code applies at renewal after it ends.'**
  String get promoErrActiveSub;

  /// No description provided for @promoErrOtherCampaign.
  ///
  /// In en, this message translates to:
  /// **'You already used another live campaign code. Wait until that campaign ends.'**
  String get promoErrOtherCampaign;

  /// No description provided for @promoErrWrongPlan.
  ///
  /// In en, this message translates to:
  /// **'This discount code is not valid for this plan.'**
  String get promoErrWrongPlan;

  /// No description provided for @promoErrWrongPeriod.
  ///
  /// In en, this message translates to:
  /// **'This discount code is not valid for this billing period.'**
  String get promoErrWrongPeriod;

  /// No description provided for @promoErrBelowMin.
  ///
  /// In en, this message translates to:
  /// **'This order is below the minimum amount for the code.'**
  String get promoErrBelowMin;

  /// No description provided for @checkoutPromoBrowse.
  ///
  /// In en, this message translates to:
  /// **'Check available codes'**
  String get checkoutPromoBrowse;

  /// No description provided for @checkoutPromoChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get checkoutPromoChange;

  /// No description provided for @checkoutPromoEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get checkoutPromoEdit;

  /// No description provided for @checkoutPromoUse.
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get checkoutPromoUse;

  /// No description provided for @checkoutPromoNone.
  ///
  /// In en, this message translates to:
  /// **'No discount codes are available for this checkout.'**
  String get checkoutPromoNone;

  /// No description provided for @checkoutPromoPercentCol.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get checkoutPromoPercentCol;

  /// No description provided for @checkoutPromoValidCol.
  ///
  /// In en, this message translates to:
  /// **'Validity'**
  String get checkoutPromoValidCol;

  /// No description provided for @checkoutPromoActionCol.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get checkoutPromoActionCol;

  /// No description provided for @checkoutPromoAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get checkoutPromoAvailable;

  /// No description provided for @checkoutPromoSortHighest.
  ///
  /// In en, this message translates to:
  /// **'Highest discount'**
  String get checkoutPromoSortHighest;

  /// No description provided for @checkoutPromoSortExpiring.
  ///
  /// In en, this message translates to:
  /// **'Ending soon'**
  String get checkoutPromoSortExpiring;

  /// No description provided for @checkoutAutoRenew.
  ///
  /// In en, this message translates to:
  /// **'Auto-renewal'**
  String get checkoutAutoRenew;

  /// No description provided for @checkoutAutoRenewHint.
  ///
  /// In en, this message translates to:
  /// **'{percent}% off applies immediately when on, and is removed when off.'**
  String checkoutAutoRenewHint(String percent);

  /// No description provided for @checkoutBetterPromoNote.
  ///
  /// In en, this message translates to:
  /// **'A higher discount code is available'**
  String get checkoutBetterPromoNote;

  /// No description provided for @checkoutWantPromoLink.
  ///
  /// In en, this message translates to:
  /// **'Do you want to use a discount code?'**
  String get checkoutWantPromoLink;

  /// No description provided for @checkoutPromoCancelIntent.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get checkoutPromoCancelIntent;

  /// No description provided for @checkoutPayLockedUntilPromo.
  ///
  /// In en, this message translates to:
  /// **'Enter and apply a valid better code, or cancel to continue with auto-renew pricing.'**
  String get checkoutPayLockedUntilPromo;

  /// No description provided for @autoRenewFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-renewal failed'**
  String get autoRenewFailedTitle;

  /// No description provided for @autoRenewFailedBody.
  ///
  /// In en, this message translates to:
  /// **'Dear customer, we could not automatically renew your {planName} plan because there was not enough balance on your card. Please update your payment details to avoid service interruption.'**
  String autoRenewFailedBody(String planName);

  /// No description provided for @checkoutAutoPayBetter.
  ///
  /// In en, this message translates to:
  /// **'Auto-pay is a better discount. Turn off auto-renew to use this code, or keep auto-pay.'**
  String get checkoutAutoPayBetter;

  /// No description provided for @checkoutAutoPayDiscountLine.
  ///
  /// In en, this message translates to:
  /// **'Auto-pay discount ({percent}%)'**
  String checkoutAutoPayDiscountLine(String percent);

  /// No description provided for @checkoutPromoDiscountLine.
  ///
  /// In en, this message translates to:
  /// **'Discount code: {code}'**
  String checkoutPromoDiscountLine(String code);

  /// No description provided for @checkoutAutoRenewDiscountPlain.
  ///
  /// In en, this message translates to:
  /// **'Auto-renew activation discount'**
  String get checkoutAutoRenewDiscountPlain;

  /// No description provided for @checkoutPromoCodeDiscountPlain.
  ///
  /// In en, this message translates to:
  /// **'Promo code discount'**
  String get checkoutPromoCodeDiscountPlain;

  /// No description provided for @trialLearnMore.
  ///
  /// In en, this message translates to:
  /// **'Tap here for details'**
  String get trialLearnMore;

  /// No description provided for @trialDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Trial details'**
  String get trialDetailsTitle;

  /// No description provided for @trialStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active now'**
  String get trialStatusActive;

  /// No description provided for @trialLimitListing.
  ///
  /// In en, this message translates to:
  /// **'Property listings'**
  String get trialLimitListing;

  /// No description provided for @trialLimitTeam.
  ///
  /// In en, this message translates to:
  /// **'Team members'**
  String get trialLimitTeam;

  /// No description provided for @trialLimitRequests.
  ///
  /// In en, this message translates to:
  /// **'Market requests'**
  String get trialLimitRequests;

  /// No description provided for @trialLimitListingValue.
  ///
  /// In en, this message translates to:
  /// **'1'**
  String get trialLimitListingValue;

  /// No description provided for @trialLimitTeamValue.
  ///
  /// In en, this message translates to:
  /// **'Not included'**
  String get trialLimitTeamValue;

  /// No description provided for @trialLimitRequestsValue.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get trialLimitRequestsValue;

  /// No description provided for @opsDeskPromoCampaign.
  ///
  /// In en, this message translates to:
  /// **'Campaign name'**
  String get opsDeskPromoCampaign;

  /// No description provided for @opsDeskPromoCampaignHint.
  ///
  /// In en, this message translates to:
  /// **'Codes in the same campaign share one window. A user with a live campaign code cannot use a different campaign until it ends.'**
  String get opsDeskPromoCampaignHint;

  /// No description provided for @opsDeskPromoCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Type the code exactly as users will enter it — Arabic, English, digits, or symbols. It is not forced to English capitals (that would break Arabic).'**
  String get opsDeskPromoCodeHint;

  /// No description provided for @opsDeskPromoValueHint.
  ///
  /// In en, this message translates to:
  /// **'Percent 1–100, or a SAR amount for a fixed discount. Never type a price into a label — the value is stored and formatted as money.'**
  String get opsDeskPromoValueHint;

  /// No description provided for @opsDeskPromoWindowHint.
  ///
  /// In en, this message translates to:
  /// **'Starts and ends at the chosen date and time. After the end, the code stops immediately.'**
  String get opsDeskPromoWindowHint;

  /// No description provided for @opsDeskPromoStarts.
  ///
  /// In en, this message translates to:
  /// **'Valid from'**
  String get opsDeskPromoStarts;

  /// No description provided for @opsDeskPromoEnds.
  ///
  /// In en, this message translates to:
  /// **'Valid until'**
  String get opsDeskPromoEnds;

  /// No description provided for @opsDeskExportExcel.
  ///
  /// In en, this message translates to:
  /// **'Excel'**
  String get opsDeskExportExcel;

  /// No description provided for @opsDeskTicketRequester.
  ///
  /// In en, this message translates to:
  /// **'Requester'**
  String get opsDeskTicketRequester;

  /// No description provided for @opsDeskTicketAssignee.
  ///
  /// In en, this message translates to:
  /// **'Assigned to'**
  String get opsDeskTicketAssignee;

  /// No description provided for @opsDeskGrantIndividualWhy.
  ///
  /// In en, this message translates to:
  /// **'Individual owners and regular users are not sold a monthly/yearly plan. They use the marketplace for free and pay catalog one-time fees when they publish. Granting a marketer/office plan would give them the wrong product.'**
  String get opsDeskGrantIndividualWhy;

  /// No description provided for @opsDeskTicketWelcome.
  ///
  /// In en, this message translates to:
  /// **'Open & greet'**
  String get opsDeskTicketWelcome;

  /// No description provided for @opsDeskNationalId.
  ///
  /// In en, this message translates to:
  /// **'National ID / Iqama'**
  String get opsDeskNationalId;

  /// No description provided for @opsDeskPhone.
  ///
  /// In en, this message translates to:
  /// **'Mobile'**
  String get opsDeskPhone;

  /// No description provided for @opsDeskLicense.
  ///
  /// In en, this message translates to:
  /// **'License number'**
  String get opsDeskLicense;

  /// No description provided for @opsDeskNoticePickHint.
  ///
  /// In en, this message translates to:
  /// **'Pick the recipient from the Users tab — system IDs are not shown'**
  String get opsDeskNoticePickHint;

  /// No description provided for @opsDeskCopiedNationalId.
  ///
  /// In en, this message translates to:
  /// **'National ID / iqama copied'**
  String get opsDeskCopiedNationalId;

  /// No description provided for @opsDeskRoleOwner.
  ///
  /// In en, this message translates to:
  /// **'Platform owner'**
  String get opsDeskRoleOwner;

  /// No description provided for @opsDeskVerifyPending.
  ///
  /// In en, this message translates to:
  /// **'Pending verification'**
  String get opsDeskVerifyPending;

  /// No description provided for @opsDeskVerifyNone.
  ///
  /// In en, this message translates to:
  /// **'Not verified'**
  String get opsDeskVerifyNone;

  /// No description provided for @opsDeskVerifyRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get opsDeskVerifyRejected;

  /// No description provided for @opsDeskTicketKindComplaint.
  ///
  /// In en, this message translates to:
  /// **'Complaint'**
  String get opsDeskTicketKindComplaint;

  /// No description provided for @opsDeskTicketKindSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Suggestion'**
  String get opsDeskTicketKindSuggestion;

  /// No description provided for @opsDeskTicketStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get opsDeskTicketStatusOpen;

  /// No description provided for @opsDeskTicketStatusResolved.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get opsDeskTicketStatusResolved;

  /// No description provided for @opsDeskTicketStatusEscalated.
  ///
  /// In en, this message translates to:
  /// **'Escalated'**
  String get opsDeskTicketStatusEscalated;

  /// No description provided for @opsDeskPulseTotal.
  ///
  /// In en, this message translates to:
  /// **'All users'**
  String get opsDeskPulseTotal;

  /// No description provided for @opsDeskPulseOnline.
  ///
  /// In en, this message translates to:
  /// **'Online now'**
  String get opsDeskPulseOnline;

  /// No description provided for @opsDeskPulseIdle.
  ///
  /// In en, this message translates to:
  /// **'Idle 30 days'**
  String get opsDeskPulseIdle;

  /// No description provided for @opsDeskPulseIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Incomplete profile'**
  String get opsDeskPulseIncomplete;

  /// No description provided for @opsDeskPulseFalExpired.
  ///
  /// In en, this message translates to:
  /// **'License expired'**
  String get opsDeskPulseFalExpired;

  /// No description provided for @opsDeskPulseFalExpiring.
  ///
  /// In en, this message translates to:
  /// **'License in 7 days'**
  String get opsDeskPulseFalExpiring;

  /// No description provided for @opsDeskPulseSubExpired.
  ///
  /// In en, this message translates to:
  /// **'Subscription ended'**
  String get opsDeskPulseSubExpired;

  /// No description provided for @opsDeskPulseSubExpiring.
  ///
  /// In en, this message translates to:
  /// **'Subscription in 7 days'**
  String get opsDeskPulseSubExpiring;

  /// No description provided for @opsDeskPulseGuests.
  ///
  /// In en, this message translates to:
  /// **'Guests (7 days)'**
  String get opsDeskPulseGuests;

  /// No description provided for @opsDeskWatchList.
  ///
  /// In en, this message translates to:
  /// **'Watch list'**
  String get opsDeskWatchList;

  /// No description provided for @opsDeskWatchNotify.
  ///
  /// In en, this message translates to:
  /// **'Notify this list'**
  String get opsDeskWatchNotify;

  /// No description provided for @opsDeskPatchProfile.
  ///
  /// In en, this message translates to:
  /// **'Complete / correct profile'**
  String get opsDeskPatchProfile;

  /// No description provided for @opsDeskPatchSaved.
  ///
  /// In en, this message translates to:
  /// **'Save profile'**
  String get opsDeskPatchSaved;

  /// No description provided for @photographerJoinTitle.
  ///
  /// In en, this message translates to:
  /// **'Join as a property photographer'**
  String get photographerJoinTitle;

  /// No description provided for @photographerJoinIntro.
  ///
  /// In en, this message translates to:
  /// **'This is an overlay on your current account (owner or marketer). Your role and My page listing tabs stay as they are. Review takes up to 24 hours.'**
  String get photographerJoinIntro;

  /// No description provided for @photographerDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get photographerDisplayName;

  /// No description provided for @photographerNationalId.
  ///
  /// In en, this message translates to:
  /// **'National ID / Iqama'**
  String get photographerNationalId;

  /// No description provided for @photographerCommercialRegister.
  ///
  /// In en, this message translates to:
  /// **'Commercial registration (optional)'**
  String get photographerCommercialRegister;

  /// No description provided for @photographerCity.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get photographerCity;

  /// No description provided for @photographerBio.
  ///
  /// In en, this message translates to:
  /// **'Bio and past work (recommended)'**
  String get photographerBio;

  /// No description provided for @photographerPhotoRate.
  ///
  /// In en, this message translates to:
  /// **'Photo session rate'**
  String get photographerPhotoRate;

  /// No description provided for @photographerVideoRate.
  ///
  /// In en, this message translates to:
  /// **'Video rate'**
  String get photographerVideoRate;

  /// No description provided for @photographerTourRate.
  ///
  /// In en, this message translates to:
  /// **'3D tour rate'**
  String get photographerTourRate;

  /// No description provided for @photographerUploadPortfolio.
  ///
  /// In en, this message translates to:
  /// **'Upload certificates or past work'**
  String get photographerUploadPortfolio;

  /// No description provided for @photographerAcceptPolicy.
  ///
  /// In en, this message translates to:
  /// **'I agree to the service and pricing policy'**
  String get photographerAcceptPolicy;

  /// No description provided for @photographerPolicyRequired.
  ///
  /// In en, this message translates to:
  /// **'You must accept the service policy.'**
  String get photographerPolicyRequired;

  /// No description provided for @photographerSubmitJoin.
  ///
  /// In en, this message translates to:
  /// **'Submit application'**
  String get photographerSubmitJoin;

  /// No description provided for @photographerJoinSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Your application is in. Manual review takes up to 24 hours.'**
  String get photographerJoinSubmitted;

  /// No description provided for @photographerStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending review'**
  String get photographerStatusPending;

  /// No description provided for @photographerStatusVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified photographer'**
  String get photographerStatusVerified;

  /// No description provided for @photographerStatusRejected.
  ///
  /// In en, this message translates to:
  /// **'Application declined'**
  String get photographerStatusRejected;

  /// No description provided for @photographerReviewSla.
  ///
  /// In en, this message translates to:
  /// **'Manual review within 24 hours. After approval you appear in the bookable directory.'**
  String get photographerReviewSla;

  /// No description provided for @photographerHubTitle.
  ///
  /// In en, this message translates to:
  /// **'My photographer page'**
  String get photographerHubTitle;

  /// No description provided for @photographerTabIncoming.
  ///
  /// In en, this message translates to:
  /// **'Incoming'**
  String get photographerTabIncoming;

  /// No description provided for @photographerTabActive.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get photographerTabActive;

  /// No description provided for @photographerTabDone.
  ///
  /// In en, this message translates to:
  /// **'Completed sessions'**
  String get photographerTabDone;

  /// No description provided for @photographerTabPortfolio.
  ///
  /// In en, this message translates to:
  /// **'My work'**
  String get photographerTabPortfolio;

  /// No description provided for @photographerTabCalendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get photographerTabCalendar;

  /// No description provided for @photographerBookFlowHint.
  ///
  /// In en, this message translates to:
  /// **'Pick the services; the price comes from the photographer’s rates. After you send, the request lands in their Incoming tab. Accepting within 24 hours agrees the price, then they upload media within the agreed limits.'**
  String get photographerBookFlowHint;

  /// No description provided for @photographerIncomingHint.
  ///
  /// In en, this message translates to:
  /// **'Accepting within 24 hours agrees the quoted price. The request then moves to In progress so you can upload only the photos/video/tour that were requested.'**
  String get photographerIncomingHint;

  /// No description provided for @photographerQuoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm shoot request and price'**
  String get photographerQuoteTitle;

  /// No description provided for @photographerQuoteBody.
  ///
  /// In en, this message translates to:
  /// **'Request to {name}. Quoted price {amount}. The photographer’s accept is the agreement. It appears in their Incoming tab.'**
  String photographerQuoteBody(String name, String amount);

  /// No description provided for @photographerQuoteAgreed.
  ///
  /// In en, this message translates to:
  /// **'Agreed price'**
  String get photographerQuoteAgreed;

  /// No description provided for @photographerDistanceKm.
  ///
  /// In en, this message translates to:
  /// **'{km} km'**
  String photographerDistanceKm(String km);

  /// No description provided for @photographerPhotoLimit.
  ///
  /// In en, this message translates to:
  /// **'This request allows at most {count} photos.'**
  String photographerPhotoLimit(int count);

  /// No description provided for @photographerDeliverCaps.
  ///
  /// In en, this message translates to:
  /// **'Limit: {photos} photos, {videos} video'**
  String photographerDeliverCaps(int photos, int videos);

  /// No description provided for @photographerCalendarEmpty.
  ///
  /// In en, this message translates to:
  /// **'No sessions on this day.'**
  String get photographerCalendarEmpty;

  /// No description provided for @photographerCalendarCapRemaining.
  ///
  /// In en, this message translates to:
  /// **'Today’s accepts: {left} of {cap} left'**
  String photographerCalendarCapRemaining(int left, int cap);

  /// No description provided for @photographerAcceptWindow.
  ///
  /// In en, this message translates to:
  /// **'Time left to respond: {left}'**
  String photographerAcceptWindow(String left);

  /// No description provided for @photographerAcceptWindowExpired.
  ///
  /// In en, this message translates to:
  /// **'The 24-hour window ended and the request was cancelled.'**
  String get photographerAcceptWindowExpired;

  /// No description provided for @photographerPickPhotos.
  ///
  /// In en, this message translates to:
  /// **'Choose photos'**
  String get photographerPickPhotos;

  /// No description provided for @photographerPickVideo.
  ///
  /// In en, this message translates to:
  /// **'Upload video'**
  String get photographerPickVideo;

  /// No description provided for @photographerVideoPicked.
  ///
  /// In en, this message translates to:
  /// **'Video selected'**
  String get photographerVideoPicked;

  /// No description provided for @photographerTourReady.
  ///
  /// In en, this message translates to:
  /// **'Tour is ready'**
  String get photographerTourReady;

  /// No description provided for @photographerDeliverNeedPhotos.
  ///
  /// In en, this message translates to:
  /// **'Add photos before delivering.'**
  String get photographerDeliverNeedPhotos;

  /// No description provided for @photographerDeliverNeedVideo.
  ///
  /// In en, this message translates to:
  /// **'Upload a video because this request includes video.'**
  String get photographerDeliverNeedVideo;

  /// No description provided for @photographerDeliverNeedTour.
  ///
  /// In en, this message translates to:
  /// **'Build the in-app tour because this request includes a 3D tour.'**
  String get photographerDeliverNeedTour;

  /// No description provided for @inAppTourEngineHint.
  ///
  /// In en, this message translates to:
  /// **'Interactive in-app walkthrough (linked photos and hotspots). An external Matterport link remains an extra option — not a built-in cloud engine.'**
  String get inAppTourEngineHint;

  /// No description provided for @inAppTourPanHint.
  ///
  /// In en, this message translates to:
  /// **'Pinch to zoom and pan inside the scene'**
  String get inAppTourPanHint;

  /// No description provided for @photographerSlaOverdue.
  ///
  /// In en, this message translates to:
  /// **'Over 24 hours — review manually'**
  String get photographerSlaOverdue;

  /// No description provided for @photographerSessionsOnDay.
  ///
  /// In en, this message translates to:
  /// **'{count} sessions on this day'**
  String photographerSessionsOnDay(int count);

  /// No description provided for @photographerEmptyTab.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get photographerEmptyTab;

  /// No description provided for @photographerEmptyPortfolio.
  ///
  /// In en, this message translates to:
  /// **'Your gallery appears after the first delivered shoot.'**
  String get photographerEmptyPortfolio;

  /// No description provided for @photographerAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get photographerAccept;

  /// No description provided for @photographerDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get photographerDecline;

  /// No description provided for @photographerDeclineTitle.
  ///
  /// In en, this message translates to:
  /// **'Decline request'**
  String get photographerDeclineTitle;

  /// No description provided for @photographerDeclineReason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get photographerDeclineReason;

  /// No description provided for @photographerDeclineConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm decline'**
  String get photographerDeclineConfirm;

  /// No description provided for @photographerUploadMedia.
  ///
  /// In en, this message translates to:
  /// **'Upload requested media'**
  String get photographerUploadMedia;

  /// No description provided for @photographerDeliverTitle.
  ///
  /// In en, this message translates to:
  /// **'Deliver work'**
  String get photographerDeliverTitle;

  /// No description provided for @photographerDeliverConfirm.
  ///
  /// In en, this message translates to:
  /// **'Deliver work'**
  String get photographerDeliverConfirm;

  /// No description provided for @photographerTechnicalNotes.
  ///
  /// In en, this message translates to:
  /// **'Technical notes (optional)'**
  String get photographerTechnicalNotes;

  /// No description provided for @photographerNeedListing.
  ///
  /// In en, this message translates to:
  /// **'Link this request to a saved listing before uploading media.'**
  String get photographerNeedListing;

  /// No description provided for @photographerDailyCapTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily accept cap'**
  String get photographerDailyCapTitle;

  /// No description provided for @photographerShootFallback.
  ///
  /// In en, this message translates to:
  /// **'Photo shoot'**
  String get photographerShootFallback;

  /// No description provided for @photographerBookTitle.
  ///
  /// In en, this message translates to:
  /// **'Request professional photography'**
  String get photographerBookTitle;

  /// No description provided for @photographerKindPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get photographerKindPhotos;

  /// No description provided for @photographerKindVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get photographerKindVideo;

  /// No description provided for @photographerKindTour.
  ///
  /// In en, this message translates to:
  /// **'3D tour'**
  String get photographerKindTour;

  /// No description provided for @photographerPickSlot.
  ///
  /// In en, this message translates to:
  /// **'Pick date and time'**
  String get photographerPickSlot;

  /// No description provided for @photographerDirectoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No verified photographers yet. You can join from My desk.'**
  String get photographerDirectoryEmpty;

  /// No description provided for @photographerSendRequest.
  ///
  /// In en, this message translates to:
  /// **'Send request'**
  String get photographerSendRequest;

  /// No description provided for @photographerRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Request sent to the photographer’s Incoming tab. They have 24 hours to accept or decline. Accepting agrees the quoted price, then they upload within the agreed limits.'**
  String get photographerRequestSent;

  /// No description provided for @photographerQueuedUntilPublish.
  ///
  /// In en, this message translates to:
  /// **'Photographer choice saved locally and sent after the listing is saved.'**
  String get photographerQueuedUntilPublish;

  /// No description provided for @photographerCertifiedTooltip.
  ///
  /// In en, this message translates to:
  /// **'Certified photographer'**
  String get photographerCertifiedTooltip;

  /// No description provided for @photographerOpenWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Open my photographer page'**
  String get photographerOpenWorkspace;

  /// No description provided for @photographerJoinCta.
  ///
  /// In en, this message translates to:
  /// **'Join as photographer'**
  String get photographerJoinCta;

  /// No description provided for @photographerRequestFromMedia.
  ///
  /// In en, this message translates to:
  /// **'Request professional photography'**
  String get photographerRequestFromMedia;

  /// No description provided for @inAppTourBuild.
  ///
  /// In en, this message translates to:
  /// **'Build in-app tour'**
  String get inAppTourBuild;

  /// No description provided for @inAppTourBadge.
  ///
  /// In en, this message translates to:
  /// **'Virtual tour'**
  String get inAppTourBadge;

  /// No description provided for @inAppTourOpen.
  ///
  /// In en, this message translates to:
  /// **'Open virtual tour'**
  String get inAppTourOpen;

  /// No description provided for @developerComingSoonTitle.
  ///
  /// In en, this message translates to:
  /// **'Property developer'**
  String get developerComingSoonTitle;

  /// No description provided for @developerComingSoonBody.
  ///
  /// In en, this message translates to:
  /// **'The developer service is being built and will be available soon. You can register your interest and we will notify you at launch.'**
  String get developerComingSoonBody;

  /// No description provided for @developerInterestName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get developerInterestName;

  /// No description provided for @developerInterestEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get developerInterestEmail;

  /// No description provided for @developerInterestType.
  ///
  /// In en, this message translates to:
  /// **'Development type needed'**
  String get developerInterestType;

  /// No description provided for @developerInterestSubmit.
  ///
  /// In en, this message translates to:
  /// **'Register interest'**
  String get developerInterestSubmit;

  /// No description provided for @developerInterestSkip.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get developerInterestSkip;

  /// No description provided for @developerInterestSaved.
  ///
  /// In en, this message translates to:
  /// **'We saved your interest and will notify you at launch.'**
  String get developerInterestSaved;

  /// No description provided for @listingInventoryCapHint.
  ///
  /// In en, this message translates to:
  /// **'Listings and requests: {used} of {max}'**
  String listingInventoryCapHint(int used, int max);

  /// No description provided for @completedDealsFilter30d.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get completedDealsFilter30d;

  /// No description provided for @completedDealsFilterYear.
  ///
  /// In en, this message translates to:
  /// **'Last year'**
  String get completedDealsFilterYear;

  /// No description provided for @completedDealsFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get completedDealsFilterAll;

  /// No description provided for @regaManualEntry.
  ///
  /// In en, this message translates to:
  /// **'Full manual entry'**
  String get regaManualEntry;

  /// No description provided for @regaManualLicenseNo.
  ///
  /// In en, this message translates to:
  /// **'License number'**
  String get regaManualLicenseNo;

  /// No description provided for @regaManualDeedNo.
  ///
  /// In en, this message translates to:
  /// **'Deed number'**
  String get regaManualDeedNo;

  /// No description provided for @regaManualPrice.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get regaManualPrice;

  /// No description provided for @regaManualCity.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get regaManualCity;

  /// No description provided for @regaManualExpiry.
  ///
  /// In en, this message translates to:
  /// **'Expiry date'**
  String get regaManualExpiry;

  /// No description provided for @regaManualImage.
  ///
  /// In en, this message translates to:
  /// **'License image (evidence)'**
  String get regaManualImage;

  /// No description provided for @regaManualSave.
  ///
  /// In en, this message translates to:
  /// **'Use manual entry'**
  String get regaManualSave;

  /// No description provided for @photographerDialogCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get photographerDialogCancel;

  /// No description provided for @photographerDialogSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get photographerDialogSave;

  /// No description provided for @photographerFilesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} files'**
  String photographerFilesCount(int count);

  /// No description provided for @photographerRatingLine.
  ///
  /// In en, this message translates to:
  /// **'{avg} ({count})'**
  String photographerRatingLine(String avg, int count);

  /// No description provided for @opsDeskTabPhotographers.
  ///
  /// In en, this message translates to:
  /// **'Photographers'**
  String get opsDeskTabPhotographers;

  /// No description provided for @plusInventoryTooltip.
  ///
  /// In en, this message translates to:
  /// **'{remaining} of {max} remaining'**
  String plusInventoryTooltip(int remaining, int max);

  /// No description provided for @listingOfficialRegaBenchTitle.
  ///
  /// In en, this message translates to:
  /// **'REGA official benchmark'**
  String get listingOfficialRegaBenchTitle;

  /// No description provided for @listingOfficialRegaBenchSale.
  ///
  /// In en, this message translates to:
  /// **'Average price per m² in {city} for {type}: {amount} — from {deals} deals ({period}). A market reference, not a required listing price.'**
  String listingOfficialRegaBenchSale(
      String city, String type, String amount, int deals, String period);

  /// No description provided for @listingOfficialRegaBenchRent.
  ///
  /// In en, this message translates to:
  /// **'Average rent in {city} for {type}: {amount} — from {deals} contracts ({period}). A market reference, not a required listing price.'**
  String listingOfficialRegaBenchRent(
      String city, String type, String amount, int deals, String period);

  /// No description provided for @marketInsightsOfficialRegaTitle.
  ///
  /// In en, this message translates to:
  /// **'REGA sale indicators'**
  String get marketInsightsOfficialRegaTitle;

  /// No description provided for @marketInsightsOfficialRegaHint.
  ///
  /// In en, this message translates to:
  /// **'Average price per m² from the latest REGA open bulletin. It does not replace your platform data.'**
  String get marketInsightsOfficialRegaHint;

  /// No description provided for @formExitKeepEditing.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get formExitKeepEditing;

  /// No description provided for @formExitSaveDraft.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get formExitSaveDraft;

  /// No description provided for @formExitLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get formExitLeave;

  /// No description provided for @formExitBody.
  ///
  /// In en, this message translates to:
  /// **'This is not published yet. Continue from where you are, save a draft on this device for this session only, or leave and clear the fields.'**
  String get formExitBody;

  /// No description provided for @formExitDraftSaved.
  ///
  /// In en, this message translates to:
  /// **'Your entries were saved as a draft on this device. You can return to the last field you filled and continue. This draft is not stored in the database and is removed when you sign out. Choosing Leave later will clear every field.'**
  String get formExitDraftSaved;

  /// No description provided for @formExitLeaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave and clear the fields?'**
  String get formExitLeaveTitle;

  /// No description provided for @formExitLeaveBody.
  ///
  /// In en, this message translates to:
  /// **'Everything you typed will be cleared. Nothing will be kept as a draft on this device. Confirm to leave, or cancel to stay where you are.'**
  String get formExitLeaveBody;

  /// No description provided for @formExitConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get formExitConfirm;

  /// No description provided for @formExitCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get formExitCancel;

  /// No description provided for @formExitCleared.
  ///
  /// In en, this message translates to:
  /// **'All entered data was cleared. Nothing was saved as a draft.'**
  String get formExitCleared;

  /// No description provided for @deedDuplicateActive.
  ///
  /// In en, this message translates to:
  /// **'This deed number is already on an active sale, auction, or investment listing whose deal is not finished. A second listing with the same deed is not allowed until that deal is closed.'**
  String get deedDuplicateActive;

  /// No description provided for @deedNumberGovHint.
  ///
  /// In en, this message translates to:
  /// **'The number is checked in-app during development. Later it will be verified with government deed data, and the project operations desk will be notified on conflicts.'**
  String get deedNumberGovHint;

  /// No description provided for @capsLockOn.
  ///
  /// In en, this message translates to:
  /// **'Caps Lock is ON'**
  String get capsLockOn;

  /// No description provided for @paymentSubscriptionActivated.
  ///
  /// In en, this message translates to:
  /// **'Payment completed and the subscription is active.'**
  String get paymentSubscriptionActivated;

  /// No description provided for @paymentConfirming.
  ///
  /// In en, this message translates to:
  /// **'Payment received. Confirming the transaction.'**
  String get paymentConfirming;

  /// No description provided for @paymentNotActivated.
  ///
  /// In en, this message translates to:
  /// **'Payment could not be completed, and the subscription was not activated.'**
  String get paymentNotActivated;

  /// No description provided for @planNotForAccount.
  ///
  /// In en, this message translates to:
  /// **'This plan is not available for your account type.'**
  String get planNotForAccount;

  /// No description provided for @paymentAmountMismatchReview.
  ///
  /// In en, this message translates to:
  /// **'The amount did not match. The payment was stopped for review.'**
  String get paymentAmountMismatchReview;

  /// No description provided for @paymentTrustNoCardStore.
  ///
  /// In en, this message translates to:
  /// **'We do not store the card number or CVV. The subscription is activated only after the payment gateway confirms, not when you tap Pay.'**
  String get paymentTrustNoCardStore;

  /// No description provided for @invoiceVatInclusiveNote.
  ///
  /// In en, this message translates to:
  /// **'The amount shown is the final total. Catalog prices are VAT-inclusive when tax applies; no extra tax is added automatically.'**
  String get invoiceVatInclusiveNote;

  /// No description provided for @invoiceBreakdownSubtotal.
  ///
  /// In en, this message translates to:
  /// **'Before discount'**
  String get invoiceBreakdownSubtotal;

  /// No description provided for @invoiceBreakdownDiscount.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get invoiceBreakdownDiscount;

  /// No description provided for @invoiceOfficialNo.
  ///
  /// In en, this message translates to:
  /// **'Invoice number'**
  String get invoiceOfficialNo;

  /// No description provided for @invoiceHideFromLedger.
  ///
  /// In en, this message translates to:
  /// **'Hide from ledger'**
  String get invoiceHideFromLedger;

  /// No description provided for @invoiceHideConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Hide this invoice from your ledger?'**
  String get invoiceHideConfirmTitle;

  /// No description provided for @invoiceHideConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This does not delete the financial record. It stays in the database for audit and is only hidden from your list.'**
  String get invoiceHideConfirmBody;

  /// No description provided for @invoiceHiddenOk.
  ///
  /// In en, this message translates to:
  /// **'Hidden from ledger'**
  String get invoiceHiddenOk;

  /// No description provided for @invoicePaymentReference.
  ///
  /// In en, this message translates to:
  /// **'Payment reference'**
  String get invoicePaymentReference;

  /// No description provided for @invoiceTechnicalSection.
  ///
  /// In en, this message translates to:
  /// **'Technical details'**
  String get invoiceTechnicalSection;

  /// No description provided for @invoiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get invoiceUnavailable;

  /// No description provided for @invoiceFeesLine.
  ///
  /// In en, this message translates to:
  /// **'Fees'**
  String get invoiceFeesLine;

  /// No description provided for @invoiceVatLine.
  ///
  /// In en, this message translates to:
  /// **'VAT'**
  String get invoiceVatLine;

  /// No description provided for @invoicePeriodStart.
  ///
  /// In en, this message translates to:
  /// **'Subscription start'**
  String get invoicePeriodStart;

  /// No description provided for @invoiceSubscriptionEnd.
  ///
  /// In en, this message translates to:
  /// **'Subscription end'**
  String get invoiceSubscriptionEnd;

  /// No description provided for @invoiceCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get invoiceCurrency;

  /// No description provided for @invoiceQrHint.
  ///
  /// In en, this message translates to:
  /// **'Scan to verify the official invoice number.'**
  String get invoiceQrHint;

  /// No description provided for @invoiceViewDetails.
  ///
  /// In en, this message translates to:
  /// **'View invoice'**
  String get invoiceViewDetails;

  /// No description provided for @invoiceStatusPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get invoiceStatusPaid;
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
