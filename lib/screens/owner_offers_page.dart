import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/branding/branding_logo_image.dart';
import '../core/input/input_normalizers.dart';
import '../core/marketing/listing_request_marketing_price.dart';
import '../core/utils/app_money.dart';
import '../core/utils/chat_display_initials.dart';
import '../core/marketing/marketing_offer_fee.dart';
import '../core/workflow/listing_workflow_copy.dart';
import '../core/workflow/listing_workflow_ui_context.dart';
import '../core/haptics/app_haptics.dart';
import '../core/notifications/app_sound_coordinator.dart';
import '../core/notifications/hub_workflow_sound.dart';
import '../services/chat_peer_service.dart';
import '../services/marketing_flow_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/app_page_close_button.dart';
import '../widgets/listing/request_summary_table.dart';
import '../widgets/listing_workflow_progress_strip.dart';
import '../widgets/user_presence_strip.dart';
import '../core/presence/presence_display_prefs.dart';

/// مراجعة عروض المسوقين وقبول عرض واحد عبر `accept_listing_offer`.
class OwnerOffersPage extends StatefulWidget {
  final String requestId;
  final String lang;
  /// عند فتح الصفحة من BottomSheet في «صفحتي».
  final bool embeddedInSheet;
  /// بعد قبول عرض بنجاح (إغلاق الورقة وتحريك تبويب التعاقد في الواجهة الأم).
  final VoidCallback? onOfferAccepted;

  const OwnerOffersPage({
    super.key,
    required this.requestId,
    this.lang = 'ar',
    this.embeddedInSheet = false,
    this.onOfferAccepted,
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
  bool _acceptInFlight = false;

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
    if (_acceptInFlight) return false;
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

  Future<void> _accept(Map<String, dynamic> o) async {
    final id = (o['id'] ?? '').toString();
    if (id.isEmpty || !_canTapAccept(o)) return;

    setState(() {
      _busyOfferId = id;
      _acceptInFlight = true;
    });
    try {
      AppHaptics.medium();
      await _svc.acceptListingOfferById(id);
      if (!mounted) return;
      playHubWorkflowSound(HubWorkflowSoundKind.contractSuccess);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ListingWorkflowCopy.snackOfferAccepted(_isAr))),
      );
      await _reload();
      if (!mounted) return;
      if (widget.embeddedInSheet) {
        Navigator.of(context).pop();
      }
      widget.onOfferAccepted?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(ListingWorkflowCopy.rpcFailedFriendly(_isAr, e))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyOfferId = null;
          _acceptInFlight = false;
        });
      }
    }
  }

  Future<void> _decline(Map<String, dynamic> o) async {
    final id = (o['id'] ?? '').toString();
    if (id.isEmpty || _acceptInFlight) return;

    final reasonCtl = TextEditingController();
    final allowRetryHolder = <bool>[false];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(
                ListingWorkflowCopy.t(_isAr, 'رفض العرض', 'Decline offer'),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _isAr
                          ? 'لن يُعتمد هذا العرض. يمكنك إضافة ملاحظة للمسوّق (اختياري).'
                          : 'This offer will be declined. Optional note to the marketer.',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      value: allowRetryHolder[0],
                      onChanged: (v) =>
                          setLocal(() => allowRetryHolder[0] = v),
                      title: Text(
                        _isAr
                            ? 'هل ترغب في إتاحة الفرصة للمسوق لرؤية إعلانك وإتمام صفقة أخرى؟'
                            : 'Allow this marketer to see your listing and submit another offer?',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          height: 1.35,
                        ),
                      ),
                      subtitle: Text(
                        _isAr
                            ? 'عند التفعيل: يُسجَّل الاعتذار ويُسمح بإعادة الظهور في «السوق العقاري» لهذا المسوّق عندما ينطبق ذلك على الطلب.'
                            : 'When enabled: softer decline and retry visibility for this marketer when allowed on the request.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    AqarTextField(
                      controller: reasonCtl,
                      maxLines: 3,
                      maxLength: 500,
                      decoration: InputDecoration(
                        labelText: _isAr
                            ? 'ملاحظة (اختياري)'
                            : 'Note (optional)',
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
            );
          },
        );
      },
    );
    final reasonText = reasonCtl.text.trim();
    reasonCtl.dispose();
    if (ok != true || !mounted) return;

    setState(() => _busyOfferId = id);
    try {
      AppHaptics.medium();
      final allowMarketerRetry = allowRetryHolder[0];
      if (allowMarketerRetry) {
        await _svc.ownerDeclineOffer(
          offerId: id,
          requestId: widget.requestId,
          ownerReason: reasonText.isEmpty ? null : reasonText,
          declineKind: 'apology',
        );
        await _svc.ownerSetAllowPreviousMarketersRetry(
          requestId: widget.requestId,
          allow: true,
        );
      } else {
        await _svc.ownerDeclineOffer(
          offerId: id,
          requestId: widget.requestId,
          ownerReason: reasonText.isEmpty ? null : reasonText,
          declineKind: 'reject',
        );
        await _svc.ownerSetAllowPreviousMarketersRetry(
          requestId: widget.requestId,
          allow: false,
        );
      }
      if (!mounted) return;
      if (_isAr) {
        await AppSoundCoordinator.playUiEffect(
          assetPath: 'sounds/in_app_chime.wav',
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAr
                ? 'تم تسجيل رفض العرض وتحديث حالة الطلب.'
                : 'Offer declined and request updated.',
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
      return _fmtNumericUi(
        DateFormat.yMMMd(loc).add_Hm().format(dt.toLocal()),
      );
    } catch (_) {
      return _fmtNumericUi(
        DateFormat('yyyy-MM-dd HH:mm').format(dt.toLocal()),
      );
    }
  }

  String? _fmtDateOnly(dynamic v) {
    if (v == null) return null;
    final dt = DateTime.tryParse(v.toString());
    if (dt == null) return null;
    try {
      return normalizeAsciiDigits(
        DateFormat('yyyy-MM-dd').format(dt.toLocal()),
      );
    } catch (_) {
      return normalizeAsciiDigits(
        DateFormat('yyyy-MM-dd').format(dt.toLocal()),
      );
    }
  }

  String? _fmtTimeOnly(dynamic v) {
    if (v == null) return null;
    final dt = DateTime.tryParse(v.toString());
    if (dt == null) return null;
    try {
      return normalizeAsciiDigits(DateFormat('HH:mm').format(dt.toLocal()));
    } catch (_) {
      return normalizeAsciiDigits(DateFormat('HH:mm').format(dt.toLocal()));
    }
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
    if (prop != null && prop['default_cover_used'] != true) {
      final imgs = prop['property_images'];
      if (imgs is List && imgs.isNotEmpty) {
        final rows =
            imgs.map((e) => Map<String, dynamic>.from(e as Map)).toList()
              ..sort((a, b) {
                final sa = (a['sort_order'] as num?)?.toInt() ?? 0;
                final sb = (b['sort_order'] as num?)?.toInt() ?? 0;
                return sa.compareTo(sb);
              });
        final fromProp = rows
            .map((row) =>
                (row['path'] ?? row['file_name'] ?? '').toString().trim())
            .where((path) => path.isNotEmpty)
            .map((path) {
              if (path.startsWith('http')) return path;
              return Supabase.instance.client.storage
                  .from('property-images')
                  .getPublicUrl(path);
            })
            .where((url) => url.trim().isNotEmpty)
            .toList(growable: false);
        if (fromProp.isNotEmpty) return fromProp;
      }
    }

    final req = _request;
    if (req == null) return const [];

    String toPublic(String path) {
      final s = path.trim();
      if (s.isEmpty) return '';
      if (s.startsWith('http://') || s.startsWith('https://')) return s;
      return Supabase.instance.client.storage
          .from('property-images')
          .getPublicUrl(s);
    }

    final out = <String>[];
    void addPaths(dynamic raw) {
      if (raw is! List) return;
      for (final e in raw) {
        final u = toPublic(e.toString());
        if (u.isNotEmpty && !out.contains(u)) out.add(u);
      }
    }

    addPaths(req['preview_image_urls']);
    final payload = req['payload_json'] ?? req['payload'];
    if (payload is Map) {
      for (final key in const [
        'request_image_paths',
        'image_paths',
        'image_urls',
        'images',
      ]) {
        addPaths(payload[key]);
      }
      final prim =
          (payload['primary_image'] ?? payload['primaryImage'] ?? '')
              .toString()
              .trim();
      if (prim.isNotEmpty) {
        final u = toPublic(prim);
        if (u.isNotEmpty && !out.contains(u)) out.add(u);
      }
    }
    return out;
  }

  String? _heroImageUrlFromProperty() {
    final urls = _propertyImageUrls();
    return urls.isEmpty ? null : urls.first;
  }

  String? _heroImageUrl() => _heroImageUrlFromProperty();

  /// أرقام لاتينية دائماً في عروض المسوقين (ويب/تطبيق).
  String _fmtNumericUi(String s) => normalizeAsciiDigits(s);

  String _fmtMoney(num n) {
    final f = NumberFormat('#,##0', 'en');
    return _fmtNumericUi(f.format(n));
  }

  String _fmtDeedDate(dynamic raw) {
    if (raw == null) return '';
    final s = raw.toString().trim();
    if (s.isEmpty) return '';
    final dt = DateTime.tryParse(s);
    if (dt != null) {
      return DateFormat('yyyy-MM-dd').format(dt.toLocal());
    }
    return normalizeAsciiDigits(s);
  }

  String _pickDeedNumber() {
    final p = (_linkedProperty?['deed_number'] ?? '').toString().trim();
    if (p.isNotEmpty) return normalizeAsciiDigits(p);
    final req = _request;
    if (req == null) return '';
    for (final key in const ['deed_number', 'preview_deed_number']) {
      final v = (req[key] ?? '').toString().trim();
      if (v.isNotEmpty) return normalizeAsciiDigits(v);
    }
    final payload = req['payload_json'] ?? req['payload'];
    if (payload is Map) {
      final v = (payload['deed_number'] ?? '').toString().trim();
      if (v.isNotEmpty) return normalizeAsciiDigits(v);
    }
    return '';
  }

  String _pickDeedDate() {
    final p = _fmtDeedDate(_linkedProperty?['deed_date']);
    if (p.isNotEmpty) return p;
    final req = _request;
    if (req == null) return '';
    for (final key in const ['deed_date', 'preview_deed_date']) {
      final v = _fmtDeedDate(req[key]);
      if (v.isNotEmpty) return v;
    }
    final payload = req['payload_json'] ?? req['payload'];
    if (payload is Map) {
      final v = _fmtDeedDate(payload['deed_date']);
      if (v.isNotEmpty) return v;
    }
    return '';
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

    final title = (req['title'] ?? _linkedProperty?['title'] ?? '')
        .toString()
        .trim();
    final city = (req['city'] ?? _linkedProperty?['city'] ?? '')
        .toString()
        .trim();
    final loc = (req['location'] ??
            req['address_line'] ??
            _linkedProperty?['location'] ??
            _linkedProperty?['address_line'] ??
            '')
        .toString()
        .trim();
    final price = _propertyBasePriceSar;
    final url = _heroImageUrl();
    final deedNo = _pickDeedNumber();
    final deedDate = _pickDeedDate();
    final roundLabel = ListingWorkflowCopy.marketingRoundLabel(
      _isAr,
      req['marketing_round'],
    );
    final screenW = MediaQuery.sizeOf(context).width;
    final heroH = (screenW * 0.52).clamp(180.0, 280.0);

    final summaryRows = <RequestSummaryRow>[
      RequestSummaryRow(
        label: _isAr ? 'المرجع' : 'Reference',
        value: _listingReferenceLine(),
      ),
      if (title.isNotEmpty)
        RequestSummaryRow(
          label: _isAr ? 'العنوان' : 'Title',
          value: title,
          emphasize: true,
        ),
      if (city.isNotEmpty)
        RequestSummaryRow(
          label: _isAr ? 'المدينة' : 'City',
          value: city,
        ),
      if (loc.isNotEmpty)
        RequestSummaryRow(
          label: _isAr ? 'الموقع' : 'Location',
          value: loc,
        ),
      if (price > 0)
        RequestSummaryRow(
          label: _isAr ? 'قيمة العقار' : 'Property value',
          value:
              '${_fmtMoney(price)} ${AppMoney.saudiRiyalSignUnicode}',
          emphasize: true,
        ),
      if (deedNo.isNotEmpty)
        RequestSummaryRow(
          label: _isAr ? 'رقم الصك' : 'Deed number',
          value: deedNo,
        ),
      if (deedDate.isNotEmpty)
        RequestSummaryRow(
          label: _isAr ? 'تاريخ الصك' : 'Deed date',
          value: deedDate,
        ),
      RequestSummaryRow(
        label: _isAr ? 'جولة التسويق' : 'Marketing round',
        value: roundLabel,
      ),
      RequestSummaryRow(
        label: _isAr ? 'عروض الشركاء' : 'Partner offers',
        value: _isAr
            ? '${_offers.length} عرض'
            : '${_offers.length} offer(s)',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) {
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 10),
                child: child,
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: heroH,
              width: double.infinity,
              child: url != null
                  ? CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: heroH,
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
                        child: const BrandingLogoImage(
                          size: 120,
                          fit: BoxFit.contain,
                          errorIcon: Icons.apartment_rounded,
                        ),
                      ),
                    )
                  : Container(
                      color: _brandTeal.withValues(alpha: 0.12),
                      alignment: Alignment.center,
                      child: const BrandingLogoImage(
                        size: 132,
                        fit: BoxFit.contain,
                        errorIcon: Icons.apartment_rounded,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        RequestSummaryTable(
          title: _isAr ? 'بيانات العقار' : 'Property details',
          rows: summaryRows,
        ),
      ],
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
          automaticallyImplyLeading: false,
          leading: (widget.embeddedInSheet || Navigator.canPop(context))
              ? AppPageCloseButton(
                  isArabic: _isAr,
                  onPressed: () {
                    if (Navigator.canPop(context)) Navigator.pop(context);
                  },
                )
              : null,
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
                                      permitSoundContextId: widget.requestId,
                                    ),
                                  const SizedBox(height: 12),
                                  _buildDeclineCapBanner(cs),
                                  const SizedBox(height: 4),
                                ],
                                _buildPropertyHero(cs),
                                const SizedBox(height: 16),
                                  Text(
                                    _isAr
                                        ? (_offers.isEmpty
                                            ? 'بانتظار عروض الشركاء المسوّقين'
                                            : 'عروض الشركاء المسوّقين')
                                        : (_offers.isEmpty
                                            ? 'Waiting for partner marketer offers'
                                            : 'Partner marketer offers'),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _isAr
                                        ? 'قارِن الجهات واختَر شريكاً موثوقاً واحداً للمتابعة.'
                                        : 'Compare parties and choose one trusted partner to proceed.',
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

  Widget _buildOfferCard(Map<String, dynamic> o, ColorScheme cs) {
    final id = (o['id'] ?? '').toString();
    final name = (o['_marketer_display_name'] ?? '').toString().trim();
    final busy = _busyOfferId == id;
    final statusRaw = (o['status'] ?? '').toString();
    final winner = _isAcceptedWinner(o);
    final canAccept = _canTapAccept(o);
    final canDecline = _canOwnerDecide(o) &&
        !_anotherOfferWasSelected(id) &&
        !_acceptInFlight;
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
                        maxLines: 6,
                        softWrap: true,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16.5,
                        ),
                      ),
                      // سطر حالة المسوّق (متصل الآن / آخر ظهور) لحظيّ —
                      // يحدّث عبر Realtime ولا يحتاج تحديث الصفحة. يظهر لكل
                      // مسوّق قدّم عرضاً داخل تبويب «العروض المقدّمة» للمالك
                      // وعند الانتقال إلى تبويب «بانتظار التعاقد» يبقى ظاهراً.
                      if (mid.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        UserPresenceStrip(
                          userId: mid,
                          isAr: _isAr,
                          compact: true,
                          surface: PresenceDisplaySurface.listingCards,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        ListingWorkflowCopy.t(
                          _isAr,
                          'شريك: ${_accountTypeHuman(o)}',
                          'Partner: ${_accountTypeHuman(o)}',
                        ),
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Chip(
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      shortStatus,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            RequestSummaryTable(
              title: _isAr ? 'بيانات الشريك والعرض' : 'Partner & offer details',
              rows: [
                  RequestSummaryRow(
                    label: _isAr ? 'اسم الشريك' : 'Partner name',
                    value: name.isNotEmpty
                        ? name
                        : ListingWorkflowCopy.t(
                            _isAr,
                            'شريك مسوّق',
                            'Partner marketer',
                          ),
                    emphasize: true,
                  ),
                  RequestSummaryRow(
                    label: _isAr ? 'نوع الجهة' : 'Entity type',
                    value: _accountTypeHuman(o),
                  ),
                  if (phone.isNotEmpty)
                    RequestSummaryRow(
                      label: _isAr ? 'الجوال' : 'Phone',
                      value: _fmtNumericUi(phone),
                    ),
                  if (license.isNotEmpty)
                    RequestSummaryRow(
                      label: _isAr ? 'ترخيص الشريك' : 'Partner license',
                      value: normalizeAsciiDigits(license),
                    ),
                  RequestSummaryRow(
                    label: _isAr ? 'حالة الشريك' : 'Partner status',
                    value: longStatus,
                  ),
                  RequestSummaryRow(
                    label: _isAr ? 'قيمة العرض' : 'Offer amount',
                    value: _amountLine(o),
                    emphasize: true,
                  ),
                  RequestSummaryRow(
                    label: _isAr ? 'تاريخ التقديم' : 'Submitted date',
                    value: _fmtDateOnly(o['created_at']) ?? '—',
                  ),
                  RequestSummaryRow(
                    label: _isAr ? 'وقت التقديم' : 'Submitted time',
                    value: _fmtTimeOnly(o['created_at']) ?? '—',
                  ),
                  if (rating != null && rating.count > 0)
                    RequestSummaryRow(
                      label: _isAr ? 'تقييم الشريك' : 'Partner rating',
                      value: _isAr
                          ? '${_fmtNumericUi(rating.avg.toStringAsFixed(1))} • ${_fmtNumericUi('${rating.count}')} تقييم'
                          : '${rating.avg.toStringAsFixed(1)} • ${rating.count} ratings',
                    ),
              ],
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
                      onPressed: (_loading ||
                              _refreshing ||
                              busy ||
                              _acceptInFlight)
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
                      onPressed: (_loading || _refreshing || busy || _acceptInFlight)
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
