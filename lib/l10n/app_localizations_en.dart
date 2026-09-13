// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Mawthuq Line Real Estate App';

  @override
  String get welcomeTitle => 'Welcome';

  @override
  String get welcomeTrustedAqar => 'Welcome to Mawthuq Line Real Estate App';

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
  String get settingsDarkModeSubtitle =>
      'Saved with this account on this device. Not copied to another account after sign-out.';

  @override
  String get settingsThemeModeSubtitle =>
      'Follows the device appearance (light/dark), including automatic mode by time or brightness.';

  @override
  String get photographerCaptureWithCamera => 'Capture with camera';

  @override
  String get photographerPickFromGallery => 'Choose from gallery';

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
  String get legalTermsCoachTitle => 'Terms & Conditions';

  @override
  String get legalTermsCoachBody =>
      'Review the Terms & Conditions via the link, then check the acknowledgment box to continue. This prompt will not appear again after you confirm.';

  @override
  String get legalTermsCoachOk => 'Acknowledged — continue';

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
  String get welcomeDashboardBannerTitle =>
      'Welcome to Mawthuq Line Real Estate';

  @override
  String get welcomeDashboardBannerBody =>
      'Browse listings on Home, manage your ads under My Ads, and open Settings at the top. You can turn off alert sounds in Settings.';

  @override
  String get welcomeDashboardBannerButton => 'Got it';

  @override
  String get usernameHint10Digits => 'Distinguished number (10 digits)';

  @override
  String get loginUsernameFieldHelper => 'Enter ID / Iqama — 10 digits';

  @override
  String get loginIdentifierFieldLabel => 'Username';

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
  String get marketerTabAwaitingOwner => '✅ Permit issuance';

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
  String get ownerBtnRealEstateOffers => 'Marketer offers';

  @override
  String get ownerHubTabWaitingMarketers => 'Awaiting marketers';

  @override
  String get ownerHubTabAwaitingApproval => 'Awaiting owner approval';

  @override
  String get ownerBtnApprove => 'Approve';

  @override
  String get ownerBtnReject => 'Decline';

  @override
  String get ownerDeclineReasonLabel => 'Decline reason';

  @override
  String get ownerDeclineReasonHint =>
      'This reason is shown to the marketer after you decline.';

  @override
  String get ownerDeclineReasonRequired =>
      'Enter a decline reason so the marketer can see it.';

  @override
  String get ownerOfferDetailsTitle => 'Marketer offer details';

  @override
  String get ownerOfferNoExtraDetails =>
      'The marketer did not fill extra offer details.';

  @override
  String get marketerBtnSendOffer => 'Send offer';

  @override
  String get marketerBtnSubmitOffer => 'Submit offer';

  @override
  String get marketerBtnTrack => 'Track';

  @override
  String get marketerBtnIssuePermit => 'Issue permit';

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
  String get communicationHubTitle => 'Notifications, chats, and ads';

  @override
  String get communicationHubNotificationsTab => 'Notifications';

  @override
  String get communicationHubChatsTab => 'Chats';

  @override
  String get communicationHubCampaignsTab => 'Ads & campaigns';

  @override
  String get openChatInboxButton => 'Open chat inbox';

  @override
  String get communicationHubChatsHint =>
      'All conversation types (property, reservation, market request, support…) are handled in the chat inbox.';

  @override
  String get supportHubTechnicalTab => 'Help center';

  @override
  String get supportHubAdminTab => 'In-app complaint';

  @override
  String get supportHubTicketsTab => 'Tickets';

  @override
  String get supportHubComplaintTab => 'In-app complaint';

  @override
  String get supportHubNeedLogin => 'Log in to access support';

  @override
  String get settingsSupportMovedHint =>
      'Technical support is on the bottom bar or here. X returns you to the screen you came from without signing you out.';

  @override
  String get supportCenterTitle => 'Support center';

  @override
  String get supportCenterIntro =>
      'Support helps with the app, your account, listings, requests, payments, and subscriptions. Describe what happened clearly, and attach a screenshot if you have one so we can resolve it faster.';

  @override
  String get supportEmailLabel => 'Email';

  @override
  String get supportPhoneLabel => 'Phone';

  @override
  String get supportCopyTooltip => 'Copy';

  @override
  String get supportWhatsAppTooltip => 'WhatsApp message';

  @override
  String get supportEmailCopied =>
      'Email copied — paste it in your mail app if it did not open.';

  @override
  String get supportPhoneCopied => 'Support number copied.';

  @override
  String get supportHoursLabel => 'Response hours';

  @override
  String get supportHoursValue => 'Business days — 9 AM to 5 PM (KSA)';

  @override
  String get supportComplaintFormTitle => 'Submit a complaint / suggestion';

  @override
  String get supportComplaintFormHint =>
      'Choose the type, write the subject and details, and attach a photo or file if needed. Choosing the type will not close this screen.';

  @override
  String get supportAttachmentsLabel => 'Attachments';

  @override
  String get supportAttachmentsHint =>
      'Optional. From files, gallery, or camera depending on your device.';

  @override
  String get supportAttachFile => 'Files';

  @override
  String get supportAttachGallery => 'Gallery';

  @override
  String get supportAttachCamera => 'Camera';

  @override
  String get supportAttachRemove => 'Remove';

  @override
  String get supportAttachFailed => 'Could not attach the file.';

  @override
  String get supportSubmitterNameLabel => 'Name';

  @override
  String get supportSubmitterPhoneLabel => 'Mobile';

  @override
  String get supportTicketRefLabel => 'Ticket reference';

  @override
  String get supportTicketConversationSection => 'Conversation';

  @override
  String get supportTicketWelcomeRow => 'Support greeting';

  @override
  String get supportTicketMessageAt => 'Time';

  @override
  String get supportTicketMessageFrom => 'From';

  @override
  String get supportTicketMessageBody => 'Message';

  @override
  String get supportTicketReplyBy => 'Replied by';

  @override
  String get supportTicketReplyAt => 'Reply time';

  @override
  String get supportTicketReceivedBy => 'Received by';

  @override
  String get supportTicketReceivedAt => 'Received at';

  @override
  String get supportTicketEscalateRemaining => 'Escalation available in';

  @override
  String get supportTicketEscalateAvailableAt => 'Escalation available at';

  @override
  String get supportTicketCopySnapshot => 'Copy ticket summary';

  @override
  String get supportTicketCopied => 'Ticket summary copied.';

  @override
  String get supportTicketOpenAttachment => 'Open attachment';

  @override
  String get supportTicketDownloadAttachment => 'Download';

  @override
  String get supportTicketNoConversation => 'No messages yet.';

  @override
  String get supportTicketInternalHidden =>
      'Internal support draft — hidden from the user.';

  @override
  String supportSlaCountdownHours(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String get supportComplaintKindLabel => 'Type';

  @override
  String get supportComplaintKindComplaint => 'Complaint';

  @override
  String get supportComplaintKindSuggestion => 'Suggestion';

  @override
  String get supportComplaintSubjectLabel => 'Subject';

  @override
  String get supportComplaintDetailsLabel => 'Details';

  @override
  String get supportComplaintSubjectHint =>
      'A clear subject, one or more lines';

  @override
  String get supportComplaintDetailsHint =>
      'Describe the issue or suggestion in detail';

  @override
  String get supportComplaintChannelLabel => 'Contact method';

  @override
  String get supportComplaintChannelWhatsApp => 'WhatsApp';

  @override
  String get supportComplaintChannelInApp => 'In-app';

  @override
  String get supportComplaintWhatsAppHint =>
      'The request is saved in the system and WhatsApp opens with support numbers — tap Send in each chat.';

  @override
  String get supportComplaintSendWhatsApp => 'Send via WhatsApp';

  @override
  String get supportComplaintSendInApp => 'Send in-app';

  @override
  String get supportComplaintSubmitFailed =>
      'Could not submit — try again later.';

  @override
  String get supportComplaintSubmitOk =>
      'Your request was sent — track it under Tickets.';

  @override
  String get supportTicketSubmittedAt => 'Submitted';

  @override
  String get supportTicketStatusLabel => 'Status';

  @override
  String get supportTicketStatusOpen => 'Open';

  @override
  String get supportTicketStatusOpenUnresolved => 'Open — unresolved';

  @override
  String get supportTicketStatusResolved => 'Resolved';

  @override
  String get supportTicketStatusEscalated => 'Escalated';

  @override
  String get supportTicketEmpty =>
      'No tickets yet. Submit a complaint or suggestion from the In-app complaint tab.';

  @override
  String get supportTicketReceiptSection => 'Submitted ticket';

  @override
  String get supportTicketReplySection => 'Support reply';

  @override
  String get supportTicketReplyEmpty =>
      'Support has not replied yet. An automatic receipt is not an admin reply.';

  @override
  String get supportTicketAckSection => 'Receipt confirmation';

  @override
  String get supportTicketEscalationSection => 'Escalation';

  @override
  String get supportTicketEscalateCta => 'Escalate';

  @override
  String get supportTicketResolvedCta => 'Resolved';

  @override
  String get supportTicketUnresolvedCta => 'Not resolved';

  @override
  String get supportTicketEscalateHint =>
      'Escalation appears 24 hours after submission if the ticket is still unresolved.';

  @override
  String get supportTicketEscalateReady =>
      'The 24-hour window has passed and the ticket is still unresolved. You can escalate to administration.';

  @override
  String get supportTicketUnresolvedLocked =>
      '“Resolved” and “Not resolved” appear only after administration replies.';

  @override
  String get supportTicketUnresolvedOk => 'Ticket remains open.';

  @override
  String get supportTicketSlaHours =>
      'Escalation window: 24 hours from submission.';

  @override
  String get supportTicketRateTitle => 'Rate the resolution';

  @override
  String get supportTicketRateSkip => 'Skip';

  @override
  String get supportTicketRateSend => 'Submit rating';

  @override
  String get supportTicketRateNotes => 'Notes (optional)';

  @override
  String supportTicketResolvedBy(String name) {
    return 'Resolved by: $name';
  }

  @override
  String get supportTicketFollowWhatsApp => 'Follow up on WhatsApp';

  @override
  String get supportTicketThreadTitle => 'Conversation';

  @override
  String get supportTicketYou => 'You';

  @override
  String get supportTicketStaff => 'Support';

  @override
  String get opsDeskTicketSubmittedAt => 'Submitted at';

  @override
  String get opsDeskTicketReplySection => 'Reply';

  @override
  String get opsDeskTicketEscalationSection => 'Escalation';

  @override
  String get opsDeskSlaOverdue =>
      'Past the 24-hour window — awaiting reply or escalation';

  @override
  String get opsDeskSlaWaiting => 'Within the 24-hour window';

  @override
  String get opsDeskTicketNoStaffReply => 'No admin reply yet';

  @override
  String get mySubmissionsSectionListings => 'My listings';

  @override
  String get mySubmissionsSectionRequests => 'Market requests';

  @override
  String get mySubmissionsEmpty =>
      'You have no published listings or market requests yet.';

  @override
  String get cartMarketOffersSectionTitle => 'Deals you submitted';

  @override
  String get cartMarketOffersEmptyHint =>
      'When someone requests to complete a deal on your listing or request, it appears under Incoming offers.';

  @override
  String get cartTabIncoming => 'Incoming offers';

  @override
  String get cartIncomingEmpty =>
      'No complete-deal offers on your listings or requests yet.';

  @override
  String get cartIncomingSectionRequests => 'On my requests';

  @override
  String get cartIncomingSectionListings => 'On my listings';

  @override
  String get dealFactsRequestedAt => 'Request date & time';

  @override
  String dealFactsRemainingMinutes(int minutes) {
    return '$minutes minutes left to complete the deal';
  }

  @override
  String dealFactsMinutesLeftShort(int minutes) {
    return '$minutes min';
  }

  @override
  String get dealFactsAddress => 'Address';

  @override
  String get dealFactsApplicantNote => 'Application window details';

  @override
  String get dealFactsOwnerApprovedAt => 'Owner approval date & time';

  @override
  String get dealFactsOwnerParty => 'Listing owner';

  @override
  String get dealFactsApplicantParty => 'Complete-deal applicant';

  @override
  String get dealFactsCopySummary => 'Copy transparency summary';

  @override
  String get dealFactsSummaryCopied => 'Transparency summary copied';

  @override
  String dealFactsQueueRank(int index, int max) {
    return 'Secret queue: $index of $max';
  }

  @override
  String get dealFactsSecretUntil72 =>
      'Applicant details are visible to you only. After 72 hours without completion, remaining waiters are re-activated and appear on Home.';

  @override
  String get dealIncomingSortOldest => 'Oldest';

  @override
  String get dealIncomingSortNewest => 'Newest';

  @override
  String get dealIncomingFilterAll => 'All';

  @override
  String get dealIncomingFilterWaiting => 'Awaiting you';

  @override
  String get dealIncomingFilterAccepted => 'You accepted';

  @override
  String get cartOutgoingEmptyHint =>
      'When you submit a complete-deal from Home it appears here.';

  @override
  String cartApplicantCount(int used, int max) {
    return '$used of $max';
  }

  @override
  String get dealWaitingOwnerAccept =>
      'Waiting for the owner to approve this deal. Messaging appears after approval.';

  @override
  String get dealOwnerAcceptPartner => 'Accept to complete deal';

  @override
  String get dealOwnerAcceptedPartner =>
      'This partner was selected to complete the deal.';

  @override
  String get dealStayPendingUntilCancel =>
      'Another partner was selected. This deal stays pending until you cancel it, or until the sale is completed — then it leaves My deals.';

  @override
  String get dealCompleteWithPartner => 'Complete deal';

  @override
  String get dealEnterPromptTitle => 'Has this deal been completed?';

  @override
  String dealEnterPromptBody(String title) {
    return 'The deal «$title» was accepted. Completion happens outside the app. Confirm if it is finished, or keep it open.';
  }

  @override
  String get dealEnterYesDone => 'Yes, it is done';

  @override
  String get dealEnterStillOpen => 'Still in progress';

  @override
  String get dealCompleteNoteTitle => 'Completion details';

  @override
  String get dealCompleteNoteHint =>
      'Write a short note about how the deal was completed outside the app (meeting, payment, handover).';

  @override
  String get dealCompleteNoteFieldHint => 'Short details…';

  @override
  String get dealCompleteNoteRequired => 'Add a short note before sending.';

  @override
  String get dealCompleteSend => 'Send';

  @override
  String get dealCompleteCancel => 'Cancel';

  @override
  String get dealSlotCapTitle => 'My deals is full';

  @override
  String dealSlotCapBody(int used, int max) {
    return 'You have $used of $max active deal cards. Complete, cancel, or remove a deal before adding another.';
  }

  @override
  String get dealSlotCapOk => 'OK';

  @override
  String get inventorySlotCapTitle => 'Listings and requests are full';

  @override
  String inventorySlotCapBody(int used, int max) {
    return 'You have $used of $max active listing/request cards. Complete, cancel, or delete some before adding more.';
  }

  @override
  String get cartTabActive => 'Open deals';

  @override
  String get cartTabCompleted => 'Completed';

  @override
  String cartActiveCount(int used, int max) {
    return '$used/$max';
  }

  @override
  String get shortsCommentsTitle => 'Comments';

  @override
  String get shortsCommentHint => 'Write a comment';

  @override
  String get shortsCommentEmpty => 'No comments yet';

  @override
  String get shortsCommenterFallback => 'Interested partner';

  @override
  String get shortsCommenterMyDeal => 'My deal';

  @override
  String get marketPropertySubmitSuccessTitle => 'Sent to Home';

  @override
  String get marketPropertySubmitSuccessBody =>
      'Your request is visible to interested parties on the market. Home refreshes instantly and opens on your new request. You can also track it under Requests/Listings.';

  @override
  String get marketPropertySubmitGoHome => 'Home';

  @override
  String get marketPropertySubmitAnother => 'Another property request';

  @override
  String get listingPublishLiveSuccessTitle => 'Sent to Home';

  @override
  String get listingPublishLiveSuccessBody =>
      'Your listing is live, verified, and linked to official records. The listing number appears on the card, and Home refreshes instantly to open on it at the top.';

  @override
  String get listingPublishLiveStatusChip => 'Live on Home';

  @override
  String get listingPublishMarketingSuccessTitle => 'Marketing request sent';

  @override
  String get listingPublishMarketingSuccessBody =>
      'Your request will be reviewed and assigned to a licensed marketer. It will not appear on Home until it is approved and linked to the official permit. Track it from Follow request.';

  @override
  String get listingPublishMarketingStatusChip => 'Waiting for a marketer';

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
      'Terms and privacy text could not be loaded from the server. By continuing you agree to use Mawthuq Line Real Estate Establishment in accordance with applicable laws in the Kingdom of Saudi Arabia, including personal data protection rules where they apply, to provide accurate information, and to use listings and messaging responsibly. For the full text, contact support or try again later.';

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
  String get loginIdentifierFieldHint => 'Enter ID / Iqama number (10 digits)';

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
      'FAL license number — for offices and real-estate entities';

  @override
  String get onboardingWelcomeTitleApp => 'Mawthuq Line Real Estate App';

  @override
  String get onboardingWelcomeTitleWeb =>
      'Mawthuq Line Real Estate Establishment';

  @override
  String get onboardingWelcomeBodyApp =>
      'We’re glad you’re here. Whether you work independently, run an office, a company, or an institution, our team is here to serve you and keep your experience smooth—your needs come first. Enjoy exploring.';

  @override
  String get onboardingWelcomeBodyWeb =>
      'We’re glad you’re here on the Mawthuq Line Real Estate Establishment platform. Whether you work independently, run an office, a company, or an institution, our team is here to serve you and keep your experience smooth—your needs come first. Enjoy exploring.';

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
      'Help center, in-app complaint, and tickets with administration. It opens over every tab; close with X to go back. Open chats from the bell icon or from here.';

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
      'Primary buttons, navigation, and card/dialog/field frames. Backgrounds and text follow light/dark. This color stays with this account only.';

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
      '• Keep using this device: stay signed in here and sign out other open sessions.\n• Sign out here: close this device only; the other session stays signed in.';

  @override
  String get securitySessionFieldKind => 'Sign-in type';

  @override
  String get securitySessionFieldMethod => 'Sign-in method';

  @override
  String get securitySessionFieldWhen => 'Date and time';

  @override
  String get securitySessionFieldWhere => 'Location';

  @override
  String get securitySessionFieldDevice => 'Device';

  @override
  String get securitySessionKindWebWindows => 'Web — Windows browser';

  @override
  String get securitySessionKindWebMobile => 'Web — mobile browser';

  @override
  String get securitySessionKindWebDesktop => 'Web — desktop browser';

  @override
  String get securitySessionKindApp => 'Device app';

  @override
  String get securitySessionMethodPassword => 'Password';

  @override
  String get securitySessionMethodPin => 'PIN';

  @override
  String get securitySessionMethodBiometric => 'Biometrics';

  @override
  String get securitySessionMethodOtp => 'Verification code';

  @override
  String get securitySessionMethodOther => 'Signed in';

  @override
  String get trackingOfferSentAt => 'Offer sent date';

  @override
  String get trackingOfferSender => 'Offer sender';

  @override
  String get trackingOfferSenderRole => 'Sender role';

  @override
  String get trackingOfferRoleOfficial => 'Official registered name';

  @override
  String get trackingOfferRoleDisplay => 'Marketing display name';

  @override
  String get trackingOfferDetails => 'Offer details';

  @override
  String get listingCreatedBy => 'Listing created by';

  @override
  String get listingCreatedByOffice => 'Listing created by real estate office';

  @override
  String get listingCreatedByCompany =>
      'Listing created by real estate company';

  @override
  String get listingCreatedByInstitution =>
      'Listing created by real estate establishment';

  @override
  String get listingCreatedByMarketer => 'Listing created by marketer';

  @override
  String get listingCreatedByAdvertiser => 'Listing created by advertiser';

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
      'Enter the 6-digit verification code. In development it arrives in-app (top banner), not by SMS.';

  @override
  String get securityDeviceRemoveConfirm => 'Remove device';

  @override
  String get securityClearOtherDevices => 'Clear other devices';

  @override
  String get securityDeviceColBrowser => 'Browser / device';

  @override
  String get securityDeviceColPlatform => 'Platform';

  @override
  String get securityDeviceColLocation => 'Location';

  @override
  String get securityDeviceColLastSignIn => 'Last sign-in';

  @override
  String get securityDeviceColRegistered => 'Registered';

  @override
  String get securityDeviceColStatus => 'Status';

  @override
  String get securityDeviceStatusCurrent => 'This device';

  @override
  String get securityDeviceUnknownBrowser => 'Unknown device';

  @override
  String get securityDeviceRemoveAction => 'Remove';

  @override
  String get securityDeviceOtpSent => 'Verification code sent';

  @override
  String get securityDeviceOtpResendWait =>
      'Wait for the timer before resending';

  @override
  String otpAttemptsRemaining(int count) {
    return 'Attempts left: $count';
  }

  @override
  String get otpAttemptsThirdNotifyTitle => 'Verification attempt notice';

  @override
  String get otpAttemptsThirdNotifyBody =>
      'You entered the code three times. Check remaining attempts or resend a new code.';

  @override
  String get otpAttemptsLocked =>
      'The three attempts were used. Resend the code.';

  @override
  String get securityRetryContinue => 'Continue after update';

  @override
  String get securityOk => 'OK';

  @override
  String get settingsSectionRegisteredDevices => 'Registered devices';

  @override
  String get settingsSectionSessionHistory => 'Sign-in history';

  @override
  String get settingsSectionAccountHub => 'Account & guided tour';

  @override
  String get settingsReplayDashboardTourTitle => 'Replay dashboard tour';

  @override
  String get settingsReplayDashboardTourSubtitle =>
      'Walks main tabs again (Home → My page → …). Starts when you return to the dashboard.';

  @override
  String get settingsReplayDashboardTourSnackbar =>
      'Tour will start when you go back to the dashboard.';

  @override
  String get settingsOpenSwitchAccountTitle => 'Switch account';

  @override
  String get settingsOpenSwitchAccountSubtitle =>
      'Pick another profile you used on this device.';

  @override
  String get settingsOpenSessionHistoryTitle => 'Full session log';

  @override
  String get settingsOpenSessionHistorySubtitle =>
      'Open the detailed sign-in history screen.';

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
      'Unified national number (10 digits starting with 700) — offices, institutions, and companies';

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
  String get listingReportReasonFraudFinancial =>
      'Fraud, extortion, or illegal payment demands';

  @override
  String get listingReportReasonIllegalContent =>
      'Illegal content or serious criminal activity';

  @override
  String get listingReportReasonPrivacyViolation =>
      'Privacy breach or misuse of personal data';

  @override
  String get listingReportReasonOther => 'Other (add details)';

  @override
  String get listingReportLegalDetailsLabel =>
      'Legal / factual explanation (required for this selection)';

  @override
  String get listingReportLegalDetailsRequired =>
      'Add a clear explanation (at least 30 characters) for the selected reason.';

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

  @override
  String get registerTitle => 'Create account';

  @override
  String get registerSubtitle =>
      'Choose account type, then complete registration.';

  @override
  String get registerAccountTypeHeading => 'Account type';

  @override
  String get accountKindIndividual => 'Individual user (browse)';

  @override
  String get accountKindOffice => 'Real estate office (max 3 members)';

  @override
  String get accountKindInstitution =>
      'Real estate institution (max 6 members)';

  @override
  String get accountKindCompany => 'Real estate company (max 12 members)';

  @override
  String get registerContinue => 'Continue to registration';

  @override
  String get accountKindIndependentAdvertiser =>
      'Independent (individual advertiser)';

  @override
  String get accountKindMarketer => 'Real estate marketer';

  @override
  String get registerOrgModeSectionTitle => 'Organization setup';

  @override
  String get registerOrgModeCreate =>
      'Create a new organization (you will be the owner)';

  @override
  String get registerOrgModeJoin => 'Join an existing organization';

  @override
  String get registerInviteCodeLabel => 'Organization or invitation code (FAL)';

  @override
  String get registerInviteCodeHint => 'Enter the code shared by the owner';

  @override
  String get registerLookupOrg => 'Look up organization';

  @override
  String get registerOrgPreviewTitle => 'Confirm organization';

  @override
  String registerOrgPreviewFal(String code) {
    return 'Display code: $code';
  }

  @override
  String get registerInviteInvalid =>
      'Code not found. Check with the owner and try again.';

  @override
  String get registerInviteContinueRequiresPreview =>
      'Look up the organization before continuing.';

  @override
  String get registerSignupJoinPendingSnackbar =>
      'Account created. After you sign in, your join request is sent to the owner for approval.';

  @override
  String get registerPendingJoinIntro =>
      'Join request submitted from account registration.';

  @override
  String get registerJoinFlowHint =>
      'After you complete signup and sign in, a join request is sent to the organization owner for approval.';

  @override
  String get orgBrowseTitle => 'Organizations';

  @override
  String get orgBrowseEmpty => 'No organizations yet.';

  @override
  String get orgJoinSubmit => 'Request to join';

  @override
  String get orgJoinMessageHint => 'Optional message';

  @override
  String get orgProfileTitle => 'Organization';

  @override
  String orgMembersCount(int count) {
    return '$count members';
  }

  @override
  String orgFalBadge(String code) {
    return 'FAL $code';
  }

  @override
  String get orgSetupTitle => 'Organization created';

  @override
  String orgSetupFalLine(String code) {
    return 'Public license: $code';
  }

  @override
  String get orgSettingsTitle => 'Organization settings';

  @override
  String get orgRenewFal => 'Renew FAL display license';

  @override
  String get orgBuySeats => 'Purchase extra seats';

  @override
  String get orgAssignPermissionsTitle => 'Member permissions';

  @override
  String get permManageTeam => 'Manage team';

  @override
  String get permAddProperties => 'Add properties';

  @override
  String get permAddAds => 'Add ads only';

  @override
  String get permViewMarket => 'Market access';

  @override
  String get permViewProfile => 'My profile tab';

  @override
  String get permAccessChat => 'Chats';

  @override
  String get permEditOrgSettings => 'Organization settings';

  @override
  String get permViewAnalytics => 'Analytics';

  @override
  String get orgListingOrgTap => 'Organization';

  @override
  String get manageMembersTitle => 'Member management';

  @override
  String get tabActiveMembers => 'Active';

  @override
  String get tabBanned => 'Banned';

  @override
  String get tabAlumni => 'Left';

  @override
  String get tabLeaveRequests => 'Leave requests';

  @override
  String get orgRejectReasonHint => 'Optional reason (shown to applicant)';

  @override
  String get deskTabTeamDashboard => 'Team board';

  @override
  String get deskTabTeamInventory => 'Team listings & requests';

  @override
  String get deskTabTeamInventoryListings => 'Listings';

  @override
  String get deskTabTeamInventoryMarketingRequests => 'Marketing requests';

  @override
  String get deskTabTeamInventoryMarketRequests => 'Market requests';

  @override
  String get deskTabTeamInventoryEmpty =>
      'No listings or requests for this team yet.';

  @override
  String get deskTabTeamInventoryLoadError =>
      'Could not load team items. Pull to refresh.';

  @override
  String get deskTabTeamInventoryUntitled => 'Untitled';

  @override
  String get ownerDeskManageListingsInMyPage =>
      'Manage your listings and marketing from the «My page» tab in the bottom bar.';

  @override
  String get deskTabRolesPermissions => 'Roles';

  @override
  String get deskTabTeamAnalytics => 'Statistics';

  @override
  String get deskTabReportsDesk => 'Reports & export';

  @override
  String get deskTabAnalyticsReports => 'Analytics';

  @override
  String get appBarOrgJoinRequestsTooltip => 'Pending join requests';

  @override
  String get orgTeamDeskTitle => 'My organization';

  @override
  String get orgStatActiveMembers => 'Active members';

  @override
  String get orgStatPendingJoin => 'Pending requests';

  @override
  String get orgStatOrgListings => 'Team listings';

  @override
  String get orgStatOrgAds => 'Team ads';

  @override
  String get orgLeaderboardTitle => 'Member leaderboard';

  @override
  String get orgLeaderboardProps => 'Listings';

  @override
  String get orgLeaderboardAds => 'Ads';

  @override
  String get orgLeaderboardRank => 'Rank';

  @override
  String get orgRolesPickMember => 'Pick a teammate';

  @override
  String get orgRolesEditPermissions => 'Edit permissions';

  @override
  String get orgExportReport => 'Export report';

  @override
  String get orgExportCsv => 'Share CSV summary';

  @override
  String get orgAnalyticsEmpty => 'No analytics data yet.';

  @override
  String get organalyticsSoldRented => 'Sold / rented (est.)';

  @override
  String get organalyticsScore => 'Score';

  @override
  String get permManageTeamHelp =>
      'Approve or decline join requests, edit permissions, ban or remove members.';

  @override
  String get permAddPropertiesHelp =>
      'Create and publish new property listings on behalf of the organization.';

  @override
  String get permAddAdsHelp =>
      'Create side or promotional ads where your role allows.';

  @override
  String get permViewMarketHelp => 'Open the public real-estate market tab.';

  @override
  String get permViewProfileHelp =>
      'Access your personal profile tab inside the app.';

  @override
  String get permAccessChatHelp =>
      'Use internal team chat and direct team messages.';

  @override
  String get permEditOrgSettingsHelp =>
      'Edit organization branding, contacts, and desk settings.';

  @override
  String get permViewAnalyticsHelp =>
      'View team dashboards, charts, and exports.';

  @override
  String get permAddListingRequests => 'Listing requests';

  @override
  String get permAddListingRequestsHelp =>
      'Add buy/rent property requests that appear on the home feed.';

  @override
  String get permEditProperties => 'Edit properties';

  @override
  String get permEditPropertiesHelp =>
      'Edit or delete any property listing owned by your organization.';

  @override
  String get permManageSubscription => 'Manage subscription';

  @override
  String get permManageSubscriptionHelp =>
      'Purchase extra seats, renew the display license, and manage the plan.';

  @override
  String get permExportData => 'Export data';

  @override
  String get permExportDataHelp =>
      'Export team summaries to CSV or share reports from analytics.';

  @override
  String get permInviteMembers => 'Invite members';

  @override
  String get permInviteMembersHelp =>
      'Show the invite / FAL code and renew it so teammates can join.';

  @override
  String get permManageChatRooms => 'Manage chat rooms';

  @override
  String get permManageChatRoomsHelp =>
      'Create private team chat rooms and assign moderators.';

  @override
  String get permViewMemberActivity => 'Member activity';

  @override
  String get permViewMemberActivityHelp =>
      'View the activity log and recent actions by teammates.';

  @override
  String get deskTabMemberActivity => 'Activity log';

  @override
  String get orgMemberActivityEmpty =>
      'No activity recorded yet for this organization.';

  @override
  String get orgMemberActivityUnknownAction => 'Activity';

  @override
  String get orgMemberLastActivity => 'Last activity';

  @override
  String get inviteMembersTitle => 'Invite teammates';

  @override
  String get inviteMembersBody =>
      'Share this code with people joining from registration. It is the same public FAL / invite code for your organization.';

  @override
  String get inviteMembersShare => 'Share code';

  @override
  String get inviteMembersRenew => 'Generate new invite code';

  @override
  String get inviteMembersRenewHint =>
      'Generating a new code invalidates the previous one for join-by-code flows.';

  @override
  String get inviteMembersQrCaption =>
      'Scan to copy the code on another device.';

  @override
  String get inviteMembersShareHint =>
      'Enter this code when choosing “Join an existing organization” in sign-up.';

  @override
  String get reportsDeskServerSyncHint =>
      'Team and billing figures in these templates will fill automatically once server analytics queries are connected. Export, print, and share work today; full platform operations console will roll out later under project policy.';

  @override
  String get subscriptionsMenuHub => 'Subscriptions & payments';

  @override
  String get subscriptionsMenuCards => 'My saved cards';

  @override
  String get subscriptionsMenuHistory => 'Payment history';

  @override
  String get subscriptionsMenuPlans => 'Subscription plans';

  @override
  String get subscriptionsTitle => 'Subscriptions & payments';

  @override
  String get subscriptionsTabPlans => 'Plans';

  @override
  String get subscriptionsTabPaymentMethods => 'Payment methods';

  @override
  String get subscriptionsTabHistory => 'History';

  @override
  String get subscriptionsTabTeam => 'Team seats';

  @override
  String get subscriptionsTabUsage => 'Plan usage';

  @override
  String get subscriptionsTabUpgrade => 'Upgrade plan';

  @override
  String get subscriptionsTabRenewFal => 'Renew FAL license';

  @override
  String get subscriptionsOrgManageTab => 'Subscription';

  @override
  String get subscriptionsBadgeExpired => 'Subscription expired or ending soon';

  @override
  String get subscriptionsSar => 'SAR';

  @override
  String get subscriptionsMonthly => 'Monthly';

  @override
  String get subscriptionsYearly => 'Yearly (20% off)';

  @override
  String get subscriptionsSubscribeNow => 'Subscribe now';

  @override
  String get subscriptionsCurrentPlan => 'Current plan';

  @override
  String subscriptionsRenewsOn(String date) {
    return 'Renews on $date';
  }

  @override
  String subscriptionsExpiredOn(String date) {
    return 'Ended on $date';
  }

  @override
  String get subscriptionsRenew => 'Renew';

  @override
  String get subscriptionsCancel => 'Cancel subscription';

  @override
  String get subscriptionsUnlimited => 'Unlimited';

  @override
  String get subscriptionsMembers => 'Members';

  @override
  String get subscriptionsProperties => 'Properties';

  @override
  String get subscriptionsAdsPerMonth => 'Ads / month';

  @override
  String get subscriptionsListingRequests => 'Listing requests';

  @override
  String get subscriptionsFalIncluded => 'FAL license included';

  @override
  String get subscriptionsSupport => 'Support';

  @override
  String get subscriptionsAddCard => 'Add payment card';

  @override
  String get subscriptionsCardSaved => 'Card saved';

  @override
  String get subscriptionsCardDeleted => 'Card removed';

  @override
  String get subscriptionsDefaultCard => 'Default';

  @override
  String get subscriptionsSetDefault => 'Set default';

  @override
  String get subscriptionsDelete => 'Delete';

  @override
  String get subscriptionsAddCardTitle => 'Add payment card';

  @override
  String get subscriptionsCardNumber => 'Card number';

  @override
  String get subscriptionsCardHolder => 'Cardholder name';

  @override
  String get subscriptionsExpiry => 'Expiry (MM/YY or MM/YYYY)';

  @override
  String get subscriptionsCapsLockOn =>
      'Caps Lock is on — card fields usually expect Latin letters.';

  @override
  String get subscriptionsCardHolderLatinTitle => 'Latin characters only';

  @override
  String get subscriptionsCardHolderLatinBody =>
      'Enter the cardholder name in English letters (as printed on the card). Arabic or Persian letters are not accepted for this field.';

  @override
  String get subscriptionsCardHolderLatinOk => 'OK';

  @override
  String get subscriptionsMoyasarCardFieldHint =>
      'Enter the cardholder name in Latin capital letters and Western digits (0–9) exactly as printed on the card.';

  @override
  String get subscriptionsCvv => 'CVV';

  @override
  String get subscriptionsCardLabel => 'Card label (optional)';

  @override
  String get subscriptionsSaveCard => 'Save card';

  @override
  String get subscriptionsFieldRequired => 'Required';

  @override
  String get subscriptionsCheckoutTitle => 'Checkout summary';

  @override
  String get subscriptionsLegalNote =>
      'Activating this subscription grants you full and unlimited access to all premium features within the platform throughout the subscription period.';

  @override
  String get subscriptionsCreditMadaTitle => 'Credit / mada card';

  @override
  String get paymentGatewayUnavailable =>
      'Payments are unavailable right now. Try again later or contact support.';

  @override
  String get subscriptionsPay => 'Complete payment';

  @override
  String get subscriptionsPlanLine => 'Plan';

  @override
  String get subscriptionsPeriodLine => 'Period';

  @override
  String get subscriptionsOriginalLine => 'Original price';

  @override
  String get subscriptionsDiscountLine => 'Discount';

  @override
  String get subscriptionsTotalLine => 'Total';

  @override
  String get subscriptionsPaymentMethod => 'Payment method';

  @override
  String get subscriptionsPaySavedCard => 'Saved card';

  @override
  String get subscriptionsPayNewCard => 'Credit / mada card';

  @override
  String get subscriptionsApplePay => 'Apple Pay';

  @override
  String get subscriptionsMadaPay => 'Mada Pay';

  @override
  String get subscriptionsPaymentSuccess => 'Payment successful';

  @override
  String get subscriptionsPaymentFailed => 'Payment failed';

  @override
  String get subscriptionsDownloadInvoice => 'Download invoice';

  @override
  String get subscriptionsInvoiceSaved => 'Invoice saved';

  @override
  String get subscriptionsFilterAll => 'All';

  @override
  String get subscriptionsFilterSuccess => 'Paid';

  @override
  String get subscriptionsFilterPending => 'Pending';

  @override
  String get subscriptionsFilterFailed => 'Failed';

  @override
  String get subscriptionsSearch => 'Search';

  @override
  String get subscriptionsTxnRef => 'Transaction ref';

  @override
  String get subscriptionsStatus => 'Status';

  @override
  String get subscriptionsTeamTitle => 'Team & seats';

  @override
  String get subscriptionsSeatsUsed => 'Seats used';

  @override
  String get subscriptionsAddMember => 'Add teammate';

  @override
  String get subscriptionsUpgradeHint =>
      'You reached the seat limit — upgrade your plan.';

  @override
  String get subscriptionsUpgradeCta => 'Upgrade plan';

  @override
  String get subscriptionsUsageTitle => 'Usage';

  @override
  String get subscriptionsRenewFalBody =>
      'FAL display renewal is linked to your active subscription. Open organization settings to renew the public license code.';

  @override
  String get subscriptionsOpenOrgSettings => 'Open organization settings';

  @override
  String get subscriptionsDetailsTitle => 'Current subscription';

  @override
  String get subscriptionsNoSubscription => 'No active subscription';

  @override
  String get subscriptionsOrgSubscriptionExpired =>
      'Organization subscription is inactive. Renew to keep FAL renewal and desk features.';

  @override
  String get subscriptionsAuthenticateToPay => 'Confirm with biometrics';

  @override
  String get subscriptionsBiometricFailed =>
      'Biometric authentication failed or cancelled';

  @override
  String get subscriptionsYearlyDiscountNote =>
      'Yearly billing includes a 20% discount vs monthly.';

  @override
  String get subscriptionsExtraSeats => 'Buy extra seats';

  @override
  String get subscriptionsSharePaymentLink => 'Share payment summary';

  @override
  String get subscriptionsSharePaymentSubject => 'Subscription payment';

  @override
  String get subscriptionsCheckoutRefundPolicy =>
      'By paying, you confirm that the subscription activates for the selected plan and billing period. Subscription fees are not refundable once charged.';

  @override
  String get subscriptionsMarketingPaywallTitle => 'Subscription required';

  @override
  String get subscriptionsMarketingPaywallBody =>
      'Marketing actions that affect contracts, permits, publishing, or listings require an active subscription. Open plans to subscribe, then you can continue immediately.';

  @override
  String get subscriptionsPaywallExpiredTitle => 'Subscription inactive';

  @override
  String get subscriptionsPaywallNoAutoRenewBody =>
      'Your paid subscription period has ended (by date and time). This action is blocked until you subscribe again. Your data remains; you can keep working within free-tier limits after closing this dialog.';

  @override
  String get subscriptionsPaywallAutoRenewFailBody =>
      'Automatic renewal could not charge your card (declined or insufficient funds). This action stays blocked until payment succeeds or you renew manually. Update your card or open plans to pay.';

  @override
  String get subscriptionsPaywallCloseLabel => 'Close';

  @override
  String get subscriptionsPaywallGoPlans => 'Plans & pay';

  @override
  String get subscriptionsCancelEndTitle => 'Cancel subscription';

  @override
  String subscriptionsCancelEndBody(String date) {
    return 'If you cancel, auto-renewal stops. Your benefits stay active until the end of the paid period ($date).';
  }

  @override
  String get subscriptionsContinue => 'Continue';

  @override
  String get subscriptionsGoBack => 'Go back';

  @override
  String get subscriptionsRetentionTitle => 'One-time loyalty offer';

  @override
  String get subscriptionsRetentionBody =>
      'Stay with us: get 20% off your next renewal if you keep your subscription now. This offer is shown only once.';

  @override
  String get subscriptionsRetentionStay => 'Keep subscription';

  @override
  String get subscriptionsRetentionDecline => 'Continue cancellation';

  @override
  String get subscriptionsChurnTitle => 'Help us improve';

  @override
  String get subscriptionsChurnBody =>
      'What is the main reason you are cancelling? (optional)';

  @override
  String get subscriptionsChurnSkip => 'Skip';

  @override
  String get subscriptionsChurnSubmit => 'Submit & cancel';

  @override
  String get subscriptionsChurnReasonPrice => 'Price';

  @override
  String get subscriptionsChurnReasonFeatures => 'Features / limits';

  @override
  String get subscriptionsChurnReasonSupport => 'Support';

  @override
  String get subscriptionsChurnReasonOther => 'Other';

  @override
  String get subscriptionsChurnDetailHint => 'Additional details (optional)';

  @override
  String get opsDeskDeniedTitle => 'Access denied';

  @override
  String get opsDeskDeniedBody =>
      'This application is reserved for the platform operations team only';

  @override
  String get opsDeskExit => 'Close the app';

  @override
  String get opsDeskTitle => 'Platform operations desk';

  @override
  String get opsTabTickets => 'Tickets';

  @override
  String get opsDeskTabReports => 'Reports';

  @override
  String get opsDeskTabUsers => 'Users';

  @override
  String get opsDeskTabTeam => 'Operations team';

  @override
  String get opsDeskTabLoginAds => 'Login ads';

  @override
  String get opsDeskTabBilling => 'Billing';

  @override
  String get opsDeskTabNotices => 'Notices';

  @override
  String get opsDeskRoleAll => 'All my roles';

  @override
  String get opsDeskRoleSupport => 'Support';

  @override
  String get opsDeskRoleCompliance => 'Compliance';

  @override
  String get opsDeskRoleFinance => 'Finance';

  @override
  String get opsDeskGrantTooltip => 'Grant operations access';

  @override
  String get opsDeskRevoke => 'Revoke access';

  @override
  String get opsDeskSearchHint =>
      'Search by name, national ID / iqama, or phone';

  @override
  String get opsDeskAiDraft => 'AI draft';

  @override
  String get opsDeskSendReply => 'Send reply';

  @override
  String get opsDeskReplyHint => 'Reply text (does not charge or ban)';

  @override
  String get opsDeskNoTickets => 'No tickets';

  @override
  String get opsDeskNoReports => 'No open reports';

  @override
  String get opsDeskNoUsers => 'No results';

  @override
  String get opsDeskSaved => 'Saved';

  @override
  String get opsDeskForbidden => 'Not allowed';

  @override
  String get opsDeskOptions => 'Options';

  @override
  String get opsDeskAccept => 'Accept';

  @override
  String get opsDeskDismiss => 'Dismiss';

  @override
  String get opsDeskFeeSave => 'Save price';

  @override
  String get opsDeskAdTitleAr => 'Ad title (Arabic)';

  @override
  String get opsDeskAdTitleEn => 'Ad title (English)';

  @override
  String get opsDeskAdSubAr => 'Ad subtitle (Arabic)';

  @override
  String get opsDeskAdSubEn => 'Ad subtitle (English)';

  @override
  String get opsDeskAdImage => 'Image URL';

  @override
  String get opsDeskAdLink => 'Destination URL';

  @override
  String get opsDeskAdPublish => 'Publish ad';

  @override
  String get opsDeskNoticeUserId => 'Recipient';

  @override
  String get opsDeskNoticeTitleAr => 'Notice title (Arabic)';

  @override
  String get opsDeskNoticeTitleEn => 'Notice title (English)';

  @override
  String get opsDeskNoticeBodyAr => 'Notice body (Arabic)';

  @override
  String get opsDeskNoticeBodyEn => 'Notice body (English)';

  @override
  String get opsDeskNoticeSend => 'Send notice';

  @override
  String opsDeskDeniedHello(String name) {
    return 'Hello $name';
  }

  @override
  String get opsDeskDeniedHelloGuest => 'Welcome';

  @override
  String get opsDeskDeniedPolite =>
      'We\'re glad you\'re here. The Windows desktop app is reserved for the platform operations team, and your account does not have access. Continue on the web or the mobile app with your marketplace permissions.';

  @override
  String get opsDeskOpenWeb => 'Open the platform on the web';

  @override
  String get opsDeskOpenMobile => 'Open the platform on mobile';

  @override
  String get opsDeskModeOps => 'Platform operations';

  @override
  String get opsDeskModeMarket => 'Marketplace user';

  @override
  String get opsDeskLoginHint =>
      'Platform operations team sign-in only. Marketplace stays on web and the mobile app.';

  @override
  String get opsDeskUsersHint =>
      'A marketplace account type (marketer / office / establishment) is not operations-team membership. Add someone to the operations team only from the shield icon after choosing capabilities.';

  @override
  String get opsDeskPreviewBeforePublish => 'Preview before approval';

  @override
  String get opsDeskPreviewWhere => 'Where it appears';

  @override
  String get opsDeskDraftLive =>
      'Your edits appear here as the user will see them. Check the placement, then approve.';

  @override
  String get opsDeskApprovePublish => 'Approve & publish';

  @override
  String get opsDeskNoticePreview => 'Notice preview';

  @override
  String get opsDeskColName => 'Name';

  @override
  String get opsDeskColType => 'Marketplace type';

  @override
  String get opsDeskColOps => 'Operations team';

  @override
  String get opsTitleOwnerIndividual => 'Individual owner';

  @override
  String get opsTitleMarketer => 'Real-estate marketer';

  @override
  String get opsTitleOffice => 'Real-estate office';

  @override
  String get opsTitleCompany => 'Real-estate company';

  @override
  String get opsTitleInstitution => 'Real-estate establishment';

  @override
  String get opsTitleAgency => 'Real-estate agency';

  @override
  String get opsTitleUser => 'User';

  @override
  String get opsDeskTabAudit => 'Audit log';

  @override
  String get opsDeskResolve => 'Close ticket';

  @override
  String get opsDeskPrint => 'Print';

  @override
  String get opsDeskNoAudit => 'No audit rows yet';

  @override
  String get opsDeskPrintTickets => 'Print tickets';

  @override
  String get opsDeskPrintAudit => 'Print audit';

  @override
  String get opsDeskRoleDeputy => 'Deputy system manager';

  @override
  String get opsDeskRoleAds => 'Ads';

  @override
  String get opsDeskRolePromo => 'Offers & discounts';

  @override
  String get opsDeskRoleBan => 'Ban';

  @override
  String get opsDeskRoleTeam => 'Team notices';

  @override
  String get opsDeskTabPromos => 'Offers';

  @override
  String get opsDeskTabOpsSettings => 'Operations settings';

  @override
  String get opsDeskAdPlacement => 'Ad placement';

  @override
  String get opsDeskAdPlaceLogin => 'Large login screens';

  @override
  String get opsDeskAdPlaceInApp => 'In-app for users';

  @override
  String get opsDeskAdPlaceTeam => 'Operations team';

  @override
  String get opsDeskAdPlaceSupport => 'Support cards';

  @override
  String get opsDeskPromoCode => 'Discount code';

  @override
  String get opsDeskPromoValue => 'Percent or value';

  @override
  String get opsDeskPromoSave => 'Save offer';

  @override
  String get opsDeskBan => 'Ban';

  @override
  String get opsDeskLiftBan => 'Lift ban';

  @override
  String get opsDeskBanReason => 'Ban reason';

  @override
  String get opsDeskBroadcastTeam => 'Send to the whole team';

  @override
  String get opsDeskSettingsHint =>
      'Language and theme for the operations desk — separate from marketplace settings on web and mobile.';

  @override
  String get opsDeskFilterAll => 'All';

  @override
  String get opsDeskFilterActive => 'Active (7 days)';

  @override
  String get opsDeskFilterInactive => 'Inactive';

  @override
  String get opsDeskFilterIdle => 'Idle (30 days)';

  @override
  String get opsDeskFilterBanned => 'Banned';

  @override
  String get opsDeskFilterLocked => 'Locked out of the app';

  @override
  String get opsDeskFilterPending => 'Pending activation';

  @override
  String get opsDeskFilterStaff => 'Operations team';

  @override
  String get opsDeskFilterOffice => 'Real-estate office';

  @override
  String get opsDeskFilterCompany => 'Real-estate company';

  @override
  String get opsDeskFilterInstitution => 'Real-estate institution';

  @override
  String get opsDeskFilterMarketer => 'Marketer';

  @override
  String get opsDeskFilterOwner => 'Individual owner';

  @override
  String get opsDeskAddToTeam => 'Add to operations team';

  @override
  String get opsDeskOnTeam => 'On the team';

  @override
  String get opsDeskTerminateSessions => 'End login sessions';

  @override
  String get opsDeskSendNoticeTo =>
      'Send a notice to this user — open the Notices tab';

  @override
  String get opsDeskCopyId => 'Copy national ID / iqama';

  @override
  String get opsDeskTabIntel => 'Activity & sales';

  @override
  String get opsDeskTabCampaigns => 'Push & in-app campaigns';

  @override
  String get opsDeskMostLogins => 'Most logins';

  @override
  String get opsDeskMostSales => 'Most sales';

  @override
  String get opsDeskPrintUsers => 'Print users';

  @override
  String get opsDeskPrintIntel => 'Print activity';

  @override
  String get opsDeskPrintCampaigns => 'Print campaigns';

  @override
  String get opsDeskCampaignMedia => 'Image or video URL next to the notice';

  @override
  String get opsDeskCampaignDeep => 'Destination when opened';

  @override
  String get opsDeskCampaignAudience => 'Recipient account type';

  @override
  String get opsDeskCampaignAllTypes => 'All account types';

  @override
  String get opsDeskCampaignSave => 'Schedule campaign';

  @override
  String get opsDeskCampaignSendNow => 'Send now';

  @override
  String get opsDeskCampaignStarts => 'Send from';

  @override
  String get opsDeskCampaignEnds => 'Campaign ends (then expires)';

  @override
  String get opsDeskCampaignTarget => 'Name or national ID (optional)';

  @override
  String get opsDeskTeamActive => 'Active on the team';

  @override
  String get opsDeskTeamInactive => 'Inactive on the team';

  @override
  String get opsDeskLogins => 'Logins';

  @override
  String get opsDeskLogouts => 'Logouts';

  @override
  String get opsDeskSales => 'Successful sales';

  @override
  String get opsDeskLastLogin => 'Last login';

  @override
  String get opsDeskLastLogout => 'Last logout';

  @override
  String get opsDeskVerification => 'Verification';

  @override
  String get opsDeskCampaignSent => 'Sent';

  @override
  String get opsDeskNoCampaigns => 'No campaigns yet';

  @override
  String get opsDeskNoIntel => 'Not enough data yet';

  @override
  String get opsDeskFilterOnline => 'Online now';

  @override
  String get opsDeskFilterOffline => 'Offline';

  @override
  String get opsDeskHoursToday => 'Hours today';

  @override
  String get opsDeskHours7d => 'Hours (7 days)';

  @override
  String opsDeskOnlineNow(int count) {
    return 'Online now: $count';
  }

  @override
  String opsDeskStaffOnline(int count) {
    return 'Staff online: $count';
  }

  @override
  String get opsDeskSubsActive => 'Active subscriptions';

  @override
  String get opsDeskSubsPending => 'Pending subscriptions';

  @override
  String get opsDeskDupGateway => 'Duplicate gateway ids';

  @override
  String get opsDeskPayStuck => 'Payments pending over 1 hour';

  @override
  String get opsDeskCampaignSendAll =>
      'Send to everyone (batched until done, no 400 cap)';

  @override
  String get opsDeskCampaignIdleNudge =>
      'Idle reminder only (30+ days) — skips active users';

  @override
  String get opsDeskCampaignReceipts => 'Delivery report';

  @override
  String get opsDeskReceiptDelivered => 'Delivered';

  @override
  String get opsDeskReceiptRead => 'Opened';

  @override
  String get opsDeskPurged => 'Removed from inboxes';

  @override
  String get opsDeskIdleHint =>
      'Normal broadcasts skip anyone idle 90 days. Use the idle reminder to reach them by name or account type.';

  @override
  String get opsDeskWatchHint =>
      'Subscription and billing anomalies — export and print with finance permission.';

  @override
  String get opsDeskTeamTimeHint =>
      'Staff attendance from login/logout sessions. Windows idle is 3 minutes then a 1-minute countdown then sign-out, and session duration is recorded.';

  @override
  String get opsDeskWorkHours => 'Work';

  @override
  String get opsDeskPromoHint =>
      'Codes may be Arabic, English, numbers, symbols, or a public name. Each signed-in user can use a code once. The discount is calculated on the server for subscriptions, invoices, and one-time payments.';

  @override
  String get opsDeskPromoKind => 'Discount type';

  @override
  String get opsDeskPromoKindPercent => 'Percent off';

  @override
  String get opsDeskPromoKindFixed => 'Fixed amount off (SAR)';

  @override
  String get opsDeskPromoKindTrial => 'Trial days (does not change the price)';

  @override
  String get opsDeskPromoKindBonus => 'First-payment bonus (SAR off)';

  @override
  String get opsDeskPromoShare => 'Share code';

  @override
  String get opsDeskPromoCopied => 'Code copied';

  @override
  String get opsDeskPromoUsed => 'Used';

  @override
  String get opsDeskPromoRedemptions => 'Who used this code';

  @override
  String get opsDeskPromoExport => 'Export who used it';

  @override
  String get opsDeskPromoActive => 'Active';

  @override
  String get opsDeskPromoInactive => 'Off';

  @override
  String get opsDeskPromoMax => 'Max uses (optional)';

  @override
  String get opsDeskPromoFilterHint => 'Name, national ID, or account type';

  @override
  String get opsDeskGrantPlan => 'Grant a plan';

  @override
  String get opsDeskGrantPlanHint =>
      'Pick the plan that matches this account type, then the period. Individual owners stay on the free tier and pay catalog fees instead. Staff without a plan can still use a discount code or pay from marketplace mode.';

  @override
  String get opsDeskGrantMonths => 'Grant period';

  @override
  String get opsDeskGrantMonth1 => '1 month';

  @override
  String get opsDeskGrantMonth3 => '3 months';

  @override
  String get opsDeskGrantMonth6 => '6 months';

  @override
  String get opsDeskGrantMonth12 => '12 months';

  @override
  String get opsDeskGrantFreeTier =>
      'This account type has no paid plan — free marketplace access plus one-time catalog fees.';

  @override
  String get opsDeskGrantConfirm => 'Activate plan';

  @override
  String get opsDeskGrantOk => 'Plan activated until the granted period ends.';

  @override
  String get checkoutPromoCode => 'Discount code';

  @override
  String get checkoutPromoApply => 'Apply';

  @override
  String get checkoutPromoApplied => 'Discount applied';

  @override
  String get checkoutPromoRemove => 'Remove code';

  @override
  String get checkoutPromoZero =>
      'This code brings the amount to zero. Ask finance to grant the plan instead of paying.';

  @override
  String get promoErrInvalid => 'This discount code is not valid.';

  @override
  String get promoErrUsed => 'You have already used this code.';

  @override
  String get promoErrExpired => 'This discount code has expired.';

  @override
  String get promoErrSoldOut => 'This discount code has reached its use limit.';

  @override
  String get promoErrAudience => 'This code is not for your account type.';

  @override
  String get promoErrNotStarted => 'This discount code is not active yet.';

  @override
  String get promoErrActiveSub =>
      'You already have an active plan — this code applies at renewal after it ends.';

  @override
  String get promoErrOtherCampaign =>
      'You already used another live campaign code. Wait until that campaign ends.';

  @override
  String get promoErrWrongPlan =>
      'This discount code is not valid for this plan.';

  @override
  String get promoErrWrongPeriod =>
      'This discount code is not valid for this billing period.';

  @override
  String get promoErrBelowMin =>
      'This order is below the minimum amount for the code.';

  @override
  String get checkoutPromoBrowse => 'Check available codes';

  @override
  String get checkoutPromoChange => 'Change';

  @override
  String get checkoutPromoEdit => 'Edit';

  @override
  String get checkoutPromoUse => 'Use';

  @override
  String get checkoutPromoNone =>
      'No discount codes are available for this checkout.';

  @override
  String get checkoutPromoPercentCol => 'Discount';

  @override
  String get checkoutPromoValidCol => 'Validity';

  @override
  String get checkoutPromoActionCol => 'Action';

  @override
  String get checkoutPromoAvailable => 'Available';

  @override
  String get checkoutPromoSortHighest => 'Highest discount';

  @override
  String get checkoutPromoSortExpiring => 'Ending soon';

  @override
  String get checkoutAutoRenew => 'Auto-renewal';

  @override
  String checkoutAutoRenewHint(String percent) {
    return '$percent% off applies immediately when on, and is removed when off.';
  }

  @override
  String get checkoutBetterPromoNote => 'A higher discount code is available';

  @override
  String get checkoutWantPromoLink => 'Do you want to use a discount code?';

  @override
  String get checkoutPromoCancelIntent => 'Cancel';

  @override
  String get checkoutPayLockedUntilPromo =>
      'Enter and apply a valid better code, or cancel to continue with auto-renew pricing.';

  @override
  String get autoRenewFailedTitle => 'Auto-renewal failed';

  @override
  String autoRenewFailedBody(String planName) {
    return 'Dear customer, we could not automatically renew your $planName plan because there was not enough balance on your card. Please update your payment details to avoid service interruption.';
  }

  @override
  String get checkoutAutoPayBetter =>
      'Auto-pay is a better discount. Turn off auto-renew to use this code, or keep auto-pay.';

  @override
  String checkoutAutoPayDiscountLine(String percent) {
    return 'Auto-pay discount ($percent%)';
  }

  @override
  String checkoutPromoDiscountLine(String code) {
    return 'Discount code: $code';
  }

  @override
  String get checkoutAutoRenewDiscountPlain => 'Auto-renew activation discount';

  @override
  String get checkoutPromoCodeDiscountPlain => 'Promo code discount';

  @override
  String get trialLearnMore => 'Tap here for details';

  @override
  String get trialDetailsTitle => 'Trial details';

  @override
  String get trialStatusActive => 'Active now';

  @override
  String get trialLimitListing => 'Property listings';

  @override
  String get trialLimitTeam => 'Team members';

  @override
  String get trialLimitRequests => 'Market requests';

  @override
  String get trialLimitListingValue => '1';

  @override
  String get trialLimitTeamValue => 'Not included';

  @override
  String get trialLimitRequestsValue => 'Unlimited';

  @override
  String get opsDeskPromoCampaign => 'Campaign name';

  @override
  String get opsDeskPromoCampaignHint =>
      'Codes in the same campaign share one window. A user with a live campaign code cannot use a different campaign until it ends.';

  @override
  String get opsDeskPromoCodeHint =>
      'Type the code exactly as users will enter it — Arabic, English, digits, or symbols. It is not forced to English capitals (that would break Arabic).';

  @override
  String get opsDeskPromoValueHint =>
      'Percent 1–100, or a SAR amount for a fixed discount. Never type a price into a label — the value is stored and formatted as money.';

  @override
  String get opsDeskPromoWindowHint =>
      'Starts and ends at the chosen date and time. After the end, the code stops immediately.';

  @override
  String get opsDeskPromoStarts => 'Valid from';

  @override
  String get opsDeskPromoEnds => 'Valid until';

  @override
  String get opsDeskExportExcel => 'Excel';

  @override
  String get opsDeskTicketRequester => 'Requester';

  @override
  String get opsDeskTicketAssignee => 'Assigned to';

  @override
  String get opsDeskGrantIndividualWhy =>
      'Individual owners and regular users are not sold a monthly/yearly plan. They use the marketplace for free and pay catalog one-time fees when they publish. Granting a marketer/office plan would give them the wrong product.';

  @override
  String get opsDeskTicketWelcome => 'Open & greet';

  @override
  String get opsDeskNationalId => 'National ID / Iqama';

  @override
  String get opsDeskPhone => 'Mobile';

  @override
  String get opsDeskLicense => 'License number';

  @override
  String get opsDeskNoticePickHint =>
      'Pick the recipient from the Users tab — system IDs are not shown';

  @override
  String get opsDeskCopiedNationalId => 'National ID / iqama copied';

  @override
  String get opsDeskRoleOwner => 'Platform owner';

  @override
  String get opsDeskVerifyPending => 'Pending verification';

  @override
  String get opsDeskVerifyNone => 'Not verified';

  @override
  String get opsDeskVerifyRejected => 'Rejected';

  @override
  String get opsDeskTicketKindComplaint => 'Complaint';

  @override
  String get opsDeskTicketKindSuggestion => 'Suggestion';

  @override
  String get opsDeskTicketStatusOpen => 'Open';

  @override
  String get opsDeskTicketStatusResolved => 'Closed';

  @override
  String get opsDeskTicketStatusEscalated => 'Escalated';

  @override
  String get opsDeskPulseTotal => 'All users';

  @override
  String get opsDeskPulseOnline => 'Online now';

  @override
  String get opsDeskPulseIdle => 'Idle 30 days';

  @override
  String get opsDeskPulseIncomplete => 'Incomplete profile';

  @override
  String get opsDeskPulseFalExpired => 'License expired';

  @override
  String get opsDeskPulseFalExpiring => 'License in 7 days';

  @override
  String get opsDeskPulseSubExpired => 'Subscription ended';

  @override
  String get opsDeskPulseSubExpiring => 'Subscription in 7 days';

  @override
  String get opsDeskPulseGuests => 'Guests (7 days)';

  @override
  String get opsDeskWatchList => 'Watch list';

  @override
  String get opsDeskWatchNotify => 'Notify this list';

  @override
  String get opsDeskPatchProfile => 'Complete / correct profile';

  @override
  String get opsDeskPatchSaved => 'Save profile';

  @override
  String get photographerJoinTitle => 'Join as a property photographer';

  @override
  String get photographerJoinIntro =>
      'This is an overlay on your current account (owner or marketer). Your role and My page listing tabs stay as they are. Review takes up to 24 hours.';

  @override
  String get photographerDisplayName => 'Display name';

  @override
  String get photographerNationalId => 'National ID / Iqama';

  @override
  String get photographerCommercialRegister =>
      'Commercial registration (optional)';

  @override
  String get photographerCity => 'City';

  @override
  String get photographerBio => 'Bio and past work (recommended)';

  @override
  String get photographerPhotoRate => 'Photo session rate';

  @override
  String get photographerVideoRate => 'Video rate';

  @override
  String get photographerTourRate => '3D tour rate';

  @override
  String get photographerUploadPortfolio => 'Upload certificates or past work';

  @override
  String get photographerAcceptPolicy =>
      'I agree to the service and pricing policy';

  @override
  String get photographerPolicyRequired =>
      'You must accept the service policy.';

  @override
  String get photographerSubmitJoin => 'Submit application';

  @override
  String get photographerJoinSubmitted =>
      'Your application is in. Manual review takes up to 24 hours.';

  @override
  String get photographerStatusPending => 'Pending review';

  @override
  String get photographerStatusVerified => 'Verified photographer';

  @override
  String get photographerStatusRejected => 'Application declined';

  @override
  String get photographerReviewSla =>
      'Manual review within 24 hours. After approval you appear in the bookable directory.';

  @override
  String get photographerHubTitle => 'My photographer page';

  @override
  String get photographerTabIncoming => 'Incoming';

  @override
  String get photographerTabActive => 'In progress';

  @override
  String get photographerTabDone => 'Completed sessions';

  @override
  String get photographerTabPortfolio => 'My work';

  @override
  String get photographerTabCalendar => 'Calendar';

  @override
  String get photographerBookFlowHint =>
      'Pick the services; the price comes from the photographer’s rates. After you send, the request lands in their Incoming tab. Accepting within 24 hours agrees the price, then they upload media within the agreed limits.';

  @override
  String get photographerIncomingHint =>
      'Accepting within 24 hours agrees the quoted price. The request then moves to In progress so you can upload only the photos/video/tour that were requested.';

  @override
  String get photographerQuoteTitle => 'Confirm shoot request and price';

  @override
  String photographerQuoteBody(String name, String amount) {
    return 'Request to $name. Quoted price $amount. The photographer’s accept is the agreement. It appears in their Incoming tab.';
  }

  @override
  String get photographerQuoteAgreed => 'Agreed price';

  @override
  String photographerDistanceKm(String km) {
    return '$km km';
  }

  @override
  String photographerPhotoLimit(int count) {
    return 'This request allows at most $count photos.';
  }

  @override
  String photographerDeliverCaps(int photos, int videos) {
    return 'Limit: $photos photos, $videos video';
  }

  @override
  String get photographerCalendarEmpty => 'No sessions on this day.';

  @override
  String photographerCalendarCapRemaining(int left, int cap) {
    return 'Today’s accepts: $left of $cap left';
  }

  @override
  String photographerAcceptWindow(String left) {
    return 'Time left to respond: $left';
  }

  @override
  String get photographerAcceptWindowExpired =>
      'The 24-hour window ended and the request was cancelled.';

  @override
  String get photographerPickPhotos => 'Choose photos';

  @override
  String get photographerPickVideo => 'Upload video';

  @override
  String get photographerVideoPicked => 'Video selected';

  @override
  String get photographerTourReady => 'Tour is ready';

  @override
  String get photographerDeliverNeedPhotos => 'Add photos before delivering.';

  @override
  String get photographerDeliverNeedVideo =>
      'Upload a video because this request includes video.';

  @override
  String get photographerDeliverNeedTour =>
      'Build the in-app tour because this request includes a 3D tour.';

  @override
  String get inAppTourEngineHint =>
      'Interactive in-app walkthrough (linked photos and hotspots). An external Matterport link remains an extra option — not a built-in cloud engine.';

  @override
  String get inAppTourPanHint => 'Pinch to zoom and pan inside the scene';

  @override
  String get photographerSlaOverdue => 'Over 24 hours — review manually';

  @override
  String photographerSessionsOnDay(int count) {
    return '$count sessions on this day';
  }

  @override
  String get photographerEmptyTab => 'Nothing here yet';

  @override
  String get photographerEmptyPortfolio =>
      'Your gallery appears after the first delivered shoot.';

  @override
  String get photographerAccept => 'Accept';

  @override
  String get photographerDecline => 'Decline';

  @override
  String get photographerDeclineTitle => 'Decline request';

  @override
  String get photographerDeclineReason => 'Reason';

  @override
  String get photographerDeclineConfirm => 'Confirm decline';

  @override
  String get photographerUploadMedia => 'Upload requested media';

  @override
  String get photographerDeliverTitle => 'Deliver work';

  @override
  String get photographerDeliverConfirm => 'Deliver work';

  @override
  String get photographerTechnicalNotes => 'Technical notes (optional)';

  @override
  String get photographerNeedListing =>
      'Link this request to a saved listing before uploading media.';

  @override
  String get photographerDailyCapTitle => 'Daily accept cap';

  @override
  String get photographerShootFallback => 'Photo shoot';

  @override
  String get photographerBookTitle => 'Request professional photography';

  @override
  String get photographerKindPhotos => 'Photos';

  @override
  String get photographerKindVideo => 'Video';

  @override
  String get photographerKindTour => '3D tour';

  @override
  String get photographerPickSlot => 'Pick date and time';

  @override
  String get photographerDirectoryEmpty =>
      'No verified photographers yet. You can join from My desk.';

  @override
  String get photographerSendRequest => 'Send request';

  @override
  String get photographerRequestSent =>
      'Request sent to the photographer’s Incoming tab. They have 24 hours to accept or decline. Accepting agrees the quoted price, then they upload within the agreed limits.';

  @override
  String get photographerQueuedUntilPublish =>
      'Photographer choice saved locally and sent after the listing is saved.';

  @override
  String get photographerCertifiedTooltip => 'Certified photographer';

  @override
  String get photographerOpenWorkspace => 'Open my photographer page';

  @override
  String get photographerJoinCta => 'Join as photographer';

  @override
  String get photographerRequestFromMedia => 'Request professional photography';

  @override
  String get inAppTourBuild => 'Build in-app tour';

  @override
  String get inAppTourBadge => 'Virtual tour';

  @override
  String get inAppTourOpen => 'Open virtual tour';

  @override
  String get developerComingSoonTitle => 'Property developer';

  @override
  String get developerComingSoonBody =>
      'The developer service is being built and will be available soon. You can register your interest and we will notify you at launch.';

  @override
  String get developerInterestName => 'Name';

  @override
  String get developerInterestEmail => 'Email';

  @override
  String get developerInterestType => 'Development type needed';

  @override
  String get developerInterestSubmit => 'Register interest';

  @override
  String get developerInterestSkip => 'Later';

  @override
  String get developerInterestSaved =>
      'We saved your interest and will notify you at launch.';

  @override
  String listingInventoryCapHint(int used, int max) {
    return 'Listings and requests: $used of $max';
  }

  @override
  String get completedDealsFilter30d => 'Last 30 days';

  @override
  String get completedDealsFilterYear => 'Last year';

  @override
  String get completedDealsFilterAll => 'All';

  @override
  String get regaManualEntry => 'Full manual entry';

  @override
  String get regaManualLicenseNo => 'License number';

  @override
  String get regaManualDeedNo => 'Deed number';

  @override
  String get regaManualPrice => 'Price';

  @override
  String get regaManualCity => 'City';

  @override
  String get regaManualExpiry => 'Expiry date';

  @override
  String get regaManualImage => 'License image (evidence)';

  @override
  String get regaManualSave => 'Use manual entry';

  @override
  String get photographerDialogCancel => 'Cancel';

  @override
  String get photographerDialogSave => 'Save';

  @override
  String photographerFilesCount(int count) {
    return '$count files';
  }

  @override
  String photographerRatingLine(String avg, int count) {
    return '$avg ($count)';
  }

  @override
  String get opsDeskTabPhotographers => 'Photographers';

  @override
  String plusInventoryTooltip(int remaining, int max) {
    return '$remaining of $max remaining';
  }

  @override
  String get listingOfficialRegaBenchTitle => 'REGA official benchmark';

  @override
  String listingOfficialRegaBenchSale(
      String city, String type, String amount, int deals, String period) {
    return 'Average price per m² in $city for $type: $amount — from $deals deals ($period). A market reference, not a required listing price.';
  }

  @override
  String listingOfficialRegaBenchRent(
      String city, String type, String amount, int deals, String period) {
    return 'Average rent in $city for $type: $amount — from $deals contracts ($period). A market reference, not a required listing price.';
  }

  @override
  String get marketInsightsOfficialRegaTitle => 'REGA sale indicators';

  @override
  String get marketInsightsOfficialRegaHint =>
      'Average price per m² from the latest REGA open bulletin. It does not replace your platform data.';

  @override
  String get formExitKeepEditing => 'Edit';

  @override
  String get formExitSaveDraft => 'Save';

  @override
  String get formExitLeave => 'Leave';

  @override
  String get formExitBody =>
      'This is not published yet. Continue from where you are, save a draft on this device for this session only, or leave and clear the fields.';

  @override
  String get formExitDraftSaved =>
      'Your entries were saved as a draft on this device. You can return to the last field you filled and continue. This draft is not stored in the database and is removed when you sign out. Choosing Leave later will clear every field.';

  @override
  String get formExitLeaveTitle => 'Leave and clear the fields?';

  @override
  String get formExitLeaveBody =>
      'Everything you typed will be cleared. Nothing will be kept as a draft on this device. Confirm to leave, or cancel to stay where you are.';

  @override
  String get formExitConfirm => 'Confirm';

  @override
  String get formExitCancel => 'Cancel';

  @override
  String get formExitCleared =>
      'All entered data was cleared. Nothing was saved as a draft.';

  @override
  String get deedDuplicateActive =>
      'This deed number is already on an active sale, auction, or investment listing whose deal is not finished. A second listing with the same deed is not allowed until that deal is closed.';

  @override
  String get deedNumberGovHint =>
      'The number is checked in-app during development. Later it will be verified with government deed data, and the project operations desk will be notified on conflicts.';

  @override
  String get capsLockOn => 'Caps Lock is ON';

  @override
  String get paymentSubscriptionActivated =>
      'Payment completed and the subscription is active.';

  @override
  String get paymentConfirming =>
      'Payment received. Confirming the transaction.';

  @override
  String get paymentNotActivated =>
      'Payment could not be completed, and the subscription was not activated.';

  @override
  String get planNotForAccount =>
      'This plan is not available for your account type.';

  @override
  String get paymentAmountMismatchReview =>
      'The amount did not match. The payment was stopped for review.';

  @override
  String get paymentTrustNoCardStore =>
      'We do not store the card number or CVV. The subscription is activated only after the payment gateway confirms, not when you tap Pay.';

  @override
  String get invoiceVatInclusiveNote =>
      'The amount shown is the final total. Catalog prices are VAT-inclusive when tax applies; no extra tax is added automatically.';

  @override
  String get invoiceBreakdownSubtotal => 'Before discount';

  @override
  String get invoiceBreakdownDiscount => 'Discount';

  @override
  String get invoiceOfficialNo => 'Invoice number';

  @override
  String get invoiceHideFromLedger => 'Hide from ledger';

  @override
  String get invoiceHideConfirmTitle => 'Hide this invoice from your ledger?';

  @override
  String get invoiceHideConfirmBody =>
      'This does not delete the financial record. It stays in the database for audit and is only hidden from your list.';

  @override
  String get invoiceHiddenOk => 'Hidden from ledger';

  @override
  String get invoicePaymentReference => 'Payment reference';

  @override
  String get invoiceTechnicalSection => 'Technical details';

  @override
  String get invoiceUnavailable => 'Unavailable';

  @override
  String get invoiceFeesLine => 'Fees';

  @override
  String get invoiceVatLine => 'VAT';

  @override
  String get invoicePeriodStart => 'Subscription start';

  @override
  String get invoiceSubscriptionEnd => 'Subscription end';

  @override
  String get invoiceCurrency => 'Currency';

  @override
  String get invoiceQrHint => 'Scan to verify the official invoice number.';

  @override
  String get invoiceViewDetails => 'View invoice';

  @override
  String get invoiceStatusPaid => 'Paid';
}
