import 'package:flutter/material.dart';
import 'package:aqar_user/core/gestures/app_keyboard_popups.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/listing/offer_identity_tag.dart';
import '../core/l10n/locale_content.dart';
import '../core/profile/publisher_identity_prefs.dart';
import '../core/utils/users_profiles_safe_select.dart';
import '../core/workflow/listing_stage_ui_helper.dart';
import '../core/workflow/listing_workflow_copy.dart';
import '../core/workflow/listing_workflow_stage.dart';
import '../core/workflow/listing_workflow_unified.dart';
import '../core/workflow/workflow_display_texts.dart';
import '../l10n/app_localizations.dart';
import '../services/marketing_flow_service.dart';
import 'app_logo_loading.dart';
import 'listing/request_summary_table.dart';

String _formatTrackDate(DateTime? dt, bool isAr) {
  if (dt == null) return '—';
  return WorkflowDisplayTexts.formatDateTime(dt.toLocal(), isAr);
}

DateTime? _parseDt(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}

/// زر/قائمة: يفتح تتبّع طلب التسويق للمالك أو المسوّق حسب الدور.
Future<void> showListingMarketingTrackingSheet({
  required BuildContext context,
  required SupabaseClient sb,
  required String requestId,
  required bool isAr,
  required String viewerUserId,
}) async {
  final rid = requestId.trim();
  if (rid.isEmpty) return;
  await showAppModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.94,
        minChildSize: 0.45,
        maxChildSize: 0.98,
        builder: (_, scrollCtrl) {
          return ListingMarketingTrackingBody(
            sb: sb,
            requestId: rid,
            isAr: isAr,
            viewerUserId: viewerUserId.trim(),
            scrollController: scrollCtrl,
          );
        },
      );
    },
  );
}

class ListingMarketingTrackingBody extends StatefulWidget {
  const ListingMarketingTrackingBody({
    super.key,
    required this.sb,
    required this.requestId,
    required this.isAr,
    required this.viewerUserId,
    this.scrollController,
  });

  final SupabaseClient sb;
  final String requestId;
  final bool isAr;
  final String viewerUserId;
  final ScrollController? scrollController;

  @override
  State<ListingMarketingTrackingBody> createState() =>
      _ListingMarketingTrackingBodyState();
}

class _ListingMarketingTrackingBodyState
    extends State<ListingMarketingTrackingBody> {
  late final Future<Map<String, dynamic>> _future;
  Map<String, String>? _selectedMarketerName;
  bool _loadErrorSnackShown = false;

  @override
  void initState() {
    super.initState();
    _future = MarketingFlowService(widget.sb).getRequestTrackingBundle(
      widget.requestId,
      viewerUserId: widget.viewerUserId,
      preferArabicNames: widget.isAr,
    );
  }

  Future<void> _maybeLoadSelectedMarketer(Map<String, dynamic>? req) async {
    if (req == null || _selectedMarketerName != null) return;
    final sid = (req['selected_marketer_id'] ?? '').toString().trim();
    if (sid.isEmpty) return;
    try {
      final map = await UsersProfilesSafeSelect.fetchProfilesByIds(
        widget.sb,
        [sid],
      );
      final row = map[sid];
      if (row == null) return;
      final parts = [
        (row['first_name_ar'] ?? '').toString().trim(),
        (row['second_name_ar'] ?? '').toString().trim(),
        (row['third_name_ar'] ?? '').toString().trim(),
        (row['fourth_name_ar'] ?? '').toString().trim(),
      ].where((e) => e.isNotEmpty).join(' ');
      final partsEn = [
        (row['first_name_en'] ?? '').toString().trim(),
        (row['second_name_en'] ?? '').toString().trim(),
        (row['third_name_en'] ?? '').toString().trim(),
        (row['fourth_name_en'] ?? '').toString().trim(),
      ].where((e) => e.isNotEmpty).join(' ');
      final fullAr = (row['full_name_ar'] ?? '').toString().trim();
      final fullEn = (row['full_name_en'] ?? '').toString().trim();
      final nameAr =
          parts.isNotEmpty ? parts : (fullAr.isNotEmpty ? fullAr : '');
      final nameEn =
          partsEn.isNotEmpty ? partsEn : (fullEn.isNotEmpty ? fullEn : '');
      if (!mounted) return;
      setState(() {
        _selectedMarketerName = {
          'ar': nameAr.isNotEmpty ? nameAr : (nameEn),
          'en': nameEn.isNotEmpty ? nameEn : nameAr,
        };
      });
    } catch (_) {}
  }

  Widget _sectionTitle(String t) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Text(
        t,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 14,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _line(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ownerBody(Map<String, dynamic> bundle) {
    final ar = widget.isAr;
    final req = bundle['request'] as Map<String, dynamic>?;
    final invites = ((bundle['invites'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeLoadSelectedMarketer(req);
      final c = widget.scrollController;
      if (c != null && c.hasClients) c.jumpTo(0);
    });

    final st = (req?['status'] ?? '').toString();
    final resolvedStage = req != null
        ? ListingWorkflowUnified.fromMergedOwnerHubRow(
            Map<String, dynamic>.from(req),
          )
        : ListingWorkflowStage.waitingMarketers;
    final stageLabel = ar
        ? ListingStageUiHelper.stageLabelAr(resolvedStage)
        : ListingStageUiHelper.stageLabelEn(resolvedStage);
    final selId = (req?['selected_marketer_id'] ?? '').toString().trim();
    final selName = selId.isEmpty
        ? (ar ? 'لم يُختر مسوّق بعد' : 'No marketer selected yet')
        : (_selectedMarketerName != null
            ? (ar
                ? (_selectedMarketerName!['ar'] ?? '')
                : (_selectedMarketerName!['en'] ?? ''))
            : (ar ? 'جارٍ التحميل…' : 'Loading…'));

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text(
          ar ? 'تتبع مسار إعلانك في التسويق' : 'Your listing marketing journey',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        const SizedBox(height: 12),
        RequestSummaryTable(
          title: ar ? 'ملخص الطلب' : 'Request summary',
          rows: [
            RequestSummaryRow(
              label: ar ? 'تاريخ إنشاء الطلب' : 'Request created',
              value: _formatTrackDate(_parseDt(req?['created_at']), ar),
            ),
            RequestSummaryRow(
              label: ar ? 'آخر تحديث' : 'Last updated',
              value: _formatTrackDate(_parseDt(req?['updated_at']), ar),
            ),
            RequestSummaryRow(
              label: ar ? 'مرحلة سير العمل' : 'Workflow stage',
              value: stageLabel,
            ),
            RequestSummaryRow(
              label: ar ? 'حالة الطلب' : 'Request status',
              value: WorkflowDisplayTexts.requestStatus(st, ar),
            ),
            RequestSummaryRow(
              label: ar ? 'المسوق المختار' : 'Selected marketer',
              value: selName,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _sectionTitle(ar ? 'سجل السوق والدعوات' : 'Invites log'),
        if (invites.isEmpty)
          Text(
            ar ? 'لا توجد دعوات مسجّلة.' : 'No invites recorded.',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          )
        else
          ...invites.asMap().entries.map((e) {
            final i = e.value;
            final idx = e.key + 1;
            final name = (i['_marketer_display_name'] ?? '').toString().trim();
            final phone = (i['_marketer_phone'] ?? '').toString().trim();
            final acc = WorkflowDisplayTexts.accountType(
              (i['_marketer_account_type'] ?? '').toString(),
              ar,
            );
            final invSt =
                (i['status'] ?? i['invite_gate_status'] ?? '').toString();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        ar ? 'دعوة رقم $idx' : 'Invite #$idx',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      _line(
                        ar ? 'الحالة' : 'Status',
                        WorkflowDisplayTexts.inviteStatus(invSt, ar),
                      ),
                      _line(ar ? 'المسوّق' : 'Marketer',
                          name.isEmpty ? '—' : name),
                      if (phone.isNotEmpty)
                        _line(ar ? 'الجوال' : 'Phone', phone),
                      _line(ar ? 'نوع الحساب' : 'Account type', acc),
                      _line(
                        ar ? 'تاريخ الإنشاء' : 'Created',
                        _formatTrackDate(_parseDt(i['created_at']), ar),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _marketerBody(Map<String, dynamic> bundle) {
    final ar = widget.isAr;
    final l10n = AppLocalizations.of(context);
    final req = bundle['request'] as Map<String, dynamic>?;
    final offers = ((bundle['offers'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final latest = offers.isNotEmpty ? offers.first : null;
    final ost = (latest?['status'] ?? '').toString().trim().toLowerCase();
    final identity = OfferIdentityTag.parse(
      (latest?['notes'] ?? '').toString(),
    );
    final offerNotes = identity.notes.trim();
    final senderName = identity.displayName.trim();
    final senderRole = identity.source == PublicNameSource.display
        ? (l10n?.trackingOfferRoleDisplay ??
            (ar ? 'الاسم المستعار للتسويق' : 'Marketing display name'))
        : identity.source == PublicNameSource.official
            ? (l10n?.trackingOfferRoleOfficial ??
                (ar ? 'الاسم الرباعي المعتمد' : 'Official registered name'))
            : '';

    final stage = req != null
        ? ListingWorkflowUnified.fromMergedOwnerHubRow(
            Map<String, dynamic>.from(req),
          )
        : ListingWorkflowStage.waitingMarketers;
    final stageLabel = ar
        ? ListingStageUiHelper.stageLabelAr(stage)
        : ListingStageUiHelper.stageLabelEn(stage);
    final round = (req?['marketing_round'] as num?)?.toInt() ?? 1;
    final relists = (req?['relist_count'] as num?)?.toInt() ?? 0;

    final submitted = latest != null;
    final ownerViewed = req?['owner_viewed_offers_at'] != null;
    final ownerResponded = latest?['owner_responded_at'] != null;
    final accepted = ost == 'owner_accepted' ||
        ost == 'selected' ||
        ost == 'converted_to_contract' ||
        stage == ListingWorkflowStage.marketerSelected;
    final contractFlow = const {
      ListingWorkflowStage.marketerSelected,
      ListingWorkflowStage.contractPending,
      ListingWorkflowStage.contractSent,
      ListingWorkflowStage.contractReturned,
      ListingWorkflowStage.contractSigned,
      ListingWorkflowStage.permitPending,
      ListingWorkflowStage.permitIssued,
    }.contains(stage);
    final permitOrLater = const {
      ListingWorkflowStage.permitIssued,
      ListingWorkflowStage.published,
      ListingWorkflowStage.reserved,
    }.contains(stage);
    final publishedLike = const {
      ListingWorkflowStage.published,
      ListingWorkflowStage.reserved,
      ListingWorkflowStage.permitIssued,
    }.contains(stage);
    final collectingOffers =
        ListingWorkflowUnified.requestActivelyCollectingOffers(
      req ?? const <String, dynamic>{},
    );

    Widget step(String text, bool done) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              done
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_off_rounded,
              size: 20,
              color: done ? Colors.teal : Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  height: 1.35,
                  color: done
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text(
          ar ? 'تتبع تقدم عرضك التسويقي' : 'Your marketing offer progress',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        const SizedBox(height: 12),
        RequestSummaryTable(
          title: ar ? 'ملخص الطلب' : 'Request summary',
          rows: [
            RequestSummaryRow(
              label: ar ? 'تاريخ تقديم الطلب' : 'Request submitted',
              value: _formatTrackDate(_parseDt(req?['created_at']), ar),
            ),
            if (round > 1 || relists > 0)
              RequestSummaryRow(
                label: ar ? 'جولة التسويق' : 'Marketing round',
                value: ListingWorkflowCopy.marketingRoundLabel(ar, round),
              ),
            RequestSummaryRow(
              label: ar ? 'بداية جمع العروض' : 'Collecting offers since',
              value: _formatTrackDate(
                _parseDt(req?['waiting_marketers_since']) ??
                    _parseDt(req?['created_at']),
                ar,
              ),
            ),
            RequestSummaryRow(
              label: ar ? 'مرحلة سير العمل الحالية' : 'Current workflow stage',
              value: stageLabel,
            ),
            RequestSummaryRow(
              label: ar ? 'حالة الطلب' : 'Request status',
              value: WorkflowDisplayTexts.requestStatus(
                (req?['status'] ?? '').toString(),
                ar,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        RequestSummaryTable(
          title: ar ? 'ملخص العرض' : 'Offer summary',
          rows: [
            RequestSummaryRow(
              label: l10n?.trackingOfferSentAt ??
                  (ar ? 'تاريخ إرسال العرض' : 'Offer sent date'),
              value: _formatTrackDate(_parseDt(latest?['created_at']), ar),
            ),
            if (senderName.isNotEmpty)
              RequestSummaryRow(
                label: l10n?.trackingOfferSender ??
                    (ar ? 'مرسل العرض' : 'Offer sender'),
                value: senderName,
              ),
            if (senderRole.isNotEmpty)
              RequestSummaryRow(
                label: l10n?.trackingOfferSenderRole ??
                    (ar ? 'صفة المرسل' : 'Sender role'),
                value: senderRole,
              ),
            RequestSummaryRow(
              label: ar ? 'حالة العرض' : 'Offer status',
              value: WorkflowDisplayTexts.offerStatus(ost, ar),
            ),
            RequestSummaryRow(
              label: ar
                  ? 'تاريخ مشاهدة المالك لصفحة العروض'
                  : 'Owner viewed offers page',
              value: _formatTrackDate(
                  _parseDt(req?['owner_viewed_offers_at']), ar),
            ),
            RequestSummaryRow(
              label: ar
                  ? 'تاريخ رد المالك على عرضك'
                  : 'Owner response on your offer',
              value:
                  _formatTrackDate(_parseDt(latest?['owner_responded_at']), ar),
            ),
            if (offerNotes.isNotEmpty)
              RequestSummaryRow(
                label: l10n?.trackingOfferDetails ??
                    (ar ? 'تفاصيل العرض' : 'Offer details'),
                value: LocaleContent.forUi(offerNotes, isAr: ar),
              ),
            if ((latest?['owner_decline_reason'] ?? '')
                .toString()
                .trim()
                .isNotEmpty)
              RequestSummaryRow(
                label: ar ? 'سبب رفض المالك' : 'Owner decline reason',
                value:
                    (latest?['owner_decline_reason'] ?? '').toString().trim(),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _sectionTitle(ar ? 'سير العمل' : 'Workflow'),
        if (collectingOffers && !submitted)
          step(
            ar
                ? 'الطلب في السوق — بانتظار إتمام صفقتك'
                : 'On market — awaiting your deal',
            true,
          ),
        step(
            ar ? 'تم إرسال عرضك إلى المالك' : 'Offer sent to owner', submitted),
        step(
          ar ? 'بانتظار مراجعة المالك للعرض' : 'Awaiting owner review',
          ownerViewed || ownerResponded || accepted || contractFlow,
        ),
        step(
          ar ? 'إصدار التصريح' : 'Permit issuance',
          permitOrLater,
        ),
        step(
          ar ? 'نشر الإعلان' : 'Publish listing',
          publishedLike,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: AppLogoLoading(compact: true, size: 28)),
          );
        }
        if (snap.hasError) {
          if (!_loadErrorSnackShown) {
            _loadErrorSnackShown = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                SnackBar(
                  content: Text(
                    widget.isAr
                        ? 'تعذر تحميل بيانات التتبع. تحقق من الاتصال وحاول مجدداً.'
                        : 'Could not load tracking. Check your connection and retry.',
                  ),
                ),
              );
            });
          }
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              widget.isAr ? 'تعذر تحميل البيانات.' : 'Failed to load.',
            ),
          );
        }
        final bundle = snap.data!;
        final role = (bundle['viewerRole'] ?? '').toString();
        if (role == 'owner') {
          return _ownerBody(bundle);
        }
        return _marketerBody(bundle);
      },
    );
  }
}
