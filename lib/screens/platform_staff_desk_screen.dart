import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/auth/safe_sign_out_service.dart';
import '../core/branding/app_branding.dart';
import '../core/l10n/locale_content.dart';
import '../core/notifications/in_app_notification_sound.dart';
import '../core/payment/platform_fee_catalog.dart';
import '../core/support/support_ticket_assist.dart';
import '../core/support/support_ticket_policy.dart';
import '../core/gestures/app_keyboard_popups.dart';
import '../core/utils/date_helper.dart';
import '../core/utils/phone_display.dart';
import '../core/utils/profile_greeting_from_row.dart';
import '../core/utils/profile_verification_status.dart';
import '../core/workflow/app_role_helper.dart';
import '../l10n/app_localizations.dart';
import '../main.dart' show langNotifier, setAppLang, setAppTheme;
import '../models.dart';
import '../services/account_management_service.dart';
import '../services/ads_service.dart';
import '../services/report_service.dart';
import '../services/support_ticket_service.dart';
import '../services/photographer_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/aqar_text_field.dart';
import '../widgets/subscription_staff_reports_panel.dart';
import '../widgets/support/support_labeled_table.dart';

/// لوحة تشغيل المنصة — قرارات مالية/حظر عبر RPC + تدقيق فقط.
/// على ويندوز/`IS_ADMIN_APP` تُعرض حصراً عبر [PostLoginHome] مع [opsLocked].
class PlatformStaffDeskScreen extends StatefulWidget {
  const PlatformStaffDeskScreen({
    super.key,
    required this.lang,
    this.embedded = false,
    this.opsLocked = false,
  });

  final String lang;
  final bool embedded;
  final bool opsLocked;

  @override
  State<PlatformStaffDeskScreen> createState() =>
      _PlatformStaffDeskScreenState();
}

class _PlatformStaffDeskScreenState extends State<PlatformStaffDeskScreen> {
  final _acct = AccountManagementService(Supabase.instance.client);
  final _tickets = SupportTicketService(Supabase.instance.client);
  final _userQ = TextEditingController();
  final _adTitleAr = TextEditingController();
  final _adTitleEn = TextEditingController();
  final _adSubAr = TextEditingController();
  final _adSubEn = TextEditingController();
  final _adImage = TextEditingController();
  final _adLink = TextEditingController();
  final _noticeTitleAr = TextEditingController();
  final _noticeTitleEn = TextEditingController();
  final _noticeBodyAr = TextEditingController();
  final _noticeBodyEn = TextEditingController();
  final _noticeUserId = TextEditingController();
  String _noticeTargetCaption = '';
  final _promoCode = TextEditingController();
  final _promoValue = TextEditingController();
  final _promoTitleAr = TextEditingController();
  final _promoTitleEn = TextEditingController();
  final _promoMax = TextEditingController();
  final _promoCampaign = TextEditingController();
  String _promoKind = 'percent_off';
  bool _promoActive = true;
  DateTime? _promoFrom;
  DateTime? _promoTo;
  final _feeCtrls = <String, TextEditingController>{};
  String _adPlacement = 'login';
  String _userFilter = 'all';
  String _teamFilter = 'all';
  String _campaignAudience = '';
  String _campDeepRoute = 'user_dashboard';
  DateTime? _campStart;
  DateTime? _campEnd;
  bool _campSendAll = false;
  bool _campIdleNudge = false;
  List<Map<String, dynamic>> _promos = const [];
  List<Map<String, dynamic>> _campaigns = const [];
  List<Map<String, dynamic>> _teamTime = const [];
  Map<String, dynamic> _intel = const {};
  Map<String, dynamic> _billingWatch = const {};
  String _watchKind = '';
  List<Map<String, dynamic>> _watchRows = const [];
  final _campTitleAr = TextEditingController();
  final _campTitleEn = TextEditingController();
  final _campBodyAr = TextEditingController();
  final _campBodyEn = TextEditingController();
  final _campMedia = TextEditingController();
  final _campTarget = TextEditingController();

  Timer? _poll;
  StreamSubscription<AuthState>? _authSub;
  Timer? _userSearchDebounce;
  bool _loading = true;
  String _dest = '';
  Map<String, dynamic> _profile = const {'ok': false, 'is_staff': false};
  Map<String, dynamic> _marketRow = const {};
  List<SupportTicketRow> _complaints = const [];
  List<Map<String, dynamic>> _reports = const [];
  List<Map<String, dynamic>> _directory = const [];
  List<Map<String, dynamic>> _team = const [];
  List<Map<String, dynamic>> _audit = const [];
  List<AdItem> _ads = const [];
  Set<String> _seenTicketIds = {};
  Set<String> _seenReportIds = {};
  bool _chimeReady = false;

  bool get _isAr => langNotifier.value != 'en';
  bool get _isStaff => _profile['is_staff'] == true;
  bool get _isOwner => _profile['is_owner'] == true;
  bool get _canGrant =>
      _profile['can_grant'] == true || _isOwner;
  bool get _canSupport => _profile['can_support'] == true || _isOwner;
  bool get _canModerate => _profile['can_moderate'] == true || _isOwner;
  bool get _canFinance => _profile['can_finance'] == true || _isOwner;
  bool get _canAds =>
      _profile['can_ads'] == true || _canModerate || _isOwner;
  bool get _canPromo =>
      _profile['can_promo'] == true || _canFinance || _isOwner;
  bool get _canBan =>
      _profile['can_ban'] == true || _canModerate || _isOwner;
  bool get _canTeamComms =>
      _profile['can_team_comms'] == true || _isOwner;
  bool get _canCampaigns =>
      _canAds || _canTeamComms || _canFinance || _isOwner;
  bool get _canDirectory =>
      _isOwner || _canGrant || _canSupport || _canBan;
  bool get _canPulse => _isOwner || _canGrant;
  bool get _canTeamTab => _isOwner || _canGrant;

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  void _onUserQueryChanged() {
    _userSearchDebounce?.cancel();
    _userSearchDebounce = Timer(const Duration(milliseconds: 320), () {
      unawaited(_searchUsers());
    });
  }

  @override
  void initState() {
    super.initState();
    langNotifier.addListener(_onLang);
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (!mounted) return;
      unawaited(_load());
    });
    for (final c in [
      _adTitleAr,
      _adTitleEn,
      _adSubAr,
      _adSubEn,
      _adImage,
      _adLink,
      _noticeTitleAr,
      _noticeTitleEn,
      _noticeBodyAr,
      _noticeBodyEn,
    ]) {
      c.addListener(_onDraftChanged);
    }
    _userQ.addListener(_onUserQueryChanged);
    unawaited(_load());
    _poll = Timer.periodic(const Duration(seconds: 22), (_) {
      if (_isStaff) unawaited(_load(quiet: true));
    });
  }

  void _onLang() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _poll?.cancel();
    _userSearchDebounce?.cancel();
    _authSub?.cancel();
    langNotifier.removeListener(_onLang);
    _userQ.dispose();
    _adTitleAr.dispose();
    _adTitleEn.dispose();
    _adSubAr.dispose();
    _adSubEn.dispose();
    _adImage.dispose();
    _adLink.dispose();
    _noticeTitleAr.dispose();
    _noticeTitleEn.dispose();
    _noticeBodyAr.dispose();
    _noticeBodyEn.dispose();
    _noticeUserId.dispose();
    _promoCode.dispose();
    _promoValue.dispose();
    _promoTitleAr.dispose();
    _promoTitleEn.dispose();
    _promoMax.dispose();
    _promoCampaign.dispose();
    _campTitleAr.dispose();
    _campTitleEn.dispose();
    _campBodyAr.dispose();
    _campBodyEn.dispose();
    _campMedia.dispose();
    _campTarget.dispose();
    for (final c in _feeCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet && mounted) setState(() => _loading = true);
    final p = await _acct.myStaffProfile();
    final market = await _acct.myMarketProfile();
    var complaints = <SupportTicketRow>[];
    var reports = <Map<String, dynamic>>[];
    var directory = <Map<String, dynamic>>[];
    var team = <Map<String, dynamic>>[];
    var ads = <AdItem>[];
    var audit = <Map<String, dynamic>>[];
    var promos = <Map<String, dynamic>>[];
    var campaigns = <Map<String, dynamic>>[];
    var intel = <String, dynamic>{};
    var teamTime = <Map<String, dynamic>>[];
    var billingWatch = <String, dynamic>{};
    if (p['is_staff'] == true) {
      complaints = await _tickets.listForStaff();
      reports = await _acct.listListingReports();
      intel = await _acct.userIntel();
      teamTime = await _acct.teamTime();
      if (p['can_finance'] == true || p['is_owner'] == true) {
        billingWatch = await _acct.billingWatch();
      }
      if (!quiet) {
        team = await _acct.teamList();
        ads = await AdsService.loadAds(
          lang: widget.lang,
          fallbackDemo: false,
          ignorePlatform: true,
        );
        directory = await _acct.directory(
          q: _userQ.text.trim(),
          filter: _userFilter,
        );
        audit = await _acct.listAudit();
        promos = await _acct.listPromos();
        campaigns = await _acct.listCampaigns();
        await _acct.runDueCampaigns();
        if (mounted) {
          try {
            await context.read<PlatformFeeCatalog>().refresh();
          } catch (_) {}
        }
      } else {
        team = _team;
        ads = _ads;
        directory = _directory;
        audit = _audit;
        promos = _promos;
        campaigns = _campaigns;
      }
    }
    if (!mounted) return;
    final ids = complaints.map((e) => e.id).where((e) => e.isNotEmpty).toSet();
    final reportIds = reports
        .map((e) => '${e['id'] ?? ''}')
        .where((e) => e.isNotEmpty)
        .toSet();
    final isNew = _chimeReady &&
        (ids.any((id) => !_seenTicketIds.contains(id)) ||
            reportIds.any((id) => !_seenReportIds.contains(id)));
    if (isNew) playInAppNotificationChime();
    setState(() {
      _profile = p;
      _marketRow = market;
      _complaints = complaints;
      _reports = reports;
      _team = team;
      _ads = ads;
      _audit = audit;
      _promos = promos;
      _campaigns = campaigns;
      _intel = intel;
      _teamTime = teamTime;
      _billingWatch = billingWatch;
      _directory = directory;
      _seenTicketIds = ids;
      _seenReportIds = reportIds;
      _chimeReady = true;
      _loading = false;
    });
  }

  Future<void> _searchUsers() async {
    final rows = await _acct.directory(
      q: _userQ.text.trim(),
      filter: _userFilter,
    );
    if (!mounted) return;
    setState(() => _directory = rows);
  }

  String _displayName(AppLocalizations l10n) {
    final fromRow = ProfileGreetingFromRow.displayName(
      _marketRow,
      isAr: _isAr,
    );
    if (fromRow != null && fromRow.trim().isNotEmpty) return fromRow.trim();
    final meta = ProfileGreetingFromRow.displayNameFromAuthMetadata(
      Supabase.instance.client.auth.currentUser?.userMetadata,
    );
    if (meta != null && meta.trim().isNotEmpty) return meta.trim();
    return l10n.opsDeskDeniedHelloGuest;
  }

  String _marketTitle(AppLocalizations l10n) {
    switch (AppRoleHelper.fromAccountType(
      '${_marketRow['account_type'] ?? ''}',
    )) {
      case AppRoleKind.ownerIndividual:
        return l10n.opsTitleOwnerIndividual;
      case AppRoleKind.marketer:
        return l10n.opsTitleMarketer;
      case AppRoleKind.realEstateOffice:
        return l10n.opsTitleOffice;
      case AppRoleKind.realEstateCompany:
        return l10n.opsTitleCompany;
      case AppRoleKind.realEstateInstitution:
        return l10n.opsTitleInstitution;
      case AppRoleKind.agency:
        return l10n.opsTitleAgency;
      case AppRoleKind.publicUser:
        return l10n.opsTitleUser;
    }
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _printTable({
    required String id,
    required String title,
    required List<String> columns,
    required List<List<String>> rows,
  }) async {
    final cfg = ReportConfig(
      id: id,
      title: title,
      columns: columns,
      rows: rows,
    );
    final bytes = await ReportService(
      Supabase.instance.client,
    ).exportToPdf(cfg, isAr: _isAr);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> _exportTable({
    required String id,
    required String title,
    required List<String> columns,
    required List<List<String>> rows,
  }) async {
    await ReportService(Supabase.instance.client).exportToCsv(
      ReportConfig(
        id: id,
        title: title,
        columns: columns,
        rows: rows,
      ),
      id,
      isAr: _isAr,
    );
  }

  Future<void> _exportExcelTable({
    required String id,
    required String title,
    required List<String> columns,
    required List<List<String>> rows,
  }) async {
    await ReportService(Supabase.instance.client).exportToExcel(
      ReportConfig(
        id: id,
        title: title,
        columns: columns,
        rows: rows,
      ),
      id,
      isAr: _isAr,
    );
  }

  Future<void> _printTickets(AppLocalizations l10n) async {
    await _printTable(
      id: 'ops_tickets',
      title: l10n.opsDeskPrintTickets,
      columns: _isAr
          ? const ['الحالة', 'النوع', 'الموضوع', 'التفاصيل', 'وقت الرفع']
          : const ['Status', 'Kind', 'Subject', 'Details', 'Submitted'],
      rows: _complaints
          .map(
            (r) => [
              _ticketStatusLabel(l10n, r.status),
              _ticketKindLabel(l10n, r.kind),
              r.subject,
              r.body,
              _opsWhen(r.createdAt),
            ],
          )
          .toList(),
    );
  }

  Future<void> _printAudit(AppLocalizations l10n) async {
    await _printTable(
      id: 'ops_audit',
      title: l10n.opsDeskPrintAudit,
      columns: _isAr
          ? const ['الوقت', 'الإجراء', 'الجدول', 'المعرف']
          : const ['Time', 'Action', 'Table', 'Id'],
      rows: _audit
          .map(
            (r) => [
              DateHelper.fmtCivilDateTimeRaw(r['created_at'], isAr: _isAr),
              '${r['action'] ?? ''}',
              '${r['target_table'] ?? ''}',
              '${r['target_id'] ?? ''}',
            ],
          )
          .toList(),
    );
  }

  Future<void> _printUsers(AppLocalizations l10n) async {
    await _printTable(
      id: 'ops_users',
      title: l10n.opsDeskPrintUsers,
      columns: _isAr
          ? const [
              'الاسم',
              'رقم الهوية / الإقامة',
              'الصفة',
              'التحقق',
              'الجوال',
              'دخول',
              'خروج',
              'مبيعات',
            ]
          : const [
              'Name',
              'National ID / Iqama',
              'Account type',
              'Verification',
              'Mobile',
              'Logins',
              'Logouts',
              'Sales',
            ],
      rows: _directory
          .map(
            (u) => [
              _opsPersonName(u),
              _opsNationalId(u),
              _accountTypeLabel(l10n, '${u['account_type'] ?? ''}'),
              _verificationLabel(l10n, '${u['verification'] ?? ''}'),
              _opsPhone(u),
              '${u['logins'] ?? ''}',
              '${u['logouts'] ?? ''}',
              '${u['sales'] ?? ''}',
            ],
          )
          .toList(),
    );
  }

  Future<void> _printIntel(AppLocalizations l10n) async {
    final logins = (_intel['most_logins'] is List)
        ? (_intel['most_logins'] as List).whereType<Map>()
        : const <Map>[];
    final sales = (_intel['most_sales'] is List)
        ? (_intel['most_sales'] as List).whereType<Map>()
        : const <Map>[];
    await _printTable(
      id: 'ops_intel',
      title: l10n.opsDeskPrintIntel,
      columns: _isAr
          ? const ['القائمة', 'الاسم', 'رقم الهوية / الإقامة', 'الصفة', 'العدد']
          : const ['List', 'Name', 'National ID / Iqama', 'Account type', 'Count'],
      rows: [
        ...logins.map(
          (r) {
            final m = Map<String, dynamic>.from(r);
            return [
              l10n.opsDeskMostLogins,
              _opsPersonName(m),
              _opsNationalId(m),
              _accountTypeLabel(l10n, '${m['account_type'] ?? ''}'),
              '${m['cnt'] ?? ''}',
            ];
          },
        ),
        ...sales.map(
          (r) {
            final m = Map<String, dynamic>.from(r);
            return [
              l10n.opsDeskMostSales,
              _opsPersonName(m),
              _opsNationalId(m),
              _accountTypeLabel(l10n, '${m['account_type'] ?? ''}'),
              '${m['cnt'] ?? ''}',
            ];
          },
        ),
      ],
    );
  }

  Future<void> _printCampaigns(AppLocalizations l10n) async {
    await _printTable(
      id: 'ops_campaigns',
      title: l10n.opsDeskPrintCampaigns,
      columns: _isAr
          ? const ['العنوان', 'الجمهور', 'الحالة', 'أُرسل', 'البداية']
          : const ['Title', 'Audience', 'Status', 'Sent', 'Starts'],
      rows: _campaigns
          .map(
            (c) => [
              LocaleContent.pick(
                isAr: _isAr,
                ar: '${c['title_ar'] ?? ''}',
                en: '${c['title_en'] ?? ''}',
                fallback: '${c['title_ar'] ?? c['title_en'] ?? ''}',
              ),
              '${c['account_type'] ?? l10n.opsDeskCampaignAllTypes}',
              '${c['status'] ?? ''}',
              '${c['sent_count'] ?? ''}',
              DateHelper.fmtCivilDateTimeRaw(c['starts_at'], isAr: _isAr),
            ],
          )
          .toList(),
    );
  }

  Future<void> _printReports(AppLocalizations l10n) async {
    await _printTable(
      id: 'ops_listing_reports',
      title: l10n.opsDeskTabReports,
      columns: _isAr
          ? const ['العقار', 'الحالة', 'ملاحظة']
          : const ['Property', 'Status', 'Note'],
      rows: _reports
          .map(
            (r) => [
              '${r['property_id'] ?? ''}',
              '${r['status'] ?? ''}',
              '${r['note'] ?? ''}',
            ],
          )
          .toList(),
    );
  }

  Future<void> _resolveTicket(SupportTicketRow row) async {
    final res = await _tickets.staffReply(
      complaintId: row.id,
      reply: row.adminReply?.trim().isNotEmpty == true
          ? row.adminReply!.trim()
          : (_isAr ? 'تم إغلاق التذكرة.' : 'Ticket closed.'),
      status: 'resolved',
    );
    await _snack(res);
    await _load();
  }

  Future<void> _snack(Map<String, dynamic> res, {String? okText}) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res['ok'] == true
              ? (okText ?? l10n.opsDeskSaved)
              : '${res['error'] ?? l10n.opsDeskForbidden}',
        ),
      ),
    );
  }

  Future<void> _reply(SupportTicketRow row) async {
    final l10n = AppLocalizations.of(context)!;
    await _tickets.staffOpenTicket(row.id);
    await _load();
    if (!mounted) return;
    var latest = row;
    for (final t in _complaints) {
      if (t.id == row.id) {
        latest = t;
        break;
      }
    }
    final ctrl = TextEditingController(
      text: SupportTicketAssist.draftStaffReply(
        isAr: _isAr,
        subject: latest.subject,
        body: latest.body,
        kind: latest.kind,
      ),
    );
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        Widget cell(String t) => Text(
              t,
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
            );
        return AlertDialog(
          title: Text(l10n.opsTabTickets),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SupportLabeledTable(
                    rows: [
                      SupportLabeledRow(
                        label: l10n.supportComplaintSubjectLabel,
                        child: cell(latest.subject),
                      ),
                      SupportLabeledRow(
                        label: l10n.supportComplaintDetailsLabel,
                        child: cell(latest.body),
                      ),
                      SupportLabeledRow(
                        label: l10n.opsDeskTicketSubmittedAt,
                        child: cell(_opsWhen(latest.createdAt)),
                      ),
                      SupportLabeledRow(
                        label: l10n.opsDeskTicketRequester,
                        child: cell(
                          latest.submitterName.isEmpty
                              ? _ticketPerson(latest.details, requester: true)
                              : latest.submitterName,
                        ),
                      ),
                      if (latest.submitterPhone.isNotEmpty)
                        SupportLabeledRow(
                          label: l10n.supportSubmitterPhoneLabel,
                          child: Text(
                            PhoneDisplay.forUi(
                              latest.submitterPhone,
                              isAr: _isAr,
                            ),
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      if (latest.receivedByName.isNotEmpty)
                        SupportLabeledRow(
                          label: l10n.supportTicketReceivedBy,
                          child: cell(
                            '${latest.receivedByName} · ${_opsWhen(latest.receivedAt)}',
                          ),
                        ),
                      SupportLabeledRow(
                        label: l10n.supportTicketStatusLabel,
                        child: cell(_ticketStatusLabel(l10n, latest.status)),
                      ),
                    ],
                  ),
                  if (latest.attachments.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SupportSectionCard(
                      title: l10n.supportAttachmentsLabel,
                      child: Column(
                        children: [
                          for (final a in latest.attachments)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: const Icon(Icons.attach_file_rounded),
                              title: Text(a.name),
                              trailing: TextButton(
                                onPressed: () async {
                                  final url =
                                      await _tickets.signedAttachmentUrl(a);
                                  if (url == null || url.isEmpty) return;
                                  final u = Uri.tryParse(url);
                                  if (u == null) return;
                                  await launchUrl(
                                    u,
                                    mode: LaunchMode.externalApplication,
                                  );
                                },
                                child: Text(l10n.supportTicketDownloadAttachment),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SupportSectionCard(
                    title: l10n.opsDeskTicketReplySection,
                    subtitle: SupportTicketPolicy.hasStaffReply(latest)
                        ? _opsWhen(
                            DateHelper.tryParse(latest.details['admin_reply_at']),
                          )
                        : l10n.opsDeskTicketNoStaffReply,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if ((latest.adminReply ?? '').trim().isNotEmpty)
                          Text(latest.adminReply!),
                        ...latest.chatThread.map(
                          (m) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              '${m['role'] ?? ''}: ${m['text'] ?? ''}',
                              style: Theme.of(ctx).textTheme.bodySmall,
                            ),
                          ),
                        ),
                        AqarTextField(
                          controller: ctrl,
                          minLines: 4,
                          maxLines: 10,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          decoration: InputDecoration(
                            hintText: l10n.opsDeskReplyHint,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SupportSectionCard(
                    title: l10n.opsDeskTicketEscalationSection,
                    subtitle: SupportTicketPolicy.isEscalated(latest)
                        ? l10n.opsDeskTicketStatusEscalated
                        : (SupportTicketPolicy.slaElapsed(latest)
                            ? l10n.opsDeskSlaOverdue
                            : l10n.opsDeskSlaWaiting),
                    tone: SupportTicketPolicy.isEscalated(latest)
                        ? cs.error.withValues(alpha: 0.45)
                        : null,
                    child: Text(
                      l10n.supportTicketSlaHours,
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        actions: [
          TextButton(
            onPressed: () {
              ctrl.text = SupportTicketAssist.draftStaffReply(
                isAr: _isAr,
                subject: row.subject,
                body: row.body,
                kind: row.kind,
              );
            },
            child: Text(l10n.opsDeskAiDraft),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.opsDeskSendReply),
          ),
        ],
        );
      },
    );
    final text = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || !mounted) return;
    final res = await _tickets.staffReply(
      complaintId: row.id,
      reply: text,
    );
    await _snack(res);
    await _load();
  }

  Future<void> _reviewReport(Map<String, dynamic> row, String decision) async {
    final res = await _acct.reviewListingReport(
      reportId: '${row['id']}',
      decision: decision,
    );
    await _snack(res, okText: decision);
    await _load();
  }

  Future<void> _grantUser(String userId) async {
    var support = true;
    var moderate = false;
    var finance = false;
    var deputy = false;
    var ads = false;
    var promo = false;
    var ban = false;
    var teamComms = false;
    final l10n = AppLocalizations.of(context)!;
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(l10n.opsDeskGrantTooltip),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CheckboxListTile(
                      value: support,
                      onChanged: (v) => setLocal(() => support = v ?? true),
                      title: Text(l10n.opsDeskRoleSupport),
                    ),
                    CheckboxListTile(
                      value: moderate,
                      onChanged: (v) => setLocal(() => moderate = v ?? false),
                      title: Text(l10n.opsDeskRoleCompliance),
                    ),
                    CheckboxListTile(
                      value: finance,
                      onChanged: (v) => setLocal(() => finance = v ?? false),
                      title: Text(l10n.opsDeskRoleFinance),
                    ),
                    CheckboxListTile(
                      value: ads,
                      onChanged: (v) => setLocal(() => ads = v ?? false),
                      title: Text(l10n.opsDeskRoleAds),
                    ),
                    CheckboxListTile(
                      value: promo,
                      onChanged: (v) => setLocal(() => promo = v ?? false),
                      title: Text(l10n.opsDeskRolePromo),
                    ),
                    CheckboxListTile(
                      value: ban,
                      onChanged: (v) => setLocal(() => ban = v ?? false),
                      title: Text(l10n.opsDeskRoleBan),
                    ),
                    CheckboxListTile(
                      value: teamComms,
                      onChanged: (v) => setLocal(() => teamComms = v ?? false),
                      title: Text(l10n.opsDeskRoleTeam),
                    ),
                    if (_isOwner)
                      CheckboxListTile(
                        value: deputy,
                        onChanged: (v) => setLocal(() => deputy = v ?? false),
                        title: Text(l10n.opsDeskRoleDeputy),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.opsDeskGrantTooltip),
              ),
            ],
          ),
        );
      },
    );
    if (ok != true || !mounted) return;
    final res = await _acct.grantOps(
      userId: userId,
      support: support,
      moderate: moderate,
      finance: finance,
      grant: deputy,
      ads: ads,
      promo: promo,
      ban: ban,
      teamComms: teamComms,
    );
    await _snack(res);
    await _load();
    await _searchUsers();
  }

  Future<void> _revokeUser(String userId) async {
    final res = await _acct.revokeOps(userId);
    await _snack(res);
    await _load();
  }

  Future<void> _publishAd() async {
    final res = await _acct.upsertLoginAd(
      titleAr: _adTitleAr.text.trim(),
      titleEn: _adTitleEn.text.trim(),
      subtitleAr: _adSubAr.text.trim(),
      subtitleEn: _adSubEn.text.trim(),
      imageUrl: _adImage.text.trim().isEmpty ? null : _adImage.text.trim(),
      linkUrl: _adLink.text.trim().isEmpty ? null : _adLink.text.trim(),
      placement: _adPlacement,
    );
    await _snack(res);
    await _load();
  }

  Future<void> _savePromo() async {
    final v = double.tryParse(_promoValue.text.trim()) ?? 0;
    final maxRaw = _promoMax.text.trim();
    final res = await _acct.upsertPromo(
      code: _promoCode.text.trim(),
      kind: _promoKind,
      value: v,
      titleAr: _promoTitleAr.text.trim(),
      titleEn: _promoTitleEn.text.trim(),
      active: _promoActive,
      maxRedemptions: maxRaw.isEmpty ? null : int.tryParse(maxRaw),
      validFrom: _promoFrom,
      validTo: _promoTo,
      campaignKey: _promoCampaign.text.trim(),
    );
    await _snack(res);
    await _load();
  }

  String _promoKindLabel(AppLocalizations l10n, String kind) {
    switch (kind) {
      case 'fixed_off':
        return l10n.opsDeskPromoKindFixed;
      case 'trial_days':
        return l10n.opsDeskPromoKindTrial;
      case 'first_payment_bonus':
        return l10n.opsDeskPromoKindBonus;
      default:
        return l10n.opsDeskPromoKindPercent;
    }
  }

  Future<void> _sharePromoCode(String code) async {
    final l10n = AppLocalizations.of(context)!;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.opsDeskPromoCopied)),
    );
    try {
      await Share.share(code, subject: l10n.opsDeskPromoCode);
    } catch (_) {}
  }

  Future<void> _openPromoRedemptions(Map<String, dynamic> promo) async {
    final l10n = AppLocalizations.of(context)!;
    final id = '${promo['id'] ?? ''}';
    if (id.isEmpty) return;
    final filter = TextEditingController();
    var rows = await _acct.promoRedemptions(id);
    if (!mounted) return;

    Future<void> refresh(StateSetter setLocal) async {
      rows = await _acct.promoRedemptions(id, q: filter.text.trim());
      setLocal(() {});
    }

    List<String> cols() => _isAr
        ? const ['الاسم', 'رقم الهوية / الإقامة', 'الصفة', 'الوقت', 'المبلغ']
        : const ['Name', 'National ID / Iqama', 'Account type', 'Time', 'Amount'];
    List<List<String>> table() => rows
        .map(
          (r) => [
            _opsPersonName(r),
            _opsNationalId(r),
            _accountTypeLabel(l10n, '${r['account_type'] ?? ''}'),
            _opsWhen(r['created_at']),
            '${r['amount'] ?? ''}',
          ],
        )
        .toList();

    await showAppModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.75,
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Text(
                      '${l10n.opsDeskPromoRedemptions} · ${promo['code'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    AqarTextField(
                      controller: filter,
                      decoration: InputDecoration(
                        hintText: l10n.opsDeskPromoFilterHint,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search_rounded),
                          onPressed: () => unawaited(refresh(setLocal)),
                        ),
                      ),
                      onSubmitted: (_) => unawaited(refresh(setLocal)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: rows.isEmpty
                              ? null
                              : () => unawaited(
                                    _printTable(
                                      id: 'ops_promo_used',
                                      title:
                                          '${l10n.opsDeskPromoRedemptions} ${promo['code'] ?? ''}',
                                      columns: cols(),
                                      rows: table(),
                                    ),
                                  ),
                          icon: const Icon(Icons.print_outlined),
                          label: Text(l10n.opsDeskPrint),
                        ),
                        OutlinedButton.icon(
                          onPressed: rows.isEmpty
                              ? null
                              : () => unawaited(
                                    _exportTable(
                                      id: 'ops_promo_used',
                                      title:
                                          '${l10n.opsDeskPromoRedemptions} ${promo['code'] ?? ''}',
                                      columns: cols(),
                                      rows: table(),
                                    ),
                                  ),
                          icon: const Icon(Icons.table_view_outlined),
                          label: Text(l10n.opsDeskPromoExport),
                        ),
                        OutlinedButton.icon(
                          onPressed: rows.isEmpty
                              ? null
                              : () => unawaited(
                                    _exportExcelTable(
                                      id: 'ops_promo_used',
                                      title:
                                          '${l10n.opsDeskPromoRedemptions} ${promo['code'] ?? ''}',
                                      columns: cols(),
                                      rows: table(),
                                    ),
                                  ),
                          icon: const Icon(Icons.grid_on_outlined),
                          label: Text(l10n.opsDeskExportExcel),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (rows.isEmpty) Text(l10n.opsDeskNoUsers),
                    ...rows.map(
                      (r) => Card(
                        child: ListTile(
                          title: Text(_opsPersonName(r)),
                          subtitle: Text(
                            '${l10n.opsDeskNationalId}: ${_opsNationalId(r).isEmpty ? '—' : _opsNationalId(r)} · '
                            '${_accountTypeLabel(l10n, '${r['account_type'] ?? ''}')}\n'
                            '${_opsWhen(r['created_at'])} · ${r['amount'] ?? ''}',
                          ),
                          isThreeLine: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    filter.dispose();
  }

  Future<void> _grantPlan(Map<String, dynamic> u) async {
    final l10n = AppLocalizations.of(context)!;
    final userId = '${u['user_id'] ?? ''}';
    if (userId.isEmpty) return;
    final suggested = await _acct.suggestedPlans(userId);
    if (!mounted) return;
    if (suggested['ok'] != true) {
      await _snack(suggested);
      return;
    }
    final free = suggested['free_tier'] == true;
    final plans = (suggested['rows'] is List)
        ? (suggested['rows'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    String? planId = plans.isEmpty ? null : '${plans.first['id']}';
    var months = 12;
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(l10n.opsDeskGrantPlan),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${_opsPersonName(u)}\n'
                      '${l10n.opsDeskNationalId}: ${_opsNationalId(u).isEmpty ? '—' : _opsNationalId(u)}\n'
                      '${_accountTypeLabel(l10n, '${u['account_type'] ?? ''}')}',
                    ),
                    const SizedBox(height: 8),
                    Text(l10n.opsDeskGrantPlanHint),
                    const SizedBox(height: 12),
                    if (free)
                      Text(
                        l10n.opsDeskGrantIndividualWhy,
                        style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4),
                      )
                    else ...[
                      DropdownButtonFormField<String>(
                        initialValue: planId,
                        decoration: InputDecoration(
                          labelText: l10n.opsDeskGrantPlan,
                        ),
                        items: [
                          for (final p in plans)
                            DropdownMenuItem(
                              value: '${p['id']}',
                              child: Text(
                                LocaleContent.pick(
                                  isAr: _isAr,
                                  ar: '${p['name_ar'] ?? ''}',
                                  en: '${p['name_en'] ?? ''}',
                                ),
                              ),
                            ),
                        ],
                        onChanged: (v) => setLocal(() => planId = v),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: months,
                        decoration: InputDecoration(
                          labelText: l10n.opsDeskGrantMonths,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 1,
                            child: Text(l10n.opsDeskGrantMonth1),
                          ),
                          DropdownMenuItem(
                            value: 3,
                            child: Text(l10n.opsDeskGrantMonth3),
                          ),
                          DropdownMenuItem(
                            value: 6,
                            child: Text(l10n.opsDeskGrantMonth6),
                          ),
                          DropdownMenuItem(
                            value: 12,
                            child: Text(l10n.opsDeskGrantMonth12),
                          ),
                        ],
                        onChanged: (v) =>
                            setLocal(() => months = v ?? 12),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
              ),
              if (!free)
                FilledButton(
                  onPressed: planId == null
                      ? null
                      : () => Navigator.pop(ctx, true),
                  child: Text(l10n.opsDeskGrantConfirm),
                ),
            ],
          ),
        );
      },
    );
    if (ok != true || free || planId == null || !mounted) return;
    final res = await _acct.grantPlan(
      userId: userId,
      planId: planId!,
      months: months,
    );
    await _snack(res, okText: l10n.opsDeskGrantOk);
  }

  Future<void> _broadcastTeam() async {
    final res = await _acct.broadcastTeam(
      titleAr: _noticeTitleAr.text.trim(),
      titleEn: _noticeTitleEn.text.trim(),
      bodyAr: _noticeBodyAr.text.trim(),
      bodyEn: _noticeBodyEn.text.trim(),
    );
    await _snack(res);
  }

  Future<void> _banUser(String userId) async {
    final l10n = AppLocalizations.of(context)!;
    final ctrl = TextEditingController();
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.opsDeskBan),
        content: AqarTextField(
          controller: ctrl,
          decoration: InputDecoration(labelText: l10n.opsDeskBanReason),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.opsDeskBan),
          ),
        ],
      ),
    );
    final reason = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || !mounted) return;
    final res = await _acct.platformBanUser(userId: userId, reason: reason);
    await _snack(res);
    await _searchUsers();
  }

  Future<void> _liftBan(String userId) async {
    final res = await _acct.platformLiftBan(userId);
    await _snack(res);
    await _searchUsers();
  }

  Future<void> _terminateSessions(String userId) async {
    final res = await _acct.platformTerminateUserSessions(userId);
    await _snack(res);
  }

  Future<void> _noticeToUser(Map<String, dynamic> u) async {
    final l10n = AppLocalizations.of(context)!;
    _noticeUserId.text = '${u['user_id'] ?? ''}';
    final nid = _opsNationalId(u);
    final name = _opsPersonName(u);
    setState(() {
      _noticeTargetCaption = [
        name,
        if (nid.isNotEmpty) '${l10n.opsDeskNationalId}: $nid',
      ].where((e) => e.trim().isNotEmpty).join(' · ');
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.opsDeskSendNoticeTo)),
    );
  }

  String _opsPersonName(Map<String, dynamic> u) {
    final fromRow = ProfileGreetingFromRow.displayName(u, isAr: _isAr);
    if (fromRow != null && fromRow.trim().isNotEmpty) return fromRow.trim();
    return LocaleContent.pick(
      isAr: _isAr,
      ar: '${u['name_ar'] ?? u['name'] ?? ''}',
      en: '${u['name_en'] ?? ''}',
      fallback: '${u['office_name'] ?? ''}',
    );
  }

  String _opsNationalId(Map<String, dynamic> u) {
    for (final k in const [
      'national_id',
      'unified_national_number',
      'username',
    ]) {
      final digits = '${u[k] ?? ''}'.replaceAll(RegExp(r'\D'), '');
      if (digits.length == 10) return digits;
    }
    final nid = '${u['national_id'] ?? ''}'.trim();
    if (nid.isNotEmpty && !nid.contains('-')) return nid;
    return '';
  }

  String _opsPhone(Map<String, dynamic> u) => '${u['phone'] ?? ''}'.trim();

  String _opsWhen(dynamic v) {
    final d = DateHelper.tryParse(v);
    if (d == null) return '—';
    return DateHelper.fmtCivilDateTime(d, isAr: _isAr);
  }

  String _verificationLabel(AppLocalizations l10n, String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    if (isProfileVerificationComplete(v)) return l10n.badgeVerifiedShort;
    if (v.contains('pending')) return l10n.opsDeskVerifyPending;
    if (v.contains('reject')) return l10n.opsDeskVerifyRejected;
    return l10n.opsDeskVerifyNone;
  }

  String _staffCapsLabel(AppLocalizations l10n, Map<String, dynamic> u) {
    if (u['is_owner'] == true) return l10n.opsDeskRoleOwner;
    final parts = <String>[];
    if (u['can_grant'] == true) parts.add(l10n.opsDeskRoleDeputy);
    if (u['can_support'] == true) parts.add(l10n.opsDeskRoleSupport);
    if (u['can_moderate'] == true) parts.add(l10n.opsDeskRoleCompliance);
    if (u['can_finance'] == true) parts.add(l10n.opsDeskRoleFinance);
    if (u['can_ads'] == true) parts.add(l10n.opsDeskRoleAds);
    if (u['can_promo'] == true) parts.add(l10n.opsDeskRolePromo);
    if (u['can_ban'] == true) parts.add(l10n.opsDeskRoleBan);
    if (u['can_team_comms'] == true) parts.add(l10n.opsDeskRoleTeam);
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  String _ticketKindLabel(AppLocalizations l10n, String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'suggestion':
        return l10n.opsDeskTicketKindSuggestion;
      default:
        return l10n.opsDeskTicketKindComplaint;
    }
  }

  String _ticketStatusLabel(AppLocalizations l10n, String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'resolved':
      case 'closed':
        return l10n.opsDeskTicketStatusResolved;
      case 'escalated':
        return l10n.opsDeskTicketStatusEscalated;
      default:
        return l10n.opsDeskTicketStatusOpen;
    }
  }

  String _ticketPerson(Map<String, dynamic> details, {required bool requester}) {
    if (requester) {
      return LocaleContent.pick(
        isAr: _isAr,
        ar: '${details['requester_name_ar'] ?? details['requester_name'] ?? ''}',
        en: '${details['requester_name_en'] ?? ''}',
        fallback: '${details['requester_name'] ?? ''}',
      );
    }
    return LocaleContent.pick(
      isAr: _isAr,
      ar: '${details['assigned_name_ar'] ?? details['assigned_name'] ?? ''}',
      en: '${details['assigned_name_en'] ?? ''}',
      fallback: '${details['assigned_name'] ?? ''}',
    );
  }

  String _feeKeyLabel(String key) {
    switch (key) {
      case PlatformFeeCatalog.instantMarketRequest:
        return _isAr ? 'الطلب الفوري' : 'Instant request';
      case PlatformFeeCatalog.saveCardVerify:
        return _isAr ? 'توثيق بطاقة محفوظة' : 'Saved-card verification';
      case PlatformFeeCatalog.guestOneTimeDeal:
        return _isAr ? 'صفقة زائر لمرة واحدة' : 'Guest one-time deal';
      default:
        return LocaleContent.forUi(key.replaceAll('_', ' '), isAr: _isAr);
    }
  }

  String _accountTypeLabel(AppLocalizations l10n, String? raw) {
    switch (AppRoleHelper.fromAccountType(raw)) {
      case AppRoleKind.ownerIndividual:
        return l10n.opsTitleOwnerIndividual;
      case AppRoleKind.marketer:
        return l10n.opsTitleMarketer;
      case AppRoleKind.realEstateOffice:
        return l10n.opsTitleOffice;
      case AppRoleKind.realEstateCompany:
        return l10n.opsTitleCompany;
      case AppRoleKind.realEstateInstitution:
        return l10n.opsTitleInstitution;
      case AppRoleKind.agency:
        return l10n.opsTitleAgency;
      case AppRoleKind.publicUser:
        return l10n.opsTitleUser;
    }
  }

  Future<DateTime?> _pickDateTime(DateTime? current) async {
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return current;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? DateTime.now()),
    );
    if (time == null) return DateTime(date.year, date.month, date.day);
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _saveCampaign() async {
    final res = await _acct.upsertCampaign(
      titleAr: _campTitleAr.text.trim(),
      titleEn: _campTitleEn.text.trim(),
      bodyAr: _campBodyAr.text.trim(),
      bodyEn: _campBodyEn.text.trim(),
      mediaUrl:
          _campMedia.text.trim().isEmpty ? null : _campMedia.text.trim(),
      deepRoute: _campDeepRoute,
      accountType: _campaignAudience,
      targetQ: _campTarget.text.trim(),
      startsAt: _campStart,
      endsAt: _campEnd,
      sendAll: _campSendAll,
      kind: _campIdleNudge ? 'idle_nudge' : 'broadcast',
    );
    await _snack(res);
    await _load();
  }

  Future<void> _dispatchCampaign(String id) async {
    final res = await _acct.dispatchCampaign(id);
    await _snack(res);
    await _load();
  }

  String _fmtHours(dynamic seconds) {
    final n = seconds is num
        ? seconds.toInt()
        : int.tryParse('${seconds ?? 0}') ?? 0;
    final h = n ~/ 3600;
    final m = (n % 3600) ~/ 60;
    return '${h}h ${m}m';
  }

  Future<void> _openReceipts(String id) async {
    final l10n = AppLocalizations.of(context)!;
    final res = await _acct.campaignReceipts(id);
    if (!mounted) return;
    final rows = (res['rows'] is List)
        ? (res['rows'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    await showAppModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(
                  '${l10n.opsDeskCampaignReceipts} · ${l10n.opsDeskReceiptDelivered}: ${res['delivered'] ?? 0} · ${l10n.opsDeskReceiptRead}: ${res['read'] ?? 0}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton.icon(
                    onPressed: rows.isEmpty
                        ? null
                        : () => unawaited(
                              _printTable(
                                id: 'ops_receipts',
                                title: l10n.opsDeskCampaignReceipts,
                                columns: _isAr
                                    ? const ['الاسم', 'رقم الهوية / الإقامة', 'وُصل', 'قُرئ']
                                    : const [
                                        'Name',
                                        'National ID / Iqama',
                                        'Delivered',
                                        'Read',
                                      ],
                                rows: rows
                                    .map(
                                      (r) => [
                                        _opsPersonName(r),
                                        _opsNationalId(r),
                                        _opsWhen(r['delivered_at']),
                                        _opsWhen(r['read_at']),
                                      ],
                                    )
                                    .toList(),
                              ),
                            ),
                    icon: const Icon(Icons.print_outlined),
                    label: Text(l10n.opsDeskPrint),
                  ),
                ),
                ...rows.map(
                  (r) => Card(
                    child: ListTile(
                      title: Text(_opsPersonName(r)),
                      subtitle: Text(
                        '${l10n.opsDeskNationalId}: ${_opsNationalId(r).isEmpty ? '—' : _opsNationalId(r)}\n'
                        '${l10n.opsDeskReceiptDelivered}: ${_opsWhen(r['delivered_at'])}\n'
                        '${l10n.opsDeskReceiptRead}: ${_opsWhen(r['read_at'])}',
                      ),
                      isThreeLine: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _filterChip(
    AppLocalizations l10n,
    String value,
    String label,
  ) {
    return FilterChip(
      label: Text(label),
      selected: _userFilter == value,
      onSelected: (_) {
        setState(() => _userFilter = value);
        unawaited(_searchUsers());
      },
    );
  }

  Widget _opsDataTable({
    required List<String> columns,
    required List<List<String>> rows,
    void Function(int index)? onTap,
  }) {
    return Scrollbar(
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            headingRowHeight: 40,
            dataRowMinHeight: 44,
            dataRowMaxHeight: 52,
            columns: [
              for (final c in columns)
                DataColumn(
                  label: Text(
                    c,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
            ],
            rows: [
              for (var i = 0; i < rows.length; i++)
                DataRow(
                  onSelectChanged:
                      onTap == null ? null : (_) => onTap(i),
                  cells: [
                    for (final cell in rows[i])
                      DataCell(Text(cell, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _watchChip(String label, String value) {
    return Chip(
      label: Text('$label: $value'),
    );
  }

  Widget _opsStrip(AppLocalizations l10n) {
    final onlineUsers = _acct.lastUsersOnlineCount;
    final staffOnline =
        _teamTime.where((u) => u['online'] == true).length;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              l10n.opsDeskOnlineNow(onlineUsers),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(l10n.opsDeskStaffOnline(staffOnline)),
            if (_canFinance && _billingWatch['ok'] == true)
              Text(
                '${l10n.opsDeskSubsActive}: ${_billingWatch['subs_active'] ?? 0}',
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUserActions(Map<String, dynamic> u) async {
    final l10n = AppLocalizations.of(context)!;
    final id = '${u['user_id'] ?? ''}';
    if (id.isEmpty) return;
    final staff = u['is_staff'] == true;
    final banned = u['banned'] == true;
    await showAppModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text(_opsPersonName(u)),
                subtitle: Text(
                  '${l10n.opsDeskNationalId}: ${_opsNationalId(u).isEmpty ? '—' : _opsNationalId(u)}\n'
                  '${_accountTypeLabel(l10n, '${u['account_type'] ?? ''}')}'
                  '${_opsPhone(u).isEmpty ? '' : '\n${l10n.opsDeskPhone}: ${_opsPhone(u)}'}'
                  '${'${u['license_no'] ?? ''}'.trim().isEmpty ? '' : '\n${l10n.opsDeskLicense}: ${u['license_no']}'}'
                  '\n${l10n.opsDeskVerification}: ${_verificationLabel(l10n, '${u['verification'] ?? ''}')}\n'
                  '${l10n.opsDeskLogins}: ${u['logins'] ?? 0} · ${l10n.opsDeskLogouts}: ${u['logouts'] ?? 0}\n'
                  '${l10n.opsDeskLastLogin}: ${_opsWhen(u['last_login'])}\n'
                  '${l10n.opsDeskLastLogout}: ${_opsWhen(u['last_logout'])}\n'
                  '${l10n.opsDeskSales}: ${u['sales'] ?? 0}',
                ),
                isThreeLine: true,
              ),
              if (_canGrant && !staff)
                ListTile(
                  leading: const Icon(Icons.group_add_outlined),
                  title: Text(l10n.opsDeskAddToTeam),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_grantUser(id));
                  },
                ),
              if (_canGrant)
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: Text(l10n.opsDeskGrantTooltip),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_grantUser(id));
                  },
                ),
              if (_canSupport || _canModerate)
                ListTile(
                  leading: const Icon(Icons.edit_note_outlined),
                  title: Text(l10n.opsDeskPatchProfile),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_patchProfile(u));
                  },
                ),
              if (_canFinance)
                ListTile(
                  leading: const Icon(Icons.card_membership_outlined),
                  title: Text(l10n.opsDeskGrantPlan),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_grantPlan(u));
                  },
                ),
              if (_canBan && !banned)
                ListTile(
                  leading: const Icon(Icons.block_outlined),
                  title: Text(l10n.opsDeskBan),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_banUser(id));
                  },
                ),
              if (_canBan && banned)
                ListTile(
                  leading: const Icon(Icons.lock_open_outlined),
                  title: Text(l10n.opsDeskLiftBan),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_liftBan(id));
                  },
                ),
              if (_canBan || _canGrant)
                ListTile(
                  leading: const Icon(Icons.logout_outlined),
                  title: Text(l10n.opsDeskTerminateSessions),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_terminateSessions(id));
                  },
                ),
              if (_canSupport || _isOwner)
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: Text(l10n.opsDeskSendNoticeTo),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_noticeToUser(u));
                  },
                ),
              if (_opsNationalId(u).isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.copy_outlined),
                  title: Text(l10n.opsDeskCopyId),
                  onTap: () {
                    Clipboard.setData(
                      ClipboardData(text: _opsNationalId(u)),
                    );
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.opsDeskCopiedNationalId)),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendNotice() async {
    final res = await _acct.sendNotice(
      userId: _noticeUserId.text.trim(),
      titleAr: _noticeTitleAr.text.trim(),
      titleEn: _noticeTitleEn.text.trim(),
      bodyAr: _noticeBodyAr.text.trim(),
      bodyEn: _noticeBodyEn.text.trim(),
    );
    await _snack(res);
  }

  Future<void> _saveFee(String key) async {
    final raw = _feeCtrls[key]?.text.trim() ?? '';
    final amt = double.tryParse(raw);
    if (amt == null) return;
    final res = await _acct.setFee(feeKey: key, amountSar: amt);
    await _snack(res);
    if (!mounted) return;
    try {
      await context.read<PlatformFeeCatalog>().refresh();
    } catch (_) {}
  }

  Future<void> _exitDenied() async {
    if (!mounted) return;
    await SafeSignOutService.signOutAndNavigateToLogin(context);
    if (!kIsWeb) {
      try {
        await SystemNavigator.pop();
      } catch (_) {}
    }
  }

  Future<void> _logout() async {
    if (!mounted) return;
    await SafeSignOutService.signOutAndNavigateToLogin(context);
  }

  void _onMenu(String value) {
    switch (value) {
      case 'lang_ar':
        unawaited(setAppLang('ar'));
        break;
      case 'lang_en':
        unawaited(setAppLang('en'));
        break;
      case 'theme_system':
        unawaited(setAppTheme(ThemeMode.system));
        break;
      case 'theme_light':
        unawaited(setAppTheme(ThemeMode.light));
        break;
      case 'theme_dark':
        unawaited(setAppTheme(ThemeMode.dark));
        break;
      case 'logout':
        unawaited(_logout());
        break;
    }
  }

  Widget _menu(AppLocalizations l10n, ColorScheme cs) {
    return PopupMenuButton<String>(
      tooltip: l10n.opsDeskOptions,
      icon: Icon(Icons.more_vert_rounded, color: cs.primary),
      onSelected: _onMenu,
      itemBuilder: (ctx) => [
        PopupMenuItem(value: 'lang_ar', child: Text(l10n.languageArabic)),
        PopupMenuItem(value: 'lang_en', child: Text(l10n.languageEnglish)),
        PopupMenuItem(value: 'theme_system', child: Text(l10n.themeSystem)),
        PopupMenuItem(value: 'theme_light', child: Text(l10n.themeLight)),
        PopupMenuItem(value: 'theme_dark', child: Text(l10n.themeDark)),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'logout', child: Text(l10n.logoutLabel)),
      ],
    );
  }

  Widget _ticketsTab(AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _complaints.isEmpty
                  ? null
                  : () => unawaited(_printTickets(l10n)),
              icon: const Icon(Icons.print_outlined),
              label: Text(l10n.opsDeskPrintTickets),
            ),
            OutlinedButton.icon(
              onPressed: _complaints.isEmpty
                  ? null
                  : () => unawaited(
                        _exportExcelTable(
                          id: 'ops_tickets',
                          title: l10n.opsDeskPrintTickets,
                          columns: _isAr
                              ? const [
                                  'الحالة',
                                  'النوع',
                                  'الموضوع',
                                  'التفاصيل',
                                  'وقت الرفع',
                                ]
                              : const [
                                  'Status',
                                  'Kind',
                                  'Subject',
                                  'Details',
                                  'Submitted',
                                ],
                          rows: _complaints
                              .map(
                                (r) => [
                                  _ticketStatusLabel(l10n, r.status),
                                  _ticketKindLabel(l10n, r.kind),
                                  r.subject,
                                  r.body,
                                  _opsWhen(r.createdAt),
                                ],
                              )
                              .toList(),
                        ),
                      ),
              icon: const Icon(Icons.grid_on_outlined),
              label: Text(l10n.opsDeskExportExcel),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_complaints.isEmpty) Text(l10n.opsDeskNoTickets),
        ..._complaints.map((r) {
          final slaOverdue = SupportTicketPolicy.slaElapsed(r) &&
              !SupportTicketPolicy.isResolved(r);
          final escalated = SupportTicketPolicy.isEscalated(r);
          final hasReply = SupportTicketPolicy.hasStaffReply(r);
          return Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SupportLabeledTable(
                    rows: [
                      SupportLabeledRow(
                        label: l10n.supportComplaintSubjectLabel,
                        child: Text(
                          r.subject,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      SupportLabeledRow(
                        label: l10n.supportComplaintDetailsLabel,
                        child: Text(
                          r.body,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SupportLabeledRow(
                        label: l10n.opsDeskTicketSubmittedAt,
                        child: Text(_opsWhen(r.createdAt)),
                      ),
                      SupportLabeledRow(
                        label: l10n.supportTicketStatusLabel,
                        child: Text(_ticketStatusLabel(l10n, r.status)),
                      ),
                      SupportLabeledRow(
                        label: l10n.opsDeskTicketRequester,
                        child: Text(
                          _ticketPerson(r.details, requester: true).isEmpty
                              ? (r.submitterName.isEmpty ? '—' : r.submitterName)
                              : _ticketPerson(r.details, requester: true),
                        ),
                      ),
                      if (r.submitterPhone.isNotEmpty)
                        SupportLabeledRow(
                          label: l10n.supportSubmitterPhoneLabel,
                          child: Text(
                            PhoneDisplay.forUi(r.submitterPhone, isAr: _isAr),
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      if (r.receivedByName.isNotEmpty)
                        SupportLabeledRow(
                          label: l10n.supportTicketReceivedBy,
                          child: Text(
                            '${r.receivedByName}'
                            '${r.receivedAt == null ? '' : ' · ${_opsWhen(r.receivedAt)}'}',
                          ),
                        ),
                      if (r.attachments.isNotEmpty)
                        SupportLabeledRow(
                          label: l10n.supportAttachmentsLabel,
                          child: Text(
                            r.attachments.map((e) => e.name).join(' · '),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Chip(
                        label: Text(
                          hasReply
                              ? l10n.opsDeskTicketReplySection
                              : l10n.opsDeskTicketNoStaffReply,
                        ),
                      ),
                      Chip(
                        label: Text(
                          escalated
                              ? l10n.opsDeskTicketStatusEscalated
                              : (slaOverdue
                                  ? l10n.opsDeskSlaOverdue
                                  : l10n.opsDeskSlaWaiting),
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Wrap(
                      spacing: 4,
                      children: [
                        TextButton(
                          onPressed: () => unawaited(_reply(r)),
                          child: Text(l10n.opsDeskSendReply),
                        ),
                        TextButton(
                          onPressed: r.status == 'resolved'
                              ? null
                              : () => unawaited(_resolveTicket(r)),
                          child: Text(l10n.opsDeskResolve),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _auditTab(AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed:
                _audit.isEmpty ? null : () => unawaited(_printAudit(l10n)),
            icon: const Icon(Icons.print_outlined),
            label: Text(l10n.opsDeskPrintAudit),
          ),
        ),
        const SizedBox(height: 8),
        if (_audit.isEmpty) Text(l10n.opsDeskNoAudit),
        ..._audit.map(
          (r) => Card(
            child: ListTile(
              title: Text('${r['action'] ?? ''}'),
              subtitle: Text(
                '${r['target_table'] ?? ''} · ${r['target_id'] ?? ''}\n${DateHelper.fmtCivilDateTimeRaw(r['created_at'], isAr: _isAr)}',
              ),
              isThreeLine: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _reportsTab(AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed:
                _reports.isEmpty ? null : () => unawaited(_printReports(l10n)),
            icon: const Icon(Icons.print_outlined),
            label: Text(l10n.opsDeskTabReports),
          ),
        ),
        const SizedBox(height: 8),
        if (_reports.isEmpty) Text(l10n.opsDeskNoReports),
        ..._reports.map(
          (r) => Card(
            child: ListTile(
              title: Text('${r['property_id'] ?? ''}'),
              subtitle: Text('${r['status']} · ${r['note'] ?? ''}'),
              trailing: Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: () => unawaited(_reviewReport(r, 'accepted')),
                    child: Text(l10n.opsDeskAccept),
                  ),
                  TextButton(
                    onPressed: () => unawaited(_reviewReport(r, 'dismissed')),
                    child: Text(l10n.opsDeskDismiss),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _usersTab(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AqarTextField(
            controller: _userQ,
            decoration: InputDecoration(
              hintText: l10n.opsDeskSearchHint,
              suffixIcon: IconButton(
                icon: const Icon(Icons.search_rounded),
                onPressed: () => unawaited(_searchUsers()),
              ),
            ),
            onSubmitted: (_) => unawaited(_searchUsers()),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.opsDeskUsersHint,
            style: const TextStyle(height: 1.4, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _filterChip(l10n, 'all', l10n.opsDeskFilterAll),
              _filterChip(l10n, 'online', l10n.opsDeskFilterOnline),
              _filterChip(l10n, 'offline', l10n.opsDeskFilterOffline),
              _filterChip(l10n, 'active', l10n.opsDeskFilterActive),
              _filterChip(l10n, 'inactive', l10n.opsDeskFilterInactive),
              _filterChip(l10n, 'idle', l10n.opsDeskFilterIdle),
              _filterChip(l10n, 'pending', l10n.opsDeskFilterPending),
              _filterChip(l10n, 'banned', l10n.opsDeskFilterBanned),
              _filterChip(l10n, 'locked', l10n.opsDeskFilterLocked),
              _filterChip(l10n, 'staff', l10n.opsDeskFilterStaff),
              _filterChip(l10n, 'owner', l10n.opsDeskFilterOwner),
              _filterChip(l10n, 'marketer', l10n.opsDeskFilterMarketer),
              _filterChip(l10n, 'office', l10n.opsDeskFilterOffice),
              _filterChip(l10n, 'company', l10n.opsDeskFilterCompany),
              _filterChip(l10n, 'institution', l10n.opsDeskFilterInstitution),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed:
                  _directory.isEmpty ? null : () => unawaited(_printUsers(l10n)),
              icon: const Icon(Icons.print_outlined),
              label: Text(l10n.opsDeskPrintUsers),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _directory.isEmpty
                ? Text(l10n.opsDeskNoUsers)
                : _opsDataTable(
                    columns: [
                      l10n.opsDeskColName,
                      l10n.opsDeskColType,
                      l10n.opsDeskColOps,
                      l10n.opsDeskNationalId,
                      l10n.opsDeskFilterOnline,
                      l10n.opsDeskLogins,
                      l10n.opsDeskSales,
                      l10n.opsDeskLastLogin,
                    ],
                    rows: _directory
                        .map(
                          (u) => [
                            _opsPersonName(u),
                            _accountTypeLabel(
                              l10n,
                              '${u['account_type'] ?? ''}',
                            ),
                            u['is_staff'] == true
                                ? l10n.opsDeskOnTeam
                                : '—',
                            _opsNationalId(u).isEmpty
                                ? '—'
                                : _opsNationalId(u),
                            u['online'] == true
                                ? l10n.opsDeskFilterOnline
                                : l10n.opsDeskFilterOffline,
                            '${u['logins'] ?? 0}',
                            '${u['sales'] ?? 0}',
                            _opsWhen(u['last_login']),
                          ],
                        )
                        .toList(),
                    onTap: (i) => unawaited(_openUserActions(_directory[i])),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _teamTab(AppLocalizations l10n) {
    final timeById = {
      for (final t in _teamTime) '${t['user_id'] ?? ''}': t,
    };
    final merged = _team.map((u) {
      final id = '${u['user_id'] ?? ''}';
      final extra = timeById[id] ?? const <String, dynamic>{};
      return {...u, ...extra};
    }).where((u) {
      if (_teamFilter == 'active') return u['is_active'] == true;
      if (_teamFilter == 'inactive') return u['is_active'] != true;
      if (_teamFilter == 'online') return u['online'] == true;
      return true;
    }).toList();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(l10n.opsDeskTeamTimeHint),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            FilterChip(
              label: Text(l10n.opsDeskFilterAll),
              selected: _teamFilter == 'all',
              onSelected: (_) => setState(() => _teamFilter = 'all'),
            ),
            FilterChip(
              label: Text(l10n.opsDeskFilterOnline),
              selected: _teamFilter == 'online',
              onSelected: (_) => setState(() => _teamFilter = 'online'),
            ),
            FilterChip(
              label: Text(l10n.opsDeskTeamActive),
              selected: _teamFilter == 'active',
              onSelected: (_) => setState(() => _teamFilter = 'active'),
            ),
            FilterChip(
              label: Text(l10n.opsDeskTeamInactive),
              selected: _teamFilter == 'inactive',
              onSelected: (_) => setState(() => _teamFilter = 'inactive'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: merged.isEmpty
                ? null
                : () => unawaited(
                      _printTable(
                        id: 'ops_team_time',
                        title: l10n.opsDeskTabTeam,
                        columns: _isAr
                            ? const [
                                'الاسم',
                                'رقم الهوية / الإقامة',
                                'الصلاحية',
                                'متصل',
                                'اليوم',
                                '7 أيام',
                                'آخر خروج',
                              ]
                            : const [
                                'Name',
                                'National ID / Iqama',
                                'Role',
                                'Online',
                                'Today',
                                '7d',
                                'Last logout',
                              ],
                        rows: merged
                            .map(
                              (u) => [
                                _opsPersonName(u),
                                _opsNationalId(u),
                                _staffCapsLabel(l10n, u),
                                u['online'] == true
                                    ? l10n.opsDeskFilterOnline
                                    : l10n.opsDeskFilterOffline,
                                _fmtHours(u['seconds_today']),
                                _fmtHours(u['seconds_7d']),
                                _opsWhen(u['last_logout']),
                              ],
                            )
                            .toList(),
                      ),
                    ),
            icon: const Icon(Icons.print_outlined),
            label: Text(l10n.opsDeskPrint),
          ),
        ),
        const SizedBox(height: 8),
        ...merged.map((u) {
          final id = '${u['user_id'] ?? ''}';
          final owner = u['is_owner'] == true;
          return Card(
            child: ListTile(
              leading: Icon(
                u['online'] == true
                    ? Icons.circle
                    : Icons.circle_outlined,
                color: u['online'] == true
                    ? Theme.of(context).colorScheme.primary
                    : null,
                size: 14,
              ),
              title: Text(_opsPersonName(u)),
              subtitle: Text(
                '${_staffCapsLabel(l10n, u)} · ${u['is_active'] == true ? l10n.opsDeskTeamActive : l10n.opsDeskTeamInactive}\n'
                '${l10n.opsDeskNationalId}: ${_opsNationalId(u).isEmpty ? '—' : _opsNationalId(u)}\n'
                '${l10n.opsDeskHoursToday}: ${_fmtHours(u['seconds_today'])} · '
                '${l10n.opsDeskHours7d}: ${_fmtHours(u['seconds_7d'])}\n'
                '${l10n.opsDeskLastLogin}: ${_opsWhen(u['last_login'])} · '
                '${l10n.opsDeskLastLogout}: ${_opsWhen(u['last_logout'])}',
              ),
              isThreeLine: true,
              trailing: Wrap(
                children: [
                  if (_canFinance)
                    IconButton(
                      tooltip: l10n.opsDeskGrantPlan,
                      icon: const Icon(Icons.card_membership_outlined),
                      onPressed: id.isEmpty
                          ? null
                          : () => unawaited(_grantPlan(u)),
                    ),
                  if (_canGrant && !owner)
                    TextButton(
                      onPressed: () => unawaited(_revokeUser(id)),
                      child: Text(l10n.opsDeskRevoke),
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Future<void> _openWatch(String kind) async {
    final rows = await _acct.watchList(kind);
    if (!mounted) return;
    setState(() {
      _watchKind = kind;
      _watchRows = rows;
    });
  }

  Future<void> _notifyWatch(AppLocalizations l10n, String kind) async {
    final titleAr = TextEditingController();
    final titleEn = TextEditingController();
    final bodyAr = TextEditingController();
    final bodyEn = TextEditingController();
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.opsDeskWatchNotify),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AqarTextField(
                  controller: titleAr,
                  decoration:
                      InputDecoration(labelText: l10n.opsDeskNoticeTitleAr),
                ),
                const SizedBox(height: 8),
                AqarTextField(
                  controller: titleEn,
                  decoration:
                      InputDecoration(labelText: l10n.opsDeskNoticeTitleEn),
                ),
                const SizedBox(height: 8),
                AqarTextField(
                  controller: bodyAr,
                  maxLines: 3,
                  decoration:
                      InputDecoration(labelText: l10n.opsDeskNoticeBodyAr),
                ),
                const SizedBox(height: 8),
                AqarTextField(
                  controller: bodyEn,
                  maxLines: 3,
                  decoration:
                      InputDecoration(labelText: l10n.opsDeskNoticeBodyEn),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.opsDeskDismiss),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.opsDeskWatchNotify),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await _acct.notifyWatch(
      kind: kind,
      titleAr: titleAr.text.trim(),
      titleEn: titleEn.text.trim(),
      bodyAr: bodyAr.text.trim(),
      bodyEn: bodyEn.text.trim(),
    );
    await _snack(res);
  }

  Future<void> _patchProfile(Map<String, dynamic> u) async {
    final l10n = AppLocalizations.of(context)!;
    final id = '${u['user_id'] ?? ''}';
    if (id.isEmpty) return;
    final nameAr =
        TextEditingController(text: '${u['name_ar'] ?? u['name'] ?? ''}');
    final nameEn = TextEditingController(text: '${u['name_en'] ?? ''}');
    final phone = TextEditingController(text: _opsPhone(u));
    final nid = TextEditingController(text: _opsNationalId(u));
    final office = TextEditingController(text: '${u['office_name'] ?? ''}');
    final license = TextEditingController(text: '${u['license_no'] ?? ''}');
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.opsDeskPatchProfile),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AqarTextField(
                  controller: nameAr,
                  decoration: InputDecoration(
                    labelText: _isAr ? 'الاسم بالعربية' : 'Name (Arabic)',
                  ),
                ),
                const SizedBox(height: 8),
                AqarTextField(
                  controller: nameEn,
                  decoration: InputDecoration(
                    labelText: _isAr ? 'الاسم بالإنجليزية' : 'Name (English)',
                  ),
                ),
                const SizedBox(height: 8),
                AqarTextField(
                  controller: nid,
                  decoration: InputDecoration(labelText: l10n.opsDeskNationalId),
                ),
                const SizedBox(height: 8),
                AqarTextField(
                  controller: phone,
                  decoration: InputDecoration(labelText: l10n.opsDeskPhone),
                ),
                const SizedBox(height: 8),
                AqarTextField(
                  controller: office,
                  decoration: InputDecoration(
                    labelText: _isAr ? 'اسم المنشأة' : 'Office name',
                  ),
                ),
                const SizedBox(height: 8),
                AqarTextField(
                  controller: license,
                  decoration: InputDecoration(labelText: l10n.opsDeskLicense),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.opsDeskDismiss),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.opsDeskPatchSaved),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await _acct.patchProfile(
      userId: id,
      fullNameAr: nameAr.text.trim(),
      fullNameEn: nameEn.text.trim(),
      phone: phone.text.trim(),
      nationalId: nid.text.trim(),
      officeName: office.text.trim(),
      licenseNo: license.text.trim(),
    );
    await _snack(res);
    if (res['ok'] == true) unawaited(_searchUsers());
  }

  Widget _intelTab(AppLocalizations l10n) {
    final logins = (_intel['most_logins'] is List)
        ? (_intel['most_logins'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    final sales = (_intel['most_sales'] is List)
        ? (_intel['most_sales'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: (logins.isEmpty && sales.isEmpty && _intel['ok'] != true)
                ? null
                : () => unawaited(_printIntel(l10n)),
            icon: const Icon(Icons.print_outlined),
            label: Text(l10n.opsDeskPrintIntel),
          ),
        ),
        const SizedBox(height: 8),
        _opsStrip(l10n),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              label: Text('${l10n.opsDeskPulseTotal}: ${_intel['users_total'] ?? '—'}'),
              onPressed: () => unawaited(_openWatch('incomplete')),
            ),
            ActionChip(
              label: Text('${l10n.opsDeskPulseOnline}: ${_intel['online_now'] ?? '—'}'),
              onPressed: () {
                _userFilter = 'online';
                setState(() => _dest = 'users');
                unawaited(_searchUsers());
              },
            ),
            ActionChip(
              label: Text('${l10n.opsDeskPulseIdle}: ${_intel['idle_30d'] ?? '—'}'),
              onPressed: () => unawaited(_openWatch('idle')),
            ),
            ActionChip(
              label: Text('${l10n.opsDeskPulseIncomplete}: ${_intel['incomplete'] ?? '—'}'),
              onPressed: () => unawaited(_openWatch('incomplete')),
            ),
            ActionChip(
              label: Text('${l10n.opsDeskPulseFalExpired}: ${_intel['fal_expired'] ?? '—'}'),
              onPressed: () => unawaited(_openWatch('fal_expired')),
            ),
            ActionChip(
              label: Text('${l10n.opsDeskPulseFalExpiring}: ${_intel['fal_expiring'] ?? '—'}'),
              onPressed: () => unawaited(_openWatch('fal_expiring')),
            ),
            ActionChip(
              label: Text('${l10n.opsDeskPulseSubExpired}: ${_intel['subs_expired'] ?? '—'}'),
              onPressed: () => unawaited(_openWatch('sub_expired')),
            ),
            ActionChip(
              label: Text('${l10n.opsDeskPulseSubExpiring}: ${_intel['subs_expiring'] ?? '—'}'),
              onPressed: () => unawaited(_openWatch('sub_expiring')),
            ),
            ActionChip(
              label: Text('${l10n.opsDeskPulseGuests}: ${_intel['guests_7d'] ?? '—'}'),
              onPressed: null,
            ),
          ],
        ),
        if (_watchKind.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${l10n.opsDeskWatchList}: $_watchKind',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              OutlinedButton(
                onPressed: _watchRows.isEmpty
                    ? null
                    : () => unawaited(_notifyWatch(l10n, _watchKind)),
                child: Text(l10n.opsDeskWatchNotify),
              ),
            ],
          ),
          ..._watchRows.map(
            (r) => Card(
              child: ListTile(
                title: Text(_opsPersonName(r)),
                subtitle: Text(
                  '${l10n.opsDeskNationalId}: ${_opsNationalId(r).isEmpty ? '—' : _opsNationalId(r)} · '
                  '${_accountTypeLabel(l10n, '${r['account_type'] ?? ''}')}',
                ),
                onTap: () => unawaited(_openUserActions(r)),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          l10n.opsDeskMostLogins,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (logins.isEmpty)
          Text(l10n.opsDeskNoIntel)
        else
          _opsDataTable(
            columns: [
              l10n.opsDeskColName,
              l10n.opsDeskColType,
              l10n.opsDeskNationalId,
              l10n.opsDeskLogins,
            ],
            rows: logins
                .map(
                  (r) => [
                    _opsPersonName(r),
                    _accountTypeLabel(l10n, '${r['account_type'] ?? ''}'),
                    _opsNationalId(r).isEmpty ? '—' : _opsNationalId(r),
                    '${r['cnt'] ?? 0}',
                  ],
                )
                .toList(),
            onTap: (i) {
              final r = logins[i];
              _userQ.text = _opsNationalId(r).isNotEmpty
                  ? _opsNationalId(r)
                  : _opsPersonName(r);
              setState(() => _dest = 'users');
              unawaited(_searchUsers());
            },
          ),
        const SizedBox(height: 16),
        Text(
          l10n.opsDeskMostSales,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (sales.isEmpty)
          Text(l10n.opsDeskNoIntel)
        else
          _opsDataTable(
            columns: [
              l10n.opsDeskColName,
              l10n.opsDeskColType,
              l10n.opsDeskNationalId,
              l10n.opsDeskSales,
            ],
            rows: sales
                .map(
                  (r) => [
                    _opsPersonName(r),
                    _accountTypeLabel(l10n, '${r['account_type'] ?? ''}'),
                    _opsNationalId(r).isEmpty ? '—' : _opsNationalId(r),
                    '${r['cnt'] ?? 0}',
                  ],
                )
                .toList(),
            onTap: (i) {
              final r = sales[i];
              _userQ.text = _opsNationalId(r).isNotEmpty
                  ? _opsNationalId(r)
                  : _opsPersonName(r);
              setState(() => _dest = 'users');
              unawaited(_searchUsers());
            },
          ),
      ],
    );
  }

  Widget _campaignsTab(AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        AqarTextField(
          controller: _campTitleAr,
          decoration: InputDecoration(labelText: l10n.opsDeskNoticeTitleAr),
        ),
        const SizedBox(height: 8),
        AqarTextField(
          controller: _campTitleEn,
          decoration: InputDecoration(labelText: l10n.opsDeskNoticeTitleEn),
        ),
        const SizedBox(height: 8),
        AqarTextField(
          controller: _campBodyAr,
          maxLines: 3,
          decoration: InputDecoration(labelText: l10n.opsDeskNoticeBodyAr),
        ),
        const SizedBox(height: 8),
        AqarTextField(
          controller: _campBodyEn,
          maxLines: 3,
          decoration: InputDecoration(labelText: l10n.opsDeskNoticeBodyEn),
        ),
        const SizedBox(height: 8),
        AqarTextField(
          controller: _campMedia,
          decoration: InputDecoration(labelText: l10n.opsDeskCampaignMedia),
        ),
        const SizedBox(height: 8),
        AqarTextField(
          controller: _campTarget,
          decoration: InputDecoration(labelText: l10n.opsDeskCampaignTarget),
        ),
        const SizedBox(height: 8),
        Text(l10n.opsDeskIdleHint),
        CheckboxListTile(
          value: _campSendAll,
          onChanged: (v) => setState(() => _campSendAll = v ?? false),
          title: Text(l10n.opsDeskCampaignSendAll),
          contentPadding: EdgeInsets.zero,
        ),
        CheckboxListTile(
          value: _campIdleNudge,
          onChanged: (v) => setState(() => _campIdleNudge = v ?? false),
          title: Text(l10n.opsDeskCampaignIdleNudge),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _campaignAudience,
          decoration: InputDecoration(labelText: l10n.opsDeskCampaignAudience),
          items: [
            DropdownMenuItem(
              value: '',
              child: Text(l10n.opsDeskCampaignAllTypes),
            ),
            DropdownMenuItem(
              value: 'owner_individual',
              child: Text(l10n.opsTitleOwnerIndividual),
            ),
            DropdownMenuItem(
              value: 'marketer',
              child: Text(l10n.opsTitleMarketer),
            ),
            DropdownMenuItem(
              value: 'office',
              child: Text(l10n.opsTitleOffice),
            ),
            DropdownMenuItem(
              value: 'company',
              child: Text(l10n.opsTitleCompany),
            ),
            DropdownMenuItem(
              value: 'institution',
              child: Text(l10n.opsTitleInstitution),
            ),
          ],
          onChanged: (v) => setState(() => _campaignAudience = v ?? ''),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _campDeepRoute,
          decoration: InputDecoration(labelText: l10n.opsDeskCampaignDeep),
          items: [
            DropdownMenuItem(
              value: 'user_dashboard',
              child: Text(l10n.opsDeskModeMarket),
            ),
            DropdownMenuItem(
              value: 'in_app_notifications',
              child: Text(l10n.opsDeskTabNotices),
            ),
            DropdownMenuItem(
              value: 'subscriptions_hub',
              child: Text(l10n.opsDeskTabBilling),
            ),
            DropdownMenuItem(
              value: 'settings',
              child: Text(l10n.opsDeskTabOpsSettings),
            ),
          ],
          onChanged: (v) =>
              setState(() => _campDeepRoute = v ?? 'user_dashboard'),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.opsDeskCampaignStarts),
          subtitle: Text('${_campStart ?? l10n.opsDeskCampaignSendNow}'),
          trailing: IconButton(
            icon: const Icon(Icons.schedule_outlined),
            onPressed: () async {
              final d = await _pickDateTime(_campStart);
              if (mounted) setState(() => _campStart = d);
            },
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.opsDeskCampaignEnds),
          subtitle: Text('${_campEnd ?? '—'}'),
          trailing: IconButton(
            icon: const Icon(Icons.event_busy_outlined),
            onPressed: () async {
              final d = await _pickDateTime(_campEnd);
              if (mounted) setState(() => _campEnd = d);
            },
          ),
        ),
        FilledButton(
          onPressed: () => unawaited(_saveCampaign()),
          child: Text(l10n.opsDeskCampaignSave),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: _campaigns.isEmpty
                ? null
                : () => unawaited(_printCampaigns(l10n)),
            icon: const Icon(Icons.print_outlined),
            label: Text(l10n.opsDeskPrintCampaigns),
          ),
        ),
        const SizedBox(height: 8),
        if (_campaigns.isEmpty) Text(l10n.opsDeskNoCampaigns),
        ..._campaigns.map((c) {
          final id = '${c['id'] ?? ''}';
          final title = LocaleContent.pick(
            isAr: _isAr,
            ar: '${c['title_ar'] ?? ''}',
            en: '${c['title_en'] ?? ''}',
            fallback: '${c['title_ar'] ?? ''}',
          );
          return Card(
            child: ListTile(
              title: Text(title.isEmpty ? id : title),
              subtitle: Text(
                '${c['status'] ?? ''} · ${l10n.opsDeskCampaignSent}: ${c['sent_count'] ?? 0}'
                '${c['send_all'] == true ? ' · all' : ''}'
                '${c['kind'] == 'idle_nudge' ? ' · idle' : ''}'
                '${c['inbox_purged_at'] != null ? ' · ${l10n.opsDeskPurged}' : ''}\n'
                '${c['account_type'] ?? l10n.opsDeskCampaignAllTypes}'
                '${'${c['target_q'] ?? ''}'.trim().isEmpty ? '' : ' · ${c['target_q']}'}',
              ),
              isThreeLine: true,
              trailing: Wrap(
                children: [
                  TextButton(
                    onPressed: id.isEmpty
                        ? null
                        : () => unawaited(_openReceipts(id)),
                    child: Text(l10n.opsDeskCampaignReceipts),
                  ),
                  TextButton(
                    onPressed: id.isEmpty
                        ? null
                        : () => unawaited(_dispatchCampaign(id)),
                    child: Text(l10n.opsDeskCampaignSendNow),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _adsTab(AppLocalizations l10n) {
    final form = ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          l10n.opsDeskDraftLive,
          style: const TextStyle(height: 1.4, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _adPlacement,
          decoration: InputDecoration(labelText: l10n.opsDeskAdPlacement),
          items: [
            DropdownMenuItem(
              value: 'login',
              child: Text(l10n.opsDeskAdPlaceLogin),
            ),
            DropdownMenuItem(
              value: 'in_app',
              child: Text(l10n.opsDeskAdPlaceInApp),
            ),
            DropdownMenuItem(
              value: 'team',
              child: Text(l10n.opsDeskAdPlaceTeam),
            ),
            DropdownMenuItem(
              value: 'support_card',
              child: Text(l10n.opsDeskAdPlaceSupport),
            ),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _adPlacement = v);
          },
        ),
        const SizedBox(height: 8),
        AqarTextField(
          controller: _adTitleAr,
          decoration: InputDecoration(labelText: l10n.opsDeskAdTitleAr),
        ),
        const SizedBox(height: 8),
        AqarTextField(
          controller: _adTitleEn,
          decoration: InputDecoration(labelText: l10n.opsDeskAdTitleEn),
        ),
        const SizedBox(height: 8),
        AqarTextField(
          controller: _adSubAr,
          decoration: InputDecoration(labelText: l10n.opsDeskAdSubAr),
        ),
        const SizedBox(height: 8),
        AqarTextField(
          controller: _adSubEn,
          decoration: InputDecoration(labelText: l10n.opsDeskAdSubEn),
        ),
        const SizedBox(height: 8),
        AqarTextField(
          controller: _adImage,
          decoration: InputDecoration(labelText: l10n.opsDeskAdImage),
        ),
        const SizedBox(height: 8),
        AqarTextField(
          controller: _adLink,
          decoration: InputDecoration(labelText: l10n.opsDeskAdLink),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => unawaited(_publishAd()),
          child: Text(
            (_isOwner || _canGrant)
                ? l10n.opsDeskApprovePublish
                : l10n.opsDeskAdPublish,
          ),
        ),
        const SizedBox(height: 16),
        ..._ads.map(
          (a) => Card(
            child: ListTile(
              title: Text(_isAr ? a.titleAr : a.titleEn),
              subtitle: Text(_isAr ? a.subtitleAr : a.subtitleEn),
              onTap: () {
                _adTitleAr.text = a.titleAr;
                _adTitleEn.text = a.titleEn;
                _adSubAr.text = a.subtitleAr;
                _adSubEn.text = a.subtitleEn;
                _adImage.text = a.imageUrl ?? '';
                _adLink.text = a.linkUrl ?? '';
              },
            ),
          ),
        ),
      ],
    );
    return _previewSplit(preview: _loginAdPreview(l10n), form: form);
  }

  Widget _billingTab(AppLocalizations l10n, PlatformFeeCatalog? fees) {
    final entries = fees?.entries ?? const <MapEntry<String, double>>[];
    for (final e in entries) {
      _feeCtrls.putIfAbsent(
        e.key,
        () => TextEditingController(text: '${e.value}'),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(l10n.opsDeskWatchHint),
        const SizedBox(height: 8),
        if (_billingWatch['ok'] == true)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _watchChip(l10n.opsDeskSubsActive, '${_billingWatch['subs_active'] ?? 0}'),
              _watchChip(l10n.opsDeskSubsPending, '${_billingWatch['subs_pending'] ?? 0}'),
              _watchChip(l10n.opsDeskDupGateway, '${_billingWatch['dup_gateway'] ?? 0}'),
              _watchChip(l10n.opsDeskPayStuck, '${_billingWatch['pay_pending'] ?? 0}'),
            ],
          ),
        const SizedBox(height: 12),
        ...entries.map((e) {
          final ctrl = _feeCtrls[e.key]!;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: AqarTextField(
                    controller: ctrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: _feeKeyLabel(e.key),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => unawaited(_saveFee(e.key)),
                  child: Text(l10n.opsDeskFeeSave),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 16),
        SubscriptionStaffReportsPanel(isAr: _isAr),
      ],
    );
  }

  Widget _noticesTab(AppLocalizations l10n) {
    final form = ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          l10n.opsDeskDraftLive,
          style: const TextStyle(height: 1.4, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.opsDeskNoticeUserId,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          _noticeTargetCaption.isEmpty
              ? l10n.opsDeskNoticePickHint
              : _noticeTargetCaption,
        ),
        const SizedBox(height: 8),
        AqarTextField(
          controller: _noticeTitleAr,
          decoration: InputDecoration(labelText: l10n.opsDeskNoticeTitleAr),
        ),
        const SizedBox(height: 8),
        AqarTextField(
          controller: _noticeTitleEn,
          decoration: InputDecoration(labelText: l10n.opsDeskNoticeTitleEn),
        ),
        const SizedBox(height: 8),
        AqarTextField(
          controller: _noticeBodyAr,
          maxLines: 3,
          decoration: InputDecoration(labelText: l10n.opsDeskNoticeBodyAr),
        ),
        const SizedBox(height: 8),
        AqarTextField(
          controller: _noticeBodyEn,
          maxLines: 3,
          decoration: InputDecoration(labelText: l10n.opsDeskNoticeBodyEn),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _noticeUserId.text.trim().isEmpty
              ? null
              : () => unawaited(_sendNotice()),
          child: Text(
            (_isOwner || _canGrant)
                ? l10n.opsDeskApprovePublish
                : l10n.opsDeskNoticeSend,
          ),
        ),
        if (_canTeamComms) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => unawaited(_broadcastTeam()),
            child: Text(l10n.opsDeskBroadcastTeam),
          ),
        ],
      ],
    );
    return _previewSplit(preview: _noticePreview(l10n), form: form);
  }

  Widget _promoTab(AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          l10n.opsDeskPromoHint,
          style: const TextStyle(height: 1.4, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        AqarTextField(
          controller: _promoCode,
          decoration: InputDecoration(
            labelText: l10n.opsDeskPromoCode,
            helperText: l10n.opsDeskPromoCodeHint,
            helperMaxLines: 4,
          ),
        ),
        const SizedBox(height: 8),
        AqarTextField(
          controller: _promoCampaign,
          decoration: InputDecoration(
            labelText: l10n.opsDeskPromoCampaign,
            helperText: l10n.opsDeskPromoCampaignHint,
            helperMaxLines: 4,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _promoKind,
          decoration: InputDecoration(labelText: l10n.opsDeskPromoKind),
          items: [
            DropdownMenuItem(
              value: 'percent_off',
              child: Text(l10n.opsDeskPromoKindPercent),
            ),
            DropdownMenuItem(
              value: 'fixed_off',
              child: Text(l10n.opsDeskPromoKindFixed),
            ),
            DropdownMenuItem(
              value: 'first_payment_bonus',
              child: Text(l10n.opsDeskPromoKindBonus),
            ),
            DropdownMenuItem(
              value: 'trial_days',
              child: Text(l10n.opsDeskPromoKindTrial),
            ),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _promoKind = v);
          },
        ),
        const SizedBox(height: 8),
        AqarTextField(
          controller: _promoValue,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: l10n.opsDeskPromoValue,
            helperText: l10n.opsDeskPromoValueHint,
            helperMaxLines: 3,
          ),
        ),
        const SizedBox(height: 8),
        AqarTextField(
          controller: _promoMax,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: l10n.opsDeskPromoMax),
        ),
        const SizedBox(height: 8),
        Text(l10n.opsDeskPromoWindowHint),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.opsDeskPromoStarts),
          subtitle: Text('${_promoFrom ?? l10n.opsDeskCampaignSendNow}'),
          trailing: IconButton(
            icon: const Icon(Icons.schedule_outlined),
            onPressed: () async {
              final d = await _pickDateTime(_promoFrom);
              if (mounted) setState(() => _promoFrom = d);
            },
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.opsDeskPromoEnds),
          subtitle: Text('${_promoTo ?? '—'}'),
          trailing: IconButton(
            icon: const Icon(Icons.event_busy_outlined),
            onPressed: () async {
              final d = await _pickDateTime(_promoTo);
              if (mounted) setState(() => _promoTo = d);
            },
          ),
        ),
        const SizedBox(height: 8),
        AqarTextField(
          controller: _promoTitleAr,
          decoration: InputDecoration(labelText: l10n.opsDeskAdTitleAr),
        ),
        const SizedBox(height: 8),
        AqarTextField(
          controller: _promoTitleEn,
          decoration: InputDecoration(labelText: l10n.opsDeskAdTitleEn),
        ),
        SwitchListTile(
          value: _promoActive,
          onChanged: (v) => setState(() => _promoActive = v),
          title: Text(
            _promoActive ? l10n.opsDeskPromoActive : l10n.opsDeskPromoInactive,
          ),
        ),
        FilledButton(
          onPressed: () => unawaited(_savePromo()),
          child: Text(l10n.opsDeskPromoSave),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _promos.isEmpty
                  ? null
                  : () => unawaited(
                        _printTable(
                          id: 'ops_promos',
                          title: l10n.opsDeskTabPromos,
                          columns: _isAr
                              ? const ['الكود', 'النوع', 'القيمة', 'مستخدم', 'مفعّل']
                              : const ['Code', 'Kind', 'Value', 'Used', 'Active'],
                          rows: _promos
                              .map(
                                (p) => [
                                  '${p['code'] ?? ''}',
                                  '${p['kind'] ?? ''}',
                                  '${p['value'] ?? ''}',
                                  '${p['used'] ?? 0}',
                                  '${p['is_active']}',
                                ],
                              )
                              .toList(),
                        ),
                      ),
              icon: const Icon(Icons.print_outlined),
              label: Text(l10n.opsDeskPrint),
            ),
            OutlinedButton.icon(
              onPressed: _promos.isEmpty
                  ? null
                  : () => unawaited(
                        _exportTable(
                          id: 'ops_promos',
                          title: l10n.opsDeskTabPromos,
                          columns: _isAr
                              ? const ['الكود', 'النوع', 'القيمة', 'مستخدم', 'مفعّل']
                              : const ['Code', 'Kind', 'Value', 'Used', 'Active'],
                          rows: _promos
                              .map(
                                (p) => [
                                  '${p['code'] ?? ''}',
                                  '${p['kind'] ?? ''}',
                                  '${p['value'] ?? ''}',
                                  '${p['used'] ?? 0}',
                                  '${p['is_active']}',
                                ],
                              )
                              .toList(),
                        ),
                      ),
              icon: const Icon(Icons.table_view_outlined),
              label: Text(l10n.opsDeskPromoExport),
            ),
            OutlinedButton.icon(
              onPressed: _promos.isEmpty
                  ? null
                  : () => unawaited(
                        _exportExcelTable(
                          id: 'ops_promos',
                          title: l10n.opsDeskTabPromos,
                          columns: _isAr
                              ? const ['الكود', 'النوع', 'القيمة', 'مستخدم', 'مفعّل']
                              : const ['Code', 'Kind', 'Value', 'Used', 'Active'],
                          rows: _promos
                              .map(
                                (p) => [
                                  '${p['code'] ?? ''}',
                                  '${p['kind'] ?? ''}',
                                  '${p['value'] ?? ''}',
                                  '${p['used'] ?? 0}',
                                  '${p['is_active']}',
                                ],
                              )
                              .toList(),
                        ),
                      ),
              icon: const Icon(Icons.grid_on_outlined),
              label: Text(l10n.opsDeskExportExcel),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ..._promos.map((p) {
          final code = '${p['code'] ?? ''}';
          final used = p['used'] ?? 0;
          final title = LocaleContent.pick(
            isAr: _isAr,
            ar: '${p['title_ar'] ?? ''}',
            en: '${p['title_en'] ?? ''}',
          );
          return Card(
            child: ListTile(
              title: Text(code),
              subtitle: Text(
                '${_promoKindLabel(l10n, '${p['kind'] ?? ''}')} · ${p['value'] ?? ''} · '
                '${l10n.opsDeskPromoUsed}: $used'
                '${title.isEmpty ? '' : '\n$title'}',
              ),
              isThreeLine: title.isNotEmpty,
              trailing: Wrap(
                spacing: 0,
                children: [
                  IconButton(
                    tooltip: l10n.opsDeskPromoShare,
                    icon: const Icon(Icons.share_outlined),
                    onPressed: code.isEmpty
                        ? null
                        : () => unawaited(_sharePromoCode(code)),
                  ),
                  IconButton(
                    tooltip: l10n.opsDeskPromoRedemptions,
                    icon: const Icon(Icons.people_outline),
                    onPressed: () => unawaited(_openPromoRedemptions(p)),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _opsSettingsTab(AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          l10n.opsDeskSettingsHint,
          style: const TextStyle(height: 1.4, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        ListTile(
          title: Text(l10n.languageArabic),
          onTap: () => unawaited(setAppLang('ar')),
        ),
        ListTile(
          title: Text(l10n.languageEnglish),
          onTap: () => unawaited(setAppLang('en')),
        ),
        ListTile(
          title: Text(l10n.themeSystem),
          onTap: () => unawaited(setAppTheme(ThemeMode.system)),
        ),
        ListTile(
          title: Text(l10n.themeLight),
          onTap: () => unawaited(setAppTheme(ThemeMode.light)),
        ),
        ListTile(
          title: Text(l10n.themeDark),
          onTap: () => unawaited(setAppTheme(ThemeMode.dark)),
        ),
      ],
    );
  }

  Widget _denied(AppLocalizations l10n) {
    final name = _displayName(l10n);
    final title = _marketTitle(l10n);
    final hello = name == l10n.opsDeskDeniedHelloGuest
        ? l10n.opsDeskDeniedHelloGuest
        : l10n.opsDeskDeniedHello(name);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.handshake_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            hello,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.opsDeskDeniedPolite,
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.45, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.opsDeskDeniedBody,
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.4, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => unawaited(_openExternal(AppBranding.websiteUrl)),
            icon: const Icon(Icons.language_rounded),
            label: Text(l10n.opsDeskOpenWeb),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => unawaited(_openExternal(AppBranding.websiteUrl)),
            icon: const Icon(Icons.smartphone_rounded),
            label: Text(l10n.opsDeskOpenMobile),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => unawaited(_logout()),
            child: Text(l10n.logoutLabel),
          ),
          TextButton(
            onPressed: () => unawaited(_exitDenied()),
            child: Text(l10n.opsDeskExit),
          ),
        ],
      ),
    );
  }

  Widget _previewSplit({required Widget preview, required Widget form}) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    if (!wide) {
      return Column(
        children: [
          SizedBox(height: 280, child: preview),
          const Divider(height: 1),
          Expanded(child: form),
        ],
      );
    }
    return Row(
      textDirection: TextDirection.ltr,
      children: [
        Expanded(flex: 5, child: preview),
        const VerticalDivider(width: 1),
        Expanded(flex: 6, child: form),
      ],
    );
  }

  String _adPlacementLabel(AppLocalizations l10n) {
    switch (_adPlacement) {
      case 'in_app':
        return l10n.opsDeskAdPlaceInApp;
      case 'team':
        return l10n.opsDeskAdPlaceTeam;
      case 'support_card':
        return l10n.opsDeskAdPlaceSupport;
      default:
        return l10n.opsDeskAdPlaceLogin;
    }
  }

  Widget _loginAdPreview(AppLocalizations l10n) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final title = _isAr ? _adTitleAr.text.trim() : _adTitleEn.text.trim();
    final sub = _isAr ? _adSubAr.text.trim() : _adSubEn.text.trim();
    final img = _adImage.text.trim();
    return ColoredBox(
      color: isLight ? const Color(0xFFF2F6FF) : const Color(0xFF0B1020),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.opsDeskPreviewBeforePublish,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            '${l10n.opsDeskPreviewWhere}: ${_adPlacementLabel(l10n)}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 160,
                  child: img.isEmpty
                      ? ColoredBox(
                          color: isLight
                              ? const Color(0xFFEFF3FF)
                              : const Color(0xFF101A33),
                          child: const Center(
                            child: Icon(Icons.image_outlined, size: 40),
                          ),
                        )
                      : CachedNetworkImage(
                          imageUrl: img,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isEmpty ? '—' : title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        sub.isEmpty ? '—' : sub,
                        style: const TextStyle(height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _noticePreview(AppLocalizations l10n) {
    final title =
        _isAr ? _noticeTitleAr.text.trim() : _noticeTitleEn.text.trim();
    final body =
        _isAr ? _noticeBodyAr.text.trim() : _noticeBodyEn.text.trim();
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.opsDeskNoticePreview,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            _noticeTargetCaption.isEmpty
                ? l10n.opsDeskNoticePickHint
                : _noticeTargetCaption,
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: Text(
                title.isEmpty ? '—' : title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                body.isEmpty ? '—' : body,
                style: const TextStyle(height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _identityTitle(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _displayName(l10n),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        Text(
          _staffCapsLabel(l10n, _profile),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    PlatformFeeCatalog? fees;
    try {
      fees = context.watch<PlatformFeeCatalog>();
    } catch (_) {}

    Widget body;
    if (_loading) {
      body = const Center(child: AppLogoLoading());
    } else if (!_isStaff) {
      body = _denied(l10n);
    } else {
      final dests = <({String id, IconData icon, String label, Widget page})>[
        if (_canSupport)
          (
            id: 'tickets',
            icon: Icons.support_agent_outlined,
            label: l10n.opsTabTickets,
            page: _ticketsTab(l10n),
          ),
        if (_canModerate)
          (
            id: 'reports',
            icon: Icons.flag_outlined,
            label: l10n.opsDeskTabReports,
            page: _reportsTab(l10n),
          ),
        if (_canDirectory)
          (
            id: 'users',
            icon: Icons.people_outline,
            label: l10n.opsDeskTabUsers,
            page: _usersTab(l10n),
          ),
        if (_canDirectory)
          (
            id: 'photographers',
            icon: Icons.photo_camera_outlined,
            label: l10n.opsDeskTabPhotographers,
            page: const _StaffPhotographerReviewPanel(),
          ),
        if (_canPulse)
          (
            id: 'intel',
            icon: Icons.insights_outlined,
            label: l10n.opsDeskTabIntel,
            page: _intelTab(l10n),
          ),
        if (_canTeamTab)
          (
            id: 'team',
            icon: Icons.verified_user_outlined,
            label: l10n.opsDeskTabTeam,
            page: _teamTab(l10n),
          ),
        if (_canAds)
          (
            id: 'ads',
            icon: Icons.campaign_outlined,
            label: l10n.opsDeskTabLoginAds,
            page: _adsTab(l10n),
          ),
        if (_canSupport || _isOwner)
          (
            id: 'notices',
            icon: Icons.notifications_outlined,
            label: l10n.opsDeskTabNotices,
            page: _noticesTab(l10n),
          ),
        if (_canCampaigns)
          (
            id: 'campaigns',
            icon: Icons.cell_tower_outlined,
            label: l10n.opsDeskTabCampaigns,
            page: _campaignsTab(l10n),
          ),
        if (_canPromo)
          (
            id: 'promos',
            icon: Icons.local_offer_outlined,
            label: l10n.opsDeskTabPromos,
            page: _promoTab(l10n),
          ),
        if (_canFinance)
          (
            id: 'billing',
            icon: Icons.payments_outlined,
            label: l10n.opsDeskTabBilling,
            page: _billingTab(l10n, fees),
          ),
        if (_isOwner || _canGrant)
          (
            id: 'audit',
            icon: Icons.fact_check_outlined,
            label: l10n.opsDeskTabAudit,
            page: _auditTab(l10n),
          ),
        (
          id: 'settings',
          icon: Icons.settings_outlined,
          label: l10n.opsDeskTabOpsSettings,
          page: _opsSettingsTab(l10n),
        ),
      ];
      if (dests.isEmpty) {
        body = Center(child: Text(l10n.opsDeskForbidden));
      } else {
        var idx = dests.indexWhere((d) => d.id == _dest);
        if (idx < 0) idx = 0;
        final wide = MediaQuery.sizeOf(context).width >= 900;
        body = Row(
          children: [
            SizedBox(
              width: wide ? 228 : 168,
              child: ListView.builder(
                itemCount: dests.length,
                itemBuilder: (context, i) {
                  final d = dests[i];
                  final selected = i == idx;
                  return ListTile(
                    selected: selected,
                    leading: Icon(d.icon),
                    title: Text(
                      d.label,
                      maxLines: wide ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: wide ? 13 : 10),
                    ),
                    dense: !wide,
                    onTap: () => setState(() => _dest = d.id),
                  );
                },
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: dests[idx].page),
          ],
        );
      }
    }

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: _isStaff ? _identityTitle(l10n) : Text(l10n.opsDeskTitle),
        actions: [
          if (_isStaff) _menu(l10n, cs),
        ],
      ),
      body: SafeArea(child: body),
    );
  }
}

class _StaffPhotographerReviewPanel extends StatefulWidget {
  const _StaffPhotographerReviewPanel();

  @override
  State<_StaffPhotographerReviewPanel> createState() =>
      _StaffPhotographerReviewPanelState();
}

class _StaffPhotographerReviewPanelState
    extends State<_StaffPhotographerReviewPanel> {
  final _svc = PhotographerService(Supabase.instance.client);
  List<PhotographerProfile> _rows = const [];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _svc.staffPending();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_loading) return const Center(child: AppLogoLoading());
    if (_rows.isEmpty) {
      return Center(child: Text(l10n.photographerEmptyTab));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final p = _rows[i];
        return Card(
          child: ListTile(
            title: Text(p.displayName, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(
              [
                if (p.joinSlaOverdue) l10n.photographerSlaOverdue,
                p.city,
                p.nationalId,
                p.commercialRegister,
              ].where((s) => s.trim().isNotEmpty).join(' · '),
            ),
            trailing: Wrap(
              spacing: 6,
              children: [
                OutlinedButton(
                  onPressed: () async {
                    await _svc.staffReview(userId: p.userId, approve: false);
                    await _load();
                  },
                  child: Text(l10n.photographerDecline),
                ),
                FilledButton(
                  onPressed: () async {
                    await _svc.staffReview(userId: p.userId, approve: true);
                    await _load();
                  },
                  child: Text(l10n.photographerAccept),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
