import 'dart:async' show unawaited;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/haptics/app_haptics.dart';
import '../core/utils/chat_display_initials.dart';
import '../core/input/saudi_input_formatters.dart';
import '../core/listing/property_type_catalog.dart';
import '../core/utils/app_money.dart';
import '../l10n/app_localizations.dart';
import '../models/market_property_request_priority.dart';
import '../models/market_property_request_row.dart';
import '../navigation/chat_navigation.dart';
import '../screens/create_market_property_request_page.dart';
import '../services/market_request_offers_service.dart';
import '../services/reservations_service.dart';

/// تفاصيل طلب السوق من الرئيسية + عروض + محادثة (بعد تطبيق SQL v20260411).
Future<void> showMarketRequestHomeSheet({
  required BuildContext context,
  required MarketPropertyRequestRow row,
  required bool isAr,
  required SupabaseClient sb,
  required String currentUserId,
  bool autoOpenSubmitOffer = false,
  VoidCallback? onDidChange,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) {
      return _MarketRequestSheetBody(
        row: row,
        isAr: isAr,
        sb: sb,
        currentUserId: currentUserId,
        autoOpenSubmitOffer: autoOpenSubmitOffer,
        onDidChange: onDidChange,
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
  });

  final MarketPropertyRequestRow row;
  final bool isAr;
  final SupabaseClient sb;
  final String currentUserId;
  final bool autoOpenSubmitOffer;
  final VoidCallback? onDidChange;

  @override
  State<_MarketRequestSheetBody> createState() =>
      _MarketRequestSheetBodyState();
}

class _MarketRequestSheetBodyState extends State<_MarketRequestSheetBody> {
  bool _loadingOffers = true;
  List<Map<String, dynamic>> _offers = const [];
  String? _offersErr;
  bool _autoOfferPromptConsumed = false;

  bool get _guest =>
      widget.currentUserId.isEmpty || widget.currentUserId == 'guest';
  bool get _isOwner =>
      widget.currentUserId.isNotEmpty &&
      widget.currentUserId != 'guest' &&
      widget.currentUserId == widget.row.requesterId;
  bool get _hasMyActiveOffer {
    if (_guest || _isOwner) return false;
    return _offers.any((o) {
      final uid = (o['offerer_id'] ?? '').toString().trim();
      if (uid != widget.currentUserId) return false;
      final st = (o['status'] ?? '').toString().trim().toLowerCase();
      return st.isEmpty || st == 'submitted' || st == 'pending';
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(_reloadOffers());
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
    try {
      final added = await MarketRequestOffersService(widget.sb).submitOffer(
        marketRequestId: widget.row.id,
        offerMessage: message,
      );
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

  Future<void> _openChat({String? counterpartyId}) async {
    if (_guest) return;
    try {
      if (!_isOwner) {
        await _ensureRequestInMyDeals();
      }
      final cid =
          await ReservationsService.getOrCreateMarketRequestConversation(
        marketRequestId: widget.row.id,
        counterpartyId: counterpartyId,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      await Navigator.of(context).push<void>(
        ChatNavigation.materialRoute(
          isAr: widget.isAr,
          conversationId: cid,
          marketRequestId: widget.row.id,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _submitOfferDialog() async {
    final msgCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) {
        return AlertDialog(
          title: Text(widget.isAr ? 'تقديم عرض' : 'Submit offer'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: msgCtrl,
                  decoration: InputDecoration(
                    labelText:
                        widget.isAr ? 'رسالة (اختياري)' : 'Message (optional)',
                  ),
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: priceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    ArabicDigitsToLatinFormatter(),
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: widget.isAr
                        ? 'سعر مقترح (${AppMoney.saudiRiyalSignUnicode})'
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
      await showDialog<void>(
        context: context,
        builder: (dCtx) {
          return AlertDialog(
            title: Text(
              widget.isAr ? 'عرض قائم بالفعل' : 'Offer already submitted',
            ),
            content: Text(
              widget.isAr
                  ? 'شريكنا العقاري، لديك عرض نشط على هذا الطلب. يمكن للمهتمين الآخرين تقديم عروض إضافية. إذا احتجت تعديلاً استثنائياً يمكنك التواصل مع الإدارة من تبويب الدعم — وسنراجع الطلب وفق السياسة.'
                  : 'You already have an active offer on this request. Others may still submit offers. If you need an exception (change or new offer), contact administration from the Support tab.',
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
      if (message.isNotEmpty) {
        try {
          final cid =
              await ReservationsService.getOrCreateMarketRequestConversation(
            marketRequestId: widget.row.id,
          );
          final requesterId = widget.row.requesterId.trim();
          if (requesterId.isNotEmpty && requesterId != widget.currentUserId) {
            await widget.sb.from('messages').insert({
              'sender_id': widget.currentUserId,
              'receiver_id': requesterId,
              'conversation_id': cid,
              'content': message,
            });
          }
        } catch (_) {
          // The offer itself is already saved; chat sync is best-effort.
        }
      }
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
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => CreateMarketPropertyRequestPage(
          userId: widget.currentUserId,
          lang: widget.isAr ? 'ar' : 'en',
          initialRequest: widget.row,
        ),
      ),
    );
    if (changed == true) {
      widget.onDidChange?.call();
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _requestDeletion() async {
    final ok = await showDialog<bool>(
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
    final ok = await showDialog<bool>(
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
    try {
      await MarketRequestOffersService(widget.sb).completeRequest(
        requestId: widget.row.id,
        offerId: offerId,
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

  Widget _detailRow(
    BuildContext context, {
    required String label,
    required String value,
    IconData? icon,
  }) {
    final v = value.trim();
    if (v.isEmpty) return const SizedBox.shrink();
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
            child: Text(
              v,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
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
    String acceptedOfferId = '';
    for (final o in _offers) {
      final st = (o['status'] ?? '').toString().trim().toLowerCase();
      if (st == 'accepted' || st == 'approved' || st == 'selected') {
        acceptedOfferId = (o['id'] ?? '').toString().trim();
        break;
      }
    }
    final hasAcceptedOffer = acceptedOfferId.isNotEmpty;
    final purposeLabel = switch (row.purpose) {
      'rent' => widget.isAr ? 'إيجار' : 'Rent',
      _ => widget.isAr ? 'شراء' : 'Purchase',
    };
    final typeLabel = PropertyTypeCatalog.label(row.propertyType, widget.isAr);
    final districts = row.districts.isEmpty
        ? (widget.isAr ? 'غير محدد' : 'Not specified')
        : row.districts.join(widget.isAr ? '، ' : ', ');

    String? budgetLine;
    if (row.budgetMin != null || row.budgetMax != null) {
      final a = row.budgetMin;
      final b = row.budgetMax;
      if (a != null && b != null) {
        final sa = AppMoney.formatWithCurrencyCode(
          a,
          isAr: widget.isAr,
          maxFractionDigits: 0,
        );
        final sMax = AppMoney.formatWithCurrencyCode(
          b,
          isAr: widget.isAr,
          maxFractionDigits: 0,
        );
        budgetLine =
            widget.isAr ? 'الميزانية: $sa – $sMax' : 'Budget: $sa – $sMax';
      } else {
        final v = (a ?? b)!;
        final sv = AppMoney.formatWithCurrencyCode(
          v,
          isAr: widget.isAr,
          maxFractionDigits: 0,
        );
        budgetLine = widget.isAr ? 'الميزانية: $sv' : 'Budget: $sv';
      }
    }

    String? areaLine;
    if (row.areaMinM2 != null) {
      areaLine = widget.isAr
          ? 'المساحة من: ${row.areaMinM2!.toStringAsFixed(0)} م²'
          : 'Area from: ${row.areaMinM2!.toStringAsFixed(0)} m²';
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.of(context).viewPadding.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              row.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
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
            Material(
              color: cs.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.forum_outlined, color: cs.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.isAr
                            ? 'يمكن لعدة مهتمين تقديم عروض. تُنشأ لكل طرف محادثة خاصة مع صاحب الطلب عبر «دردشة» — وليست غرفة جماعية واحدة.'
                            : 'Multiple people can submit offers. Each party gets a private chat with the requester via «Chat» — there is no single group room.',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    _priorityLabel(context, row.requestPriority),
                  ),
                ),
                Chip(label: Text(purposeLabel)),
                Chip(label: Text(typeLabel)),
                Chip(label: Text(row.city)),
              ],
            ),
            if (row.showRequesterName &&
                (row.requesterPublicName ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.person_outline, color: cs.primary),
                title: Text(widget.isAr ? 'منشئ الطلب' : 'Request creator'),
                subtitle: Text(row.requesterPublicName!.trim()),
              ),
            ],
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.location_on_outlined, color: cs.primary),
              title: Text(widget.isAr ? 'الأحياء' : 'Districts'),
              subtitle: Text(districts),
            ),
            if (budgetLine != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.payments_outlined, color: cs.primary),
                title: Text(widget.isAr ? 'الميزانية' : 'Budget'),
                subtitle: Text(budgetLine),
              ),
            if (areaLine != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.square_foot_outlined, color: cs.primary),
                title: Text(widget.isAr ? 'المساحة' : 'Area'),
                subtitle: Text(areaLine),
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
            if (!_guest && !_isOwner && !isCompleted && !deletionRequested) ...[
              FilledButton.icon(
                onPressed: () => unawaited(_openChat()),
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text(
                  widget.isAr ? 'مراسلة صاحب الطلب' : 'Message requester',
                ),
              ),
              if (!_hasMyActiveOffer) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => unawaited(_submitOfferDialog()),
                  icon: const Icon(Icons.local_offer_outlined),
                  label: Text(widget.isAr ? 'تقديم عرض' : 'Submit offer'),
                ),
              ] else ...[
                const SizedBox(height: 8),
                Material(
                  color: cs.secondaryContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      widget.isAr
                          ? 'لديك عرض نشط على هذا الطلب، لذلك لا يظهر زر تقديم عرض مرة أخرى.'
                          : 'You already have an active offer on this request, so Submit offer is hidden.',
                      style: TextStyle(
                        color: cs.onSecondaryContainer,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ],
            ] else if (!_guest &&
                !_isOwner &&
                (isCompleted || deletionRequested)) ...[
              Material(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    isCompleted
                        ? (widget.isAr
                            ? 'تم إتمام الصفقة، ولا يمكن تقديم عرض جديد.'
                            : 'The deal is completed; new offers are closed.')
                        : (widget.isAr
                            ? 'هذا الطلب بانتظار حذف إداري، ولا يمكن تقديم عرض جديد.'
                            : 'This request is pending admin deletion; new offers are closed.'),
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
                      : MaterialLocalizations.of(context)
                          .formatShortDate(localCreated);
                  final createdTime = localCreated == null
                      ? ''
                      : MaterialLocalizations.of(context).formatTimeOfDay(
                          TimeOfDay.fromDateTime(localCreated),
                        );
                  final accepted = st.toLowerCase() == 'accepted' ||
                      st.toLowerCase() == 'approved' ||
                      st.toLowerCase() == 'selected';
                  final rejected = st.toLowerCase() == 'rejected' ||
                      st.toLowerCase() == 'declined';
                  final nameLine = disp.isNotEmpty
                      ? disp
                      : (widget.isAr ? 'شريكنا المهتم' : 'Interested partner');
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
                                      widget.isAr
                                          ? 'شريكنا المهتم'
                                          : 'Interested partner',
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
                            value: acc,
                            icon: Icons.badge_outlined,
                          ),
                          _detailRow(
                            context,
                            label: widget.isAr ? 'المدينة' : 'City',
                            value: city,
                            icon: Icons.location_city_outlined,
                          ),
                          _detailRow(
                            context,
                            label: widget.isAr ? 'التواصل' : 'Contact',
                            value: phone,
                            icon: Icons.phone_outlined,
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
                              value: AppMoney.formatWithCurrencyCode(
                                priceValue,
                                isAr: widget.isAr,
                                maxFractionDigits: 0,
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
                                  widget.isAr
                                      ? 'تم اختيار هذا العرض لإتمام الصفقة. ستختفي إجراءات القبول من بقية العروض.'
                                      : 'This offer was selected to complete the deal. Accept actions are hidden for other offers.',
                                  style: TextStyle(
                                    color: Colors.green.shade800,
                                    fontWeight: FontWeight.w900,
                                    height: 1.35,
                                  ),
                                ),
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
                                OutlinedButton.icon(
                                  onPressed: () => unawaited(
                                    _openChat(counterpartyId: offerer),
                                  ),
                                  icon: const Icon(Icons.chat_bubble_outline),
                                  label: Text(widget.isAr ? 'محادثة' : 'Chat'),
                                ),
                                if (!isCompleted &&
                                    !deletionRequested &&
                                    (st.toLowerCase() == 'submitted' ||
                                        st.toLowerCase() == 'pending')) ...[
                                  FilledButton.icon(
                                    onPressed: () =>
                                        unawaited(_respondOffer(oid, true)),
                                    icon:
                                        const Icon(Icons.check_circle_outline),
                                    label:
                                        Text(widget.isAr ? 'قبول' : 'Accept'),
                                  ),
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: cs.errorContainer,
                                      foregroundColor: cs.onErrorContainer,
                                    ),
                                    onPressed: () =>
                                        unawaited(_respondOffer(oid, false)),
                                    icon: const Icon(Icons.close),
                                    label: Text(widget.isAr ? 'رفض' : 'Reject'),
                                  ),
                                ] else if (!isCompleted &&
                                    !deletionRequested &&
                                    accepted) ...[
                                  FilledButton.icon(
                                    onPressed: () => unawaited(
                                      _completeRequest(offerId: oid),
                                    ),
                                    icon: const Icon(Icons.done_all_outlined),
                                    label: Text(widget.isAr
                                        ? 'إتمام الصفقة'
                                        : 'Complete deal'),
                                  ),
                                ],
                              ];
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
