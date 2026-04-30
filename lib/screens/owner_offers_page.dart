import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/marketing/listing_request_marketing_price.dart';
import '../core/utils/app_money.dart';
import '../core/utils/chat_display_initials.dart';
import '../core/marketing/marketing_offer_fee.dart';
import '../core/workflow/listing_workflow_copy.dart';
import '../core/workflow/listing_workflow_ui_context.dart';
import '../services/chat_peer_service.dart';
import '../services/marketing_flow_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/listing_workflow_progress_strip.dart';

/// مراجعة عروض المسوقين وقبول عرض واحد عبر `accept_listing_offer`.
class OwnerOffersPage extends StatefulWidget {
  final String requestId;
  final String lang;

  const OwnerOffersPage({
    super.key,
    required this.requestId,
    this.lang = 'ar',
  });

  @override
  State<OwnerOffersPage> createState() => _OwnerOffersPageState();
}

class _OwnerOffersPageState extends State<OwnerOffersPage> {
  final _svc = MarketingFlowService(Supabase.instance.client);

  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  Map<String, dynamic>? _request;
  Map<String, dynamic>? _linkedProperty;
  List<Map<String, dynamic>> _offers = const [];
  Map<String, ({double avg, int count})> _ratingByMarketerId = const {};
  String? _busyOfferId;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  @override
  void initState() {
    super.initState();
    _reload(initial: true);
  }

  Future<void> _reload({bool initial = false}) async {
    if (initial) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() {
        _refreshing = true;
        _error = null;
      });
    }
    try {
      final req = await _svc.ownerListingRequestSnapshot(widget.requestId);
      final list = await _svc.ownerOffersEnriched(
        widget.requestId,
        preferArabicNames: _isAr,
      );
      final prop = await _svc.linkedPropertyForListingRequest(widget.requestId);

      final mids = list
          .map((e) => (e['marketer_id'] ?? '').toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      final ratings = mids.isEmpty
          ? const <String, ({double avg, int count})>{}
          : await ChatPeerService.fetchRatingSummariesForUserIds(
              Supabase.instance.client,
              mids,
            );

      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid != null && req != null) {
        final ownerId = (req['owner_id'] ?? '').toString().trim();
        if (ownerId.isNotEmpty && ownerId == uid) {
          unawaited(_svc.recordOwnerViewedListingOffers(widget.requestId));
        }
      }

      if (!mounted) return;
      setState(() {
        _request = req;
        _linkedProperty = prop;
        _offers = list;
        _ratingByMarketerId = ratings;
        _loading = false;
        _refreshing = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      final hadData = _offers.isNotEmpty || _request != null;
      setState(() {
        _loading = false;
        _refreshing = false;
        if (!hadData) {
          _error = e.toString();
        }
      });
      if (hadData && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(ListingWorkflowCopy.rpcFailedFriendly(_isAr, e))),
        );
      }
    }
  }

  ListingWorkflowUiContext? get _ctx => _request == null
      ? null
      : ListingWorkflowUiContext.fromListingRequest(_request!);

  String get _selectedOfferId =>
      (_request?['selected_offer_id'] ?? '').toString().trim();

  /// يمنع قبول عرض آخر إذا كان النظام قد ثبّت عرضًا (حتى قبل اكتمال التحديث).
  bool _anotherOfferWasSelected(String thisOfferId) {
    final sel = _selectedOfferId;
    if (sel.isEmpty) return false;
    return sel != thisOfferId;
  }

  bool _canOwnerDecide(Map<String, dynamic> o) {
    if (_requestBannedUnderReview) return false;
    final st = (o['status'] ?? '').toString().toLowerCase();
    return const {'submitted', 'pending', ''}.contains(st);
  }

  /// المصدر الأساسي: `listing_requests.selected_offer_id`؛ ثم حالات الـ enum الفائزة.
  bool _isAcceptedWinner(Map<String, dynamic> o) {
    final id = (o['id'] ?? '').toString();
    final st = (o['status'] ?? '').toString().toLowerCase();
    final sel = _selectedOfferId;
    if (sel.isNotEmpty && id == sel) return true;
    return st == 'owner_accepted' || st == 'selected';
  }

  bool _canTapAccept(Map<String, dynamic> o) {
    final id = (o['id'] ?? '').toString();
    if (!_canOwnerDecide(o)) return false;
    if (_anotherOfferWasSelected(id)) return false;
    return true;
  }

  int get _distinctMarketerDeclines {
    final r = _request;
    if (r == null) return 0;
    final v = r['owner_distinct_marketer_declines'];
    if (v is num) return v.toInt().clamp(0, 99);
    return int.tryParse('$v') ?? 0;
  }

  bool get _requestBannedUnderReview {
    final r = _request;
    if (r == null) return false;
    final b = r['banned_under_review'];
    if (b == true) return true;
    if ('$b'.toLowerCase() == 'true') return true;
    return _distinctMarketerDeclines >= 3;
  }

  Widget _buildDeclineCapBanner(ColorScheme cs) {
    if (_request == null) return const SizedBox.shrink();
    if (_distinctMarketerDeclines >= 3 || _requestBannedUnderReview) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: cs.errorContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.block, color: cs.error, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    ListingWorkflowCopy.ownerOfferDeclineLimitReached(_isAr),
                    style: TextStyle(
                      color: cs.onErrorContainer,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_distinctMarketerDeclines > 0) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: cs.secondaryContainer.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: cs.secondary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    ListingWorkflowCopy.ownerOfferDeclineCounter(
                      _isAr,
                      _distinctMarketerDeclines,
                      3,
                    ),
                    style: TextStyle(
                      color: cs.onSecondaryContainer,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  /// بعد [accept_listing_offer]: مرحلة `marketer_selected` ولا يوجد `contract_id` بعد.
  bool _canStartContractForOffer(Map<String, dynamic> o) {
    if (!_isAcceptedWinner(o)) return false;
    final wf =
        (_request?['workflow_stage'] ?? '').toString().toLowerCase().trim();
    if (wf != 'marketer_selected') return false;
    final cid = (_request?['contract_id'] ?? '').toString().trim();
    return cid.isEmpty;
  }

  Future<void> _startContract(Map<String, dynamic> o) async {
    final id = (o['id'] ?? '').toString();
    if (id.isEmpty || !_canStartContractForOffer(o)) return;

    setState(() => _busyOfferId = id);
    try {
      await _svc.createListingContractFromOffer(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(ListingWorkflowCopy.snackContractFromOfferCreated(_isAr)),
        ),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(ListingWorkflowCopy.rpcFailedFriendly(_isAr, e))),
      );
    } finally {
      if (mounted) setState(() => _busyOfferId = null);
    }
  }

  Future<void> _accept(Map<String, dynamic> o) async {
    final id = (o['id'] ?? '').toString();
    if (id.isEmpty || !_canTapAccept(o)) return;

    setState(() => _busyOfferId = id);
    try {
      await _svc.acceptListingOfferById(id);
      try {
        await _svc.createListingContractFromOffer(id);
      } catch (_) {
        // Some backends may create the draft contract as part of acceptance.
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ListingWorkflowCopy.snackOfferAccepted(_isAr))),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(ListingWorkflowCopy.rpcFailedFriendly(_isAr, e))),
      );
    } finally {
      if (mounted) setState(() => _busyOfferId = null);
    }
  }

  Future<void> _decline(Map<String, dynamic> o) async {
    final id = (o['id'] ?? '').toString();
    if (id.isEmpty) return;

    final reasonCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ListingWorkflowCopy.t(_isAr, 'رفض العرض', 'Decline offer')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                ListingWorkflowCopy.t(
                  _isAr,
                  'لن يُعتمد هذا العرض. يمكنك توضيح السبب للمسوّق (اختياري).',
                  'This offer will be declined. You may add a reason for the marketer (optional).',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtl,
                maxLines: 3,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: ListingWorkflowCopy.t(
                    _isAr,
                    'سبب الرفض (اختياري)',
                    'Reason (optional)',
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ListingWorkflowCopy.t(_isAr, 'إلغاء', 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ListingWorkflowCopy.t(_isAr, 'رفض', 'Decline')),
          ),
        ],
      ),
    );
    final reasonText = reasonCtl.text.trim();
    reasonCtl.dispose();
    if (ok != true || !mounted) return;

    setState(() => _busyOfferId = id);
    try {
      await _svc.ownerDeclineOffer(
        offerId: id,
        requestId: widget.requestId,
        ownerReason: reasonText.isEmpty ? null : reasonText,
        declineKind: 'reject',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ListingWorkflowCopy.snackOfferDeclined(_isAr))),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(ListingWorkflowCopy.rpcFailedFriendly(_isAr, e))),
      );
    } finally {
      if (mounted) setState(() => _busyOfferId = null);
    }
  }

  /// اعتذار للمسوّق: لا يُحسب ضمن حدّ 3 رفض؛ يُبلّغ بلهجة أخف (بعد ترحيل SQL).
  Future<void> _apology(Map<String, dynamic> o) async {
    final id = (o['id'] ?? '').toString();
    if (id.isEmpty) return;

    final reasonCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ListingWorkflowCopy.t(
            _isAr, 'اعتذار عن العرض', 'Apologize to marketer')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                ListingWorkflowCopy.t(
                  _isAr,
                  'يُسجَّل كاعتذار وليس كرفض ضمن حدّ المسوّقين. يمكنك شرح السبب (اختياري).',
                  'Recorded as an apology, not counted toward the marketer decline cap. Optional reason.',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtl,
                maxLines: 3,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: ListingWorkflowCopy.t(
                    _isAr,
                    'سبب الاعتذار (اختياري)',
                    'Apology note (optional)',
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ListingWorkflowCopy.t(_isAr, 'إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
                ListingWorkflowCopy.t(_isAr, 'إرسال الاعتذار', 'Send apology')),
          ),
        ],
      ),
    );
    final reasonText = reasonCtl.text.trim();
    reasonCtl.dispose();
    if (ok != true || !mounted) return;

    setState(() => _busyOfferId = id);
    try {
      await _svc.ownerDeclineOffer(
        offerId: id,
        requestId: widget.requestId,
        ownerReason: reasonText.isEmpty ? null : reasonText,
        declineKind: 'apology',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ListingWorkflowCopy.t(
              _isAr,
              'تم تسجيل الاعتذار وإشعار المسوّق.',
              'Apology recorded; marketer notified.',
            ),
          ),
        ),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(ListingWorkflowCopy.rpcFailedFriendly(_isAr, e))),
      );
    } finally {
      if (mounted) setState(() => _busyOfferId = null);
    }
  }

  String? _fmtDt(dynamic v) {
    if (v == null) return null;
    final dt = DateTime.tryParse(v.toString());
    if (dt == null) return null;
    final loc = _isAr ? 'ar_SA' : 'en_US';
    try {
      return DateFormat.yMMMd(loc).add_Hm().format(dt.toLocal());
    } catch (_) {
      return DateFormat('yyyy-MM-dd HH:mm').format(dt.toLocal());
    }
  }

  String? _fmtDateOnly(dynamic v) {
    if (v == null) return null;
    final dt = DateTime.tryParse(v.toString());
    if (dt == null) return null;
    final loc = _isAr ? 'ar_SA' : 'en_US';
    try {
      return DateFormat.yMMMd(loc).format(dt.toLocal());
    } catch (_) {
      return DateFormat('yyyy-MM-dd').format(dt.toLocal());
    }
  }

  String? _fmtTimeOnly(dynamic v) {
    if (v == null) return null;
    final dt = DateTime.tryParse(v.toString());
    if (dt == null) return null;
    try {
      return DateFormat.Hm().format(dt.toLocal());
    } catch (_) {
      return DateFormat('HH:mm').format(dt.toLocal());
    }
  }

  Widget _detailRow(ColorScheme cs, String label, String value,
      {IconData? icon}) {
    final v = value.trim();
    if (v.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: cs.primary),
            const SizedBox(width: 6),
          ],
          SizedBox(
            width: 112,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              v,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const Color _brandTeal = Color(0xFF0F766E);

  double get _propertyBasePriceSar {
    final r = _request;
    if (r == null) return 0;
    return effectivePropertyPriceSarForMarketingFee(r, _linkedProperty);
  }

  String _listingReferenceLine() {
    final code =
        (_linkedProperty?['listing_public_code'] ?? '').toString().trim();
    if (code.isNotEmpty) {
      return _isAr ? 'رقم الإعلان: $code' : 'Listing no.: $code';
    }
    return _isAr
        ? 'طلب تسويق عقاري — يُنشأ رقم الإعلان عند النشر'
        : 'Marketing request — listing number is assigned at publish';
  }

  List<String> _propertyImageUrls() {
    final prop = _linkedProperty;
    if (prop == null) return const [];
    final imgs = prop['property_images'];
    if (imgs is! List || imgs.isEmpty) return const [];
    final rows = imgs.map((e) => Map<String, dynamic>.from(e as Map)).toList()
      ..sort((a, b) {
        final sa = (a['sort_order'] as num?)?.toInt() ?? 0;
        final sb = (b['sort_order'] as num?)?.toInt() ?? 0;
        return sa.compareTo(sb);
      });
    return rows
        .map((row) => (row['path'] ?? row['file_name'] ?? '').toString().trim())
        .where((path) => path.isNotEmpty)
        .map((path) {
          if (path.startsWith('http')) return path;
          return Supabase.instance.client.storage
              .from('property-images')
              .getPublicUrl(path);
        })
        .where((url) => url.trim().isNotEmpty)
        .toList(growable: false);
  }

  String? _heroImageUrl() {
    final urls = _propertyImageUrls();
    return urls.isEmpty ? null : urls.first;
  }

  String _fmtMoney(num n) {
    final f = NumberFormat('#,##0', _isAr ? 'ar' : 'en');
    return f.format(n);
  }

  String _accountTypeHuman(Map<String, dynamic> o) {
    final mt = (o['marketer_type'] ?? '').toString().trim();
    if (mt.isNotEmpty) return mt;
    final at =
        (o['_marketer_account_type'] ?? '').toString().trim().toLowerCase();
    if (_isAr) {
      switch (at) {
        case 'marketer':
        case 'mediator':
          return 'مسوّق عقاري فرد';
        case 'office':
          return 'مكتب عقاري';
        case 'company':
        case 'establishment':
          return 'شركة / مؤسسة عقارية';
        case 'org':
        case 'organization':
          return 'جهة عقارية';
        default:
          if (at.isNotEmpty) return at;
          return 'مسوّق عقاري';
      }
    }
    switch (at) {
      case 'marketer':
      case 'mediator':
        return 'Individual marketer';
      case 'office':
        return 'Real estate office';
      case 'company':
      case 'establishment':
        return 'Company / establishment';
      case 'org':
      case 'organization':
        return 'Real estate organization';
      default:
        if (at.isNotEmpty) return at;
        return 'Marketer';
    }
  }

  String _amountLine(Map<String, dynamic> o) {
    final base = _propertyBasePriceSar;
    final price = o['offer_amount'] ?? o['price'];
    if (base > 0) {
      final expected = MarketingOfferFee.totalDue(base);
      final pct = MarketingOfferFee.commissionPercentLabel(isAr: _isAr);
      final sub = _isAr
          ? '($pct من مجموع قيمة العقار + ضريبة 5٪ على العقار)'
          : '($pct of property value including 5% VAT on property)';
      return _isAr
          ? 'قيمة التسويق: ${_fmtMoney(expected)} ${AppMoney.saudiRiyalSignUnicode} • $sub'
          : 'Marketing fee: ${_fmtMoney(expected)} SAR • $sub';
    }
    final ct = (o['commission_type'] ?? '').toString().trim();
    final cv = o['commission_value'];
    if (ct.isNotEmpty && cv != null) {
      return ListingWorkflowCopy.t(
        _isAr,
        'العمولة: $cv ($ct)',
        'Commission: $cv ($ct)',
      );
    }
    return ListingWorkflowCopy.t(
      _isAr,
      'قيمة العرض: $price ${AppMoney.saudiRiyalSignUnicode}',
      'Offer: $price SAR',
    );
  }

  Widget _buildPropertyHero(ColorScheme cs) {
    final req = _request;
    if (req == null) return const SizedBox.shrink();

    final title = (req['title'] ?? '').toString().trim();
    final city = (req['city'] ?? '').toString().trim();
    final loc = (req['location'] ?? _linkedProperty?['location'] ?? '')
        .toString()
        .trim();
    final price = _propertyBasePriceSar;
    final url = _heroImageUrl();

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 12),
            child: child,
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              height: 210,
              width: double.infinity,
              child: url != null
                  ? CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: _brandTeal.withValues(alpha: 0.12),
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: _brandTeal.withValues(alpha: 0.12),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.apartment_rounded,
                          size: 56,
                          color: _brandTeal.withValues(alpha: 0.65),
                        ),
                      ),
                    )
                  : Container(
                      color: _brandTeal.withValues(alpha: 0.14),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.apartment_rounded,
                        size: 64,
                        color: _brandTeal.withValues(alpha: 0.55),
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
                      Colors.black.withValues(alpha: 0.72),
                    ],
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              start: 16,
              end: 16,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _listingReferenceLine(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                  if (title.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                  ],
                  if (city.isNotEmpty || loc.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            loc.isNotEmpty ? loc : city,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (price > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      _isAr
                          ? 'قيمة العقار: ${_fmtMoney(price)} ${AppMoney.saudiRiyalSignUnicode}'
                          : 'Property: ${_fmtMoney(price)} SAR',
                      style: TextStyle(
                        color: Colors.amber.shade100,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 56, color: cs.outline),
          const SizedBox(height: 16),
          Text(
            ListingWorkflowCopy.ownerOffersEmptyTitle(_isAr),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 17,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            ListingWorkflowCopy.ownerOffersEmptyBody(_isAr),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_outlined, size: 52, color: cs.error),
          const SizedBox(height: 16),
          Text(
            ListingWorkflowCopy.loadFailedTitle(_isAr),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 17,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            _error ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.error, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            ListingWorkflowCopy.loadFailedBody(_isAr),
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.3),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () =>
                _reload(initial: _offers.isEmpty && _request == null),
            icon: const Icon(Icons.refresh),
            label: Text(ListingWorkflowCopy.btnRetry(_isAr)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ctxModel = _ctx;

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(ListingWorkflowCopy.ownerOffersTitle(_isAr)),
          actions: [
            if (Navigator.of(context).canPop())
              IconButton(
                tooltip: ListingWorkflowCopy.btnDoneReview(_isAr),
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.check_circle_outline),
              ),
            IconButton(
              onPressed: (_loading || _refreshing) ? null : () => _reload(),
              icon: const Icon(Icons.refresh),
              tooltip: ListingWorkflowCopy.btnRefresh(_isAr),
            ),
          ],
        ),
        body: _loading && _offers.isEmpty && _request == null
            ? const Center(child: AppLogoLoading())
            : _error != null && _offers.isEmpty && _request == null
                ? _buildErrorState(cs)
                : Stack(
                    children: [
                      RefreshIndicator(
                        onRefresh: () => _reload(),
                        child: CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                              sliver: SliverList(
                                delegate: SliverChildListDelegate([
                                  if (ctxModel != null) ...[
                                    Text(
                                      _isAr
                                          ? ctxModel.statusLabelAr
                                          : ctxModel.statusLabelEn,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 17,
                                        color: _brandTeal,
                                      ),
                                    ),
                                    ListingWorkflowProgressStrip(
                                      stage: ctxModel.stage,
                                      compact: true,
                                      dense: true,
                                      deadline: ctxModel.primaryDeadline,
                                    ),
                                    const SizedBox(height: 12),
                                    _buildDeclineCapBanner(cs),
                                    const SizedBox(height: 4),
                                  ],
                                  _buildPropertyHero(cs),
                                  const SizedBox(height: 16),
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 280),
                                    curve: Curves.easeOutCubic,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: cs.surfaceContainerHighest
                                          .withValues(alpha: 0.45),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color:
                                            _brandTeal.withValues(alpha: 0.22),
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(
                                          Icons.info_outline_rounded,
                                          color: _brandTeal,
                                          size: 22,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            ListingWorkflowCopy
                                                .ownerOffersIntro(_isAr),
                                            style: TextStyle(
                                              color: cs.onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                              height: 1.4,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    _isAr
                                        ? 'عروض التسويق العقاري'
                                        : 'Marketing offers',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _isAr
                                        ? 'قارِن الجهات واختَر مسوّقاً واحداً فقط للمتابعة.'
                                        : 'Compare marketers and select one to proceed.',
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ]),
                              ),
                            ),
                            if (_offers.isEmpty)
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: _buildEmptyState(cs),
                              )
                            else
                              SliverPadding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 28),
                                sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, i) =>
                                        _buildOfferCard(_offers[i], cs),
                                    childCount: _offers.length,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_refreshing && _offers.isNotEmpty)
                        const Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                    ],
                  ),
      ),
    );
  }

  void _openOfferDetails(Map<String, dynamic> o) {
    final mid = (o['marketer_id'] ?? '').toString().trim();
    final rating = mid.isEmpty ? null : _ratingByMarketerId[mid];
    final name = (o['_marketer_display_name'] ?? '').toString().trim();
    final phone = (o['_marketer_phone'] ?? '').toString().trim();
    final license = (o['_marketer_license_no'] ?? '').toString().trim();
    final notes = (o['notes'] ?? '').toString().trim();
    final declineReason = (o['owner_decline_reason'] ?? '').toString().trim();
    final declineKindModal = (o['decline_kind'] ?? 'reject').toString().trim();
    final statusRaw = (o['status'] ?? '').toString();
    final id = (o['id'] ?? '').toString();
    final busy = _busyOfferId == id;
    final canAccept = _canTapAccept(o);
    final canDecline = _canOwnerDecide(o) && !_anotherOfferWasSelected(id);
    final propertyImages = _propertyImageUrls();
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final apology = declineKindModal == 'apology';
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    ListingWorkflowCopy.t(
                      _isAr,
                      'تفاصيل العرض والمسوّق',
                      'Offer & marketer details',
                    ),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (propertyImages.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: CachedNetworkImage(
                          imageUrl: propertyImages.first,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: _brandTeal.withValues(alpha: 0.12),
                            alignment: Alignment.center,
                            child: const SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: _brandTeal.withValues(alpha: 0.12),
                            alignment: Alignment.center,
                            child:
                                const Icon(Icons.apartment_rounded, size: 48),
                          ),
                        ),
                      ),
                    ),
                    if (propertyImages.length > 1) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 78,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: propertyImages.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) => ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: AspectRatio(
                              aspectRatio: 1.25,
                              child: CachedNetworkImage(
                                imageUrl: propertyImages[i],
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                  ],
                  if (rating != null && rating.count > 0) ...[
                    Row(
                      children: [
                        Icon(Icons.star_rounded,
                            color: Colors.amber.shade700, size: 26),
                        const SizedBox(width: 6),
                        Text(
                          ListingWorkflowCopy.t(
                            _isAr,
                            '${rating.avg.toStringAsFixed(1)} من 5 • ${rating.count} تقييم',
                            '${rating.avg.toStringAsFixed(1)} / 5 • ${rating.count} ratings',
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    name.isNotEmpty
                        ? name
                        : ListingWorkflowCopy.t(
                            _isAr,
                            'شريكنا المسوّق العقاري',
                            'Our real-estate partner',
                          ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    ListingWorkflowCopy.t(
                      _isAr,
                      'نوع الجهة: ${_accountTypeHuman(o)}',
                      'Entity: ${_accountTypeHuman(o)}',
                    ),
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (license.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      ListingWorkflowCopy.t(
                        _isAr,
                        'رقم الترخيص: $license',
                        'License no.: $license',
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                  if (phone.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      phone,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    _amountLine(o),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ListingWorkflowCopy.offerStatusLong(_isAr, statusRaw),
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      ListingWorkflowCopy.t(
                        _isAr,
                        'تفاصيل إضافية من المسوّق',
                        'Additional details from marketer',
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(notes, style: const TextStyle(height: 1.35)),
                  ],
                  if (declineReason.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Material(
                      color: apology
                          ? cs.primaryContainer.withValues(alpha: 0.45)
                          : cs.errorContainer.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ListingWorkflowCopy.t(
                                _isAr,
                                apology
                                    ? 'ملاحظة الاعتذار (للمسوّق)'
                                    : 'سبب الرفض (للمسوّق)',
                                apology
                                    ? 'Apology note (shared with marketer)'
                                    : 'Decline reason (shared with marketer)',
                              ),
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: apology ? cs.primary : cs.error,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(declineReason),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (canAccept || canDecline) ...[
                    if (canAccept)
                      FilledButton.icon(
                        onPressed: (_loading || _refreshing || busy)
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                _accept(o);
                              },
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(
                          ListingWorkflowCopy.btnAcceptOffer(_isAr),
                        ),
                      ),
                    if (canAccept && canDecline) const SizedBox(height: 10),
                    if (canDecline)
                      OutlinedButton.icon(
                        onPressed: (_loading || _refreshing || busy)
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                _decline(o);
                              },
                        icon: const Icon(Icons.cancel_outlined),
                        label: Text(
                          ListingWorkflowCopy.btnDeclineOffer(_isAr),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cs.error,
                          side: BorderSide(
                            color: cs.error.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                  ],
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(ListingWorkflowCopy.t(_isAr, 'إغلاق', 'Close')),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOfferCard(Map<String, dynamic> o, ColorScheme cs) {
    final id = (o['id'] ?? '').toString();
    final name = (o['_marketer_display_name'] ?? '').toString().trim();
    final busy = _busyOfferId == id;
    final statusRaw = (o['status'] ?? '').toString();
    final winner = _isAcceptedWinner(o);
    final canAccept = _canTapAccept(o);
    final canDecline = _canOwnerDecide(o) && !_anotherOfferWasSelected(id);
    final notes = (o['notes'] ?? '').toString().trim();
    final shortStatus = ListingWorkflowCopy.offerStatusShort(_isAr, statusRaw);
    final longStatus = ListingWorkflowCopy.offerStatusLong(_isAr, statusRaw);
    final mid = (o['marketer_id'] ?? '').toString().trim();
    final rating = mid.isEmpty ? null : _ratingByMarketerId[mid];
    final declineReason = (o['owner_decline_reason'] ?? '').toString().trim();
    final declineKind = (o['decline_kind'] ?? 'reject').toString().trim();

    final borderColor =
        winner ? _brandTeal : cs.outlineVariant.withValues(alpha: 0.45);

    final avatarUrl = (o['_marketer_avatar_url'] ?? '').toString().trim();
    final phone = (o['_marketer_phone'] ?? '').toString().trim();
    final license = (o['_marketer_license_no'] ?? '').toString().trim();
    final exp =
        DateTime.tryParse((o['expires_at'] ?? '').toString())?.toLocal();

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: winner ? 3 : 0.8,
      shadowColor: _brandTeal.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: borderColor, width: winner ? 2.2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (winner) ...[
              Material(
                color: _brandTeal.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.verified_rounded, color: cs.primary, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          ListingWorkflowCopy.ownerSelectedMarketerBadge(_isAr),
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: cs.primary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_canStartContractForOffer(o)) ...[
              FilledButton(
                onPressed: (_loading || _refreshing || busy)
                    ? null
                    : () => _startContract(o),
                style: FilledButton.styleFrom(
                  backgroundColor: cs.primaryContainer.withValues(alpha: 0.85),
                  foregroundColor: cs.onPrimaryContainer,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: busy
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.onPrimaryContainer,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.description_outlined),
                          const SizedBox(width: 8),
                          Text(ListingWorkflowCopy.btnStartContract(_isAr)),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: _brandTeal.withValues(alpha: 0.18),
                  backgroundImage: avatarUrl.isNotEmpty
                      ? CachedNetworkImageProvider(avatarUrl)
                      : null,
                  child: avatarUrl.isEmpty
                      ? Text(
                          chatAvatarInitialLetter(
                            name.isNotEmpty ? name : (_isAr ? 'م' : 'P'),
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                            color: _brandTeal,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isNotEmpty
                            ? name
                            : ListingWorkflowCopy.t(
                                _isAr,
                                'مسوّق عقاري',
                                'Marketer',
                              ),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ListingWorkflowCopy.t(
                          _isAr,
                          'نوع الجهة: ${_accountTypeHuman(o)}',
                          'Entity: ${_accountTypeHuman(o)}',
                        ),
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.phone_outlined,
                              size: 15,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: SelectableText(
                                phone,
                                style: TextStyle(
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (license.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.verified_user_outlined,
                              size: 15,
                              color: cs.primary,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: SelectableText(
                                ListingWorkflowCopy.t(
                                  _isAr,
                                  'ترخيص: $license',
                                  'License: $license',
                                ),
                                style: TextStyle(
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Chip(
                  label: Text(
                    _isAr
                        ? 'شريكنا المهتم: $shortStatus'
                        : 'Interested partner: $shortStatus',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: _isAr ? Alignment.centerRight : Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _openOfferDetails(o),
                icon: const Icon(Icons.open_in_full_rounded, size: 18),
                label: Text(
                  ListingWorkflowCopy.t(
                    _isAr,
                    'تفاصيل العرض',
                    'Offer details',
                  ),
                ),
              ),
            ),
            if (rating != null && rating.count > 0) ...[
              Row(
                children: [
                  Icon(Icons.star_rounded,
                      color: Colors.amber.shade700, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    ListingWorkflowCopy.t(
                      _isAr,
                      '${rating.avg.toStringAsFixed(1)} • ${rating.count} تقييم',
                      '${rating.avg.toStringAsFixed(1)} • ${rating.count} ratings',
                    ),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.38),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.42),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _detailRow(
                      cs,
                      _isAr ? 'حالة الشريك' : 'Partner status',
                      longStatus,
                      icon: Icons.verified_outlined,
                    ),
                    _detailRow(
                      cs,
                      _isAr ? 'قيمة العرض' : 'Offer amount',
                      _amountLine(o),
                      icon: Icons.payments_outlined,
                    ),
                    _detailRow(
                      cs,
                      _isAr ? 'تاريخ التقديم' : 'Submitted date',
                      _fmtDateOnly(o['created_at']) ?? '—',
                      icon: Icons.calendar_today_outlined,
                    ),
                    _detailRow(
                      cs,
                      _isAr ? 'وقت التقديم' : 'Submitted time',
                      _fmtTimeOnly(o['created_at']) ?? '—',
                      icon: Icons.schedule_outlined,
                    ),
                  ],
                ),
              ),
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                notes,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
            if (declineReason.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                ListingWorkflowCopy.t(
                  _isAr,
                  declineKind == 'apology'
                      ? 'سبب الاعتذار: $declineReason'
                      : 'سبب الرفض: $declineReason',
                  declineKind == 'apology'
                      ? 'Apology note: $declineReason'
                      : 'Decline reason: $declineReason',
                ),
                style: TextStyle(
                  color: declineKind == 'apology' ? cs.primary : cs.error,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ],
            if (exp != null) ...[
              const SizedBox(height: 4),
              Text(
                ListingWorkflowCopy.t(
                  _isAr,
                  'آخر موعد للرد: ${_fmtDt(o['expires_at'])}',
                  'Respond by: ${_fmtDt(o['expires_at'])}',
                ),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.orange.shade900,
                ),
              ),
              _OfferExpiryCountdown(expiresAt: exp, isAr: _isAr),
            ],
            if (!canAccept &&
                _canOwnerDecide(o) &&
                _anotherOfferWasSelected(id)) ...[
              const SizedBox(height: 10),
              Text(
                ListingWorkflowCopy.t(
                  _isAr,
                  'تم تثبيت عرض آخر — لا يمكن قبول هذا العرض.',
                  'Another offer was selected — this offer cannot be accepted.',
                ),
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
            if (canAccept || canDecline) ...[
              const SizedBox(height: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (canAccept)
                    FilledButton(
                      onPressed: (_loading || _refreshing || busy)
                          ? null
                          : () => _accept(o),
                      style: FilledButton.styleFrom(
                        backgroundColor: _brandTeal,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: busy
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.onPrimary,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle_outline,
                                    size: 22),
                                const SizedBox(width: 8),
                                Text(
                                  ListingWorkflowCopy.btnAcceptOffer(_isAr),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  if (canAccept && canDecline) const SizedBox(height: 10),
                  if (canDecline) ...[
                    OutlinedButton.icon(
                      onPressed: (_loading || _refreshing || busy)
                          ? null
                          : () => _apology(o),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.primary,
                        side: BorderSide(
                          color: cs.primary.withValues(alpha: 0.45),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: Icon(
                        Icons.front_hand_outlined,
                        size: 22,
                        color: cs.primary,
                      ),
                      label: Text(
                        ListingWorkflowCopy.t(
                          _isAr,
                          'اعتذار للمسوّق',
                          'Apologize to marketer',
                        ),
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14.5,
                          color: cs.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: (_loading || _refreshing || busy)
                          ? null
                          : () => _decline(o),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.error,
                        side: BorderSide(
                          color: cs.error.withValues(alpha: 0.55),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: Icon(
                        Icons.cancel_outlined,
                        size: 22,
                        color: cs.error,
                      ),
                      label: Text(
                        ListingWorkflowCopy.btnDeclineOffer(_isAr),
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14.5,
                          color: cs.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OfferExpiryCountdown extends StatefulWidget {
  final DateTime expiresAt;
  final bool isAr;

  const _OfferExpiryCountdown({
    required this.expiresAt,
    required this.isAr,
  });

  @override
  State<_OfferExpiryCountdown> createState() => _OfferExpiryCountdownState();
}

class _OfferExpiryCountdownState extends State<_OfferExpiryCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final exp = widget.expiresAt;
    final cs = Theme.of(context).colorScheme;
    if (!exp.isAfter(now)) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          widget.isAr
              ? 'انتهى الوقت المحدد لهذا العرض.'
              : 'The response window for this offer has ended.',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12,
            color: cs.error,
          ),
        ),
      );
    }

    final d = exp.difference(now);
    final days = d.inDays;
    final h = d.inHours.remainder(24);
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);

    final parts = widget.isAr
        ? [
            if (days > 0) '$days يوم',
            '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}',
          ]
        : [
            if (days > 0) '${days}d',
            '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}',
          ];

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [
              Colors.orange.shade100.withValues(alpha: 0.95),
              Colors.amber.shade50.withValues(alpha: 0.9),
            ],
          ),
          border:
              Border.all(color: Colors.orange.shade300.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            Icon(Icons.timer_outlined, color: Colors.orange.shade900, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.isAr
                    ? 'العد التنازلي: ${parts.join(' • ')}'
                    : 'Time left: ${parts.join(' • ')}',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: Colors.orange.shade900,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
