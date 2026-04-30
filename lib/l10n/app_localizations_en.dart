// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Motawoq Real Estate';

  @override
  String get welcomeTitle => 'Welcome';

  @override
  String get welcomeTrustedAqar => 'Welcome to Motawoq Real Estate';

  @override
  String get signInToContinue => 'Sign in to continue';

  @override
  String get userSignIn => 'Sign In';

  @override
  String get allFieldsRequired => 'Please fill in all fields';

  @override
  String get usernameMustBe10Digits => 'Username must be 10 digits';

  @override
  String get passwordTooShort => 'Password is too short';

  @override
  String get invalidCredentials => 'Invalid credentials';

  @override
  String get rememberMe => 'Remind me';

  @override
  String get quickLogin => 'Quick login';

  @override
  String get quickLoginSubtitle =>
      'Unlock with device PIN, fingerprint, or Face ID if you enabled it in Settings.';

  @override
  String get forgotUsernameOrPassword => 'Forgot username or password?';

  @override
  String get theme => 'Appearance';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeSystem => 'System';

  @override
  String get language => 'Language';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageEnglish => 'English';

  @override
  String get settings => 'Settings';

  @override
  String get settingsAppearanceLanguageSection => 'Appearance & language';

  @override
  String get settingsAppearanceHubSubtitle =>
      'Language, dark mode, and accent in one place.';

  @override
  String get settingsHapticsTitle => 'Haptic feedback';

  @override
  String get settingsHapticsSubtitle =>
      'Light vibration on some interactions (mobile only).';

  @override
  String get settingsDarkModeSubtitle => 'Use dark colors across the app';

  @override
  String get settingsInAppNotificationSoundTitle => 'In-app alert sound';

  @override
  String get settingsInAppNotificationSoundSubtitle =>
      'Web: in-app chime from app assets. Phone/tablet: short system feedback (haptic + system sound) so it does not fight your notification channel ringtones. Foreground FCM stays silent; background uses system notifications. OTP codes: web plays the app chime plus a banner; phone uses the OTP notification channel (your system sound/vibration).';

  @override
  String get settingsChatMessageSoundTitle => 'Chat message sound';

  @override
  String get settingsChatMessageSoundSubtitle =>
      'Web: in-app chime from assets. Phone/tablet: light haptic + system click (no bundled WAV). Separate from in-app banner alerts and from push notification sounds.';

  @override
  String get legalTermsCoachTitle => 'Terms & privacy';

  @override
  String get legalTermsCoachBody =>
      'You can review the terms and privacy policy anytime in Settings. Acceptance may still be required at sign-in.';

  @override
  String get legalTermsCoachOk => 'OK';

  @override
  String get fieldGroupCredentialsTitle => 'Sign-in details';

  @override
  String get fieldGroupCredentialsSubtitle =>
      'Your distinguished number and password';

  @override
  String get fieldGroupOtpTitle => 'Verification code';

  @override
  String get fieldGroupOtpSubtitle => 'Enter the digits sent to you';

  @override
  String get fieldGroupGateTitle => 'How do you want to continue?';

  @override
  String get fieldGroupVerificationFalTitle => 'Broker license & contact';

  @override
  String get fieldGroupVerificationFalSubtitle =>
      'FAL verification and broker details for this request.';

  @override
  String get fieldGroupVerificationOrgTitle =>
      'Organization & commercial register';

  @override
  String get fieldGroupVerificationOrgSubtitle =>
      'Office name and unified CR where applicable.';

  @override
  String get fieldGroupVerificationOptionalLicenseTitle => 'License reference';

  @override
  String get fieldGroupVerificationOptionalLicenseSubtitle =>
      'If you have a license number, enter it here.';

  @override
  String get fieldGroupVerificationMoreTitle => 'Team & notes';

  @override
  String get fieldGroupVerificationMoreSubtitle =>
      'Optional team join code and a message for reviewers.';

  @override
  String get fieldGroupVerificationDocumentsTitle => 'Documents';

  @override
  String get fieldGroupVerificationDocumentsSubtitle =>
      'Upload PDF or image files for verification.';

  @override
  String get fieldGroupFalRenewalTitle => 'License renewal';

  @override
  String get fieldGroupFalRenewalSubtitle =>
      'Enter your FAL number to verify with REGA.';

  @override
  String get fieldGroupListingRequestTitle => 'Listing request';

  @override
  String get fieldGroupListingRequestSubtitle =>
      'Property title, city, and map coordinates.';

  @override
  String get fieldGroupListingRequestSubmit => 'Send request';

  @override
  String get listingRequestFieldTitleLabel => 'Property title';

  @override
  String get listingRequestFieldCityLabel => 'City';

  @override
  String get listingRequestFieldLatLabel => 'Latitude';

  @override
  String get listingRequestFieldLngLabel => 'Longitude';

  @override
  String get mapPickerHuaweiNoGmsBanner =>
      'Google Maps may not load on some Huawei/Honor devices without Google services. Use search or confirm coordinates manually.';

  @override
  String get mapPickerMapLoadStalledBanner =>
      'The map is slow or did not finish loading. Use city search, type latitude/longitude, or open Google Maps externally.';

  @override
  String get mapPickerOpenExternalMaps => 'Open in Maps';

  @override
  String get welcomeDashboardBannerTitle => 'Welcome to Motawoq Real Estate';

  @override
  String get welcomeDashboardBannerBody =>
      'Browse listings on Home, manage your ads under My Ads, and open Settings at the top. You can turn off alert sounds in Settings.';

  @override
  String get welcomeDashboardBannerButton => 'Got it';

  @override
  String get usernameHint10Digits => 'Distinguished number (10 digits)';

  @override
  String get loginUsernameFieldHelper =>
      'ID/Iqama, FAL license, or unified national no. 700… (10 digits)';

  @override
  String get loginIdentifierFieldLabel =>
      'National ID, unified CR, or FAL license — 10 digits';

  @override
  String get loginPasswordFieldLabel => 'Enter your password';

  @override
  String get loginPasswordFieldShortLabel => 'Password';

  @override
  String get passwordHint => 'Password';

  @override
  String get passwordArabicKeyboardHint =>
      'Use English letters or numbers for your password. Switch keyboard layout if needed.';

  @override
  String get rightPanelTitle => 'Your gateway to documented property';

  @override
  String get rightPanelSubtitle =>
      'Verify licences, message securely, and follow listings in one experience aligned with Mawthuq.';

  @override
  String get noEnabledAds => 'No enabled ads right now';

  @override
  String get accountLockedTitle => 'Account locked';

  @override
  String get accountLockedBody =>
      'Your account is locked due to multiple attempts. Use recovery.';

  @override
  String get recover => 'Recover';

  @override
  String get verifyTitle => 'Verification';

  @override
  String get otpTitle => 'Verification';

  @override
  String get verifySubtitle => 'Enter the verification code';

  @override
  String get confirm => 'Confirm';

  @override
  String get clear => 'Clear';

  @override
  String get securityAlert => 'Security alert';

  @override
  String get verifyTimeout => 'Verification timed out';

  @override
  String get invalidCode => 'Invalid verification code';

  @override
  String get accountLocked => 'Account locked';

  @override
  String get notificationDefaultTitle => 'Notification';

  @override
  String get listingStagesTitle => 'Listing stages';

  @override
  String get marketingStagesTitle => 'Marketing stages';

  @override
  String get marketingStepInvite => 'Invite';

  @override
  String get marketingStepOffer => 'Offer';

  @override
  String get marketingStepContract => 'Contract';

  @override
  String get marketingStepPermit => 'Permit';

  @override
  String get marketingStepPublish => 'Publish';

  @override
  String ownerOfferRejectionReason(Object reason) {
    return 'Offer rejection/counter reason: $reason';
  }

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get noNewNotifications => 'No new notifications';

  @override
  String get closeLabel => 'Close';

  @override
  String get retryLabel => 'Retry';

  @override
  String get offlineNoInternetTitle => 'No internet connection';

  @override
  String get offlineNoInternetBody =>
      'The app cannot start without internet. Enable internet then retry.';

  @override
  String get loginRequiredDialogTitle => 'Login required';

  @override
  String get loginRequiredDialogMessage =>
      'You need to log in to access this feature. Would you like to log in now?';

  @override
  String get laterLabel => 'Later';

  @override
  String get loginToManageListingsBody => 'Log in to manage your listings';

  @override
  String get preparingMarketingTabsTitle => 'Preparing marketing tabs';

  @override
  String get preparingListingsTabsTitle => 'Preparing listings tabs';

  @override
  String get ifContinuesTapRetry => 'If this continues, tap retry.';

  @override
  String get myAdsOwnerTabWaitingMediator => '🤝 Awaiting marketers';

  @override
  String get myAdsOwnerTabAwaitContract => '📝 Contracting';

  @override
  String get myAdsOwnerTabPublishedHome => '🏡 Published';

  @override
  String get myAdsEmptyWaitingMediator => 'No listings awaiting marketers';

  @override
  String get myAdsEmptyAwaitContract => 'No listings in contracting';

  @override
  String get myAdsEmptyPublishedHome => 'No published listings';

  @override
  String get marketerTabInvites => '🏢 Real estate market';

  @override
  String get marketerTabAwaitingOwner => '⏳ Awaiting owner · contracting';

  @override
  String get marketerTabMyOffers => '💼 Offers';

  @override
  String get marketerTabContracts => '📄 Contracts';

  @override
  String get marketerTabPermits => '✅ Permits';

  @override
  String get marketerTabPublished => '🚀 Published';

  @override
  String get marketerEmptyInvites => 'Nothing in the market yet';

  @override
  String get marketerBtnPropertyListingDetails => 'Listing details';

  @override
  String get ownerBtnRealEstateOffers => 'Real estate offers';

  @override
  String get marketerEmptyOffers => 'No offers';

  @override
  String get marketerEmptyContracts => 'No contracts';

  @override
  String get marketerEmptyPermits => 'No permits';

  @override
  String get marketerEmptyPublished => 'No published';

  @override
  String get listingsControlHubTitle => 'Listings Control Hub';

  @override
  String get marketerFullScenarioGuideTooltip =>
      'Full path: invite → owner decision → contract → REGA permit → publish — and notifications';

  @override
  String get marketerFullScenarioSheetTitle => 'Professional marketing path';

  @override
  String get marketerFullScenarioOpenInbox => 'Open notification inbox';

  @override
  String get marketerFullScenarioUnderstood => 'Done';

  @override
  String get ownerFullScenarioGuideTooltip =>
      'Owner path: offers → contract → REGA permit → publish — and notifications';

  @override
  String get ownerFullScenarioSheetTitle => 'Your listing marketing path';

  @override
  String get scenarioOpenRequestStatusButton => 'Open request status';

  @override
  String get workflowGuideDialogButton => 'Full workflow guide';

  @override
  String get workflowGuideSheetIntro =>
      'Follow the numbered steps. Your notifications link to each stage so nothing is missed.';

  @override
  String get listingRequestStatusWorkflowTooltip =>
      'Open the step-by-step guide for this request';

  @override
  String get workflowGuideHubSubtitle =>
      'Tip: tap the route icon next to the title for the full step-by-step path and notification shortcuts.';

  @override
  String get navHome => 'Home';

  @override
  String get navMyAds => 'My page';

  @override
  String get navFavorites => 'Favorites';

  @override
  String get navAdd => 'Post ad';

  @override
  String get navMyDesk => 'My desk';

  @override
  String get navMyDeskPipelineBadgeTooltip =>
      'My desk: stats, team, and work management based on your account type.';

  @override
  String get navCart => 'My deals';

  @override
  String get navReservations => 'Reserved properties';

  @override
  String get navChat => 'Chat';

  @override
  String get navMySubmissions => 'Requests/Listings';

  @override
  String get navSupport => 'Technical support';

  @override
  String get communicationHubTitle => 'Notifications & chats';

  @override
  String get communicationHubNotificationsTab => 'Notifications';

  @override
  String get communicationHubChatsTab => 'Chats';

  @override
  String get openChatInboxButton => 'Open chat inbox';

  @override
  String get communicationHubChatsHint =>
      'All conversation types (property, reservation, market request, support…) are handled in the chat inbox.';

  @override
  String get supportHubTechnicalTab => 'Help center';

  @override
  String get supportHubAdminTab => 'Administration';

  @override
  String get supportHubTicketsTab => 'Tickets';

  @override
  String get supportHubAdminSoon =>
      'Coming soon: contact administration and official requests.';

  @override
  String get supportHubTicketsSoon =>
      'Coming soon: create and track support tickets with administration.';

  @override
  String get settingsSupportMovedHint =>
      'Technical support and admin contact are now in the bottom Technical support tab.';

  @override
  String get mySubmissionsSectionListings => 'My listings';

  @override
  String get mySubmissionsSectionRequests => 'Market requests';

  @override
  String get mySubmissionsEmpty =>
      'You have no published listings or market requests yet.';

  @override
  String get cartMarketOffersSectionTitle => 'Offers on my requests';

  @override
  String get cartMarketOffersEmptyHint =>
      'When someone submits an offer on your market request, it appears here for follow-up.';

  @override
  String get marketPropertySubmitSuccessTitle => 'Thank you, partner';

  @override
  String get marketPropertySubmitSuccessBody =>
      'Your property request was submitted successfully. It will appear to interested parties according to our policies. You can track it under «Requests/Listings».';

  @override
  String get marketPropertySubmitGoHome => 'Back to Home';

  @override
  String get marketPropertySubmitAnother => 'Another property request';

  @override
  String get supportLabel => 'Support';

  @override
  String get logoutLabel => 'Logout';

  @override
  String get settingsLabel => 'Settings';

  @override
  String get loginNowLabel => 'Login Now';

  @override
  String get noInternetConnectionTitle => 'No Internet Connection';

  @override
  String get ensureInternetThenRetry => 'Make sure you are online, then retry.';

  @override
  String get offlineGlobalOverlayHint =>
      'Your session stays on this device. When the connection returns, the app will detect it automatically — or tap Retry. You will not be sent back to login unless you sign out.';

  @override
  String get refreshLabel => 'Refresh';

  @override
  String get failedToLoadAds => 'Failed to load ads';

  @override
  String get failedToLoadCart => 'Failed to load your deals';

  @override
  String get failedToLoadReservations => 'Failed to load reservations';

  @override
  String get changePasswordTitle => 'Change password';

  @override
  String get currentPasswordLabel => 'Current password';

  @override
  String get newPasswordLabel => 'New password';

  @override
  String get confirmNewPasswordLabel => 'Confirm new password';

  @override
  String get savePassword => 'Update password';

  @override
  String get passwordChangedSuccess => 'Password updated successfully';

  @override
  String get changePasswordFailed => 'Could not change password';

  @override
  String get wrongCurrentPassword => 'Current password is incorrect';

  @override
  String get profileChangePhoto => 'Change profile photo';

  @override
  String get profilePhotoUploading => 'Uploading…';

  @override
  String get profilePhotoUpdated => 'Profile photo updated';

  @override
  String get profilePhotoFailed => 'Could not update photo';

  @override
  String get fullNameLabel => 'Full name';

  @override
  String get accountCategoryLabel => 'Account category';

  @override
  String get permissionRoleLabel => 'Role / permission';

  @override
  String get changeQuickPin => 'Change quick PIN';

  @override
  String get newPinLabel => 'New PIN (6 digits)';

  @override
  String get confirmPinLabel => 'Confirm PIN';

  @override
  String get pinUpdated => 'PIN updated';

  @override
  String get pinMismatch => 'PINs do not match';

  @override
  String get biometricNotAvailable =>
      'Biometrics are not available on this device';

  @override
  String get fastLoginAfterLoginHint =>
      'After signing in, enable quick login in Settings (mobile only).';

  @override
  String get fastLoginOfferTitle => 'Faster sign-in next time?';

  @override
  String get fastLoginOfferBody =>
      'Enable a quick PIN or biometrics (if your device supports it). You can change this anytime in Settings.';

  @override
  String get fastLoginOfferOpenSettings => 'Open Settings';

  @override
  String get fastLoginOfferBiometric => 'Use biometrics';

  @override
  String get fastLoginOfferNotNow => 'No thanks';

  @override
  String get fastLoginOfferRemindLater => 'Remind me later';

  @override
  String get legalTermsTitle => 'Terms and conditions';

  @override
  String get legalAccept => 'I agree';

  @override
  String get legalDecline => 'Decline';

  @override
  String get legalDeclineTitle => 'Cannot continue';

  @override
  String get legalDeclineBody => 'You must accept the terms to use the app.';

  @override
  String get legalTermsFallbackBody =>
      'Terms and privacy text could not be loaded from the server. By continuing you agree to use Motawoq Real Estate in accordance with applicable laws in the Kingdom of Saudi Arabia, including personal data protection rules where they apply, to provide accurate information, and to use listings and messaging responsibly. For the full text, contact support or try again later.';

  @override
  String get permissionsGateTitle => 'Before we start';

  @override
  String get permissionsGateSubtitle =>
      'We ask for permissions in a standard order: notifications (chat and updates), location (map and nearby accuracy), then photos and camera (listing images). You can skip now and enable later from Settings or when the app prompts you.';

  @override
  String get permissionsGateWebSubtitle =>
      'On the web, your browser will request notifications and location when needed. Location improves maps and nearby sorting; gallery and camera use the browser or file picker.';

  @override
  String get permissionsGateContinueAllow => 'Continue & allow';

  @override
  String get permissionsGateNotNow => 'Not now';

  @override
  String get permissionsGateOpenSettings => 'Open settings';

  @override
  String get permissionsGateNotificationsTitle => 'Notifications';

  @override
  String get permissionsGateNotificationsDesc =>
      'Alerts for chat, bookings, and listing activity.';

  @override
  String get permissionsGateLocationTitle => 'Location';

  @override
  String get permissionsGateLocationDesc =>
      'Pick property locations on the map and improve nearby accuracy.';

  @override
  String get permissionsGatePhotosTitle => 'Photos / gallery';

  @override
  String get permissionsGatePhotosDesc =>
      'Attach images to listings and uploads.';

  @override
  String get permissionsGateCameraTitle => 'Camera';

  @override
  String get permissionsGateCameraDesc => 'Take photos for listings directly.';

  @override
  String get permissionsGateDesktopNote =>
      'On desktop, images are usually chosen from files; mobile-style gallery permissions may not appear.';

  @override
  String get permissionRationalePhotosTitle => 'Photos access needed';

  @override
  String get permissionRationalePhotosBody =>
      'Photo access is turned off. Open system settings to allow gallery access, then try again.';

  @override
  String get permissionRationaleCameraTitle => 'Camera access needed';

  @override
  String get permissionRationaleCameraBody =>
      'Camera access is turned off. Open system settings to allow the camera, then try again.';

  @override
  String get permissionRationaleNotificationsTitle => 'Notifications off';

  @override
  String get permissionRationaleNotificationsBody =>
      'Notifications are disabled for this app. Turn them on in system settings to receive alerts.';

  @override
  String get permissionRationaleLocationTitle => 'Location access needed';

  @override
  String get permissionRationaleLocationBody =>
      'Location is off or denied. Open system settings to allow location, then use “My location” again.';

  @override
  String get deviceLimitTitle => 'Device limit';

  @override
  String get deviceLimitBody =>
      'This account already has two registered devices. Remove one from Settings (or ask your organization owner) before signing in here.';

  @override
  String get orgMandatoryPasswordHint =>
      'For security, you must set a new password before continuing (use the temporary password you were given as the current password).';

  @override
  String get orgTeamManagement => 'Team management';

  @override
  String get orgMonitoring => 'My desk — team monitoring';

  @override
  String get orgInviteMember => 'Invite team member';

  @override
  String get orgNationalIdHint =>
      'Unique Business ID (700…) — tap field to copy';

  @override
  String get orgTempPasswordHint => 'Temporary password (min 8 characters)';

  @override
  String get orgPermissionsJsonHint => 'Permissions (JSON object, optional)';

  @override
  String orgSeatUsage(int used, int limit) {
    return 'Seats: $used / $limit';
  }

  @override
  String get orgInviteSend => 'Create member';

  @override
  String get orgInviteSuccess => 'Member created or linked successfully';

  @override
  String get orgInviteFailed => 'Could not invite member';

  @override
  String get orgMembersTitle => 'Members';

  @override
  String get orgActivityTitle => 'Recent activity';

  @override
  String get orgDevicesTitle => 'Trusted devices';

  @override
  String get orgNoOrg => 'No organization record';

  @override
  String get orgOwnerOnly => 'Only the organization owner can open this';

  @override
  String get orgRemoveDevice => 'Revoke device';

  @override
  String get orgDeviceRevoked => 'Device revoked';

  @override
  String get orgStatsLogins => 'Logins (sample)';

  @override
  String get orgStatsListings => 'Listing actions (sample)';

  @override
  String get orgMonitorRoleOwner =>
      'You see the full team activity log (organization owner).';

  @override
  String get orgMonitorRoleMember =>
      'You see only actions performed with your account.';

  @override
  String get orgMonitorChartDaily => 'Events per day (last 14 days)';

  @override
  String get orgMonitorChartActions => 'Most frequent actions';

  @override
  String get orgMonitorChartMembers => 'Events by team member';

  @override
  String get orgMonitorEngagementNote =>
      'Engagement scores are derived from logged actions in the app (not external ratings).';

  @override
  String get orgMonitorEmptyCharts => 'Not enough activity yet for charts.';

  @override
  String get orgMonitorTotalEvents => 'Total events';

  @override
  String get orgMonitorEngagementScore => 'Engagement (estimated)';

  @override
  String get postAuthChecking => 'Checking account…';

  @override
  String get loginIdentifierFieldHint =>
      'ID/Iqama, FAL license, or unified national no. 700… (10 digits)';

  @override
  String get loginEnterIdentifierFirst =>
      'Enter 10 digits: ID, Iqama, or FAL license number.';

  @override
  String get loginNoAccountLinkedIdentifier =>
      'No account is linked to this number.';

  @override
  String get loginIdentifierMustBe10 => 'Enter exactly 10 digits.';

  @override
  String get verScreenTitleMarketer => 'Marketer verification request';

  @override
  String get verScreenTitleOffice => 'Real estate office verification';

  @override
  String get verScreenTitleInstitution =>
      'Real estate institution verification';

  @override
  String get verScreenTitleCompany => 'Real estate company verification';

  @override
  String get verFalLicenseLabel => 'FAL license number';

  @override
  String get verFalLicenseHint => 'Official 10-digit FAL license from REGA.';

  @override
  String get verFalLookupButton => 'Verify license (REGA)';

  @override
  String get verFalLookupBusy => 'Looking up…';

  @override
  String get verBrokerEmailLabel => 'Email';

  @override
  String get verBrokerEmailHint => 'Contact email used for verification.';

  @override
  String get verBrokerNameLabel => 'Broker name';

  @override
  String get verBrokerNameHint =>
      'As on the license (Arabic only in this field).';

  @override
  String get verBrokerPhoneHint => 'Mobile number (Western digits).';

  @override
  String get verPhoneLabel => 'Phone';

  @override
  String get verCityLabel => 'City';

  @override
  String get verCityHint => 'Arabic only.';

  @override
  String get verDistrictLabel => 'District';

  @override
  String get verDistrictHint => 'Arabic only.';

  @override
  String get verRegionLabel => 'Region';

  @override
  String get verRegionHint => 'Arabic only.';

  @override
  String get verLicenseTypeLabel => 'License type';

  @override
  String get verLicenseStatusLabel => 'License status';

  @override
  String get verOfficeNameLabel => 'Entity name';

  @override
  String get verOfficeNameHint =>
      'Official name as on the registry or license.';

  @override
  String get verCrLabel => 'Commercial registration (CR)';

  @override
  String get verCrHint => 'Digits as shown on documents.';

  @override
  String get verUnifiedCrLabel => 'Unified CR number (10 digits)';

  @override
  String get verUnifiedCrHint =>
      'Unified commercial registration from MC (often starts with 700…).';

  @override
  String get verMcLookupButton => 'Lookup CR (Ministry of Commerce)';

  @override
  String get verMcRegistryNotActive =>
      'This commercial registration is not active (e.g. struck off). You cannot continue.';

  @override
  String get verMcLookupSuccess => 'Commercial registry data loaded.';

  @override
  String get verMcPleaseLookup =>
      'Enter the 10-digit unified CR and tap lookup before submitting.';

  @override
  String get verFalDataLoadedSnackbar =>
      'License data loaded. Review the fields and complete the form.';

  @override
  String get verTeamSwitchTitle =>
      'Are you part of a real estate organization team?';

  @override
  String get verTeamSwitchSubtitle =>
      'If yes, enter the confidential 10-digit code from your organization manager.';

  @override
  String get verTeamCodeHint => 'Team join code (10 digits).';

  @override
  String get verTeamPendingNote =>
      'After submit, your manager will approve and assign permissions.';

  @override
  String get verNoteHint => 'Optional notes for reviewers.';

  @override
  String get badgeVerifiedShort => 'Verified';

  @override
  String get latinCharsNotAllowedSnackbar =>
      'English letters are not allowed in this field.';

  @override
  String get falRenewalTitle => 'Renew FAL license';

  @override
  String get falRenewalBody =>
      'Your FAL license has expired or must be updated. Enter the new license number and tap verify to refresh data from REGA.';

  @override
  String get falRenewalSubmit => 'Verify and update';

  @override
  String get falRenewalExpired => 'This license is expired.';

  @override
  String get falRenewalInvalid => 'Could not verify the license.';

  @override
  String get falExpiryBannerWeek =>
      'Reminder: your FAL license expires within a week — renew to avoid account suspension.';

  @override
  String get profileSignatureTitle => 'Complete signature';

  @override
  String get profileSignatureBody =>
      'Upload a clear signature image (PNG or JPG) on a light background.';

  @override
  String get profileSignaturePick => 'Choose signature image';

  @override
  String get profileSignatureNoBytes => 'Could not read the file.';

  @override
  String get profileSignatureTabDraw => 'Draw';

  @override
  String get profileSignatureTabUpload => 'Upload image';

  @override
  String get profileSignatureDrawHint =>
      'Sign inside the box with your finger or stylus. It is saved as an image for contracts.';

  @override
  String get profileSignatureClear => 'Clear';

  @override
  String get profileSignatureSaveDraw => 'Save signature';

  @override
  String get profileSignatureEmpty => 'Draw your signature in the box first.';

  @override
  String get profileRevisionGateTitle => 'Profile update required';

  @override
  String get profileRevisionGateBody =>
      'This app version needs you to confirm you have reviewed your profile information. Tap confirm to continue.';

  @override
  String get profileRevisionGateConfirm => 'I have reviewed — continue';

  @override
  String get settingsPublicMemberIdSubtitle =>
      'Your 10-digit public ID (offices and teams)';

  @override
  String get onboardingWelcomeTitleApp => 'Motawoq Real Estate app';

  @override
  String get onboardingWelcomeTitleWeb => 'Motawoq Real Estate online platform';

  @override
  String get onboardingWelcomeBodyApp =>
      'We’re glad you’re here. Whether you work independently, run an office, a company, or an institution, our team is here to serve you and keep your experience smooth—your needs come first. Enjoy exploring.';

  @override
  String get onboardingWelcomeBodyWeb =>
      'We’re glad you’re here on the Motawoq Real Estate online platform. Whether you work independently, run an office, a company, or an institution, our team is here to serve you and keep your experience smooth—your needs come first. Enjoy exploring.';

  @override
  String get onboardingHomeTitle => 'Home';

  @override
  String get onboardingHomeBody =>
      'Browse listings and use the filters at the top (city, type, purpose). Tap any card to open full details.';

  @override
  String get onboardingMyAdsTitle => 'My page';

  @override
  String get onboardingMyAdsBodyMarketing =>
      'Your listings, marketing requests, offers, and contracts—in one place, aligned with your marketing role.';

  @override
  String get onboardingMyAdsBodyOwner =>
      'Manage your listings and requests as a property owner from this tab.';

  @override
  String get onboardingFavoritesTitle => 'Favorites';

  @override
  String get onboardingFavoritesBody =>
      'Save listings you care about and come back to them anytime from this tab.';

  @override
  String get onboardingMySubmissionsTitle => 'Requests/Listings';

  @override
  String get onboardingMySubmissionsBody =>
      'Your property listings and market requests you submitted appear as cards, similar to Home — open them from the Requests/Listings tab.';

  @override
  String get onboardingCartTitle => 'My deals';

  @override
  String get onboardingCartBody =>
      'Review properties you added to My deals before you continue.';

  @override
  String get onboardingChatTitle => 'Chats';

  @override
  String get onboardingChatBody =>
      'Reach the people involved in your deals from your chat inbox.';

  @override
  String get onboardingSupportTitle => 'Technical support';

  @override
  String get onboardingSupportBody =>
      'Help center, and soon administration contact and tickets. Open chats from the bell icon or from here.';

  @override
  String get onboardingMyDeskTitle => 'My desk';

  @override
  String get onboardingMyDeskBodyMarketing =>
      'Your organization or team workspace—approvals and tasks from the My desk icon in the top app bar.';

  @override
  String get onboardingMyDeskBodyOwnerIndividual =>
      'Your personal workspace as an owner—manage listings and tasks from the My desk icon in the top app bar.';

  @override
  String get onboardingMyDeskBodyOrgMember =>
      'Your organization workspace—follow tasks according to your permissions from the My desk icon in the top app bar.';

  @override
  String onboardingStepCounter(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingPrevious => 'Back';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingClose => 'Close';

  @override
  String get onboardingFinish => 'Got it';

  @override
  String get settingsAccentTitle => 'Accent color';

  @override
  String get settingsAccentSubtitle =>
      'Five preset colors for light and dark theme. Applies to primary actions and accent frames (cards, dialogs, fields)—surfaces stay neutral.';

  @override
  String get accentColorDialogTitle => 'Choose accent color';

  @override
  String get accentColorDialogBody =>
      'Pick a color that fits you. Language, dark mode, and accent are together under Settings → Appearance & language.';

  @override
  String get accentColorLater => 'Not now';

  @override
  String get accentColorSkipKeepsDefault =>
      'If you skip or close this dialog, your current accent stays unchanged.';

  @override
  String get marketInsightsTitle => 'Market insights';

  @override
  String get settingsMarketInsightsCardSubtitle =>
      'Leaderboards, listing stats, and organization activity—same as the chart icon on the home screen. Background refresh about every 2 hours.';

  @override
  String get onboardingMarketInsightsBody =>
      'Tap the insights icon at the top of the screen for market stats, leaderboards for individuals and marketers, and top organizations. Numbers update about every two hours—pull down on that screen to refresh now.';

  @override
  String get marketInsightsRefreshHint =>
      'Numbers refresh in the background about every 2 hours; pull down on any tab for an instant update.';

  @override
  String get marketInsightsPublishedTotal => 'Published listings';

  @override
  String get marketInsightsKpiTotal => 'Total';

  @override
  String get marketInsightsNew7d => 'New (7 days)';

  @override
  String get marketInsightsNew30d => 'New (30 days)';

  @override
  String get marketInsightsFeatured => 'Featured';

  @override
  String get marketInsightsByAccountType => 'By account type';

  @override
  String get marketInsightsByPropertyType => 'By property type';

  @override
  String get marketInsightsListingRequests => 'Marketing requests';

  @override
  String get marketInsightsOrgsRegistered =>
      'Offices / institutions / companies';

  @override
  String get marketInsightsTopOrgs => 'Top organizations by listings';

  @override
  String get marketInsightsLeaderboard => 'Leaderboard';

  @override
  String get marketInsightsLeaderboardIndividuals => 'Individuals';

  @override
  String get marketInsightsLeaderboardMarketers => 'Marketers & orgs';

  @override
  String get marketInsightsFilterAll => 'All';

  @override
  String get marketInsightsRank => 'Rank';

  @override
  String get marketInsightsListingsShort => 'listings';

  @override
  String get marketInsightsYourSnapshot => 'Your position';

  @override
  String get marketInsightsCompetitiveHint =>
      'Publish quality listings and climb the leaderboard—healthy competition helps everyone find better deals.';

  @override
  String get marketInsightsLoadError =>
      'Could not load market insights. Check your connection or ensure the server migration is applied.';

  @override
  String get marketInsightsRetry => 'Retry';

  @override
  String marketInsightsLastUpdated(String time) {
    return 'Last updated: $time';
  }

  @override
  String marketInsightsYourRankGlobal(String rank) {
    return 'Your overall rank: $rank';
  }

  @override
  String marketInsightsYourListings(int count) {
    return 'Your published listings: $count';
  }

  @override
  String get marketInsightsEmpty => 'No data yet.';

  @override
  String get marketInsightsTabOverview => 'Overview';

  @override
  String get marketInsightsTabAnalytics => 'Breakdown';

  @override
  String get marketInsightsTabCommunity => 'Leaderboards';

  @override
  String get marketInsightsShareSummary => 'Share summary';

  @override
  String get marketInsightsCopySummary => 'Copy summary';

  @override
  String get marketInsightsCopied => 'Summary copied';

  @override
  String get marketInsightsGuestHint =>
      'Sign in to see your rank and listing count alongside everyone else.';

  @override
  String get marketInsightsSignInToSeeRank => 'Sign in';

  @override
  String get securityInactivityTitle => 'Inactivity detected';

  @override
  String securityInactivityTime(String time) {
    return 'Time: $time';
  }

  @override
  String securityInactivityBodyLock(int seconds) {
    return 'Continue? If you do not respond in $seconds seconds you will be asked to unlock the app (PIN or device biometrics).';
  }

  @override
  String securityInactivityBodySignOut(int seconds) {
    return 'Continue? If you do not respond in $seconds seconds you will be signed out.';
  }

  @override
  String get securityContinue => 'Continue';

  @override
  String get securitySignOutFromPrompt => 'Sign out';

  @override
  String get securitySessionSupersededTitle => 'Session notice';

  @override
  String get securitySessionSupersededBody =>
      'Your account was signed in from another browser or device. This session will close for your security.';

  @override
  String securitySessionSupersededBodyDetail(String city, String device) {
    return 'Signed in from another device (Location: $city, Device: $device). You were signed out for security.';
  }

  @override
  String get securitySessionContinueHere => 'Keep using this device';

  @override
  String get securitySessionSignOutThisDevice => 'Sign out here';

  @override
  String get securitySessionSupersededChooseHint =>
      '• Keep using this device: makes this session active again and signs out other open sessions.\n• Sign out here: closes this session on this device only (the other session stays signed in).';

  @override
  String get securityDeviceLimitMessage =>
      'Sorry, sign-in is not possible. You have reached the maximum number of devices (2). Manage your devices to continue.';

  @override
  String get securityInactivityLockMessage =>
      'Session locked due to inactivity. Please authenticate again.';

  @override
  String get securityDeviceManagementTitle => 'Device management';

  @override
  String get securityDeviceOtpHint =>
      'Enter the verification code sent to your registered phone.';

  @override
  String get securityDeviceRemoveConfirm => 'Remove device';

  @override
  String get securityClearOtherDevices => 'Clear other devices';

  @override
  String get securityRetryContinue => 'Continue after update';

  @override
  String get securityOk => 'OK';

  @override
  String get settingsSectionRegisteredDevices => 'Registered devices';

  @override
  String get settingsSectionSessionHistory => 'Sign-in history';

  @override
  String get settingsDevicesFooterHint =>
      'Shows this app, web, and other clients when your project records sessions on the server.';

  @override
  String get settingsSessionKindWeb => 'Web';

  @override
  String get settingsSessionKindApp => 'Mobile app';

  @override
  String get settingsSessionKindUnknown => 'Unknown client';

  @override
  String get marketInsightsDistinctPublishers => 'Distinct publishers';

  @override
  String get marketInsightsRegisteredProfiles => 'Registered profiles';

  @override
  String get settingsTextScaleTitle => 'Text size';

  @override
  String get settingsTextScaleSubtitle =>
      'Adjusts text across the app. Combines with your system accessibility size, then stays within safe limits to reduce broken layouts.';

  @override
  String get settingsTextScaleReset => 'Reset to default';

  @override
  String settingsTextScalePercent(int percent) {
    return '$percent%';
  }

  @override
  String get orgJoinPendingTitle => 'Join request pending';

  @override
  String orgJoinPendingBody(String orgLabel) {
    return 'Your request to join $orgLabel is still under review. The manager will approve or decline it. After approval, tap refresh below to continue.';
  }

  @override
  String get orgJoinPendingRecheck => 'Refresh status';

  @override
  String get orgKindOffice => 'real estate office';

  @override
  String get orgKindInstitution => 'institution';

  @override
  String get orgKindCompany => 'real estate company';

  @override
  String get orgKindGeneric => 'the organization';

  @override
  String get deskTabMonitoring => 'Monitor';

  @override
  String get deskTabTeamChat => 'Team chat';

  @override
  String get deskTabTeam => 'Team';

  @override
  String get deskTabJoinRequests => 'Join requests';

  @override
  String get deskTabInsights => 'Insights';

  @override
  String get settingsDistinguishedNumberSubtitle =>
      'Your distinguished number (10 digits starting with 700 when applicable)';

  @override
  String get settingsRevealDistinguishedNumber => 'Show';

  @override
  String get settingsHideDistinguishedNumber => 'Hide';

  @override
  String get settingsCopyDistinguishedNumber => 'Copy';

  @override
  String get settingsEditDistinguishedNumber => 'Update number';

  @override
  String get settingsLastSeenPrivacyTitle => 'Hide my last seen in chat';

  @override
  String get settingsLastSeenPrivacySubtitle =>
      'Others will not see when you were last active in chat (you can still appear online while using the app).';

  @override
  String get sensitiveActionConfirm => 'Confirm';

  @override
  String get sensitiveActionCancel => 'Go back';

  @override
  String get chatKindDirect => 'Team message';

  @override
  String get chatListKindDirect => 'Team';

  @override
  String get globalPresenceOnlineTooltip =>
      'You appear online while the app is open';

  @override
  String get orgJoinApprove => 'Approve';

  @override
  String get orgJoinReject => 'Reject';

  @override
  String get orgJoinApprovedToast => 'Member approved';

  @override
  String get orgJoinRejectedToast => 'Request declined';

  @override
  String get orgJoinActionFailed => 'Could not update request';

  @override
  String get orgJoinNoPending => 'No pending join requests';

  @override
  String get listingPublicActionsTooltip => 'Options';

  @override
  String get listingPublicShareLink => 'Share link';

  @override
  String get listingPublicCopyLink => 'Copy link';

  @override
  String get listingPublicToggleBest => 'Favorite';

  @override
  String get listingPublicShowOnHome => 'Show on home feed';

  @override
  String get listingPublicWithdrawPendingReport => 'Withdraw pending report';

  @override
  String get listingPublicHideFromHome => 'Hide from home';

  @override
  String get listingPublicReport => 'Report';

  @override
  String get listingReportGateHourlyBlock =>
      'You exceeded the hourly report limit. Reports affect others’ rights — please wait before filing another.';

  @override
  String get listingReportGateDailyBlock =>
      'You exceeded the daily report limit. Contact support if you have an exceptional case.';

  @override
  String get listingReportGateSternWarning =>
      'Warning: repeated reports without good cause may trigger a review. Listings involve real people’s rights — use reports responsibly.';

  @override
  String get listingReportCannotSubmitGeneric =>
      'You cannot submit a report right now.';

  @override
  String get listingReportImportantNoticeTitle => 'Important notice';

  @override
  String get listingReportContinueToReport => 'Continue to report';

  @override
  String get listingReportDialogCancel => 'Cancel';

  @override
  String get listingReportPropertySheetTitle => 'Report listing';

  @override
  String get listingReportPropertySheetSubtitle =>
      'The listing is hidden from your home feed; the assigned marketer is notified for admin review.';

  @override
  String get listingReportRequestSheetTitle => 'Report request';

  @override
  String get listingReportRequestSheetSubtitle =>
      'The request is hidden from your home feed for admin review.';

  @override
  String get listingReportPickAtLeastOneReason => 'Pick at least one reason';

  @override
  String get listingReportOtherDetailsRequired =>
      'Please add details for «Other»';

  @override
  String get listingReportSubmit => 'Submit report';

  @override
  String get listingReportDetailsLabel => 'Details';

  @override
  String get listingReportDuplicateOpen =>
      'You already have an open report on this listing. Withdraw it or wait for review before filing again.';

  @override
  String get listingReportReasonMisleading =>
      'Misleading or inaccurate property information';

  @override
  String get listingReportReasonDuplicateSpam =>
      'Duplicate listing, spam, or scam-like content';

  @override
  String get listingReportReasonWrongPrice =>
      'Price or terms do not match reality';

  @override
  String get listingReportReasonImpersonation =>
      'Impersonation or unauthorized marketing entity';

  @override
  String get listingReportReasonLicenseMismatch =>
      'REGA ad license mismatch or missing';

  @override
  String get listingReportReasonHarassment =>
      'Inappropriate behavior after contact';

  @override
  String get listingReportReasonOther => 'Other (add details)';

  @override
  String get inAppNotifListingReportTitle => 'Report on your listing';

  @override
  String get inAppNotifListingReportBody =>
      'A user filed a report. The listing stays visible to others until admin review.';

  @override
  String get inAppNotifListingReportEscalatedTitle =>
      'Urgent: multiple reports on your listing';

  @override
  String get inAppNotifListingReportEscalatedBody =>
      'Multiple distinct users reported this listing. It is temporarily hidden from the home feed pending admin review.';

  @override
  String get inAppNotifListingReportOwnerEscalatedTitle =>
      'Notice: listing reports escalated';

  @override
  String get inAppNotifListingReportOwnerEscalatedBody =>
      'Your listing is temporarily hidden from the home feed due to multiple distinct user reports. Admin review is in progress.';

  @override
  String get dashboardToastListingHiddenFromHome =>
      'Hidden from home — open «Hidden» to view.';

  @override
  String get dashboardToastListingShownOnHomeAgain =>
      'Listing shows on home again.';

  @override
  String get dashboardToastListingReportWithdrawn =>
      'Pending report withdrawn.';

  @override
  String get dashboardToastMarketRequestHiddenFromHome =>
      'Request hidden from home.';

  @override
  String get dashboardToastMarketRequestShownOnHomeAgain =>
      'Request shows on home again.';

  @override
  String get propertyDetailsReportWithdrawnSnack => 'Pending report withdrawn.';

  @override
  String get propertyDetailsHiddenFromYourHomeSnack =>
      'Hidden from your home feed.';

  @override
  String get propertyDetailsShownOnHomeAgainSnack => 'Shown on home again.';

  @override
  String get settingsReportsActivityTitle => 'Reports (on this device)';

  @override
  String settingsReportsActivitySubtitle(
      int listingCount, int requestCount, int events30) {
    return 'Listing reports: $listingCount · Requests: $requestCount · Events last 30 days: $events30';
  }

  @override
  String get marketRequestUrgencyTitle => 'Request urgency';

  @override
  String get marketRequestUrgencyHint =>
      'How time-sensitive is this request? Higher urgency is surfaced sooner on the home feed.';

  @override
  String get marketRequestPriorityFlexible => 'Flexible timeline';

  @override
  String get marketRequestPriorityStandard => 'Standard';

  @override
  String get marketRequestPriorityPriority => 'High priority';

  @override
  String get marketRequestPriorityUrgent => 'Urgent';

  @override
  String get marketRequestPriorityImmediate => 'Immediate';

  @override
  String get inboxSearchHint => 'Search notifications…';
}
