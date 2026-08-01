// lib/screens/marketer_request_details_page.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../navigation/chat_navigation.dart';
import '../core/marketing/marketer_owner_chat_intro_ar.dart';
import '../core/marketing/listing_request_marketing_price.dart';
import '../core/workflow/listing_workflow_copy.dart';
import '../core/workflow/listing_workflow_stage.dart';
import '../core/workflow/listing_workflow_unified.dart';
import '../core/workflow/listing_workflow_ui_context.dart';
import '../core/workflow/workflow_display_texts.dart';
import '../services/marketing_flow_service.dart';
import '../core/listing/property_listing_display.dart';
import '../core/utils/app_money.dart';
import '../core/utils/users_profiles_safe_select.dart';
import '../theme.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/listing/request_summary_table.dart';
import '../widgets/listing_marketing_tracking_sheet.dart';
import '../widgets/listing_workflow_progress_strip.dart';
import '../widgets/listing_pricing_breakdown.dart';
import '../widgets/marketing_offer_submit_sheet.dart';
import 'chat_page.dart';

class MarketerRequestDetailsPage extends StatefulWidget {
  final String lang;
  final String inviteId;
  final String requestId;

  /// داخل لوحة المستخدم بعرض ≥580: شريط [UserDashboard] يعرض العنوان والرجوع — لا نكرر AppBar هنا.
  final bool embedAppBar;

  const MarketerRequestDetailsPage({
    super.key,
    required this.lang,
    required this.inviteId,
    required this.requestId,
    this.embedAppBar = false,
  });

  @override
  State<MarketerRequestDetailsPage> createState() => _MarketerRequestDetailsPageState();
}

class _MarketerRequestDetailsPageState extends State<MarketerRequestDetailsPage> {
  late final MarketingFlowService _svc;

  /// Controller مخصّص للتمرير — يُستخدم مع `Scrollbar` لتفعيل شريط التمرير
  /// على الويب وتفادي تنازع التمرير مع الأشرطة العلوية/السفلية.
  final ScrollController _detailsScrollCtrl = ScrollController();

  bool _loading = true;
  String? _err;

  Map<String, dynamic>? _invite;
  Map<String, dynamic>? _request;
  Map<String, dynamic>? _previewProperty;
  Map<String, dynamic>? _contractSnap;
  bool _hasLiveOfferThisRound = false;
  String? _ownerDisplayNameResolved;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  String _t(String ar, String en) => _isAr ? ar : en;

  /// لغة تسميات الحالات: نفضّل لغة واجهة Material ثم `widget.lang`.
  bool _labelsAr(BuildContext context) {
    try {
      if (Localizations.localeOf(context)
          .languageCode
          .toLowerCase()
          .startsWith('ar')) {
        return true;
      }
    } catch (_) {}
    final w = widget.lang.toLowerCase();
    if (w == 'ar') return true;
    if (w == 'en') return false;
    return true;
  }

  @override
  void initState() {
    super.initState();
    _svc = MarketingFlowService(Supabase.instance.client);
    _load();
  }

  @override
  void dispose() {
    _detailsScrollCtrl.dispose();
    super.dispose();
  }

  String _safeText(dynamic v, {String fallback = '-'}) {
    final s = (v == null) ? '' : v.toString().trim();
    return s.isEmpty ? fallback : s;
  }

  String _ownerDisplayName() {
    final cached = (_ownerDisplayNameResolved ?? '').trim();
    if (cached.isNotEmpty) return cached;
    final r = _request ?? const <String, dynamic>{};
    for (final k in const [
      'request_owner_full_name',
      'preview_owner_full_name',
      'owner_full_name',
      'request_owner_legal_name',
      'preview_owner_legal_name',
      'owner_legal_name',
      'request_owner_name',
      'preview_owner_name',
      'owner_name',
    ]) {
      final s = (r[k] ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return _t('غير معروف', 'Unknown');
  }

  Future<void> _resolveOwnerDisplayNameFromProfile() async {
    final r = _request;
    if (r == null) return;
    for (final k in const [
      'request_owner_full_name',
      'preview_owner_full_name',
      'owner_full_name',
      'request_owner_name',
      'preview_owner_name',
      'owner_name',
    ]) {
      final s = (r[k] ?? '').toString().trim();
      if (s.isNotEmpty) {
        _ownerDisplayNameResolved = s;
        return;
      }
    }
    final oid =
        (r['owner_id'] ?? r['request_owner_id'] ?? '').toString().trim();
    if (oid.isEmpty) return;
    try {
      final prof = await UsersProfilesSafeSelect.fetchProfileById(
        Supabase.instance.client,
        oid,
        columnAttempts: UsersProfilesSafeSelect.structuredLegalNameColumns,
      );
      if (prof == null) return;
      String pick(dynamic v) => (v ?? '').toString().trim();
      final ar = _isAr;
      if (ar) {
        final quad = [
          pick(prof['first_name_ar']),
          pick(prof['second_name_ar']),
          pick(prof['third_name_ar']),
          pick(prof['fourth_name_ar']),
        ].where((s) => s.isNotEmpty).join(' ');
        if (quad.isNotEmpty) {
          _ownerDisplayNameResolved = quad;
          return;
        }
        final full = pick(prof['full_name_ar']);
        if (full.isNotEmpty) {
          _ownerDisplayNameResolved = full;
          return;
        }
      } else {
        final quad = [
          pick(prof['first_name_en']),
          pick(prof['second_name_en']),
          pick(prof['third_name_en']),
          pick(prof['fourth_name_en']),
        ].where((s) => s.isNotEmpty).join(' ');
        if (quad.isNotEmpty) {
          _ownerDisplayNameResolved = quad;
          return;
        }
        final full = pick(prof['full_name_en']);
        if (full.isNotEmpty) {
          _ownerDisplayNameResolved = full;
          return;
        }
      }
      final any = pick(prof['full_name']);
      final un = pick(prof['username']);
      final name = any.isNotEmpty ? any : un;
      if (name.isNotEmpty) _ownerDisplayNameResolved = name;
    } catch (_) {}
  }

  String _formatRowDateTime(dynamic v) {
    final dt = DateTime.tryParse((v ?? '').toString());
    if (dt == null) return _t('غير محدد', 'Not set');
    final local = dt.toLocal();
    final y = local.year;
    final mo = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    return '$y-$mo-$d  $h:$mi';
  }

  String _summaryPriceLabel() {
    final r = _request ?? const <String, dynamic>{};
    final p = _previewProperty;
    final amount = effectivePropertyPriceSarForMarketingFee(r, p);
    if (amount <= 0) return _t('غير محدد', 'Not set');
    return AppMoney.formatWithCurrencyCode(
      amount,
      isAr: _isAr,
      currencyCode: 'SAR',
    );
  }

  Widget _summaryMetricCell({
    required String label,
    required String value,
    required ColorScheme cs,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: cs.primary),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
              height: 1.25,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildRequestSummaryGrid(BuildContext context) {
    final la = _labelsAr(context);
    final r = _request ?? const <String, dynamic>{};
    final p = _previewProperty;
    final wfCtx = _wfCtx;
    final inviteStatus = _inviteStatus();
    final distanceKm = _invite?['distance_km'];
    final area = (p?['area'] as num?)?.toDouble() ??
        (r['area'] as num?)?.toDouble();
    final propertyType = _safeText(
      p?['property_type'] ?? r['property_type'] ?? r['preview_property_type'],
      fallback: '',
    );
    final listingCode = _safeText(
      r['listing_code'] ?? r['request_listing_code'] ?? p?['listing_code'],
      fallback: '',
    );
    final location = _safeText(
      p?['location'] ?? r['location'] ?? r['address_line'],
      fallback: _safeText(r['address_line'], fallback: ''),
    );

    final rows = <RequestSummaryRow>[
      RequestSummaryRow(
        label: _t('اسم المالك', 'Owner name'),
        value: _ownerDisplayName(),
      ),
      RequestSummaryRow(
        label: _t('تاريخ ووقت الإعلان', 'Listing date & time'),
        value: _formatRowDateTime(r['created_at']),
      ),
      RequestSummaryRow(
        label: _t('السعر', 'Price'),
        value: _summaryPriceLabel(),
        emphasize: true,
      ),
      RequestSummaryRow(
        label: _t('العنوان', 'Title'),
        value: _safeText(r['title'], fallback: _t('طلب تسويق', 'Marketing request')),
      ),
      RequestSummaryRow(
        label: _t('المدينة', 'City'),
        value: _safeText(r['city'] ?? p?['city']),
      ),
      RequestSummaryRow(
        label: _t('الموقع', 'Location'),
        value: location.isEmpty ? _t('غير محدد', 'Not set') : location,
      ),
      if (area != null)
        RequestSummaryRow(
          label: _t('المساحة', 'Area'),
          value: '${area.toStringAsFixed(0)} ${_t('م²', 'm²')}',
        ),
      RequestSummaryRow(
        label: _t('الغرض', 'Purpose'),
        value: PropertyListingDisplay.purposeLabelForRequestRow(r, la),
      ),
      if (propertyType.isNotEmpty)
        RequestSummaryRow(
          label: _t('نوع العقار', 'Property type'),
          value: propertyType,
        ),
      RequestSummaryRow(
        label: _t('حالة الطلب', 'Request status'),
        value: WorkflowDisplayTexts.requestStatus(
          (r['status'] ?? '').toString().trim().isEmpty
              ? 'unknown'
              : (r['status'] ?? '').toString().trim(),
          la,
        ),
      ),
      if (wfCtx != null)
        RequestSummaryRow(
          label: _t('مرحلة سير العمل', 'Workflow'),
          value: la ? wfCtx.statusLabelAr : wfCtx.statusLabelEn,
        ),
      RequestSummaryRow(
        label: _t('حالة الدعوة', 'Invite status'),
        value: WorkflowDisplayTexts.inviteStatus(inviteStatus, la),
      ),
      if (distanceKm != null)
        RequestSummaryRow(
          label: _t('المسافة', 'Distance'),
          value: '${distanceKm.toString()} km',
        ),
      if (listingCode.isNotEmpty && listingCode != '-')
        RequestSummaryRow(
          label: _t('رمز الإعلان', 'Listing code'),
          value: listingCode,
        ),
    ];

    return RequestSummaryTable(
      title: _t('ملخص الطلب', 'Request summary'),
      rows: rows,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });

    try {
      final data = await _svc.marketerInviteDetails(
        widget.inviteId,
        fallbackRequestId: widget.requestId,
      );

      final inv = (data['invite'] as Map?)?.cast<String, dynamic>();
      final req = (data['request'] as Map?)?.cast<String, dynamic>();

      setState(() {
        _invite = inv;
        _request = req;
      });

      await _loadPreviewProperty();
      await _resolveOwnerDisplayNameFromProfile();
      if (mounted) setState(() {});
      await _refreshLiveOfferFlag();
      await _loadContractSnapshot();

      // تعبئة مبدئية (اختياري): إذا عندك حقول افتراضية أو payload
      // يمكنك وضع شيء هنا لاحقًا.
    } catch (e) {
      final raw = e.toString();
      final notFound = raw.contains('Invite not found');
      setState(() {
        _err = notFound
            ? _t(
                'تعذّر فتح التفاصيل: الدعوة غير متاحة أو انتهت. ارجع للقائمة وافتح الطلب من تبويب «السوق العقاري».',
                'Could not open details: the invite is unavailable or expired. Go back and open the request from the Real estate market tab.',
              )
            : raw;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _inviteStatus() => _safeText(_invite?['status'], fallback: 'pending').toLowerCase();

  List<String> _heroUrlsForBanner() {
    final p = _previewProperty;
    if (p != null) {
      final imgs = ((p['property_images'] as List?) ?? const <dynamic>[])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList()
        ..sort((a, b) => ((a['sort_order'] as num?)?.toInt() ?? 0)
            .compareTo((b['sort_order'] as num?)?.toInt() ?? 0));
      final out = <String>[];
      for (final im in imgs) {
        final path =
            (im['path'] ?? im['file_name'] ?? '').toString().trim();
        if (path.isEmpty) continue;
        out.add(
          Supabase.instance.client.storage
              .from('property-images')
              .getPublicUrl(path),
        );
      }
      if (out.isNotEmpty) return out;
    }
    final req = _request;
    if (req == null) return [];
    final dyn = req['preview_image_urls'];
    if (dyn is! List) return [];
    final out = <String>[];
    for (final e in dyn) {
      final s = e.toString().trim();
      if (s.isEmpty) continue;
      if (s.startsWith('http://') || s.startsWith('https://')) {
        out.add(s);
      } else {
        out.add(
          Supabase.instance.client.storage
              .from('property-images')
              .getPublicUrl(s),
        );
      }
    }
    return out;
  }

  String get _resolvedInviteId {
    final fromRow = (_invite?['id'] ?? '').toString().trim();
    if (fromRow.isNotEmpty) return fromRow;
    return widget.inviteId.trim();
  }

  bool get _inviteAllowsOffer {
    final st = _inviteStatus();
    return st == 'pending' || st == 'offered' || st == 'seen';
  }

  bool get _isPublishedLike {
    final r = _request;
    if (r == null) return false;
    if (ListingWorkflowUnified.requestActivelyCollectingOffers(r)) {
      return false;
    }
    final ctx = _wfCtx;
    if (ctx != null && ctx.showMarketerSubmitOffer) return false;
    final wf = (r['workflow_stage'] ?? '').toString().trim().toLowerCase();
    final st = (r['status'] ?? '').toString().trim().toLowerCase();
    return ctx?.stage == ListingWorkflowStage.published ||
        ctx?.stage == ListingWorkflowStage.reserved ||
        wf == 'published' ||
        wf == 'reserved' ||
        ((st == 'published' || st == 'live') && wf != 'waiting_marketers');
  }

  bool get _shouldShowOfferPanel {
    if (_request == null) return false;
    if (_hasLiveOfferThisRound) return true;
    if (!_inviteAllowsOffer) return false;
    if (_isContractStageOrLater) return false;
    final ctx = _wfCtx;
    return ctx?.showMarketerSubmitOffer == true;
  }

  /// `true` عندما يكون الطلب في مرحلة تعاقد أو ما بعده (موافقة المالك +
  /// إرسال العقد + توقيع العقد + التصريح + النشر). في هذه الحالات لا يجوز
  /// إظهار حقل «إرسال عرض» للمسوّق المختار — العرض قد قُبل بالفعل.
  bool get _isContractStageOrLater {
    final wf = (_request?['workflow_stage'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return wf == 'contract_sent' ||
        wf == 'contract_signed' ||
        wf == 'awaiting_contract' ||
        wf == 'pending_owner' ||
        wf == 'contract_returned' ||
        wf == 'permit_pending' ||
        wf == 'awaiting_permits' ||
        wf == 'pending_permits' ||
        wf == 'permit_issued' ||
        wf == 'published';
  }

  double? get _propertyBaseSarHint {
    final req = _request;
    if (req == null) return null;
    final v = effectivePropertyPriceSarForMarketingFee(req, _previewProperty);
    return v > 0 ? v : null;
  }

  ListingWorkflowUiContext? get _wfCtx => _request == null
      ? null
      : ListingWorkflowUiContext.fromListingRequest(
          Map<String, dynamic>.from(_request!),
        );

  /// المسوق المختار والعقد أُرسل للمالك (`pending_owner` / `contract_sent`).
  bool get _isSelectedMarketerAwaitingContract {
    final uid = (Supabase.instance.client.auth.currentUser?.id ?? '').trim();
    if (uid.isEmpty || _request == null) return false;
    final sel = (_request!['selected_marketer_id'] ?? '').toString().trim();
    final wf = (_request!['workflow_stage'] ?? '').toString().toLowerCase().trim();
    return sel == uid && wf == 'contract_sent';
  }

  bool get _isSelectedMarketerContractReturned {
    final uid = (Supabase.instance.client.auth.currentUser?.id ?? '').trim();
    if (uid.isEmpty || _request == null) return false;
    final sel = (_request!['selected_marketer_id'] ?? '').toString().trim();
    final wf = (_request!['workflow_stage'] ?? '').toString().toLowerCase().trim();
    return sel == uid && wf == 'contract_returned';
  }

  String _returnedContractNoticeText() {
    final reason = (_contractSnap?['returned_reason'] ?? '').toString().trim();
    final rLine = reason.isEmpty
        ? ''
        : '${ListingWorkflowCopy.lblReturnReason(_isAr)}: $reason\n\n';
    return '${ListingWorkflowCopy.marketerContractReturnedTitle(_isAr)}\n\n$rLine'
        '${_isAr ? 'عدّل المسودة ثم أعد الإرسال من تبويب «التعاقد» في صفحتي.' : 'Revise the draft, then resend from the «Contracting» tab under My ads.'}';
  }

  Future<void> _loadContractSnapshot() async {
    final cid = (_request?['contract_id'] ?? '').toString().trim();
    if (cid.isEmpty) {
      if (mounted) setState(() => _contractSnap = null);
      return;
    }
    try {
      final c = await _svc.contractById(cid);
      if (!mounted) return;
      setState(() => _contractSnap = c);
    } catch (_) {
      if (mounted) setState(() => _contractSnap = null);
    }
  }

  Future<void> _refreshLiveOfferFlag() async {
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (uid.isEmpty) return;
    final round = (_request?['marketing_round'] as num?)?.toInt() ?? 1;
    try {
      final rows = await Supabase.instance.client
          .from('listing_offers')
          .select('id,round_no')
          .eq('request_id', widget.requestId)
          .eq('marketer_id', uid)
          .inFilter('status', ['submitted', 'pending']);
      if (!mounted) return;
      final list = rows as List;
      var has = false;
      for (final raw in list) {
        final m = Map<String, dynamic>.from(raw as Map);
        final rno = (m['round_no'] as num?)?.toInt() ?? 1;
        if (rno == round) {
          has = true;
          break;
        }
      }
      setState(() => _hasLiveOfferThisRound = has);
    } catch (_) {
      if (mounted) setState(() => _hasLiveOfferThisRound = false);
    }
  }

  Future<void> _loadPreviewProperty() async {
    try {
      final previewId =
          (_request?['preview_property_id'] ?? '').toString().trim();
      const propSelect =
          'id,title,city,location,address_line,area,price,created_at,status,'
          'default_cover_used,latitude,longitude,property_images(path,file_name,sort_order)';
      dynamic rows;
      if (previewId.isNotEmpty) {
        final one = await Supabase.instance.client
            .from('properties')
            .select(propSelect)
            .eq('id', previewId)
            .maybeSingle();
        if (one != null) {
          if (!mounted) return;
          setState(
            () => _previewProperty = Map<String, dynamic>.from(one as Map),
          );
          return;
        }
      }
      rows = await Supabase.instance.client
          .from('properties')
          .select(propSelect)
          .eq('request_id', widget.requestId)
          .order('created_at', ascending: false)
          .limit(1);
      if (!mounted) return;
      final list = rows as List;
      if (list.isNotEmpty) {
        setState(
          () => _previewProperty =
              Map<String, dynamic>.from(list.first as Map),
        );
      }
    } catch (_) {}
  }

  String get _contractIdStr =>
      (_request?['contract_id'] ?? '').toString().trim();

  String get _contractPdfStr =>
      (_request?['contract_pdf_url'] ?? '').toString().trim();

  bool get _showMarketerOwnerChatAction {
    if (!_marketerOwnerChatUnlocked) return false;
    final r = _request;
    if (r == null || _isPublishedLike) return false;
    final pid = (_previewProperty?['id'] ?? r['preview_property_id'] ?? '')
        .toString()
        .trim();
    final oid =
        (r['request_owner_id'] ?? r['owner_id'] ?? '').toString().trim();
    if (pid.isEmpty && oid.isEmpty) return false;
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (oid.isNotEmpty && oid == uid) return false;
    return true;
  }

  bool get _marketerOwnerChatUnlocked {
    final uid = (Supabase.instance.client.auth.currentUser?.id ?? '').trim();
    if (uid.isEmpty || _request == null) return false;
    final sel = (_request!['selected_marketer_id'] ?? '').toString().trim();
    if (sel.isEmpty || sel != uid) return false;
    return _isContractStageOrLater;
  }

  String _marketerOwnerChatDraft() {
    final r = _request ?? const <String, dynamic>{};
    final p = _previewProperty;
    final city = _safeText(r['city'] ?? p?['city']);
    final location = _safeText(
      p?['location'] ?? r['location'] ?? r['address_line'],
      fallback: _safeText(r['address_line'], fallback: ''),
    );
    final loc = [city, location].where((s) => s.trim().isNotEmpty).join(' — ');
    return MarketerOwnerChatIntroAr.build(
      isAr: _isAr,
      ownerDisplayName: _ownerDisplayName(),
      listingNoTenDigit: MarketerOwnerChatIntroAr.tenDigitListingCodeFromRow(r),
      locationLine: loc,
    );
  }

  Future<void> _openContractPdfUrl() async {
    final raw = _contractPdfStr;
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('رابط غير صالح', 'Invalid link'))),
      );
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'تعذّر فتح الملف. جرّب من المتصفح.',
              'Could not open the file.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openOwnerChatAction() async {
    final r = _request;
    if (r == null) return;
    final draft = _marketerOwnerChatDraft();
    final pid = (_previewProperty?['id'] ?? r['preview_property_id'] ?? '')
        .toString()
        .trim();
    if (pid.isNotEmpty) {
      await ChatNavigation.push(
        context,
        isAr: _isAr,
        embedInParentDashboardShell: widget.embedAppBar,
        propertyId: pid,
        title: _t('محادثة مع المالك', 'Chat with owner'),
        initialDraftMessage: draft,
      );
      return;
    }
    final oid =
        (r['request_owner_id'] ?? r['owner_id'] ?? '').toString().trim();
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (oid.isNotEmpty && oid != uid) {
      await ChatNavigation.push(
        context,
        isAr: _isAr,
        embedInParentDashboardShell: widget.embedAppBar,
        counterpartyId: oid,
        kind: ConversationKind.direct,
        title: _t('محادثة مع المالك', 'Chat with owner'),
        initialDraftMessage: draft,
      );
    }
  }

  void _openMarketingTrackSheet() {
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (uid.isEmpty) return;
    unawaited(
      showListingMarketingTrackingSheet(
        context: context,
        sb: Supabase.instance.client,
        requestId: widget.requestId,
        isAr: _isAr,
        viewerUserId: uid,
      ),
    );
  }

  Future<void> _reloadInviteAndRequestAfterOffer() async {
    try {
      final data = await _svc.marketerInviteDetails(
        widget.inviteId,
        fallbackRequestId: widget.requestId,
      );
      if (!mounted) return;
      final inv = (data['invite'] as Map?)?.cast<String, dynamic>();
      final req = (data['request'] as Map?)?.cast<String, dynamic>();
      setState(() {
        _invite = inv;
        _request = req;
      });
      await _loadPreviewProperty();
      await _loadContractSnapshot();
      await _refreshLiveOfferFlag();
    } catch (_) {
      if (mounted) await _refreshLiveOfferFlag();
    }
  }

  Future<void> _afterOfferSubmittedFromDetails() async {
    // لا نُغلق الصفحة بعد إرسال العرض كي يَرى المسوّق فور التحديث:
    //   • أن حقل «تفاصيل عرضك» وزر «إرسال العرض» اختفيا.
    //   • قسم «حالة عرضك» وزر «إشعار آخر للمالك» (مُعطَّل حتى 48 ساعة).
    // وعند ضغطه «رجوع» يدوياً، يُرجِع التحديث للوحة عبر `pop(true)` لتنعكس
    // بطاقة العرض الجديدة في تبويب «عروضي».
    await _reloadInviteAndRequestAfterOffer();
  }

  Widget _buildMarketerDetailsQuickActions(BuildContext context) {
    // — الإجراءات السريعة في تفاصيل طلب التسويق.
    //   حسب طلب المستخدم: لم نعد نعرض «دردشة مع المالك» هنا — فقط
    //   «تتبع الطلب» وأزرار العقد (إن وُجد عقد فعلي).
    final chips = <Widget>[
      FilledButton.tonalIcon(
        onPressed: _openMarketingTrackSheet,
        icon: const Icon(Icons.timeline_outlined),
        label: Text(_t('تتبع الطلب', 'Track request')),
      ),
    ];
    if (_showMarketerOwnerChatAction) {
      chips.add(
        OutlinedButton.icon(
          onPressed: () => unawaited(_openOwnerChatAction()),
          icon: const Icon(Icons.chat_outlined),
          label: Text(_t('دردشة مع المالك', 'Chat with owner')),
        ),
      );
    }
    if (_contractPdfStr.isNotEmpty) {
      chips.add(
        OutlinedButton.icon(
          onPressed: () => unawaited(_openContractPdfUrl()),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: Text(_t('عقد PDF', 'Contract PDF')),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: LayoutBuilder(
        builder: (_, cts) {
          final narrow = cts.maxWidth < 420;
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < chips.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  chips[i],
                ],
              ],
            );
          }
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: widget.embedAppBar
            ? null
            : AppBar(
                automaticallyImplyLeading: false,
                leading: BackButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                title: Text(_t('تفاصيل طلب التسويق', 'Marketing Request Details')),
                actions: [
                  IconButton(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh),
                    tooltip: _t('تحديث', 'Refresh'),
                  ),
                ],
              ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _invite == null) {
      return const Center(child: AppLogoLoading());
    }

    if (_err != null && _invite == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('تعذّر تحميل التفاصيل', 'Failed to load details'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(_err!),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text(_t('إعادة المحاولة', 'Retry')),
            ),
          ],
        ),
      );
    }

    final wfCtx = _wfCtx;
    final notesOwner = _safeText(
      PropertyListingDisplay.ownerNotesFromListingRequestRow(_request),
      fallback: '',
    );

    final bottomPad =
        24.0 + MediaQuery.paddingOf(context).bottom + MediaQuery.viewInsetsOf(context).bottom;

    final heroUrls = _heroUrlsForBanner();

    return PrimaryScrollController(
      controller: _detailsScrollCtrl,
      child: Scrollbar(
        controller: _detailsScrollCtrl,
        child: SingleChildScrollView(
          controller: _detailsScrollCtrl,
          // physics ثابتة قابلة للتمرير دائماً — تحلّ مشكلة «العلاقة عند السحب»
          // على متصفّحات الجوال والويب.
          physics: kIsWeb && AqarScrollBehavior.isCompactTouchLike(context)
              ? const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                )
              : const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          if (widget.embedAppBar)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: IconButton.filledTonal(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: _t('تحديث', 'Refresh'),
                ),
              ),
            ),
          if (heroUrls.isNotEmpty) ...[
            RepaintBoundary(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: Image.network(
                    heroUrls.first,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => ColoredBox(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      child: Center(
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          _sectionTitle(_t('ملخص', 'Summary')),
          _buildRequestSummaryGrid(context),
          if (_previewProperty != null) ...[
            const SizedBox(height: 12),
            _sectionTitle(_t('تفاصيل العقار', 'Property details')),
            _propertyPreviewCard(
              _previewProperty!,
              showLeadImage: heroUrls.isEmpty,
            ),
          ],

          if (notesOwner.isNotEmpty) ...[
            const SizedBox(height: 12),
            _sectionTitle(_t('ملاحظات المالك', 'Owner notes')),
            Text(notesOwner),
          ],

          if (wfCtx != null) ...[
            const SizedBox(height: 12),
            ListingWorkflowProgressStrip(
              stage: wfCtx.stage,
              compact: false,
              dense: true,
              deadline: wfCtx.primaryDeadline,
              permitSoundContextId: widget.requestId,
            ),
          ],

          if (_isSelectedMarketerAwaitingContract) ...[
            const SizedBox(height: 12),
            _noticeCard(
              context: context,
              text:
                  '${ListingWorkflowCopy.marketerAwaitingContractTitle(_isAr)}\n\n'
                  '${ListingWorkflowCopy.marketerAwaitingContractBody(_isAr)}',
              tone: _NoticeTone.success,
            ),
          ],

          if (_isSelectedMarketerContractReturned) ...[
            const SizedBox(height: 12),
            _noticeCard(
              context: context,
              text: _returnedContractNoticeText(),
              tone: _NoticeTone.blocked,
            ),
          ],

          const SizedBox(height: 20),
          _sectionTitle(_t('إجراءات', 'Actions')),
          _noticeCard(
            context: context,
            text: _t(
              'لا يلزم قبول يدوي للدعوة. يكفي إرسال العرض وسيتم تحديث حالة الدعوة تلقائيًا.',
              'Manual invite acceptance is not required. Sending an offer updates invite status automatically.',
            ),
            tone: _NoticeTone.info,
          ),
          _buildMarketerDetailsQuickActions(context),

          // قسم العرض: نُبقي اللوحة مرئية كي تستطيع عرض «حالة عرضك» وزر
          // «إشعار آخر» للمالك بعد 48 ساعة، أو إخفاء الزر والحقل تلقائياً
          // حين يَختار المالك مسوّقاً آخر.
          //
          // — تُخفى تماماً (لا حقل ولا زر) في الحالات التالية:
          //   * الإعلان منشور (`_isPublishedLike`).
          //   * المرحلة وصلت لـ«تم الموافقة/التعاقد» وما بعدها
          //     (`_isContractStageOrLater`) — تطلَب المستخدم عدم ظهور
          //     الحقل وزر «إرسال العرض» في تبويب التعاقد.
          if (!_shouldShowOfferPanel &&
              !_isContractStageOrLater &&
              _inviteAllowsOffer &&
              _wfCtx != null &&
              !_wfCtx!.showMarketerSubmitOffer) ...[
            const SizedBox(height: 12),
            _noticeCard(
              context: context,
              text: ListingWorkflowCopy.marketerSubmitBlockedExplanation(
                _isAr,
                hasLiveOfferThisRound: _hasLiveOfferThisRound,
                ctx: _wfCtx,
              ) ??
                  _t(
                    'لا يمكن إتمام الصفقة حالياً.',
                    'Cannot complete a deal right now.',
                  ),
              tone: _NoticeTone.blocked,
            ),
          ],

          if (_shouldShowOfferPanel) ...[
            const SizedBox(height: 20),
            _sectionTitle(
              _hasLiveOfferThisRound
                  ? _t('حالة عرضك', 'Your offer status')
                  : _t('إرسال عرض تسويقي', 'Send marketing offer'),
            ),
            MarketingOfferSubmitPanel(
              requestId: widget.requestId,
              inviteId:
                  _resolvedInviteId.isEmpty ? null : _resolvedInviteId,
              isAr: _isAr,
              showDragHandle: false,
              useInnerScroll: false,
              propertyBaseSarHint: _propertyBaseSarHint,
              onSuccess: () => unawaited(_afterOfferSubmittedFromDetails()),
            ),
          ] else if (_isPublishedLike) ...[
            const SizedBox(height: 20),
            _noticeCard(
              context: context,
              text: _t(
                'تم نشر الإعلان، لا يمكن إتمام صفقة تسويق جديدة.',
                'The listing is published; new marketing offers are disabled.',
              ),
              tone: _NoticeTone.info,
            ),
          ] else if (!_inviteAllowsOffer) ...[
            const SizedBox(height: 20),
            _noticeCard(
              context: context,
              text: ListingWorkflowCopy.inviteBlocksOffer(
                _isAr,
                _inviteStatus(),
              ),
              tone: _NoticeTone.blocked,
            ),
          ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        t,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _propertyPreviewCard(
    Map<String, dynamic> p, {
    bool showLeadImage = true,
  }) {
    final imgs = ((p['property_images'] as List?) ?? const <dynamic>[])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList()
      ..sort((a, b) =>
          ((a['sort_order'] as num?)?.toInt() ?? 0).compareTo((b['sort_order'] as num?)?.toInt() ?? 0));
    final path = imgs.isEmpty
        ? ''
        : ((imgs.first['path'] ?? imgs.first['file_name'] ?? '') as String)
            .toString()
            .trim();
    final imgUrl = path.isEmpty
        ? ''
        : Supabase.instance.client.storage.from('property-images').getPublicUrl(path);

    final title = _safeText(p['title'], fallback: _t('عقار بدون عنوان', 'Untitled listing'));
    final city = _safeText(p['city']);
    final location = _safeText(p['location'], fallback: _safeText(p['address_line']));
    final area = (p['area'] as num?)?.toDouble();
    final price = (p['price'] as num?)?.toDouble();
    final dt = DateTime.tryParse((p['created_at'] ?? '').toString());
    final listedAt = dt == null
        ? '-'
        : '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showLeadImage && imgUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  imgUrl,
                  height: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            if (showLeadImage && imgUrl.isNotEmpty) const SizedBox(height: 10),
            _kv(_t('العنوان', 'Title'), title),
            _kv(_t('المدينة', 'City'), city),
            _kv(_t('الموقع', 'Location'), location),
            if (area != null) _kv(_t('المساحة', 'Area'), '${area.toStringAsFixed(0)} ${_t('م²', 'm²')}'),
            if (price != null) _kv(_t('السعر', 'Price'), '${price.toStringAsFixed(0)} SAR'),
            _kv(_t('تاريخ الطرح', 'Listed at'), listedAt),

            // — فاتورة الإعلان (الأساسي + الضريبة + العمولة + الإجمالي
            //   المستحق) مأخوذة من إعدادات المعلن نفسه. تظهر دائماً داخل
            //   تفاصيل الطلب — حتى يَعلم المسوّق المبلغ الفعلي قبل تقديم
            //   عرضه. متكيّفة مع الشاشات الصغيرة (لا التفاف للنصوص).
            if (price != null && price > 0) ...[
              const SizedBox(height: 12),
              _listingInvoiceCard(price),
            ],
          ],
        ),
      ),
    );
  }

  /// بطاقة الفاتورة (الأساسي + الضريبة + العمولة + المجموع النهائي) المشتقّة
  /// من إعدادات المعلن في الإعلان نفسه (v9). تَستخدم الويدجت الموحّد
  /// [ListingPricingBreakdown] الذي يتكيّف مع الشاشات الضيّقة تلقائياً
  /// (يضع التسمية فوق المبلغ بدل صفّ واحد ملتفّ).
  Widget _listingInvoiceCard(double enteredPrice) {
    final r = _request ?? const <String, dynamic>{};

    bool toB(Object? v, {bool fallback = true}) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final s = v.trim().toLowerCase();
        if (s == 'true' || s == '1' || s == 'yes') return true;
        if (s == 'false' || s == '0' || s == 'no') return false;
      }
      return fallback;
    }

    double toD(Object? v, double fallback) {
      if (v is num) return v.toDouble();
      if (v is String) {
        final s = v.trim();
        if (s.isEmpty) return fallback;
        return double.tryParse(s) ?? fallback;
      }
      return fallback;
    }

    final inv = ListingInvoiceModel(
      enteredPrice: enteredPrice,
      priceIncludesVat: toB(r['price_includes_vat'], fallback: true),
      vatRate: toD(r['vat_rate'], 0.05),
      commissionKind: () {
        final raw =
            (r['marketing_commission_kind'] ?? 'none').toString().trim().toLowerCase();
        return const {'none', 'percent', 'fixed'}.contains(raw) ? raw : 'none';
      }(),
      commissionRate: toD(r['marketing_commission_rate'], 0.025),
      commissionAmount: toD(r['marketing_commission_amount'], 0.0),
      currencyCode: 'SAR',
    );

    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _t('الإجمالي المستحق والفاتورة', 'Total due & invoice'),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
          ),
          const SizedBox(height: 8),
          ListingPricingBreakdown(
            invoice: inv,
            isAr: _isAr,
            showTitle: false,
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text(k, style: TextStyle(color: Colors.grey.shade700))),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }

  Widget _noticeCard({
    required BuildContext context,
    required String text,
    required _NoticeTone tone,
  }) {
    final cs = Theme.of(context).colorScheme;
    final (Color bg, Color fg, IconData icon) = switch (tone) {
      _NoticeTone.success => (
          cs.primaryContainer.withValues(alpha: 0.45),
          cs.onSurface,
          Icons.check_circle_outline,
        ),
      _NoticeTone.info => (
          cs.secondaryContainer.withValues(alpha: 0.45),
          cs.onSurface,
          Icons.info_outline,
        ),
      _NoticeTone.blocked => (
          cs.errorContainer.withValues(alpha: 0.4),
          cs.onSurface,
          Icons.info_outline,
        ),
    };

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: tone == _NoticeTone.blocked
                  ? cs.error
                  : (tone == _NoticeTone.info ? cs.secondary : cs.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _NoticeTone { success, info, blocked }