// lib/screens/marketer_request_details_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/marketing/listing_request_marketing_price.dart';
import '../core/workflow/listing_workflow_copy.dart';
import '../core/workflow/listing_workflow_ui_context.dart';
import '../services/marketing_flow_service.dart';
import '../core/listing/property_listing_display.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/listing_workflow_progress_strip.dart';
import '../widgets/marketing_offer_submit_sheet.dart';

class MarketerRequestDetailsPage extends StatefulWidget {
  final String lang;
  final String inviteId;
  final String requestId;

  const MarketerRequestDetailsPage({
    super.key,
    required this.lang,
    required this.inviteId,
    required this.requestId,
  });

  @override
  State<MarketerRequestDetailsPage> createState() => _MarketerRequestDetailsPageState();
}

class _MarketerRequestDetailsPageState extends State<MarketerRequestDetailsPage> {
  late final MarketingFlowService _svc;

  bool _loading = true;
  String? _err;

  Map<String, dynamic>? _invite;
  Map<String, dynamic>? _request;
  Map<String, dynamic>? _previewProperty;
  Map<String, dynamic>? _contractSnap;
  bool _hasLiveOfferThisRound = false;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  @override
  void initState() {
    super.initState();
    _svc = MarketingFlowService(Supabase.instance.client);
    _load();
  }

  String _t(String ar, String en) => _isAr ? ar : en;

  String _safeText(dynamic v, {String fallback = '-'}) {
    final s = (v == null) ? '' : v.toString().trim();
    return s.isEmpty ? fallback : s;
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
    final wf = (_request?['workflow_stage'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final st = (_request?['status'] ?? '').toString().trim().toLowerCase();
    return wf == 'published' || st == 'published' || st == 'live' || st == 'active';
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
        '${_isAr ? 'عدّل المسودة ثم أعد الإرسال من تبويب «التعاقد» في إدارتي.' : 'Revise the draft, then resend from the «Contracting» tab in My hub.'}';
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
      final rows = await Supabase.instance.client
          .from('properties')
          .select(
            'id,title,city,location,address_line,area,price,created_at,status,'
            'latitude,longitude,property_images(path,file_name,sort_order)',
          )
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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
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

    final inviteStatus = _inviteStatus();
    final distanceKm = _invite?['distance_km'];

    final city = _safeText(_request?['city']);
    final reqStatus = _safeText(_request?['status']);
    final wfCtx = _wfCtx;
    final title = _safeText(_request?['title'], fallback: _t('طلب تسويق', 'Marketing request'));
    final notesOwner = _safeText(
      PropertyListingDisplay.ownerNotesFromListingRequestRow(_request),
      fallback: '',
    );

    // دعم اختلاف اسم الإحداثيات (lat/lng أو latitude/longitude)
    final lat = _request?['lat'] ?? _request?['latitude'];
    final lng = _request?['lng'] ?? _request?['longitude'];

    final bottomPad =
        24.0 + MediaQuery.paddingOf(context).bottom + MediaQuery.viewInsetsOf(context).bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(_t('ملخص', 'Summary')),
          _kv(_t('العنوان', 'Title'), title),
          _kv(_t('المدينة', 'City'), city),
          _kv(_t('حالة الطلب', 'Request status'), reqStatus),
          if (wfCtx != null)
            _kv(
              _t('مرحلة سير العمل', 'Workflow'),
              _isAr ? wfCtx.statusLabelAr : wfCtx.statusLabelEn,
            ),
          _kv(_t('حالة الدعوة', 'Invite status'), inviteStatus),
          if (distanceKm != null) _kv(_t('المسافة', 'Distance'), '${distanceKm.toString()} km'),
          _kv(
            _t('الإحداثيات', 'Coordinates'),
            (lat == null || lng == null) ? _t('غير محددة', 'Not set') : '$lat, $lng',
          ),
          if (_previewProperty != null) ...[
            const SizedBox(height: 12),
            _sectionTitle(_t('تفاصيل العقار', 'Property details')),
            _propertyPreviewCard(_previewProperty!),
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

          const SizedBox(height: 20),
          _sectionTitle(_t('إرسال عرض تسويق', 'Send Marketing Offer')),
          if (_isPublishedLike)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _noticeCard(
                context: context,
                text: _t(
                  'تم نشر الإعلان، لا يمكن تقديم عرض تسويق جديد.',
                  'The listing is published; new marketing offers are disabled.',
                ),
                tone: _NoticeTone.info,
              ),
            )
          else if (!_inviteAllowsOffer)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _noticeCard(
                context: context,
                text: ListingWorkflowCopy.inviteBlocksOffer(_isAr, _inviteStatus()),
                tone: _NoticeTone.blocked,
              ),
            )
          else ...[
            Builder(
              builder: (ctx) {
                final m = ListingWorkflowCopy.marketerSubmitBlockedExplanation(
                  _isAr,
                  hasLiveOfferThisRound: _hasLiveOfferThisRound,
                  ctx: _wfCtx,
                );
                if (m == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _noticeCard(
                    context: ctx,
                    text: m,
                    tone: _hasLiveOfferThisRound
                        ? _NoticeTone.success
                        : _NoticeTone.blocked,
                  ),
                );
              },
            ),
          ],
          if (!_isPublishedLike && _inviteAllowsOffer)
            MarketingOfferSubmitPanel(
              requestId: widget.requestId,
              inviteId:
                  _resolvedInviteId.isEmpty ? null : _resolvedInviteId,
              isAr: _isAr,
              showDragHandle: false,
              propertyBaseSarHint: _propertyBaseSarHint,
              onSuccess: () {
                if (mounted) Navigator.of(context).pop(true);
              },
            ),
          const SizedBox(height: 24),
        ],
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

  Widget _propertyPreviewCard(Map<String, dynamic> p) {
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
            if (imgUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  imgUrl,
                  height: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            if (imgUrl.isNotEmpty) const SizedBox(height: 10),
            _kv(_t('العنوان', 'Title'), title),
            _kv(_t('المدينة', 'City'), city),
            _kv(_t('الموقع', 'Location'), location),
            if (area != null) _kv(_t('المساحة', 'Area'), '${area.toStringAsFixed(0)} ${_t('م²', 'm²')}'),
            if (price != null) _kv(_t('السعر', 'Price'), '${price.toStringAsFixed(0)} SAR'),
            _kv(_t('تاريخ الطرح', 'Listed at'), listedAt),
          ],
        ),
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