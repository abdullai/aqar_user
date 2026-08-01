import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/branding/branding_logo_image.dart';
import '../core/listing/listing_media_urls.dart';
import '../core/subscription/app_subscription_gate.dart';
import '../core/subscription/marketing_subscription_access.dart';
import '../core/subscription/subscription_gate_helper.dart';
import '../core/marketing/listing_request_marketing_price.dart';
import '../core/utils/app_money.dart';
import '../core/marketing/marketing_offer_fee.dart';
import '../core/workflow/listing_workflow_copy.dart';
import '../core/workflow/listing_workflow_ui_context.dart';
import '../services/account_completion_service.dart';
import '../core/network/supabase_interceptor.dart';
import '../services/marketing_flow_service.dart';
import '../services/marketing_workflow_automation_service.dart';
import '../services/marketing_workflow_hub.dart';
import '../services/profile_compliance_service.dart';
import '../screens/profile_signature_gate_screen.dart';
import '../screens/settings_page.dart';
import '../screens/subscriptions/subscriptions_root_screen.dart';
import 'app_shimmer.dart';
import 'listing_pricing_breakdown.dart';

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

  /// عندما يكون `true` (الافتراضي): يلفّ المحتوى داخل `SingleChildScrollView`
  /// — مناسب للحوار المنبثق. عند `false`: نُستخدم Column مباشرة دون scroll
  /// داخلي، وهذا يَمنع التعطّل عند تضمين اللوحة داخل صفحة قابلة للتمرير.
  final bool useInnerScroll;

  const MarketingOfferSubmitPanel({
    super.key,
    required this.requestId,
    this.inviteId,
    required this.isAr,
    this.showDragHandle = false,
    this.propertyBaseSarHint,
    this.onSuccess,
    this.useInnerScroll = true,
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
  late final MarketingWorkflowAutomationService _autoSvc =
      MarketingWorkflowAutomationService(Supabase.instance.client);

  bool _loading = true;
  bool _submitting = false;
  bool _sendingLastCall = false;
  Map<String, dynamic>? _request;
  Map<String, dynamic>? _linkedProperty;

  /// صف العرض الحيّ للمسوّق الحالي على هذا الطلب (إن وُجد). عند توفّره
  /// نُخفي حقل ملاحظات العرض وزر «إرسال العرض»، ونعرض حالة العرض مع
  /// زر «إشعار آخر للمالك» بعد 48 ساعة بحسب RPC الخادم.
  Map<String, dynamic>? _liveOffer;
  String? _loadError;

  static const Color _brandTeal = Color(0xFF0F766E);

  bool get _hasLiveOffer => _liveOffer != null;

  ListingWorkflowUiContext? get _wfCtx => _request == null
      ? null
      : ListingWorkflowUiContext.fromListingRequest(_request!);

  /// المالك اختار مسوّقاً آخر؟ في هذه الحالة نُخفي العرض الكامل وكل الأزرار
  /// لأنه لا فائدة من تقديم أو تجديد عرض حالياً (سياسة موحَّدة).
  bool get _ownerSelectedOtherMarketer {
    final r = _request;
    if (r == null) return false;
    final selected = (r['selected_marketer_id'] ?? '').toString().trim();
    if (selected.isEmpty) return false;
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    return selected != uid;
  }

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
      final live = _svc.marketerLiveOfferRowForRequestRound(widget.requestId);
      final prop = _svc.linkedPropertyForListingRequest(widget.requestId);
      final results = await Future.wait<Object?>([req, live, prop]);
      if (!mounted) return;
      setState(() {
        _request = results[0] as Map<String, dynamic>?;
        _liveOffer = results[1] as Map<String, dynamic>?;
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

  // ---------------------------------------------------------------------------
  // «إشعار آخر» — Last Call (v8 — أتمتة 48 ساعة).
  //
  // - الزر يظهر فقط عندما يكون للمسوّق عرض نشط في الجولة الحالية.
  // - يُعطَّل قبل مرور 48 ساعة على إنشاء العرض/آخر إشعار (cooldown).
  // - يختفي تماماً إن اختار المالك مسوّقاً آخر، أو إن لم يَعُد العرض نشطاً.
  // ---------------------------------------------------------------------------
  DateTime? _liveOfferLastEventUtc() {
    final o = _liveOffer;
    if (o == null) return null;
    final lc = (o['last_call_at'] ?? '').toString();
    final cr = (o['created_at'] ?? '').toString();
    final raw = lc.isNotEmpty ? lc : cr;
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  bool get _lastCallReady {
    final ref = _liveOfferLastEventUtc();
    if (ref == null) return false;
    return DateTime.now().toUtc().difference(ref) >= const Duration(hours: 48);
  }

  Duration? get _lastCallRemaining {
    final ref = _liveOfferLastEventUtc();
    if (ref == null) return null;
    final eligibleAt = ref.add(const Duration(hours: 48));
    final remaining = eligibleAt.difference(DateTime.now().toUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  String _formatRemaining(Duration d) {
    if (d.inMinutes <= 0) {
      return ListingWorkflowCopy.t(
        widget.isAr,
        'أقل من دقيقة',
        'less than a minute',
      );
    }
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (widget.isAr) {
      if (hours <= 0) return '$minutes دقيقة';
      if (minutes <= 0) return '$hours ساعة';
      return '$hoursس $minutesد';
    }
    if (hours <= 0) return '${minutes}m';
    if (minutes <= 0) return '${hours}h';
    return '${hours}h ${minutes}m';
  }

  Future<void> _sendLastCall() async {
    final offerId = (_liveOffer?['id'] ?? '').toString().trim();
    if (offerId.isEmpty) return;
    setState(() => _sendingLastCall = true);
    try {
      final pre = await _autoSvc.canSendLastCall(offerId);
      if (pre['allow'] != true) {
        final reason = (pre['reason'] ?? '').toString();
        String msg;
        if (reason == 'owner_selected_other') {
          msg = widget.isAr
              ? 'تعذّر الإشعار: المالك اختار مسوّقاً آخر.'
              : 'Owner has selected another marketer.';
        } else if (reason == 'cooldown' || reason == 'before_first_window') {
          msg = widget.isAr
              ? 'لا يمكن إرسال إشعار آخر قبل مرور 48 ساعة على آخر تواصل.'
              : 'You can send a last-call only 48 hours after the previous one.';
        } else if (reason == 'offer_not_active') {
          msg = widget.isAr
              ? 'هذا العرض لم يَعد نشطاً.'
              : 'This offer is no longer active.';
        } else {
          msg = widget.isAr
              ? 'تعذّر إرسال إشعار آخر الآن.'
              : 'Cannot send a last-call right now.';
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
        return;
      }

      final res = await _autoSvc.sendLastCall(offerId);
      if (!mounted) return;
      if (res['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isAr
                  ? 'تم إرسال إشعار صوتي للمالك وتجديد عرضك 48 ساعة أخرى.'
                  : 'A sound alert was sent to the owner and your offer was renewed for 48 hours.',
            ),
          ),
        );
        await _load();
        MarketingWorkflowHub.notifyBucketsChanged();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isAr
                  ? 'تعذّر إرسال الإشعار. حاول لاحقاً.'
                  : 'Could not send the alert. Try again later.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingLastCall = false);
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

  /// نموذج الفاتورة الكامل المشتقّ من بيانات الإعلان (v9):
  ///   * `enteredPrice` = السعر الذي أدخله المعلن.
  ///   * `priceIncludesVat` = إن كان شامل ضريبة 5% (افتراضي true).
  ///   * `commissionKind` = none/percent/fixed (افتراضي none).
  ///   * `commissionRate` و`commissionAmount`: حسب اختيار المعلن.
  ///
  /// — يعتمد على الأعمدة الجديدة من `listing_requests` (v9). إن لم تكن متوفّرة
  ///   (بيئة قديمة)، يعود للقيم الافتراضية الآمنة (شامل + بدون عمولة).
  ListingInvoiceModel? get _listingInvoice {
    final r = _request;
    if (r == null) return null;
    final base = _effectiveBaseSar;
    if (base <= 0) return null;

    bool? toB(Object? v) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final s = v.trim().toLowerCase();
        if (s == 'true' || s == '1' || s == 'yes') return true;
        if (s == 'false' || s == '0' || s == 'no') return false;
      }
      return null;
    }

    double? toD(Object? v) {
      if (v is num) return v.toDouble();
      if (v is String) {
        final s = v.trim();
        if (s.isEmpty) return null;
        return double.tryParse(s);
      }
      return null;
    }

    final inclVat = toB(r['price_includes_vat']) ?? true;
    final vRate = toD(r['vat_rate']) ?? 0.05;
    final kindRaw =
        (r['marketing_commission_kind'] ?? 'none').toString().trim().toLowerCase();
    final kind = const {'none', 'percent', 'fixed'}.contains(kindRaw)
        ? kindRaw
        : 'none';
    final cRate = toD(r['marketing_commission_rate']) ?? 0.025;
    final cAmount = toD(r['marketing_commission_amount']) ?? 0.0;

    return ListingInvoiceModel(
      enteredPrice: base,
      priceIncludesVat: inclVat,
      vatRate: vRate,
      commissionKind: kind,
      commissionRate: cRate,
      commissionAmount: cAmount,
      currencyCode: 'SAR',
    );
  }

  /// المبلغ المستحق من المسوّق للمالك حسب الإعلان نفسه:
  ///   * إن كانت العمولة `percent` أو `fixed` على الإعلان: نستخدم قيمتها فعلياً.
  ///   * إن كانت `none`: نَعود للقيمة القديمة (2.5% من المجموع شامل ضريبة)
  ///     حتى لا يتعطّل الإرسال على الإعلانات القديمة قبل أن يحدّث المالك السؤالين.
  double get _autoTotalDueSar {
    final inv = _listingInvoice;
    if (inv != null && inv.commissionTotal > 0) {
      return inv.commissionTotal;
    }
    final base = _effectiveBaseSar;
    return base > 0 ? MarketingOfferFee.totalDue(base) : 0.0;
  }

  String? _coverUrl() {
    final sb = Supabase.instance.client;
    String? fromPath(String path) {
      final p = path.trim();
      if (p.isEmpty) return null;
      if (p.startsWith('http')) return p;
      return sb.storage.from('property-images').getPublicUrl(p);
    }

    final prop = _linkedProperty;
    if (prop != null && prop['default_cover_used'] != true) {
      final imgs = prop['property_images'];
      if (imgs is List && imgs.isNotEmpty) {
        final rows = imgs.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          ..sort((a, b) {
            final sa = (a['sort_order'] as num?)?.toInt() ?? 0;
            final sb = (b['sort_order'] as num?)?.toInt() ?? 0;
            return sa.compareTo(sb);
          });
        final path =
            (rows.first['path'] ?? rows.first['file_name'] ?? '').toString();
        final u = fromPath(path);
        if (u != null) return u;
      }
    }

    final r = _request;
    if (r != null && r['default_cover_used'] != true) {
      final previewUrls = r['preview_image_urls'];
      if (previewUrls is List && previewUrls.isNotEmpty) {
        final u = fromPath(previewUrls.first.toString());
        if (u != null) return u;
      }
      final payload = r['payload_json'] is Map
          ? Map<String, dynamic>.from(r['payload_json'] as Map)
          : r['payload'] is Map
              ? Map<String, dynamic>.from(r['payload'] as Map)
              : null;
      if (payload != null) {
        final imgs = payload['images'] ?? payload['image_urls'];
        if (imgs is List && imgs.isNotEmpty) {
          final u = fromPath(imgs.first.toString());
          if (u != null) return u;
        }
      }
    }
    return null;
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

    // المبلغ المُرسَل للمالك: عمولة الإعلان الفعلية (نسبة/مقطوع) إن كانت محدّدة،
    // وإلا نرجع للنموذج القديم (2.5% من المجموع شامل الضريبة) للإعلانات التي
    // لم يَختر فيها المالك نوع العمولة بعد.
    final total = _autoTotalDueSar;

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
      await _load();
      if (!mounted) return;
      widget.onSuccess?.call();
    } on ListingOfferConflictException catch (_) {
      if (mounted) {
        SupabaseRequestInterceptor.showIfHandled(context, const ListingOfferConflictException(), isAr: widget.isAr);
      }
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
          await _load();
          if (mounted) widget.onSuccess?.call();
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
    final labelWidget = Text(
      label,
      style: TextStyle(
        fontWeight: emphasize ? FontWeight.w900 : FontWeight.w700,
        fontSize: emphasize ? 15 : 13,
        color: cs.onSurface,
      ),
    );
    // — متكيّف: على الشاشات الضيّقة (< 280) نضع التسمية فوق القيمة بدل
    //   صفّ واحد قد يُجبر النص على الالتفاف.
    return LayoutBuilder(
      builder: (ctx, c) {
        final narrow = c.maxWidth.isFinite && c.maxWidth < 280;
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              labelWidget,
              const SizedBox(height: 4),
              Align(
                alignment:
                    widget.isAr ? Alignment.centerLeft : Alignment.centerRight,
                child: FittedBox(fit: BoxFit.scaleDown, child: value),
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: labelWidget),
            const SizedBox(width: 8),
            FittedBox(fit: BoxFit.scaleDown, child: value),
          ],
        );
      },
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

  /// نموذج فاتورة احتياطي للإعلانات القديمة التي لم يَختر فيها المعلن نوع
  /// العمولة (`marketing_commission_kind = none`) حسب صفحة «نشر الإعلان»
  /// الجديدة. يحافظ على نموذج 2.5٪ من المجموع شامل الضريبة 5٪ الموحَّد
  /// المُستخدَم سابقاً، حتى لا يتعطّل الإرسال على هذه الإعلانات.
  Widget _legacyFeeBox({
    required ColorScheme cs,
    required double base,
    required double propVat,
    required double subtotal,
    required double fee,
    required double total,
    required String feePctLabel,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _brandTeal.withValues(alpha: 0.28)),
        color: _brandTeal.withValues(alpha: 0.06),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _feeRow(
            widget.isAr ? 'قيمة العقار' : 'Property value',
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
                ? 'المجموع شامل ضريبة القيمة المضافة 5٪'
                : 'Subtotal incl. 5% VAT',
            _feeAmount(subtotal, cs),
            cs,
          ),
          const SizedBox(height: 8),
          _feeRow(
            widget.isAr
                ? 'نسبة التسويق $feePctLabel من المجموع الإجمالي المستحق'
                : 'Marketing rate $feePctLabel of total due',
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
        ],
      ),
    );
  }

  /// بطاقة موحَّدة: صورة العقار في الأعلى ثم البيانات (عمودان: يمين/يسار).
  /// تستبدل البانر القديم ذي النصوص فوق الصورة.
  Widget _buildPropertySnapshot(ColorScheme cs) {
    final r = _request;
    if (r == null) return const SizedBox.shrink();
    final lp = _linkedProperty;

    final title = (lp?['title'] ?? r['title'] ?? '').toString().trim();
    final city = (lp?['city'] ?? r['city'] ?? '').toString().trim();
    final loc = [
      (lp?['location'] ?? r['location'] ?? '').toString().trim(),
      (lp?['address_line'] ?? r['address_line'] ?? '').toString().trim(),
      (r['district'] ?? '').toString().trim(),
    ].where((s) => s.isNotEmpty).join(' · ');
    final code = (lp?['listing_public_code'] ?? '').toString().trim();
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

    // عناصر العمودين: نُرتّب البيانات يمين/يسار بدل التكديس فوق بعض.
    final entries = <_SnapshotEntry>[];
    if (title.isNotEmpty) {
      entries.add(_SnapshotEntry(
        icon: Icons.title_outlined,
        label: ListingWorkflowCopy.t(widget.isAr, 'العنوان', 'Title'),
        value: title,
      ));
    }
    if (city.isNotEmpty) {
      entries.add(_SnapshotEntry(
        icon: Icons.location_city_outlined,
        label: ListingWorkflowCopy.t(widget.isAr, 'المدينة', 'City'),
        value: city,
      ));
    }
    if (loc.isNotEmpty) {
      entries.add(_SnapshotEntry(
        icon: Icons.map_outlined,
        label: ListingWorkflowCopy.t(widget.isAr, 'الموقع والعنوان',
            'Location'),
        value: loc,
      ));
    }
    if (ownerName.isNotEmpty) {
      entries.add(_SnapshotEntry(
        icon: Icons.person_outline,
        label: ListingWorkflowCopy.t(widget.isAr, 'صاحب الإعلان',
            'Advertiser'),
        value: ownerName,
      ));
    }
    if (code.isNotEmpty) {
      entries.add(_SnapshotEntry(
        icon: Icons.qr_code_2_outlined,
        label: ListingWorkflowCopy.t(widget.isAr, 'رقم الإعلان',
            'Listing no.'),
        value: code,
      ));
    }
    // لا نُكرّر «قيمة العقار» هنا — تظهر في تفصيل الفاتورة أسفل اللوحة.

    return RepaintBoundary(
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // الصورة المرتبطة فعلاً بالعقار (من جدول property_images عبر
            // linkedPropertyForListingRequest). بدون نصوص فوق الصورة.
            AspectRatio(
              aspectRatio: 16 / 9,
              child: url != null
                  ? CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        color: _brandTeal.withValues(alpha: 0.12),
                        alignment: Alignment.center,
                        child: BrandingLogoImage(
                          fit: BoxFit.cover,
                          errorIcon: Icons.apartment_rounded,
                        ),
                      ),
                    )
                  : Container(
                      color: _brandTeal.withValues(alpha: 0.12),
                      alignment: Alignment.center,
                      child: BrandingLogoImage(
                        fit: BoxFit.cover,
                        errorIcon: Icons.apartment_rounded,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
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
                  _buildSnapshotGrid(entries, cs),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// شبكة عمودين (يمين/يسار) للبيانات. على الشاشات الضيقة جداً تتحوّل لعمود
  /// واحد كي لا تُكسّر النصوص.
  Widget _buildSnapshotGrid(
    List<_SnapshotEntry> entries,
    ColorScheme cs,
  ) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (_, c) {
        final mw = c.maxWidth.isFinite && c.maxWidth > 0 ? c.maxWidth : 400.0;
        final twoCols = mw >= 340;
        const gap = 10.0;
        if (!twoCols) {
          return Column(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) const SizedBox(height: gap),
                _snapshotTile(entries[i], cs),
              ],
            ],
          );
        }
        final rows = <Widget>[];
        for (var i = 0; i < entries.length; i += 2) {
          final left = entries[i];
          final right =
              (i + 1 < entries.length) ? entries[i + 1] : null;
          rows.add(
            Padding(
              padding: EdgeInsets.only(top: rows.isEmpty ? 0 : gap),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _snapshotTile(left, cs)),
                  const SizedBox(width: gap),
                  Expanded(
                    child: right == null
                        ? const SizedBox.shrink()
                        : _snapshotTile(right, cs),
                  ),
                ],
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }

  Widget _snapshotTile(_SnapshotEntry e, ColorScheme cs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(e.icon, size: 18, color: _brandTeal),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                e.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              if (e.valueWidget != null)
                e.valueWidget!
              else
                Text(
                  e.value ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    height: 1.3,
                    color: cs.onSurface,
                  ),
                ),
            ],
          ),
        ),
      ],
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
      // عند التضمين داخل صفحة قابلة للتمرير (مثل MarketerRequestDetailsPage)
      // نُعطّل الـScrollView الداخلي لتجنّب التداخل والتعطّل عند السحب.
      final EdgeInsets contentPadding = widget.useInnerScroll
          ? const EdgeInsets.fromLTRB(20, 0, 20, 28)
          : EdgeInsets.zero;
      final innerContent = Column(
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
                    'إرسال عرض تسويقي',
                    'Send marketing offer',
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
              _buildPropertySnapshot(cs),
              const SizedBox(height: 14),

              // ---------------------------------------------------------------
              // مسارات العرض الثلاثة:
              //
              // (1) المالك اختار مسوّقاً آخر: لا فائدة من تقديم/تجديد عرض، نُخفي
              //     ملخّص الأتعاب وحقل العرض والزر تماماً ونعرض إشعاراً واحداً.
              // (2) لدى المسوّق عرض حيّ: نُخفي حقل العرض وزر «إرسال العرض»،
              //     ونعرض حالة العرض + زر «إشعار آخر» (مفعَّل بعد 48 ساعة).
              // (3) لا يوجد عرض حيّ بعد: المسار الأصلي — ملخص الأتعاب + حقل
              //     ملاحظات + زر إرسال العرض.
              //
              // ملاحظة: شاشة المسوّق تعرض هذه المنطقة كما هي بعد أن يُتيح المالك
              // فرصة ثانية بعد انقضاء 72 ساعة (تُرجع الحالة لـ waiting_marketers
              // وتُسحب العروض القديمة، فيختفي _liveOffer ويُعاد إظهار الحقل).
              // ---------------------------------------------------------------
              if (_ownerSelectedOtherMarketer)
                _noticeCard(
                  cs: cs,
                  icon: Icons.info_outline,
                  background: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                  iconColor: cs.onSurfaceVariant,
                  text: widget.isAr
                      ? 'تم اختيار مسوّق آخر لهذا الطلب. لا تظهر هنا أي أزرار أو حقول حتى يُعيد المالك الطلب للسوق ويمنحك فرصة جديدة بعد 72 ساعة.'
                      : 'Another marketer has been selected for this request. Buttons and fields are hidden until the owner re-opens the request to the market after 72 hours.',
                )
              else if (_hasLiveOffer) ...[
                _buildLiveOfferStatusCard(cs, blocked),
                const SizedBox(height: 10),
                _buildLastCallSection(cs),
              ] else ...[
                if (blocked != null)
                  _noticeCard(
                    cs: cs,
                    icon: Icons.info_outline,
                    background: cs.errorContainer.withValues(alpha: 0.35),
                    iconColor: cs.error,
                    text: blocked,
                  ),
                if (blocked != null) const SizedBox(height: 14),
                if (autoBase <= 0)
                  _noticeCard(
                    cs: cs,
                    icon: Icons.warning_amber_rounded,
                    background: cs.errorContainer.withValues(alpha: 0.35),
                    iconColor: cs.error,
                    text: ListingWorkflowCopy.t(
                      widget.isAr,
                      'سعر العقار غير مضبوط في الطلب. يجب على المالك تحديد السعر أولاً، ثم يمكنك إرسال العرض تلقائياً.',
                      'Property price is missing on this request. The owner must set it first, then you can submit the offer automatically.',
                    ),
                  ),
                if (base > 0) ...[
                  Text(
                    ListingWorkflowCopy.t(
                      widget.isAr,
                      'تفصيل الفاتورة (مطابق لإعدادات المعلن)',
                      'Invoice breakdown (matches advertiser settings)',
                    ),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // — لوحة الفاتورة المركزية تتكيّف مع الشاشات الصغيرة (بدون
                  //   التفاف للنصوص) وتعكس فعلياً اختيار المعلن (شامل/غير شامل
                  //   الضريبة، عمولة نسبة 2.5% أو مبلغ مقطوع، أو بدون عمولة).
                  Builder(builder: (ctx) {
                    final inv = _listingInvoice;
                    if (inv == null) {
                      // إعلان قديم بدون أعمدة فوترة — نعرض النموذج القديم
                      // (2.5% من المجموع شامل ضريبة) كاحتياطي.
                      return _legacyFeeBox(
                        cs: cs,
                        base: base,
                        propVat: propVat,
                        subtotal: subtotal,
                        fee: fee,
                        total: total,
                        feePctLabel: feePctLabel,
                      );
                    }
                    return ListingPricingBreakdown(
                      invoice: inv,
                      isAr: widget.isAr,
                      showTitle: false,
                    );
                  }),
                ],
                const SizedBox(height: 18),
                // — زر «إرسال العرض» وحده — الحقل النصّي وتفاصيل «الإجمالي
                //   المستحق» حُذفت بناءً على طلب المستخدم: الفاتورة كافية
                //   لإيصال المبلغ، ولا حاجة لملاحظات نصّية على المالك في هذه
                //   المرحلة (يبقى الزرّ نفسه ليُرسل العرض بقيمة العمولة
                //   المحسوبة تلقائياً من إعدادات الإعلان).
                FilledButton(
                  onPressed: (_submitting || _effectiveBaseSar <= 0)
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
            ],
          );

      body = Form(
        key: _formKey,
        child: widget.useInnerScroll
            ? SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: contentPadding,
                child: innerContent,
              )
            : Padding(
                padding: contentPadding,
                child: innerContent,
              ),
      );
    }

    return Directionality(
      textDirection: widget.isAr ? TextDirection.rtl : TextDirection.ltr,
      child: body,
    );
  }

  /// بطاقة إشعار موحَّدة (تجنّب تكرار `Material(...)` في كل مكان).
  Widget _noticeCard({
    required ColorScheme cs,
    required IconData icon,
    required Color background,
    required Color iconColor,
    required String text,
  }) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                  color: cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// بطاقة حالة العرض الحيّ — تُعرض حين يكون للمسوّق عرض نشط في هذه الجولة.
  Widget _buildLiveOfferStatusCard(ColorScheme cs, String? blocked) {
    final text = blocked ??
        ListingWorkflowCopy.marketerOfferAlreadyInRound(widget.isAr);
    return _noticeCard(
      cs: cs,
      icon: Icons.check_circle_outline,
      background: cs.primaryContainer.withValues(alpha: 0.4),
      iconColor: cs.primary,
      text: text,
    );
  }

  /// قسم زر «إشعار آخر للمالك» — يحلّ محلّ زر «إرسال العرض» بعد التقديم.
  /// قواعد العرض:
  ///   • يظهر فقط عند وجود عرض حيّ ولم يَختَر المالك مسوّقاً آخر.
  ///   • مُعطَّل قبل مرور 48 ساعة على آخر تواصل، مع توضيح المدة المتبقّية.
  ///   • بعد 48 ساعة: مُفعَّل ويُجدّد العرض تلقائياً عبر RPC.
  Widget _buildLastCallSection(ColorScheme cs) {
    final ready = _lastCallReady;
    final remaining = _lastCallRemaining;
    final count = (_liveOffer?['last_call_count'] as num?)?.toInt() ?? 0;

    final label = ready
        ? (count > 0
            ? ListingWorkflowCopy.t(
                widget.isAr,
                'إشعار آخر للمالك (${count + 1})',
                'Send last-call (${count + 1})',
              )
            : ListingWorkflowCopy.t(
                widget.isAr,
                'إشعار آخر للمالك',
                'Send last-call',
              ))
        : ListingWorkflowCopy.t(
            widget.isAr,
            'إشعار آخر للمالك — يُفعَّل بعد 48 ساعة',
            'Last-call — unlocks after 48h',
          );

    final hint = ready
        ? ListingWorkflowCopy.t(
            widget.isAr,
            'تذكير صوتي مباشر للمالك مع تجديد عرضك 48 ساعة أخرى.',
            'A sound alert to the owner and your offer is renewed for another 48h.',
          )
        : (remaining != null && remaining > Duration.zero
            ? ListingWorkflowCopy.t(
                widget.isAr,
                'يمكنك إرسال «إشعار آخر» بعد ${_formatRemaining(remaining)}.',
                'You can send a last-call in ${_formatRemaining(remaining)}.',
              )
            : ListingWorkflowCopy.t(
                widget.isAr,
                'يمكنك إرسال «إشعار آخر» بعد 48 ساعة من إتمام الصفقة.',
                'You can send a last-call 48 hours after completing your deal.',
              ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed:
              (!ready || _sendingLastCall) ? null : () => unawaited(_sendLastCall()),
          icon: _sendingLastCall
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.notifications_active_outlined),
          style: FilledButton.styleFrom(
            backgroundColor: ready ? _brandTeal : cs.outlineVariant,
            foregroundColor: ready ? Colors.white : cs.onSurfaceVariant,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          label: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          hint,
          style: TextStyle(
            fontSize: 12,
            height: 1.35,
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
  final sb = Supabase.instance.client;
  if (sb.auth.currentUser == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAr ? 'سجّل الدخول لإتمام الصفقة.' : 'Sign in to complete a deal.',
          ),
        ),
      );
    }
    return;
  }
  if (!await SubscriptionGateHelper.ensure(
    context,
    isAr: isAr,
    action: SubscriptionGateAction.marketingPaidWorkflow,
    onGoSubscribe: () async {
      if (!context.mounted) return;
      final (at, oid) = await MarketingSubscriptionAccess.loadBillingContext(sb);
      if (!context.mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/marketingOffer/subscriptions'),
          builder: (_) => SubscriptionsRootScreen(
            lang: isAr ? 'ar' : 'en',
            accountType: at,
            organizationId: oid,
            embedAppBar: false,
          ),
        ),
      );
      if (context.mounted) {
        await SubscriptionGateHelper.refresh(context, force: true);
      }
    },
  )) {
    return;
  }

  final profile = await ProfileComplianceService.loadProfileRow(sb);
  if (profile == null) {
    if (context.mounted) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const SettingsPage(),
        ),
      );
    }
    return;
  }
  final displayName = (profile['username'] ?? '').toString().trim();
  if (displayName.isEmpty) {
    if (context.mounted) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const SettingsPage(),
        ),
      );
    }
    return;
  }
  if (AccountCompletionService.needsUnifiedNationalCompletion(profile)) {
    if (context.mounted) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const SettingsPage(),
        ),
      );
    }
    return;
  }
  final at = profile['account_type']?.toString();
  if (AccountCompletionService.accountTypeNeedsUnifiedNational(at) &&
      ProfileComplianceService.needsSignature(profile)) {
    if (!context.mounted) return;
    final lang = isAr ? 'ar' : 'en';
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isAr ? 'اكتمال الملف' : 'Complete profile',
        ),
        content: Text(
          isAr
              ? 'يلزم إدخال الرقم الوطني الموحّد (700…) والتوقيع الرسمي قبل إتمام الصفقة. اختر أيهما تريد إكماله أولاً.'
              : 'You need the unified national number (700…) and your official signature before completing a deal. Choose which to complete first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'unified'),
            child: Text(isAr ? 'الرقم الموحّد' : 'Unified number'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'signature'),
            child: Text(isAr ? 'التوقيع' : 'Signature'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isAr ? 'إلغاء' : 'Cancel'),
          ),
        ],
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'unified') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
      );
    } else if (choice == 'signature') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (sigCtx) => ProfileSignatureGateScreen(
            lang: lang,
            onDone: () => Navigator.of(sigCtx).pop(),
          ),
        ),
      );
    }
    return;
  }

  if (ProfileComplianceService.needsSignature(profile)) {
    if (!context.mounted) return;
    final lang = isAr ? 'ar' : 'en';
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (sigCtx) => ProfileSignatureGateScreen(
          lang: lang,
          onDone: () => Navigator.of(sigCtx).pop(),
        ),
      ),
    );
    return;
  }

  if (!context.mounted) return;
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
                            'إرسال عرض تسويقي',
                            'Send marketing offer',
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

/// عنصر بيان في «ملخص سريع للعقار» (يمين/يسار).
class _SnapshotEntry {
  _SnapshotEntry({
    required this.icon,
    required this.label,
    this.value,
    this.valueWidget,
  }) : assert(value != null || valueWidget != null);

  final IconData icon;
  final String label;
  final String? value;
  final Widget? valueWidget;
}
