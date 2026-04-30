import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/marketing/listing_request_marketing_price.dart';
import '../core/utils/app_money.dart';
import '../core/marketing/marketing_offer_fee.dart';
import '../core/workflow/listing_workflow_copy.dart';
import '../core/workflow/listing_workflow_ui_context.dart';
import '../services/marketing_flow_service.dart';
import '../services/marketing_workflow_hub.dart';
import '../screens/support_page.dart';
import 'app_shimmer.dart';

/// نموذج موحّد: أتعاب التسويق من [MarketingOfferFee] على (قيمة العقار + ضريبة 5٪ على العقار).
/// يُستخدم داخل حوار منبثق أو [SubmitOfferPage].
class MarketingOfferSubmitPanel extends StatefulWidget {
  final String requestId;
  final String? inviteId;
  final bool isAr;

  /// عند true: يُعرض مقبض سحب (للتوافق مع التخطيطات القديمة).
  final bool showDragHandle;

  /// عند الجلب من اللوحة: سعر الأساس المعروض على البطاقة إن لم يُعاد من الطلب في REST.
  final double? propertyBaseSarHint;
  final VoidCallback? onSuccess;

  const MarketingOfferSubmitPanel({
    super.key,
    required this.requestId,
    this.inviteId,
    required this.isAr,
    this.showDragHandle = false,
    this.propertyBaseSarHint,
    this.onSuccess,
  });

  @override
  State<MarketingOfferSubmitPanel> createState() =>
      _MarketingOfferSubmitPanelState();
}

class _MarketingOfferSubmitPanelState extends State<MarketingOfferSubmitPanel> {
  final _notes = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late final MarketingFlowService _svc =
      MarketingFlowService(Supabase.instance.client);

  bool _loading = true;
  bool _submitting = false;
  Map<String, dynamic>? _request;
  Map<String, dynamic>? _linkedProperty;
  bool _hasLiveOffer = false;
  String? _loadError;

  static const Color _brandTeal = Color(0xFF0F766E);

  ListingWorkflowUiContext? get _wfCtx => _request == null
      ? null
      : ListingWorkflowUiContext.fromListingRequest(_request!);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  double get _effectiveBaseSar => _basePropertySar;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final req = _svc.ownerListingRequestSnapshot(widget.requestId);
      final live = _svc.marketerHasLiveOfferForRequestRound(widget.requestId);
      final prop = _svc.linkedPropertyForListingRequest(widget.requestId);
      final results = await Future.wait<Object?>([req, live, prop]);
      if (!mounted) return;
      setState(() {
        _request = results[0] as Map<String, dynamic>?;
        _hasLiveOffer = results[1] as bool;
        _linkedProperty = results[2] as Map<String, dynamic>?;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  double get _basePropertySar {
    final r = _request;
    final fromRow = r == null
        ? 0.0
        : effectivePropertyPriceSarForMarketingFee(r, _linkedProperty);
    if (fromRow > 0) return fromRow;
    final hint = widget.propertyBaseSarHint;
    if (hint != null && hint > 0) return hint;
    return 0;
  }

  String? _coverUrl() {
    final prop = _linkedProperty;
    if (prop == null) return null;
    final imgs = prop['property_images'];
    if (imgs is! List || imgs.isEmpty) return null;
    final rows = imgs.map((e) => Map<String, dynamic>.from(e as Map)).toList()
      ..sort((a, b) {
        final sa = (a['sort_order'] as num?)?.toInt() ?? 0;
        final sb = (b['sort_order'] as num?)?.toInt() ?? 0;
        return sa.compareTo(sb);
      });
    final path =
        (rows.first['path'] ?? rows.first['file_name'] ?? '').toString().trim();
    if (path.isEmpty) return null;
    if (path.startsWith('http')) return path;
    return Supabase.instance.client.storage
        .from('property-images')
        .getPublicUrl(path);
  }

  String? _blockedExplanation() {
    return ListingWorkflowCopy.marketerSubmitBlockedExplanation(
      widget.isAr,
      hasLiveOfferThisRound: _hasLiveOffer,
      ctx: _wfCtx,
    );
  }

  Future<void> _submit() async {
    final block = _blockedExplanation();
    if (block != null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(block)));
      }
      return;
    }

    final base = _effectiveBaseSar;
    if (base <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ListingWorkflowCopy.t(
                widget.isAr,
                'لا يمكن إرسال العرض قبل تحديد قيمة العقار من المالك داخل الطلب.',
                'Offer cannot be submitted until the owner sets the property price in the request.',
              ),
            ),
          ),
        );
      }
      return;
    }

    final total = MarketingOfferFee.totalDue(base);

    setState(() => _submitting = true);
    try {
      await _svc.marketerSubmitOffer(
        requestId: widget.requestId,
        price: total,
        notes: _notes.text.trim(),
      );
      final iid = (widget.inviteId ?? '').trim();
      if (iid.isNotEmpty) {
        try {
          await Supabase.instance.client
              .from('listing_request_invites')
              .update({
            'status': 'seen',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', iid);
        } catch (_) {}
      }
      try {
        await _svc.notifyOwnerNewMarketingOffer(requestId: widget.requestId);
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(ListingWorkflowCopy.snackOfferSubmitted(widget.isAr))),
      );
      MarketingWorkflowHub.notifyBucketsChanged();
      widget.onSuccess?.call();
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('duplicate_offer_same_round')) {
        final iid = (widget.inviteId ?? '').trim();
        if (iid.isNotEmpty) {
          try {
            await Supabase.instance.client
                .from('listing_request_invites')
                .update({
              'status': 'seen',
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            }).eq('id', iid);
          } catch (_) {}
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                ListingWorkflowCopy.t(
                  widget.isAr,
                  'تم إرسال عرضك مسبقًا لهذه الجولة.',
                  'Your offer is already submitted for this round.',
                ),
              ),
            ),
          );
          MarketingWorkflowHub.notifyBucketsChanged();
          widget.onSuccess?.call();
        }
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(ListingWorkflowCopy.rpcFailedFriendly(widget.isAr, e)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _feeRow(
    String label,
    Widget value,
    ColorScheme cs, {
    bool emphasize = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: emphasize ? FontWeight.w900 : FontWeight.w700,
              fontSize: emphasize ? 15 : 13,
              color: cs.onSurface,
            ),
          ),
        ),
        value,
      ],
    );
  }

  Widget _feeAmount(double amount, ColorScheme cs, {bool emphasize = false}) {
    return AppMoneyLine(
      amount: amount,
      currencyCode: 'SAR',
      isAr: widget.isAr,
      style: TextStyle(
        fontWeight: FontWeight.w900,
        fontSize: emphasize ? 16 : 13,
        color: emphasize ? _brandTeal : cs.onSurface,
      ),
    );
  }

  Widget _buildRequestSummary(ColorScheme cs) {
    final r = _request;
    if (r == null) return const SizedBox.shrink();
    final title = (r['title'] ?? '').toString().trim();
    final city = (r['city'] ?? '').toString().trim();
    final locLine = [
      (r['location'] ?? '').toString().trim(),
      (r['address_line'] ?? '').toString().trim(),
      (r['district'] ?? '').toString().trim(),
    ].where((s) => s.isNotEmpty).join(' · ');
    final code =
        (_linkedProperty?['listing_public_code'] ?? '').toString().trim();
    final payload = r['payload_json'] is Map
        ? Map<String, dynamic>.from(r['payload_json'] as Map)
        : r['payload'] is Map
            ? Map<String, dynamic>.from(r['payload'] as Map)
            : const <String, dynamic>{};
    final ownerName = (r['request_owner_full_name'] ??
            r['preview_owner_full_name'] ??
            r['owner_full_name'] ??
            r['request_owner_legal_name'] ??
            r['preview_owner_legal_name'] ??
            r['owner_legal_name'] ??
            r['request_owner_name'] ??
            r['preview_owner_name'] ??
            r['owner_name'] ??
            payload['owner_full_name'] ??
            payload['owner_name'] ??
            payload['full_name'] ??
            '')
        .toString()
        .trim();
    final url = _coverUrl();

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          SizedBox(
            height: 168,
            width: double.infinity,
            child: url != null
                ? CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: _brandTeal.withValues(alpha: 0.12),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.apartment_rounded,
                        size: 36,
                        color: _brandTeal.withValues(alpha: 0.5),
                      ),
                    ),
                  )
                : Container(
                    color: _brandTeal.withValues(alpha: 0.12),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.apartment_rounded,
                      size: 36,
                      color: _brandTeal.withValues(alpha: 0.5),
                    ),
                  ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.05),
                    Colors.black.withValues(alpha: 0.75),
                  ],
                ),
              ),
            ),
          ),
          PositionedDirectional(
            start: 12,
            end: 12,
            bottom: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  code.isNotEmpty
                      ? (widget.isAr
                          ? 'رقم الإعلان: $code'
                          : 'Listing no.: $code')
                      : (widget.isAr ? 'طلب تسويق عقاري' : 'Marketing request'),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (title.isNotEmpty)
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                if (city.isNotEmpty)
                  Text(
                    city,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                if (ownerName.isNotEmpty)
                  Text(
                    widget.isAr
                        ? 'صاحب الإعلان: $ownerName'
                        : 'Advertiser: $ownerName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                if (locLine.isNotEmpty)
                  Text(
                    locLine,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfferFactsStrip(ColorScheme cs) {
    final r = _request;
    if (r == null) return const SizedBox.shrink();
    final lp = _linkedProperty;
    final city = (r['city'] ?? lp?['city'] ?? '').toString().trim();
    final title = (r['title'] ?? lp?['title'] ?? '').toString().trim();
    final loc = [
      (lp?['location'] ?? r['location'] ?? '').toString().trim(),
      (lp?['address_line'] ?? r['address_line'] ?? '').toString().trim(),
      (r['district'] ?? '').toString().trim(),
    ].where((s) => s.isNotEmpty).join(' · ');
    final base = _effectiveBaseSar;

    Widget row(IconData ic, String label, String value) {
      if (value.trim().isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(ic, size: 20, color: _brandTeal),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      height: 1.3,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ListingWorkflowCopy.t(
                widget.isAr,
                'ملخص سريع للعقار',
                'Property snapshot',
              ),
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            if (title.isNotEmpty)
              row(
                Icons.title_outlined,
                ListingWorkflowCopy.t(widget.isAr, 'العنوان', 'Title'),
                title,
              ),
            if (city.isNotEmpty)
              row(
                Icons.location_city_outlined,
                ListingWorkflowCopy.t(widget.isAr, 'المدينة', 'City'),
                city,
              ),
            if (loc.isNotEmpty)
              row(
                Icons.map_outlined,
                ListingWorkflowCopy.t(
                  widget.isAr,
                  'الموقع والعنوان',
                  'Location',
                ),
                loc,
              ),
            if (base > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.payments_outlined,
                        size: 20, color: _brandTeal),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ListingWorkflowCopy.t(
                              widget.isAr,
                              'قيمة العقار (أساس الأتعاب)',
                              'Property value (fee basis)',
                            ),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          AppMoneyLine(
                            amount: base,
                            currencyCode: 'SAR',
                            isAr: widget.isAr,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final wf = _wfCtx;
    final blocked = _blockedExplanation();
    final autoBase = _basePropertySar;
    final base = _effectiveBaseSar;
    final propVat = base > 0 ? MarketingOfferFee.propertyVatAmount(base) : 0.0;
    final subtotal =
        base > 0 ? MarketingOfferFee.propertySubtotalWithVat(base) : 0.0;
    final fee = base > 0 ? MarketingOfferFee.marketingFeeAmount(base) : 0.0;
    final total = base > 0 ? MarketingOfferFee.totalDue(base) : 0.0;
    final feePctLabel =
        MarketingOfferFee.commissionPercentLabel(isAr: widget.isAr);

    Widget body;
    if (_loading) {
      body = const Padding(
        padding: EdgeInsets.fromLTRB(16, 24, 16, 24),
        child: PropertyCardSkeleton(),
      );
    } else if (_loadError != null) {
      body = Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: cs.error),
            const SizedBox(height: 10),
            Text(
              ListingWorkflowCopy.loadFailedTitle(widget.isAr),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            SelectableText(_loadError!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text(ListingWorkflowCopy.btnRetry(widget.isAr)),
            ),
          ],
        ),
      );
    } else {
      body = Form(
        key: _formKey,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.showDragHandle) ...[
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Text(
                  ListingWorkflowCopy.t(
                    widget.isAr,
                    'إرسال عرض تسويق',
                    'Submit marketing offer',
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
              ] else ...[
                const SizedBox(height: 8),
              ],
              if (wf != null) ...[
                Text(
                  widget.isAr ? wf.statusLabelAr : wf.statusLabelEn,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: _brandTeal,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              _buildRequestSummary(cs),
              const SizedBox(height: 14),
              _buildOfferFactsStrip(cs),
              const SizedBox(height: 14),
              if (blocked != null)
                Material(
                  color: _hasLiveOffer
                      ? cs.primaryContainer.withValues(alpha: 0.4)
                      : cs.errorContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _hasLiveOffer
                              ? Icons.check_circle_outline
                              : Icons.info_outline,
                          color: _hasLiveOffer ? cs.primary : cs.error,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            blocked,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (blocked != null && _hasLiveOffer) ...[
                const SizedBox(height: 10),
                Material(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          ListingWorkflowCopy
                              .hintAdminOfferReviewWhenOfferLocked(
                            widget.isAr,
                          ),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                            color: cs.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () {
                            final uid =
                                Supabase.instance.client.auth.currentUser?.id ??
                                    '';
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (ctx) => SupportPage(
                                  userId: uid,
                                  isAr: widget.isAr,
                                  bankColor: Theme.of(ctx).colorScheme.primary,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.support_agent_outlined),
                          label: Text(
                            ListingWorkflowCopy.btnRequestAdminOfferReview(
                              widget.isAr,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (blocked != null) const SizedBox(height: 14),
              if (autoBase <= 0) ...[
                Material(
                  color: cs.errorContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded, color: cs.error),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            ListingWorkflowCopy.t(
                              widget.isAr,
                              'سعر العقار غير مضبوط في الطلب. يجب على المالك تحديد السعر أولاً، ثم يمكنك إرسال العرض تلقائياً.',
                              'Property price is missing on this request. The owner must set it first, then you can submit the offer automatically.',
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (base > 0) ...[
                Text(
                  ListingWorkflowCopy.t(
                    widget.isAr,
                    'أتعاب التسويق (ثابتة)',
                    'Marketing fee (fixed)',
                  ),
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: _brandTeal.withValues(alpha: 0.28)),
                    color: _brandTeal.withValues(alpha: 0.06),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _feeRow(
                        widget.isAr ? 'قيمة العقار (الأساس)' : 'Property value',
                        _feeAmount(base, cs),
                        cs,
                      ),
                      const SizedBox(height: 8),
                      _feeRow(
                        widget.isAr
                            ? 'ضريبة القيمة المضافة 5٪ على قيمة العقار'
                            : '5% VAT on property value',
                        _feeAmount(propVat, cs),
                        cs,
                      ),
                      const SizedBox(height: 8),
                      _feeRow(
                        widget.isAr
                            ? 'المجموع (عقار + الضريبة)'
                            : 'Subtotal (property + VAT)',
                        _feeAmount(subtotal, cs),
                        cs,
                      ),
                      const SizedBox(height: 8),
                      _feeRow(
                        widget.isAr
                            ? 'أتعاب التسويق $feePctLabel من المجموع'
                            : 'Marketing fee $feePctLabel of subtotal',
                        _feeAmount(fee, cs),
                        cs,
                      ),
                      const Divider(height: 22),
                      _feeRow(
                        widget.isAr ? 'الإجمالي المستحق' : 'Total due',
                        _feeAmount(total, cs, emphasize: true),
                        cs,
                        emphasize: true,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        ListingWorkflowCopy.t(
                          widget.isAr,
                          'يُحتسب تلقائياً ويُرسل للمالك بهذا المبلغ — لا يمكن تعديله يدوياً.',
                          'Calculated automatically; the owner sees this exact amount.',
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _notes,
                maxLines: 5,
                readOnly: blocked != null,
                decoration: InputDecoration(
                  labelText: ListingWorkflowCopy.t(
                    widget.isAr,
                    'تفاصيل عرضك على المالك',
                    'Your pitch to the owner',
                  ),
                  hintText: ListingWorkflowCopy.t(
                    widget.isAr,
                    'مثال: خطة تسويق، قنوات العرض (منصّات/زيارات)، مدة الالتزام، أي ملاحظات تساعد المالك على المقارنة.',
                    'e.g. marketing plan, channels (online/visits), commitment window, anything that helps the owner compare offers.',
                  ),
                  helperText: ListingWorkflowCopy.t(
                    widget.isAr,
                    'حقل تعليمي: اكتب باختصار ما يميز عرضك؛ يُرسل للمالك مع المبلغ المحسوب أعلاه.',
                    'Educational: briefly state what makes your offer stand out; it is sent to the owner with the calculated amount.',
                  ),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed:
                    (_submitting || blocked != null || _effectiveBaseSar <= 0)
                        ? null
                        : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: _brandTeal,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        ListingWorkflowCopy.btnSendOffer(widget.isAr),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
              ),
            ],
          ),
        ),
      );
    }

    return Directionality(
      textDirection: widget.isAr ? TextDirection.rtl : TextDirection.ltr,
      child: body,
    );
  }
}

/// حوار منبثق متمركز — مناسب للويب والجوال.
Future<void> showMarketingOfferSubmitSheet(
  BuildContext context, {
  required String requestId,
  String? inviteId,
  required bool isAr,
  Future<void> Function()? onAfterSubmit,
  double? propertyBaseSarHint,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final mq = MediaQuery.of(ctx);
      final w = mq.size.width;
      final h = mq.size.height;
      final viewInsets = MediaQuery.viewInsetsOf(ctx);
      final padding = MediaQuery.paddingOf(ctx);
      // مساحة فعلية مع لوحة المفاتيح (جوال/ويب) حتى لا يُقصّ زر الإرسال.
      final availableH =
          (h - viewInsets.vertical - padding.vertical).clamp(240.0, 2000.0);
      final sidePad = w < 400 ? 10.0 : 20.0;
      final maxW = math.min(560.0, w - sidePad * 2);
      final maxH = math.min(availableH * 0.94, 820.0);
      return Dialog(
        insetPadding: EdgeInsets.fromLTRB(
          sidePad,
          10,
          sidePad,
          10 + viewInsets.bottom,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: maxW,
          height: maxH,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: Theme.of(ctx)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.4),
                child: SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          ListingWorkflowCopy.t(
                            isAr,
                            'تقديم عرض تسويق',
                            'Submit marketing offer',
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                          textAlign: isAr ? TextAlign.right : TextAlign.left,
                        ),
                      ),
                      IconButton(
                        tooltip: ListingWorkflowCopy.t(isAr, 'إغلاق', 'Close'),
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: MarketingOfferSubmitPanel(
                  requestId: requestId,
                  inviteId: inviteId,
                  isAr: isAr,
                  showDragHandle: false,
                  propertyBaseSarHint: propertyBaseSarHint,
                  onSuccess: () {
                    Navigator.of(ctx).pop();
                    onAfterSubmit?.call();
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
