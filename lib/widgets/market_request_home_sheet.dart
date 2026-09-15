// ignore_for_file: unused_element

import 'dart:async' show unawaited;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/deals/deal_messaging_gate.dart';
import '../core/deals/deal_completion_inbox.dart';
import '../core/deals/deal_inventory_policy.dart';
import '../core/gestures/app_keyboard_inset.dart';
import '../core/gestures/app_keyboard_popups.dart';
import '../core/haptics/app_haptics.dart';
import '../core/utils/chat_display_initials.dart';
import '../core/input/saudi_input_formatters.dart';
import '../core/listing/property_listing_display.dart';
import '../core/subscription/app_subscription_gate.dart';
import '../core/subscription/subscription_gate_helper.dart';
import '../core/workflow/app_role_helper.dart';
import '../core/utils/app_money.dart';
import '../core/utils/date_helper.dart';
import '../core/utils/phone_display.dart';
import '../core/market/market_request_detail_facts.dart';
import '../l10n/app_localizations.dart';
import '../models/market_property_request_priority.dart';
import '../models/market_property_request_row.dart';
import '../navigation/chat_navigation.dart';
import '../screens/create_market_property_request_page.dart';
import '../services/chat_peer_service.dart';
import '../services/individual_market_offer_service.dart';
import '../services/market_request_offers_service.dart';
import '../services/reservations_service.dart';
import '../core/utils/users_profiles_safe_select.dart';
import 'guest_participation_gate.dart';
import 'deal_completion_flow.dart';
import 'instant_market_request_badge.dart';
import 'marketer_policy_notice_card.dart';
import 'specified_budget_display.dart';

/// تفاصيل طلب السوق من الرئيسية + عروض + محادثة (بعد تطبيق SQL v20260411).
Future<void> showMarketRequestHomeSheet({
  required BuildContext context,
  required MarketPropertyRequestRow row,
  required bool isAr,
  required SupabaseClient sb,
  required String currentUserId,
  bool autoOpenSubmitOffer = false,
  VoidCallback? onDidChange,
  VoidCallback? onGuestRequiresAuth,
  Future<void> Function()? onGuestPayOfferUnlock,
  Future<bool> Function()? onSubscriptionRequiredForOffer,
  String? accountType,
  String? organizationId,
  bool useRootNavigator = false,
}) {
  return showAppModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    useRootNavigator: useRootNavigator,
    builder: (ctx) {
      return _MarketRequestSheetBody(
        row: row,
        isAr: isAr,
        sb: sb,
        currentUserId: currentUserId,
        autoOpenSubmitOffer: autoOpenSubmitOffer,
        onDidChange: onDidChange,
        onGuestRequiresAuth: onGuestRequiresAuth,
        onGuestPayOfferUnlock: onGuestPayOfferUnlock,
        onSubscriptionRequiredForOffer: onSubscriptionRequiredForOffer,
        accountType: accountType,
        organizationId: organizationId,
      );
    },
  );
}

class _MarketRequestSheetBody extends StatefulWidget {
  const _MarketRequestSheetBody({
    required this.row,
    required this.isAr,
    required this.sb,
    required this.currentUserId,
    this.autoOpenSubmitOffer = false,
    this.onDidChange,
    this.onGuestRequiresAuth,
    this.onGuestPayOfferUnlock,
    this.onSubscriptionRequiredForOffer,
    this.accountType,
    this.organizationId,
  });

  final MarketPropertyRequestRow row;
  final bool isAr;
  final SupabaseClient sb;
  final String currentUserId;
  final bool autoOpenSubmitOffer;
  final VoidCallback? onDidChange;
  final VoidCallback? onGuestRequiresAuth;
  final Future<void> Function()? onGuestPayOfferUnlock;

  /// Lien vers le hub d'abonnements (paywall): يجب أن يُرجع `true` لو فعّل
  /// المستخدم اشتراكاً مناسباً وعاد. الواجهة هنا تعيد فحص الحصة ثم تتابع تلقائياً.
  final Future<bool> Function()? onSubscriptionRequiredForOffer;
  final String? accountType;
  final String? organizationId;

  @override
  State<_MarketRequestSheetBody> createState() =>
      _MarketRequestSheetBodyState();
}

class _MarketRequestSheetBodyState extends State<_MarketRequestSheetBody> {
  bool _loadingOffers = true;
  List<Map<String, dynamic>> _offers = const [];
  String? _offersErr;
  bool _autoOfferPromptConsumed = false;
  IndividualMarketOfferAllowance? _allowance;
  int _myPriorWithdrawCount = 0;

  bool get _guest =>
      widget.currentUserId.isEmpty || widget.currentUserId == 'guest';
  bool get _isOwner =>
      widget.currentUserId.isNotEmpty &&
      widget.currentUserId != 'guest' &&
      widget.currentUserId == widget.row.requesterId;
  Map<String, dynamic>? get _myActiveOffer {
    if (_guest || _isOwner) return null;
    for (final o in _offers) {
      final uid = (o['offerer_id'] ?? '').toString().trim();
      if (uid != widget.currentUserId) continue;
      final st = (o['status'] ?? '').toString().trim().toLowerCase();
      if (st.isEmpty || st == 'submitted' || st == 'pending') return o;
    }
    return null;
  }

  /// أي عرض لي على هذا الطلب (بما فيه المقبول/المختار).
  Map<String, dynamic>? get _myOfferAny {
    if (_guest || _isOwner) return null;
    for (final o in _offers) {
      final uid = (o['offerer_id'] ?? '').toString().trim();
      if (uid == widget.currentUserId) return o;
    }
    return null;
  }

  bool get _hasMyActiveOffer => _myActiveOffer != null;

  bool get _mySelectedForDeal {
    final mine = _myOfferAny;
    if (mine == null) return false;
    final oid = (mine['id'] ?? '').toString().trim();
    if (oid.isEmpty) return false;
    final selected = (widget.row.selectedOfferId ?? '').trim();
    if (selected.isNotEmpty && selected == oid) return true;
    final st = (mine['status'] ?? '').toString().trim().toLowerCase();
    return st == 'accepted' || st == 'approved' || st == 'selected';
  }

  bool get _myOfferAccepted => _mySelectedForDeal;

  /// المراسلة ورقم صاحب الطلب فقط بعد اختيار صاحب الطلب لعرضك.
  bool get _canContactRequester => !_guest && !_isOwner && _mySelectedForDeal;

  String? _requesterPhone;

  @override
  void initState() {
    super.initState();
    unawaited(_reloadOffers());
    unawaited(_reloadAllowance());
    unawaited(_reloadPriorWithdrawCount());
  }

  Future<void> _loadRequesterPhoneIfSelected() async {
    if (!_canContactRequester) {
      if (_requesterPhone != null && mounted) {
        setState(() => _requesterPhone = null);
      }
      return;
    }
    final rid = widget.row.requesterId.trim();
    if (rid.isEmpty) return;
    try {
      final prof = await UsersProfilesSafeSelect.fetchProfileById(
        widget.sb,
        rid,
        columnAttempts: const [
          'user_id,phone',
          'user_id',
        ],
      );
      final phone = (prof?['phone'] ?? '').toString().trim();
      if (!mounted) return;
      setState(() => _requesterPhone = phone.isEmpty ? null : phone);
    } catch (_) {}
  }

  Future<void> _reloadAllowance() async {
    if (_guest || _isOwner) return;
    try {
      final allow =
          await IndividualMarketOfferService(widget.sb).currentAllowance(
        accountType: widget.accountType,
        organizationId: widget.organizationId,
      );
      if (!mounted) return;
      setState(() => _allowance = allow);
    } catch (_) {}
  }

  Future<void> _reloadPriorWithdrawCount() async {
    if (_guest || _isOwner) return;
    try {
      final row = await widget.sb
          .from('market_request_offer_user_withdrawals')
          .select('withdrawn_count')
          .eq('user_id', widget.currentUserId)
          .eq('market_request_id', widget.row.id)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _myPriorWithdrawCount =
            int.tryParse('${row?['withdrawn_count'] ?? 0}') ?? 0;
      });
    } catch (_) {}
  }

  Future<void> _reloadOffers() async {
    setState(() {
      _loadingOffers = true;
      _offersErr = null;
    });
    try {
      final list = await MarketRequestOffersService(widget.sb)
          .listOffersForRequestEnriched(
        widget.row.id,
        preferArabicNames: widget.isAr,
      );
      if (!mounted) return;
      setState(() {
        _offers = list;
        _loadingOffers = false;
      });
      unawaited(_loadRequesterPhoneIfSelected());
      if (widget.autoOpenSubmitOffer &&
          !_autoOfferPromptConsumed &&
          !_guest &&
          !_isOwner &&
          !_hasMyActiveOffer) {
        _autoOfferPromptConsumed = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(_submitOfferDialog());
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _offersErr = e.toString();
        _loadingOffers = false;
        _offers = const [];
      });
    }
  }

  Future<bool> _ensureRequestInMyDeals({String? message}) async {
    if (_guest || _isOwner) return false;
    final used = await DealCompletionInbox.activeDealCount(widget.sb);
    if (!mounted) return false;
    if (DealInventoryPolicy.dealsAtCap(used)) {
      await showDealSlotCapDialog(
        context: context,
        used: used,
        max: DealInventoryPolicy.maxActiveDeals,
      );
      return false;
    }
    // قبل تسجيل العرض/المراسلة نتحقق أن لدى المستخدم اشتراكاً بحصة كافية.
    final allowed = await _ensureOfferAllowanceOrPaywall();
    if (!allowed || !mounted) return false;
    try {
      final added = await MarketRequestOffersService(widget.sb).submitOffer(
        marketRequestId: widget.row.id,
        offerMessage: message,
      );
      if (added &&
          !widget.row.isInstantPaid &&
          AppRoleHelper.isMarketingAccountType(widget.accountType)) {
        unawaited(IndividualMarketOfferService(widget.sb)
            .recordUsageOnSuccess(widget.row.id));
        unawaited(_reloadAllowance());
      }
      widget.onDidChange?.call();
      if (!mounted) return added;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            added
                ? (widget.isAr
                    ? 'تمت إضافة الطلب إلى صفقاتك.'
                    : 'Request added to My deals.')
                : (widget.isAr
                    ? 'الطلب موجود بالفعل في صفقاتك.'
                    : 'Request is already in My deals.'),
          ),
        ),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
      return false;
    }
  }

  bool _ownerMayMessageOfferer(String offererId) {
    final peer = offererId.trim();
    if (peer.isEmpty) return false;
    final selected = (widget.row.selectedOfferId ?? '').trim();
    for (final o in _offers) {
      if ((o['offerer_id'] ?? '').toString().trim() != peer) continue;
      final oid = (o['id'] ?? '').toString().trim();
      if (selected.isNotEmpty && oid == selected) return true;
      return DealMessagingGate.offerApprovedByOwner(
        (o['status'] ?? '').toString(),
      );
    }
    return false;
  }

  Future<void> _openChat({String? counterpartyId}) async {
    if (_guest) return;
    try {
      if (_isOwner) {
        final peer = (counterpartyId ?? '').trim();
        if (!_ownerMayMessageOfferer(peer)) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context)?.dealWaitingOwnerAccept ??
                    (widget.isAr
                        ? 'المراسلة تظهر بعد اختيار الشريك لإتمام الصفقة.'
                        : 'Messaging appears after you select a partner to complete the deal.'),
              ),
            ),
          );
          return;
        }
      } else if (!_canContactRequester) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)?.dealWaitingOwnerAccept ??
                  (widget.isAr
                      ? 'المراسلة ورقم التواصل يظهران بعد اختيار صاحب الطلب لعرضك.'
                      : 'Chat and contact appear after the requester selects your offer.'),
            ),
          ),
        );
        return;
      }
      final cid =
          await ReservationsService.getOrCreateMarketRequestConversation(
        marketRequestId: widget.row.id,
        counterpartyId: counterpartyId,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      await ChatNavigation.push(
        context,
        isAr: widget.isAr,
        conversationId: cid,
        marketRequestId: widget.row.id,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  /// Paywall: قبل فتح حوار «تقديم عرض» نتحقق من حصة المستخدم.
  /// لو لا اشتراك / الحصة 0 → نطلب من اللوحة الأم تحويله لـ «الاشتراكات والمدفوعات».
  /// بعد عودته نُعيد فحص الحصة. إن نجح يُسمح بالمتابعة.
  Future<bool> _ensureOfferAllowanceOrPaywall() async {
    if (_guest || _isOwner) return false;
    if (!AppRoleHelper.isMarketingAccountType(widget.accountType)) {
      return true;
    }
    if (widget.row.isInstantPaid) return true;
    // الإجراءات للمستخدم بعد سحبتين على نفس الطلب — السحب ممنوع وتقديم العرض أيضاً.
    if (_myPriorWithdrawCount >= 2) {
      _toast(widget.isAr
          ? 'لقد سحبت عرضك على هذا الطلب مرتين سابقاً — لن يظهر لك مجدداً.'
          : 'You withdrew your offer on this request twice before — it will not appear again.');
      return false;
    }
    var allow = _allowance;
    allow ??= await IndividualMarketOfferService(widget.sb).currentAllowance(
      accountType: widget.accountType,
      organizationId: widget.organizationId,
    );
    if (!mounted) return false;
    if (allow.canSubmitNow) return true;

    if (!mounted) return false;
    final ok = await SubscriptionGateHelper.ensure(
      context,
      isAr: widget.isAr,
      action: SubscriptionGateAction.completeMarketDeal,
      onGoSubscribe: () async {
        if (widget.onSubscriptionRequiredForOffer != null) {
          await widget.onSubscriptionRequiredForOffer!();
        }
      },
    );
    if (!ok || !mounted) return false;
    final refreshed =
        await IndividualMarketOfferService(widget.sb).currentAllowance(
      accountType: widget.accountType,
      organizationId: widget.organizationId,
    );
    if (!mounted) return false;
    setState(() => _allowance = refreshed);
    if (!refreshed.canSubmitNow) {
      _toast(
          widget.isAr ? refreshed.shortStatusAr() : refreshed.shortStatusEn());
      return false;
    }
    return true;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _withdrawMyOffer() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(widget.isAr ? 'حذف عرضي' : 'Withdraw my offer'),
        content: Text(
          widget.isAr
              ? 'سيتم سحب عرضك وإعادة الطلب إلى الرئيسية مع ملاحظة أنك سبق وأن قدّمت عرضاً عليه. لا يمكن السحب لو اختارك صاحب الطلب لإتمام الصفقة، وبعد سحبتين على نفس الطلب لن يظهر لك مجدداً.'
              : 'Your offer will be withdrawn and the request will return to Home with a note that you previously offered. Withdrawal is blocked if the requester selected you for the deal; after two withdrawals on the same request it will not show again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(widget.isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(widget.isAr ? 'سحب العرض' : 'Withdraw'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final res = await IndividualMarketOfferService(widget.sb)
        .withdrawMyOffer(widget.row.id);
    if (!mounted) return;
    final ok = res['ok'] == true;
    if (!ok) {
      final code = (res['error'] ?? '').toString();
      _toast(widget.isAr
          ? individualOfferShortReasonAr(code)
          : 'Could not withdraw: $code');
      return;
    }
    widget.onDidChange?.call();
    await Future.wait([
      _reloadOffers(),
      _reloadPriorWithdrawCount(),
    ]);
    if (!mounted) return;
    final isFinal = res['final'] == true;
    _toast(isFinal
        ? (widget.isAr
            ? 'تم السحب. لن يظهر لك هذا الطلب مرة أخرى (الحد سحبتان لكل طلب).'
            : 'Withdrawn. This request will no longer appear (limit: 2 withdrawals per request).')
        : (widget.isAr
            ? 'تم سحب عرضك. سيظهر الطلب في الرئيسية مع علامة «سبق أن قدّمت عرضاً».'
            : 'Offer withdrawn. The request will reappear in Home with a "previously offered" marker.'));
  }

  Future<void> _submitOfferDialog() async {
    if (!_hasMyActiveOffer) {
      final used = await DealCompletionInbox.activeDealCount(widget.sb);
      if (!mounted) return;
      if (DealInventoryPolicy.dealsAtCap(used)) {
        await showDealSlotCapDialog(
          context: context,
          used: used,
          max: DealInventoryPolicy.maxActiveDeals,
        );
        return;
      }
    }
    final allowed = await _ensureOfferAllowanceOrPaywall();
    if (!allowed || !mounted) return;
    final msgCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (dCtx) {
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          title: Text(widget.isAr ? 'إتمام الصفقة' : 'Complete deal'),
          content: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AqarTextField(
                  controller: msgCtrl,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    labelText:
                        widget.isAr ? 'رسالة (اختياري)' : 'Message (optional)',
                    alignLabelWithHint: true,
                  ),
                  minLines: 3,
                  maxLines: 8,
                ),
                const SizedBox(height: 10),
                AqarTextField(
                  controller: priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    const ArabicDigitsToLatinFormatter(),
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: widget.isAr
                        ? 'سعر مقترح (${AppMoney.sarUiSuffix(isAr: true)})'
                        : 'Suggested price (SAR)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: Text(widget.isAr ? 'إلغاء' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dCtx, true),
              child: Text(widget.isAr ? 'إرسال' : 'Send'),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) return;

    if (!widget.row.isInstantPaid &&
        AppRoleHelper.isMarketingAccountType(widget.accountType)) {
      // تسجيل الحصة عند تأكيد الإرسال (حسابات التسويق فقط).
      final usageRes = await IndividualMarketOfferService(widget.sb)
          .recordUsageOnSuccess(widget.row.id);
      if (!mounted) return;
      if (usageRes['ok'] != true) {
        final err = '${usageRes['error'] ?? ''}';
        _toast(widget.isAr ? individualOfferShortReasonAr(err) : 'Quota: $err');
        unawaited(_reloadAllowance());
        return;
      }
      unawaited(_reloadAllowance());
    }

    final svc = MarketRequestOffersService(widget.sb);
    final price = double.tryParse(
      arabicAndPersianDigitsToLatin(priceCtrl.text.trim()).replaceAll(',', ''),
    );
    final message = msgCtrl.text.trim();
    msgCtrl.dispose();
    priceCtrl.dispose();
    final sent = await svc.submitOffer(
      marketRequestId: widget.row.id,
      offerMessage: message,
      priceOffer: price,
    );
    if (!mounted) return;
    if (!sent) {
      await showAppDialog<void>(
        context: context,
        builder: (dCtx) {
          return AlertDialog(
            title: Text(
              widget.isAr ? 'عرض قائم بالفعل' : 'Offer already submitted',
            ),
            content: Text(
              widget.isAr
                  ? 'شريكنا العقاري، لديك صفقة نشطة على هذا الطلب. يمكن للمهتمين الآخرين إتمام صفقات إضافية. إذا احتجت تعديلاً استثنائياً يمكنك التواصل مع الإدارة من تبويب الدعم — وسنراجع الطلب وفق السياسة.'
                  : 'You already have an active deal on this request. Others may still complete deals. If you need an exception (change or new deal), contact administration from the Support tab.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx),
                child: Text(widget.isAr ? 'حسناً' : 'OK'),
              ),
            ],
          );
        },
      );
    } else {
      widget.onDidChange?.call();
      AppHaptics.medium();
      await _reloadOffers();
    }
  }

  Future<void> _respondOffer(String offerId, bool accept) async {
    try {
      await MarketRequestOffersService(widget.sb).respondOffer(
        offerId: offerId,
        accept: accept,
      );
      widget.onDidChange?.call();
      await _reloadOffers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _editRequestDialog() async {
    final changed = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => CreateMarketPropertyRequestPage(
          userId: widget.currentUserId,
          lang: widget.isAr ? 'ar' : 'en',
          initialRequest: widget.row,
          embedAppBar: false,
        ),
      ),
    );
    if (changed == true) {
      widget.onDidChange?.call();
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _requestDeletion() async {
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(widget.isAr ? 'رفع طلب حذف' : 'Request deletion'),
        content: Text(
          widget.isAr
              ? 'سيظهر للآخرين أن الطلب مرفوع للحذف، ولن يُحذف نهائياً إلا بعد موافقة الإدارة.'
              : 'Others will see that deletion was requested. The request is not removed until admin approval.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(widget.isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(widget.isAr ? 'تأكيد' : 'Confirm'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await MarketRequestOffersService(widget.sb)
          .requestDeletion(widget.row.id);
      widget.onDidChange?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isAr
              ? 'تم رفع طلب الحذف وبانتظار الإدارة.'
              : 'Deletion request submitted for admin approval.'),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _completeRequest({String? offerId}) async {
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(widget.isAr ? 'إتمام الصفقة' : 'Complete deal'),
        content: Text(
          widget.isAr
              ? 'سيتم إغلاق الطلب وإخفاؤه من الرئيسية ومن صفقات غير المقبولين.'
              : 'The request will be closed and hidden from Home and unsuccessful offerers.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(widget.isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(widget.isAr ? 'إتمام' : 'Complete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final note = await showDealCompletionNoteSheet(context: context);
    if (note == null || note.trim().isEmpty || !mounted) return;
    try {
      await MarketRequestOffersService(widget.sb).completeRequest(
        requestId: widget.row.id,
        offerId: offerId,
        note: note.trim(),
      );
      widget.onDidChange?.call();
      await _reloadOffers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isAr ? 'تم إتمام الصفقة.' : 'Deal completed.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  String _priorityLabel(BuildContext context, MarketPropertyRequestPriority p) {
    final t = AppLocalizations.of(context);
    if (t == null) return p.wireValue;
    switch (p) {
      case MarketPropertyRequestPriority.flexible:
        return t.marketRequestPriorityFlexible;
      case MarketPropertyRequestPriority.standard:
        return t.marketRequestPriorityStandard;
      case MarketPropertyRequestPriority.priority:
        return t.marketRequestPriorityPriority;
      case MarketPropertyRequestPriority.urgent:
        return t.marketRequestPriorityUrgent;
      case MarketPropertyRequestPriority.immediate:
        return t.marketRequestPriorityImmediate;
    }
  }

  String _offerStatusLabel(String raw) {
    final s = raw.trim().toLowerCase();
    if (widget.isAr) {
      switch (s) {
        case '':
        case 'submitted':
        case 'pending':
          return 'قيد الانتظار';
        case 'accepted':
        case 'approved':
        case 'selected':
          return 'مقبول';
        case 'rejected':
        case 'declined':
          return 'مرفوض';
        case 'completed':
          return 'مكتمل';
        case 'withdrawn':
          return 'مسحوب';
        case 'expired':
          return 'منتهي';
        default:
          return raw.trim();
      }
    }
    switch (s) {
      case '':
      case 'submitted':
      case 'pending':
        return 'Pending';
      case 'accepted':
      case 'approved':
      case 'selected':
        return 'Accepted';
      case 'rejected':
      case 'declined':
        return 'Rejected';
      case 'completed':
        return 'Completed';
      default:
        return raw.trim();
    }
  }

  String _waDigits(String raw) {
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('00')) d = d.substring(2);
    if (d.startsWith('0')) d = d.substring(1);
    if (d.startsWith('966')) return d;
    if (d.length == 9 && d.startsWith('5')) return '966$d';
    return d.isEmpty ? d : '966$d';
  }

  Future<void> _copyOfferPhone(BuildContext context, String raw) async {
    final shown = PhoneDisplay.localTenDigits(raw);
    if (shown.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: shown));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.isAr ? 'تم نسخ رقم الجوال' : 'Phone copied'),
      ),
    );
  }

  Future<void> _openOfferWhatsApp(BuildContext context, String raw) async {
    final digits = _waDigits(raw);
    if (digits.isEmpty) return;
    final uri = Uri.parse('https://wa.me/$digits');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return;
    } catch (_) {}
    try {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isAr ? 'تعذّر فتح واتساب.' : 'Could not open WhatsApp.',
          ),
        ),
      );
    }
  }

  Widget _detailRow(
    BuildContext context, {
    required String label,
    required String value,
    IconData? icon,
    Widget? valueWidget,
    Widget? trailing,
  }) {
    final v = value.trim();
    if (v.isEmpty && valueWidget == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: cs.primary),
            const SizedBox(width: 7),
          ],
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: valueWidget ??
                Text(
                  v,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final row = widget.row;
    final requestStatus = row.status.trim().toLowerCase();
    final isCompleted = requestStatus == 'completed' ||
        requestStatus == 'closed' ||
        requestStatus == 'sold';
    final deletionRequested =
        requestStatus == 'delete_requested' || row.deletionRequestedAt != null;
    final remainingEdits =
        (row.maxEdits - row.editCount).clamp(0, row.maxEdits);
    String acceptedOfferId = (row.selectedOfferId ?? '').trim();
    if (acceptedOfferId.isEmpty) {
      for (final o in _offers) {
        final st = (o['status'] ?? '').toString().trim().toLowerCase();
        if (DealMessagingGate.offerApprovedByOwner(st)) {
          acceptedOfferId = (o['id'] ?? '').toString().trim();
          break;
        }
      }
    }
    final hasAcceptedOffer = acceptedOfferId.isNotEmpty;
    final headline =
        PropertyListingDisplay.displayRequestTitle(row, widget.isAr);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.of(context).viewPadding.bottom +
            AppKeyboardInset.bottomOf(context) +
            20,
      ),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              headline,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Cairo',
                    height: 1.25,
                  ),
            ),
            const SizedBox(height: 10),
            if (isCompleted || deletionRequested) ...[
              Material(
                color: isCompleted
                    ? Colors.green.withValues(alpha: 0.12)
                    : cs.errorContainer.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    isCompleted
                        ? (widget.isAr
                            ? 'تمت الصفقة على هذا الطلب، لذلك تم إيقاف الأزرار التفاعلية.'
                            : 'This request deal is completed, so interactive actions are disabled.')
                        : (widget.isAr
                            ? 'تم رفع طلب حذف لهذا الطلب وهو بانتظار موافقة الإدارة.'
                            : 'Deletion was requested for this request and is pending admin approval.'),
                    style: TextStyle(
                      color: isCompleted
                          ? Colors.green.shade800
                          : cs.onErrorContainer,
                      fontWeight: FontWeight.w900,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (_guest && !_isOwner && !isCompleted && !deletionRequested) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  final nav = Navigator.of(context);
                  if (row.isInstantPaid) {
                    final choice = await showGuestInstantDealAuthSheet(
                      context: context,
                      isAr: widget.isAr,
                    );
                    if (!mounted) return;
                    if (choice == GuestAuthRequiredResult.login) {
                      nav.pop();
                      widget.onGuestRequiresAuth?.call();
                    } else if (choice == GuestAuthRequiredResult.register) {
                      nav.pop();
                      if (!context.mounted) return;
                      await Navigator.of(context, rootNavigator: true)
                          .pushNamed('/register');
                    }
                    return;
                  }
                  final choice = await showGuestHomeOfferGateSheet(
                    context: context,
                    isAr: widget.isAr,
                  );
                  if (!mounted) return;
                  if (choice == GuestHomeOfferGateResult.login) {
                    nav.pop();
                    widget.onGuestRequiresAuth?.call();
                  } else if (choice == GuestHomeOfferGateResult.register) {
                    nav.pop();
                    if (!context.mounted) return;
                    await Navigator.of(context, rootNavigator: true)
                        .pushNamed('/register');
                  } else if (choice == GuestHomeOfferGateResult.payOnce) {
                    nav.pop();
                    if (widget.onGuestPayOfferUnlock != null) {
                      await widget.onGuestPayOfferUnlock!();
                    }
                  }
                },
                icon: const Icon(Icons.local_offer_outlined),
                label: Text(widget.isAr ? 'إتمام الصفقة' : 'Complete deal'),
              ),
            ],
            const SizedBox(height: 12),
            if (row.isInstantPaid) ...[
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: InstantMarketRequestBadge(
                  isAr: widget.isAr,
                  compact: true,
                ),
              ),
              const SizedBox(height: 10),
            ],
            _MarketRequestFactsGrid(
              isAr: widget.isAr,
              rows: [
                for (final f in MarketRequestDetailFacts.build(
                  row,
                  isAr: widget.isAr,
                  l10n: AppLocalizations.of(context),
                ))
                  _MarketRequestFact(
                    icon: f.icon,
                    label: f.label,
                    value: f.value,
                    copyText: f.copyText,
                  ),
              ],
              amount: ((row.budgetMin ?? 0) > 0 || (row.budgetMax ?? 0) > 0)
                  ? _MarketRequestSpecifiedAmountCard(
                      isAr: widget.isAr,
                      min: row.budgetMin,
                      max: row.budgetMax,
                    )
                  : null,
            ),
            if ((row.description ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                widget.isAr ? 'التفاصيل' : 'Details',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                row.description!.trim(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
            const SizedBox(height: 16),
            if (!_guest && !_isOwner && !deletionRequested) ...[
              if (_canContactRequester) ...[
                if ((_requesterPhone ?? '').trim().isNotEmpty) ...[
                  _detailRow(
                    context,
                    label: widget.isAr ? 'رقم صاحب الطلب' : 'Requester phone',
                    value: _requesterPhone!.trim(),
                    icon: Icons.phone_outlined,
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton.icon(
                  onPressed: () => unawaited(_openChat()),
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: Text(
                    widget.isAr ? 'مراسلة صاحب الطلب' : 'Message requester',
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (!isCompleted &&
                  !_hasMyActiveOffer &&
                  !_mySelectedForDeal) ...[
                if (_myPriorWithdrawCount == 1) ...[
                  const SizedBox(height: 8),
                  Material(
                    color: cs.tertiaryContainer.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.history_toggle_off,
                              color: cs.onTertiaryContainer),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.isAr
                                  ? 'سبق أن أتممت صفقة على هذا الطلب ثم حذفتها. يمكنك إتمام صفقة جديدة (يُحتسب من حصتك). الحذف الثاني نهائي ولن يظهر لك الطلب مجدداً.'
                                  : 'You previously offered on this request and withdrew. You can offer again (counts toward your quota). A second withdrawal hides the request permanently.',
                              style: TextStyle(
                                color: cs.onTertiaryContainer,
                                fontWeight: FontWeight.w800,
                                height: 1.3,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _myPriorWithdrawCount >= 2
                      ? null
                      : () => unawaited(_submitOfferDialog()),
                  icon: const Icon(Icons.local_offer_outlined),
                  label: Text(widget.isAr ? 'إتمام الصفقة' : 'Complete deal'),
                ),
              ] else if (!isCompleted &&
                  (_hasMyActiveOffer || _mySelectedForDeal)) ...[
                const SizedBox(height: 8),
                // بدل الرسالة المختصرة — بطاقة سياسة كاملة للمسوّقين بعد تقديم
                // العرض على الطلب: تشرح خطوات منع التواصل قبل القبول، التعاقد،
                // ثم 72 ساعة لاستخراج التصاريح والنشر.
                MarketerPolicyNoticeCard(
                  isAr: widget.isAr,
                  stageHint: _mySelectedForDeal
                      ? MarketerPolicyStage.contractPending
                      : MarketerPolicyStage.afterOffer,
                ),
                const SizedBox(height: 8),
                if (_mySelectedForDeal)
                  Material(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        widget.isAr
                            ? 'تم اختيارك لإتمام الصفقة، لذلك زر حذف العرض معطّل التزاماً بحقوق صاحب الطلب.'
                            : 'You were selected to complete this deal, so withdraw is disabled out of fairness to the requester.',
                        style: TextStyle(
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.w800,
                          height: 1.35,
                        ),
                      ),
                    ),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () => unawaited(_withdrawMyOffer()),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(widget.isAr
                        ? (_myPriorWithdrawCount >= 1
                            ? 'حذف عرضي (الأخير — لن يظهر مجدداً)'
                            : 'حذف عرضي')
                        : (_myPriorWithdrawCount >= 1
                            ? 'Withdraw (final — hides request)'
                            : 'Withdraw my offer')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.error,
                      side: BorderSide(color: cs.error.withValues(alpha: 0.5)),
                    ),
                  ),
              ] else if (isCompleted && !_canContactRequester) ...[
                Material(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      widget.isAr
                          ? 'تم إتمام الصفقة، ولا يمكن إتمام صفقة جديدة.'
                          : 'The deal is completed; new offers are closed.',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ],
            ] else if (!_guest && !_isOwner && deletionRequested) ...[
              Material(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    widget.isAr
                        ? 'هذا الطلب بانتظار حذف إداري، ولا يمكن إتمام صفقة جديدة.'
                        : 'This request is pending admin deletion; new offers are closed.',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ],
            if (!_guest && _isOwner) ...[
              Material(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.isAr
                            ? 'إدارة الطلب: المتبقي من التعديلات $remainingEdits من ${row.maxEdits}'
                            : 'Request management: $remainingEdits of ${row.maxEdits} edits remaining',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: isCompleted ||
                                    deletionRequested ||
                                    remainingEdits <= 0
                                ? null
                                : () => unawaited(_editRequestDialog()),
                            icon: const Icon(Icons.edit_outlined),
                            label: Text(widget.isAr ? 'تعديل' : 'Edit'),
                          ),
                          OutlinedButton.icon(
                            onPressed: isCompleted || deletionRequested
                                ? null
                                : () => unawaited(_requestDeletion()),
                            icon: const Icon(Icons.delete_outline),
                            label: Text(widget.isAr
                                ? 'رفع طلب حذف'
                                : 'Request deletion'),
                          ),
                          if (!isCompleted && !deletionRequested)
                            FilledButton.icon(
                              onPressed: hasAcceptedOffer
                                  ? () => unawaited(
                                        _completeRequest(
                                          offerId: acceptedOfferId,
                                        ),
                                      )
                                  : null,
                              icon: const Icon(Icons.done_all_outlined),
                              label: Text(widget.isAr
                                  ? 'إتمام الصفقة'
                                  : 'Complete deal'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.isAr ? 'العروض والمراسلات' : 'Offers & chats',
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              const SizedBox(height: 8),
              if (_loadingOffers)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                ))
              else if (_offersErr != null)
                Text(
                  _offersErr!,
                  style: TextStyle(color: cs.error, fontSize: 12),
                )
              else if (_offers.isEmpty)
                Text(
                  widget.isAr ? 'لا عروض بعد' : 'No offers yet',
                  style: TextStyle(color: cs.onSurfaceVariant),
                )
              else
                ..._offers.map((o) {
                  final oid = (o['id'] ?? '').toString();
                  final st = (o['status'] ?? '').toString();
                  final offerer = (o['offerer_id'] ?? '').toString();
                  final price = o['price_offer'];
                  final priceValue = price is num
                      ? price.toDouble()
                      : double.tryParse(
                          arabicAndPersianDigitsToLatin(
                            price?.toString().trim() ?? '',
                          ).replaceAll(',', ''),
                        );
                  final msg = (o['message'] ?? '').toString().trim();
                  final disp =
                      (o['_offerer_display_name'] ?? '').toString().trim();
                  final acc =
                      (o['_offerer_account_type'] ?? '').toString().trim();
                  final av = (o['_offerer_avatar_url'] ?? '').toString().trim();
                  final phone = (o['_offerer_phone'] ?? '').toString().trim();
                  final city = (o['_offerer_city'] ?? '').toString().trim();
                  final license =
                      (o['_offerer_license_no'] ?? '').toString().trim();
                  final createdAt = DateTime.tryParse(
                    (o['created_at'] ?? '').toString(),
                  );
                  final localCreated = createdAt?.toLocal();
                  final createdDate = localCreated == null
                      ? ''
                      : DateHelper.fmtCivilDate(
                          localCreated,
                          isAr: widget.isAr,
                        );
                  final createdTime = localCreated == null
                      ? ''
                      : DateHelper.fmtClock(localCreated);
                  final accepted = DealMessagingGate.offerApprovedByOwner(st) ||
                      (acceptedOfferId.isNotEmpty &&
                          oid.trim() == acceptedOfferId);
                  final pending = st.toLowerCase() == 'submitted' ||
                      st.toLowerCase() == 'pending' ||
                      st.trim().isEmpty;
                  final rejected = st.toLowerCase() == 'rejected' ||
                      st.toLowerCase() == 'declined';
                  final nameLine = disp.isNotEmpty
                      ? disp
                      : (widget.isAr ? 'مستخدم عقاري' : 'Real estate user');
                  final roleLine = ChatPeerService.accountTypeLabel(
                    acc,
                    widget.isAr,
                  );
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor:
                                    cs.primaryContainer.withValues(alpha: 0.9),
                                backgroundImage: av.isNotEmpty
                                    ? CachedNetworkImageProvider(av)
                                    : null,
                                child: av.isEmpty
                                    ? Text(
                                        chatAvatarInitialLetter(nameLine),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 18,
                                          color: cs.onPrimaryContainer,
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
                                      nameLine,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      roleLine,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _detailRow(
                            context,
                            label: widget.isAr ? 'الحالة' : 'Status',
                            value: _offerStatusLabel(st),
                            icon: Icons.verified_outlined,
                          ),
                          _detailRow(
                            context,
                            label: widget.isAr ? 'تاريخ التقديم' : 'Date',
                            value: createdDate,
                            icon: Icons.calendar_today_outlined,
                          ),
                          _detailRow(
                            context,
                            label: widget.isAr ? 'وقت التقديم' : 'Time',
                            value: createdTime,
                            icon: Icons.schedule_outlined,
                          ),
                          _detailRow(
                            context,
                            label: widget.isAr ? 'الصفة' : 'Role',
                            value: roleLine,
                            icon: Icons.badge_outlined,
                          ),
                          _detailRow(
                            context,
                            label: widget.isAr ? 'المدينة' : 'City',
                            value: city,
                            icon: Icons.location_city_outlined,
                          ),
                          if (PhoneDisplay.localTenDigits(phone).isNotEmpty)
                            _detailRow(
                              context,
                              label: widget.isAr ? 'التواصل' : 'Contact',
                              value: PhoneDisplay.localTenDigits(phone),
                              icon: Icons.phone_outlined,
                              valueWidget: Text(
                                PhoneDisplay.forUi(phone, isAr: widget.isAr),
                                textDirection: TextDirection.ltr,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  height: 1.25,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: widget.isAr
                                        ? 'نسخ الرقم'
                                        : 'Copy number',
                                    icon: const Icon(Icons.copy_rounded,
                                        size: 18),
                                    onPressed: () => unawaited(
                                        _copyOfferPhone(context, phone)),
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: widget.isAr
                                        ? 'فتح واتساب'
                                        : 'Open WhatsApp',
                                    icon: const Icon(Icons.chat_rounded,
                                        size: 18, color: Color(0xFF25D366)),
                                    onPressed: () => unawaited(
                                      _openOfferWhatsApp(context, phone),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          _detailRow(
                            context,
                            label: widget.isAr ? 'الترخيص' : 'License',
                            value: license,
                            icon: Icons.verified_user_outlined,
                          ),
                          if (priceValue != null)
                            _detailRow(
                              context,
                              label: widget.isAr ? 'السعر' : 'Price',
                              value: AppMoney.formatNumber(
                                priceValue,
                                isAr: widget.isAr,
                                maxFractionDigits: 0,
                              ),
                              valueWidget: AppMoneyInline(
                                amountText: AppMoney.formatNumber(
                                  priceValue,
                                  isAr: widget.isAr,
                                  maxFractionDigits: 0,
                                ),
                                isAr: widget.isAr,
                              ),
                              icon: Icons.payments_outlined,
                            ),
                          _detailRow(
                            context,
                            label: widget.isAr ? 'الرسالة' : 'Message',
                            value: msg,
                            icon: Icons.notes_outlined,
                          ),
                          const SizedBox(height: 8),
                          if (accepted)
                            Material(
                              color: Colors.green.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Text(
                                  AppLocalizations.of(context)
                                          ?.dealOwnerAcceptedPartner ??
                                      (widget.isAr
                                          ? 'تم اختيار هذا العرض لإتمام الصفقة. ستختفي إجراءات القبول من بقية العروض.'
                                          : 'This offer was selected to complete the deal. Accept actions are hidden for other offers.'),
                                  style: TextStyle(
                                    color: Colors.green.shade800,
                                    fontWeight: FontWeight.w900,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            )
                          else if (pending && hasAcceptedOffer)
                            Text(
                              AppLocalizations.of(context)
                                      ?.dealStayPendingUntilCancel ??
                                  (widget.isAr
                                      ? 'تم اختيار شريك آخر. تبقى هذه الصفقة معلّقة حتى تلغيها أو حتى يتم إتمام البيع.'
                                      : 'Another partner was selected. This deal stays pending until cancelled or the sale completes.'),
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w800,
                                height: 1.35,
                              ),
                            ),
                          if (rejected)
                            Text(
                              widget.isAr
                                  ? 'لم يتم اختيار هذا العرض.'
                                  : 'This offer was not selected.',
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          const SizedBox(height: 8),
                          LayoutBuilder(
                            builder: (context, c) {
                              final narrow = c.maxWidth < 420;
                              final buttons = <Widget>[
                                if (accepted)
                                  OutlinedButton.icon(
                                    onPressed: () => unawaited(
                                      _openChat(counterpartyId: offerer),
                                    ),
                                    icon: const Icon(Icons.chat_bubble_outline),
                                    label: Text(
                                      widget.isAr ? 'مراسلة' : 'Message',
                                    ),
                                  ),
                                if (!isCompleted &&
                                    !deletionRequested &&
                                    pending &&
                                    !hasAcceptedOffer) ...[
                                  FilledButton.icon(
                                    onPressed: () =>
                                        unawaited(_respondOffer(oid, true)),
                                    icon:
                                        const Icon(Icons.check_circle_outline),
                                    label: Text(
                                      AppLocalizations.of(context)
                                              ?.dealOwnerAcceptPartner ??
                                          (widget.isAr ? 'قبول' : 'Accept'),
                                    ),
                                  ),
                                ] else if (!isCompleted &&
                                    !deletionRequested &&
                                    accepted) ...[
                                  FilledButton.icon(
                                    onPressed: () => unawaited(
                                      _completeRequest(offerId: oid),
                                    ),
                                    icon: const Icon(Icons.done_all_outlined),
                                    label: Text(
                                      AppLocalizations.of(context)
                                              ?.dealCompleteWithPartner ??
                                          (widget.isAr
                                              ? 'إتمام الصفقة'
                                              : 'Complete deal'),
                                    ),
                                  ),
                                ],
                              ];
                              if (buttons.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              if (narrow) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (var i = 0;
                                        i < buttons.length;
                                        i++) ...[
                                      buttons[i],
                                      if (i != buttons.length - 1)
                                        const SizedBox(height: 8),
                                    ],
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  for (var i = 0; i < buttons.length; i++) ...[
                                    Expanded(child: buttons[i]),
                                    if (i != buttons.length - 1)
                                      const SizedBox(width: 8),
                                  ],
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(widget.isAr ? 'إغلاق' : 'Close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarketRequestFact {
  const _MarketRequestFact({
    required this.icon,
    required this.label,
    required this.value,
    this.copyText,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? copyText;
}

class _MarketRequestSpecifiedAmountCard extends StatelessWidget {
  const _MarketRequestSpecifiedAmountCard({
    required this.isAr,
    required this.min,
    required this.max,
  });

  final bool isAr;
  final double? min;
  final double? max;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
          color: cs.surface.withValues(alpha: 0.55),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.payments_outlined, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isAr ? 'المبلغ المحدد' : 'Specified amount',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        height: 1.2,
                        color: cs.onSurfaceVariant,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SpecifiedBudgetLine(
                min: min,
                max: max,
                isAr: isAr,
                showCaption: false,
                alignEnd: true,
                fontSize: 18,
                color: cs.onSurface,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarketRequestFactsGrid extends StatelessWidget {
  const _MarketRequestFactsGrid({
    required this.isAr,
    required this.rows,
    required this.amount,
  });

  final bool isAr;
  final List<_MarketRequestFact> rows;
  final Widget? amount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final w = MediaQuery.sizeOf(context).width;
    final twoCol = w >= 720;
    final cells = [
      if (amount != null) amount!,
      ...rows.map((r) => _factCell(context, r)),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withValues(alpha: 0.45)),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isAr ? 'تفاصيل الطلب' : 'Request details',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.primary,
                    fontFamily: 'Cairo',
                  ),
            ),
            const SizedBox(height: 10),
            if (!twoCol)
              ...cells
            else
              ..._pairs(cells).map(
                (pair) => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: pair.$1),
                    const SizedBox(width: 8),
                    Expanded(child: pair.$2 ?? const SizedBox.shrink()),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<(Widget, Widget?)> _pairs(List<Widget> items) {
    final out = <(Widget, Widget?)>[];
    for (var i = 0; i < items.length; i += 2) {
      out.add((items[i], i + 1 < items.length ? items[i + 1] : null));
    }
    return out;
  }

  Widget _factCell(BuildContext context, _MarketRequestFact fact) {
    final cs = Theme.of(context).colorScheme;
    final canCopy = (fact.copyText ?? '').trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
          color: cs.surface.withValues(alpha: 0.55),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(fact.icon, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: Text(
                  fact.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    height: 1.3,
                    color: cs.onSurfaceVariant,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 7,
                child: Text(
                  fact.value,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  textAlign: isAr ? TextAlign.right : TextAlign.left,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    height: 1.35,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
              if (canCopy)
                IconButton(
                  tooltip: isAr ? 'نسخ' : 'Copy',
                  visualDensity: VisualDensity.compact,
                  constraints:
                      const BoxConstraints.tightFor(width: 32, height: 32),
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  icon: Icon(Icons.copy_rounded, color: cs.primary),
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: fact.copyText!.trim()),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        behavior: SnackBarBehavior.floating,
                        content: Text(isAr ? 'تم النسخ' : 'Copied'),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
