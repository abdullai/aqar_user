import 'org_permission_manager.dart';



/// واجهة للتحقق من إظهار التبويبات والشاشات داخل «إدارتي» والشريط الرئيسي.

class PermissionService {

  PermissionService(this._perm, {required this.isOwner});



  final Map<String, dynamic>? _perm;

  final bool isOwner;



  bool can(String key) =>

      OrgPermissionManager.ownerOr(_perm, key, isOwner: isOwner);



  bool get manageTeam => can(OrgPermissionKeys.manageTeam);

  bool get addProperties => can(OrgPermissionKeys.addProperties);

  bool get addAds => can(OrgPermissionKeys.addAds);

  bool get addListingRequests => can(OrgPermissionKeys.addListingRequests);

  bool get editProperties => can(OrgPermissionKeys.editProperties);

  bool get viewMarket => can(OrgPermissionKeys.viewMarket);

  bool get viewProfile => can(OrgPermissionKeys.viewProfile);

  bool get accessChat => can(OrgPermissionKeys.accessChat);

  bool get editOrgSettings => can(OrgPermissionKeys.editOrgSettings);

  bool get viewAnalytics => can(OrgPermissionKeys.viewAnalytics);

  bool get viewReports => can(OrgPermissionKeys.viewReports);

  bool get manageSubscription => can(OrgPermissionKeys.manageSubscription);

  bool get exportData => can(OrgPermissionKeys.exportData);

  bool get inviteMembers => can(OrgPermissionKeys.inviteMembers);

  bool get manageChatRooms => can(OrgPermissionKeys.manageChatRooms);

  bool get viewMemberActivity => can(OrgPermissionKeys.viewMemberActivity);



  // --- Legacy names (ما يزال بعض الشاشات يشير إليها) ---

  bool get showDeskTabMonitoring => viewAnalytics;

  bool get showDeskTabTeamChat => accessChat;

  bool get showDeskTabTeam => manageTeam;

  bool get showDeskTabJoinRequests => manageTeam;

  bool get showDeskTabInsights => viewAnalytics;



  /// لوحة الفريق: ملخص + رسوم للمالك أو من يدير الفريق أو يرى الإحصائيات.

  bool get showDeskTabTeamDashboard =>

      isOwner || manageTeam || viewAnalytics;



  /// إدارة الأعضاء.

  bool get showDeskTabManageMembers => manageTeam;



  /// طلبات الانضمام المعلّقة.

  bool get showDeskTabJoinRequestsDesk => manageTeam;



  /// اختيار عضو وتعديل صلاحياته.

  bool get showDeskTabRolesPermissions => manageTeam;



  /// الدردشات الداخلية.

  bool get showDeskTabInternalChat => accessChat;



  /// إحصائيات وتقارير موسّعة.

  bool get showDeskTabAnalyticsReports => viewAnalytics || viewReports;



  /// إعدادات المنشأة (هوية، فال، مقاعد) — اشتراك ضمن الإعدادات.

  bool get showDeskTabOrganizationSettings =>

      editOrgSettings || manageSubscription;



  /// سجل نشاط الأعضاء (سجلات org_activity_log).

  bool get showDeskTabMemberActivity => viewMemberActivity;



  /// تبويبات الشريط السفلي الرئيسية (معرّفات ثابتة للاستدعاء من الواجهة).

  static const String mainTabHome = 'home';

  static const String mainTabMarket = 'market';

  static const String mainTabProfile = 'profile';

  static const String mainTabAddProperty = 'add_property';

  static const String mainTabAddAd = 'add_ad';

  static const String mainTabAddRequest = 'add_request';

  static const String mainTabMyOrg = 'my_org';

  static const String mainTabChat = 'chat';

  static const String mainTabNotifications = 'notifications';



  /// تبويبات فرعية داخل «إدارتي».

  static const String orgSubTeamDashboard = 'team_dashboard';

  static const String orgSubManageMembers = 'manage_members';

  static const String orgSubJoinRequests = 'join_requests';

  static const String orgSubRoles = 'roles_permissions';

  static const String orgSubTeamChat = 'team_chat';

  static const String orgSubAnalytics = 'analytics';

  static const String orgSubOrgSettings = 'org_settings';

  static const String orgSubMemberActivity = 'member_activity';



  bool canViewMainNavTab(String tab) {

    switch (tab) {

      case mainTabHome:

      case mainTabNotifications:

        return true;

      case mainTabMarket:

        return viewMarket;

      case mainTabProfile:

        return viewProfile;

      case mainTabAddProperty:

        return addProperties;

      case mainTabAddAd:

        return addAds;

      case mainTabAddRequest:

        return addListingRequests;

      case mainTabMyOrg:

        return isOwner ||

            manageTeam ||

            accessChat ||

            viewAnalytics ||

            viewReports ||

            editOrgSettings ||

            manageSubscription ||

            addProperties ||

            addAds ||

            viewMemberActivity;

      case mainTabChat:

        return accessChat;

      default:

        return false;

    }

  }



  bool canViewOrgSubTab(String subTab) {

    switch (subTab) {

      case orgSubTeamDashboard:

        return showDeskTabTeamDashboard;

      case orgSubManageMembers:

        return showDeskTabManageMembers;

      case orgSubJoinRequests:

        return showDeskTabJoinRequestsDesk;

      case orgSubRoles:

        return showDeskTabRolesPermissions;

      case orgSubTeamChat:

        return showDeskTabInternalChat;

      case orgSubAnalytics:

        return showDeskTabAnalyticsReports;

      case orgSubOrgSettings:

        return showDeskTabOrganizationSettings;

      case orgSubMemberActivity:

        return showDeskTabMemberActivity;

      default:

        return false;

    }

  }

}

