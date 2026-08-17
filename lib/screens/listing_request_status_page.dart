import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/listing/property_listing_display.dart';
import '../core/branding/branding_logo_image.dart';
import '../core/input/input_normalizers.dart';
import '../core/workflow/listing_workflow_copy.dart';
import '../core/workflow/listing_post_publish_ui_helper.dart';
import '../core/workflow/listing_workflow_ui_context.dart';
import '../core/workflow/listing_workflow_stage.dart';
import '../routes.dart';
import '../core/navigation/post_auth_navigation.dart';
import '../models/property.dart';
import '../services/marketing_flow_service.dart';
import '../services/contract_pdf_service.dart';
import '../core/notifications/hub_workflow_sound.dart';
import '../core/haptics/app_haptics.dart';
import 'listing_contract_chat_page.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/app_page_close_button.dart';
import '../widgets/app_confirm_dialog.dart';
import '../widgets/listing/request_summary_table.dart';
import '../widgets/listing_workflow_progress_strip.dart';
import '../shared/core/supabase_schema_selects.dart';
import '../core/utils/app_money.dart';
import '../core/utils/owner_display_lookup.dart';
import 'property_details_page.dart' as details;

class ListingRequestStatusPage extends StatefulWidget {
  final String requestId;
  final String lang;

  const ListingRequestStatusPage({
    super.key,
    required this.requestId,
    required this.lang,
  });

  @override
  State<ListingRequestStatusPage> createState() =>
      _ListingRequestStatusPageState();
}

class _ListingRequestStatusPageState extends State<ListingRequestStatusPage> {
  final _sb = Supabase.instance.client;
  late final MarketingFlowService _flow = MarketingFlowService(_sb);

  Map<String, dynamic>? _row;
  Map<String, dynamic>? _contract;
  String? _publishedPropertyId;
  bool _loading = true;
  String? _err;
  bool _relistBusy = false;
  bool _contractBusy = false;
  bool _permitBusy = false;
  bool _ackRegulatoryBusy = false;

  /// بيانات مدمجة من `payload_json` لعرض الصور والمساحة ونوع العقار.
  Map<String, dynamic> _payloadDetail = {};

  /// صف عقار مرتبط بنفس `request_id` (إن وُجد) لاستكمال العرض.
  Map<String, dynamic>? _propPreview;

  /// أحدث صف تصريح مرتبط بالطلب (للتحقق من حزمة REGA قبل النشر في الواجهة).
  Map<String, dynamic>? _latestPermit;

  List<String> _heroImageUrls = const [];

  /// اسم المعلن للعرض الداخلي (لوحة المسوق/المالك).
  String _ownerDisplayName = '';

  bool get _isAr => widget.lang == 'ar';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });

    try {
      final r = await _sb
          .from('listing_requests')
          .select(SupabaseSchemaSelects.listingRequestsLookup)
          .eq('id', widget.requestId)
          .maybeSingle();

      if (r == null) {
        if (!mounted) return;
        setState(() {
          _err = _isAr
              ? 'تعذر تحميل الطلب. قد يكون غير موجود أو ليست لديك صلاحية عرضه (سياسات RLS في Supabase).'
              : 'Could not load this request. It may not exist or your account may lack access (Supabase RLS).';
          _loading = false;
        });
        return;
      }

      final rowMap = Map<String, dynamic>.from(r);

      final payload = <String, dynamic>{};
      void mergePayload(dynamic v) {
        if (v is Map) {
          payload.addAll(Map<String, dynamic>.from(v));
          return;
        }
        if (v is String && v.trim().isNotEmpty) {
          try {
            final d = jsonDecode(v);
            if (d is Map) {
              payload.addAll(Map<String, dynamic>.from(d));
            }
          } catch (_) {}
        }
      }

      mergePayload(rowMap['payload_json']);
      mergePayload(rowMap['payload']);

      Map<String, dynamic>? propPreview;
      String? publishedPid;
      try {
        final pr = await _sb
            .from('properties')
            .select(SupabaseSchemaSelects.propertiesPreviewByRequestId)
            .eq('request_id', widget.requestId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (pr != null) {
          propPreview = Map<String, dynamic>.from(pr);
          publishedPid = (propPreview['id'] ?? '').toString().trim();
          if (publishedPid.isEmpty) publishedPid = null;
        }
      } catch (_) {}

      final bucket = _sb.storage.from('property-images');
      String toPublic(String path) {
        final p = path.trim();
        if (p.isEmpty) return '';
        return p.startsWith('http://') || p.startsWith('https://')
            ? p
            : bucket.getPublicUrl(p);
      }

      final urls = <String>[];
      void addUrl(String u) {
        final s = u.trim();
        if (s.isEmpty) return;
        if (!urls.contains(s)) urls.add(s);
      }

      if (propPreview != null) {
        final propMap = Map<String, dynamic>.from(propPreview);
        try {
          final p = Property.fromJson(propMap);
          for (final im in p.images) {
            addUrl(toPublic(im));
          }
        } catch (_) {}
      }

      void addPathsFromPayload(dynamic raw) {
        if (raw is! List) return;
        for (final e in raw) {
          addUrl(toPublic(e.toString()));
        }
      }

      for (final key in const [
        'request_image_paths',
        'image_paths',
        'image_urls',
        'images',
      ]) {
        addPathsFromPayload(payload[key]);
      }
      final prim = (payload['primary_image'] ?? payload['primaryImage'] ?? '')
          .toString()
          .trim();
      if (prim.isNotEmpty) addUrl(toPublic(prim));

      var ownerName = '';
      final oid = (rowMap['owner_id'] ?? '').toString().trim();
      if (oid.isNotEmpty) {
        try {
          ownerName = await fetchOwnerDisplayName(
            _sb,
            ownerUserId: oid,
            isAr: widget.lang == 'ar',
          );
        } catch (_) {}
      }

      Map<String, dynamic>? cRow;
      final cid = (rowMap['contract_id'] ?? '').toString().trim();
      if (cid.isNotEmpty) {
        try {
          cRow = await _flow.contractById(cid);
        } catch (_) {
          cRow = null;
        }
      }

      Map<String, dynamic>? permitRow;
      try {
        final pr = await _sb
            .from('listing_permits')
            .select('id,status,payload,permit_no,marketer_id,created_at')
            .eq('request_id', widget.requestId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (pr != null) {
          permitRow = Map<String, dynamic>.from(pr);
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _row = rowMap;
        _contract = cRow;
        _publishedPropertyId = publishedPid;
        _payloadDetail = payload;
        _propPreview = propPreview;
        _heroImageUrls = urls;
        _ownerDisplayName = ownerName;
        _latestPermit = permitRow;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: _isAr ? ui.TextDirection.rtl : ui.TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: Navigator.canPop(context)
              ? AppPageCloseButton(
                  isArabic: _isAr,
                  onPressed: () {
                    if (Navigator.canPop(context)) Navigator.pop(context);
                  },
                )
              : null,
          title: Text(_isAr ? 'حالة طلب التسويق' : 'Request Status'),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _loading
                ? const Center(child: AppLogoLoading())
                : _err != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _isAr ? 'حدث خطأ' : 'Error',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          Text(_err!, style: TextStyle(color: cs.error)),
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh),
                            label: Text(_isAr ? 'إعادة المحاولة' : 'Retry'),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_row != null && _needsOwnerRegulatoryAck(_row!))
                            _ownerRegulatoryAckBanner(cs),
                          Expanded(child: _buildBody()),
                        ],
                      ),
          ),
        ),
      ),
    );
  }

  bool _canRelistForMarketing() {
    if (_row == null) return false;
    return ListingWorkflowUiContext.fromListingRequest(
      Map<String, dynamic>.from(_row!),
    ).showOwnerRelist;
  }

  Future<void> _relistForMarketing() async {
    final opts = <String, dynamic>{'allow': false};
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocal) {
          return AlertDialog(
            title: Text(_isAr ? 'إعادة طرحه للتسويق' : 'Relist for marketing'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _isAr
                      ? 'سيتم فتح الطلب لعروض مسوقين جدد حسب الجولة التالية.'
                      : 'The request will reopen for new marketer offers.',
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _isAr
                        ? 'السماح للمسوقين السابقين بالتقديم'
                        : 'Allow previous marketers to submit again',
                  ),
                  value: opts['allow'] == true,
                  onChanged: (v) => setLocal(() => opts['allow'] = v),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(_isAr ? 'إلغاء' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(_isAr ? 'تأكيد' : 'Confirm'),
              ),
            ],
          );
        },
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _relistBusy = true);
    try {
      await _flow.relistListingRequestForMarketing(
        requestId: widget.requestId,
        allowPreviousMarketersRetry: opts['allow'] == true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ListingWorkflowCopy.snackRelistSuccess(_isAr))),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(ListingWorkflowCopy.rpcFailedFriendly(_isAr, e))),
      );
    } finally {
      if (mounted) setState(() => _relistBusy = false);
    }
  }

  bool _isOwner(Map<String, dynamic> row) {
    final u = (_sb.auth.currentUser?.id ?? '').trim();
    return u.isNotEmpty && u == (row['owner_id'] ?? '').toString().trim();
  }

  /// طلبات قديمة: owner_regulatory_ack_at فارغ — يحتاج المالك إقراراً تنظيمياً لمرة واحدة.
  /// الطلبات الجديدة تُملأ تلقائياً من التطبيق/المحفّز ولا تمر هنا.
  bool _needsOwnerRegulatoryAck(Map<String, dynamic> row) {
    if (!_isOwner(row)) return false;
    final v = row['owner_regulatory_ack_at'];
    if (v == null) return true;
    return v.toString().trim().isEmpty;
  }

  Future<void> _onOwnerRegulatoryAck() async {
    setState(() => _ackRegulatoryBusy = true);
    try {
      await _flow.ownerAckListingRequestRegulatoryAck(
        requestId: widget.requestId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isAr ? 'تم تسجيل الإقرار' : 'Acknowledgment saved'),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ListingWorkflowCopy.rpcFailedFriendly(_isAr, e)),
        ),
      );
    } finally {
      if (mounted) setState(() => _ackRegulatoryBusy = false);
    }
  }

  Widget _ownerRegulatoryAckBanner(ColorScheme cs) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: cs.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isAr
                  ? 'مطلوب إقرار تنظيمي (طلب قديم)'
                  : 'Regulatory acknowledgment (legacy request)',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              _isAr
                  ? 'طلبات الإعلان الجديدة لا تحتاج هذه الخطوة. هذا الطلب أقدم من حدّ الترحيل ويحتاج تأكيداً واحداً منك قبل المتابعة.'
                  : 'New listing requests skip this. This request predates compliance backfill and needs a one-time acknowledgment.',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _ackRegulatoryBusy ? null : _onOwnerRegulatoryAck,
              child: _ackRegulatoryBusy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isAr ? 'أقر وأتابع' : 'Acknowledge and continue'),
            ),
          ],
        ),
      ),
    );
  }

  bool _isPartyMarketer(Map<String, dynamic> row) {
    final u = (_sb.auth.currentUser?.id ?? '').trim();
    if (u.isEmpty) return false;
    final mid = (row['selected_marketer_id'] ?? row['marketer_id'] ?? '')
        .toString()
        .trim();
    return u == mid;
  }

  bool _regaPermitPackageReady(Map<String, dynamic>? permit) {
    if (permit == null) return false;
    final pn = (permit['permit_no'] ?? '').toString().trim();
    if (pn.isEmpty) return false;
    final raw = permit['payload'];
    Map<String, dynamic> m = {};
    if (raw is Map) {
      m = Map<String, dynamic>.from(raw);
    }
    final qr = (m['ad_qr_storage_path'] ?? '').toString().trim();
    final pdf = (m['rega_pdf_storage_path'] ?? '').toString().trim();
    return qr.isNotEmpty || pdf.isNotEmpty;
  }

  /// العقد «موقَّع» إذا كانت الحالة signed أو وُجد توقيع الطرفين.
  bool _contractIsSigned(Map<String, dynamic> c) {
    final st = (c['status'] ?? '').toString().toLowerCase().trim();
    if (st == 'signed') return true;
    return _contractRowFullySigned(c);
  }

  /// النشر من العقد — للمسوّق فقط؛ المالك لا ينشر الإعلان العام.
  bool _canPublishFromContract(
      Map<String, dynamic> row, Map<String, dynamic> c) {
    final u = (_sb.auth.currentUser?.id ?? '').trim();
    if (u.isEmpty) return false;
    if (!_contractIsSigned(c)) return false;
    final stage = ListingWorkflowStage.resolve(
      workflowStage: (row['workflow_stage'] ?? '').toString(),
      legacyStatus: (row['status'] ?? '').toString(),
      publishedAt: null,
    );
    if (stage == ListingWorkflowStage.published ||
        stage == ListingWorkflowStage.reserved) {
      return false;
    }
    if (stage == ListingWorkflowStage.permitPending ||
        stage == ListingWorkflowStage.permitIssued) {
      return false;
    }
    final mid = (c['marketer_id'] ??
            row['selected_marketer_id'] ??
            '')
        .toString()
        .trim();
    return u == mid;
  }

  bool _ownerPastContractSign(Map<String, dynamic> row) {
    if (!_isOwner(row)) return false;
    final wf = ListingWorkflowUiContext.fromListingRequest(
      Map<String, dynamic>.from(row),
    ).stage;
    if (wf == ListingWorkflowStage.contractSigned ||
        wf == ListingWorkflowStage.permitPending ||
        wf == ListingWorkflowStage.permitIssued ||
        wf == ListingWorkflowStage.published ||
        wf == ListingWorkflowStage.reserved) {
      return true;
    }
    if (_contract != null && _contractIsSigned(_contract!)) return true;
    return false;
  }

  String _contractBodyDisplay(Map<String, dynamic> c) {
    final b =
        (c['contract_body'] ?? c['contract_text'] ?? '').toString().trim();
    return b.isEmpty
        ? (_isAr ? '(لا يوجد نص للعقد بعد)' : '(No contract text yet)')
        : b;
  }

  Future<void> _runContractAction(
    Future<void> Function() fn, {
    void Function()? onSuccess,
  }) async {
    if (_contractBusy) return;
    setState(() => _contractBusy = true);
    try {
      await fn();
      if (!mounted) return;
      onSuccess?.call();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ListingWorkflowCopy.rpcFailed(_isAr, e))),
      );
    } finally {
      if (mounted) setState(() => _contractBusy = false);
    }
  }

  Future<void> _showReviewContractDialog(Map<String, dynamic> c) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ListingWorkflowCopy.btnReviewContract(_isAr)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(_contractBodyDisplay(c)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_isAr ? 'إغلاق' : 'Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _promptReturnContract(String contractId) async {
    final go = await showAppConfirmDialog(
      context: context,
      title: ListingWorkflowCopy.btnReturnContract(_isAr),
      message: _isAr
          ? 'سيتم إرجاع العقد للمسوّق للتعديل. هل تريد المتابعة؟'
          : 'The contract will be returned to the marketer for edits. Continue?',
      confirmLabel: _isAr ? 'متابعة' : 'Continue',
      cancelLabel: _isAr ? 'إلغاء' : 'Cancel',
    );
    if (!go || !mounted) return;

    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ListingWorkflowCopy.btnReturnContract(_isAr)),
        content: AqarTextField(
          controller: ctrl,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: ListingWorkflowCopy.lblReturnReason(_isAr),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_isAr ? 'إرسال' : 'Submit'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _runContractAction(() => _flow.ownerReturnListingContract(
          contractId: contractId,
          reason: ctrl.text.trim().isEmpty ? null : ctrl.text.trim(),
        ));
  }

  Future<bool> _currentUserHasKycSignature() async {
    final uid = (_sb.auth.currentUser?.id ?? '').trim();
    if (uid.isEmpty) return false;
    try {
      final row = await _sb
          .from('users_profiles')
          .select('signature_storage_path')
          .eq('user_id', uid)
          .maybeSingle();
      final p = (row?['signature_storage_path'] ?? '').toString().trim();
      return p.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _confirmSignContract(String contractId) async {
    if (_contractBusy) return;
    final hasSig = await _currentUserHasKycSignature();
    if (!hasSig) {
      if (!mounted) return;
      await showAppConfirmDialog(
        context: context,
        title: _isAr ? 'التوقيع غير جاهز' : 'Signature not set up',
        message: _isAr
            ? 'أكمل توقيعك الرقمي من ملفك الشخصي (التحقق / KYC) قبل توقيع عقد التسويق.'
            : 'Add your digital signature in your profile (KYC) before signing the marketing contract.',
        confirmLabel: _isAr ? 'حسناً' : 'OK',
        cancelLabel: _isAr ? 'إغلاق' : 'Close',
      );
      return;
    }

    final ok = await showAppConfirmDialog(
      context: context,
      title: ListingWorkflowCopy.btnSignContract(_isAr),
      message: _isAr
          ? 'هل تؤكد توقيعك على عقد التسويق؟'
          : 'Confirm signing the marketing contract?',
      confirmLabel: ListingWorkflowCopy.btnSignContract(_isAr),
      cancelLabel: _isAr ? 'إلغاء' : 'Cancel',
    );
    if (!ok || !mounted) return;
    await _runContractAction(
      () => _flow.ownerSignListingContract(contractId),
      onSuccess: () {
        // تنبيه المسوّق عبر إشعار Realtime؛ هنا نغطي أيضاً وضع المالك بعد التوقيع.
        playHubWorkflowSound(HubWorkflowSoundKind.contractSuccess);
        AppHaptics.medium();
      },
    );
  }

  Future<void> _promptCancelContract(String contractId) async {
    final go = await showAppConfirmDialog(
      context: context,
      title: ListingWorkflowCopy.btnCancelContract(_isAr),
      message: _isAr
          ? 'سيتم إلغاء عقد التسويق الحالي. هذا إجراء مهم — هل أنت متأكد؟'
          : 'This will cancel the current marketing contract. Are you sure?',
      confirmLabel: ListingWorkflowCopy.btnCancelContract(_isAr),
      cancelLabel: _isAr ? 'تراجع' : 'Back',
      isDanger: true,
    );
    if (!go || !mounted) return;

    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ListingWorkflowCopy.btnCancelContract(_isAr)),
        content: AqarTextField(
          controller: ctrl,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: _isAr ? 'السبب (اختياري)' : 'Reason (optional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ListingWorkflowCopy.btnCancelContract(_isAr)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _runContractAction(() => _flow.cancelListingContract(
          contractId: contractId,
          reason: ctrl.text.trim().isEmpty ? null : ctrl.text.trim(),
        ));
  }

  Future<void> _runPublishFromContract(String contractId) async {
    setState(() => _contractBusy = true);
    try {
      await _flow.publishListingDispatch(
        requestId: widget.requestId,
        preferPermitPath: false,
        contractId: contractId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ListingWorkflowCopy.snackPublishedFromContract(_isAr)),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ListingWorkflowCopy.rpcFailed(_isAr, e))),
      );
    } finally {
      if (mounted) setState(() => _contractBusy = false);
    }
  }

  Future<void> _runPublishAfterPermit() async {
    final ok = await showAppConfirmDialog(
      context: context,
      title: ListingWorkflowCopy.btnPublishAd(_isAr),
      message: _isAr
          ? 'سيتم نشر الإعلان على الرئيسية للجمهور. هل تؤكد؟'
          : 'This will publish the listing on the public home feed. Confirm?',
      confirmLabel: _isAr ? 'نشر' : 'Publish',
      cancelLabel: _isAr ? 'إلغاء' : 'Cancel',
    );
    if (!ok || !mounted) return;

    setState(() => _permitBusy = true);
    try {
      await _flow.publishListingDispatch(
        requestId: widget.requestId,
        preferPermitPath: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(ListingWorkflowCopy.snackPublishedFromContract(_isAr))),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      if (msg.contains('permit_not_approved')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  ListingWorkflowCopy.errCannotPublishBeforePermit(_isAr))),
        );
      } else if (msg.contains('permit_rega_package_incomplete')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(ListingWorkflowCopy.errRegaPackageIncomplete(_isAr))),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ListingWorkflowCopy.rpcFailed(_isAr, e))),
        );
      }
    } finally {
      if (mounted) setState(() => _permitBusy = false);
    }
  }

  bool _contractRowFullySigned(Map<String, dynamic> c) {
    final o = c['owner_signed_at'];
    final m = c['marketer_signed_at'];
    return o != null &&
        o.toString().trim().isNotEmpty &&
        m != null &&
        m.toString().trim().isNotEmpty;
  }

  Future<void> _openStoredContractPdfUrl(String raw) async {
    final url = raw.trim();
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isAr ? 'رابط PDF غير صالح' : 'Invalid PDF link')),
      );
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAr
                ? 'تعذّر فتح ملف PDF. جرّب من المتصفح.'
                : 'Could not open PDF. Try in browser.',
          ),
        ),
      );
    }
  }

  Future<void> _openContractPdfAction(
    String contractId,
    Map<String, dynamic> c,
  ) async {
    final stored = (c['contract_pdf_url'] ?? '').toString().trim();
    if (stored.isNotEmpty) {
      await _openStoredContractPdfUrl(stored);
      return;
    }
    if (_contractIsSigned(c) || _contractRowFullySigned(c)) {
      await _exportContractPdf(contractId, c);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isAr
              ? 'ملف PDF غير جاهز بعد — يُنشأ بعد اكتمال توقيع الطرفين.'
              : 'PDF not ready yet — available after both parties sign.',
        ),
      ),
    );
  }

  Future<void> _exportContractPdf(
      String contractId, Map<String, dynamic> c) async {
    if (!_contractIsSigned(c) && !_contractRowFullySigned(c)) return;
    final body = (c['contract_body'] ?? c['contract_text'] ?? '').toString();
    try {
      final ownerId = (c['owner_id'] ?? '').toString().trim();
      final mkId = (c['marketer_id'] ?? '').toString().trim();
      final ownerSig = ownerId.isNotEmpty
          ? await ContractPdfService.downloadUserSignaturePng(_sb, ownerId)
          : null;
      final mkSig = mkId.isNotEmpty
          ? await ContractPdfService.downloadUserSignaturePng(_sb, mkId)
          : null;
      final vt = (c['verify_public_token'] ?? '').toString().trim();
      final bytes = await ContractPdfService.buildListingContractFullPdf(
        contractId: contractId,
        isAr: _isAr,
        contractBody: body,
        ownerSignedAtIso: c['owner_signed_at']?.toString(),
        marketerSignedAtIso: c['marketer_signed_at']?.toString(),
        marketerSignaturePng: mkSig,
        ownerSignaturePng: ownerSig,
        verifyQrToken: vt.isEmpty ? null : vt,
      );
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: 'application/pdf',
            name: 'listing_contract_$contractId.pdf',
          ),
        ],
        text: _isAr ? 'مرجعية عقد' : 'Contract reference',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _runIssuePermit() async {
    setState(() => _permitBusy = true);
    try {
      await _flow.issueListingPermit(requestId: widget.requestId);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      if (msg.contains('permit_data_incomplete')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(ListingWorkflowCopy.errPermitDataIncomplete(_isAr))),
        );
      } else if (msg.contains('permit_rega_package_incomplete')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(ListingWorkflowCopy.errRegaPackageIncomplete(_isAr))),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(ListingWorkflowCopy.errCannotIssuePermitHere(_isAr))),
        );
      }
    } finally {
      if (mounted) setState(() => _permitBusy = false);
    }
  }

  Future<void> _runSendContractToOwner(String contractId) async {
    await _runContractAction(
        () => _flow.sendListingContractToOwner(contractId));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isAr ? 'تم إرسال العقد للمالك' : 'Contract sent to owner',
        ),
      ),
    );
  }

  bool _hasMarketingEscalationRequest(Map<String, dynamic> row) {
    final v = row['marketing_cancel_request_at'];
    return v != null && v.toString().trim().isNotEmpty;
  }

  bool _needsComplianceBanner(Map<String, dynamic> row) {
    final b = row['banned_under_review'];
    final m = row['needs_manual_review'];
    if (b == true) return true;
    if (m == true) return true;
    if (b is String && b.toLowerCase() == 'true') return true;
    if (m is String && m.toLowerCase() == 'true') return true;
    return false;
  }

  Widget _buildComplianceReviewBanner(
    Map<String, dynamic> row,
    ColorScheme cs,
  ) {
    final banned = row['banned_under_review'] == true ||
        '${row['banned_under_review']}'.toLowerCase() == 'true';
    final declineN = int.tryParse(
          '${row['owner_distinct_marketer_declines'] ?? 0}',
        ) ??
        0;
    final offerDeclineBan = declineN >= 3;
    return Material(
      color: cs.errorContainer.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              banned
                  ? (_isAr
                      ? 'الإعلان موقوف للمراجعة'
                      : 'Listing paused for review')
                  : (_isAr
                      ? 'يُنصح بمراجعة إدارية'
                      : 'Administrative review recommended'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              offerDeclineBan
                  ? (_isAr
                      ? 'وصل الطلب لحد رفض ثلاثة مسوّقين مميزين في الجولة الحالية. يحتاج قرار إداري قبل المتابعة.'
                      : 'This request hit the limit of three declined marketers in the current round. Ops review is required to continue.')
                  : (_isAr
                      ? 'سُجّلت عدة إلغاءات/إرجاعات للعقود أو تنبيهات امتثال. قد تتدخل الإدارة قبل متابعة التسويق.'
                      : 'Multiple contract cancellations/returns or compliance flags were recorded. Ops review may apply before marketing continues.'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarketingEscalationBanner(
    Map<String, dynamic> row,
    ColorScheme cs,
  ) {
    final reason =
        (row['marketing_cancel_request_reason'] ?? '').toString().trim();
    return Material(
      color: cs.errorContainer.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isAr
                  ? 'طلب مراجعة إدارية مسجّل'
                  : 'Admin review has been requested',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(reason),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _promptMarketingAdminEscalation() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _isAr
              ? 'طلب مراجعة إدارية / إيقاف التسويق'
              : 'Request admin review / stop marketing',
        ),
        content: AqarTextField(
          controller: ctrl,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: _isAr ? 'السبب (مستحسن)' : 'Reason (recommended)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_isAr ? 'إرسال الطلب' : 'Submit request'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _contractBusy = true);
    try {
      await _flow.ownerRequestMarketingAdminEscalation(
        requestId: widget.requestId,
        reason: ctrl.text.trim().isEmpty ? null : ctrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAr
                ? 'تم تسجيل طلبك. ستتابع الإدارة.'
                : 'Your request was recorded for admin review.',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ListingWorkflowCopy.rpcFailed(_isAr, e))),
      );
    } finally {
      if (mounted) setState(() => _contractBusy = false);
    }
  }

  Widget _buildOwnerContractSection(
      Map<String, dynamic> row, Map<String, dynamic> c) {
    final isOwner = _isOwner(row);
    final isMarketer = _isPartyMarketer(row);
    final st = (c['status'] ?? '').toString().toLowerCase().trim();
    final ownerSignedAt = c['owner_signed_at'];
    final ownerAlreadySigned = ownerSignedAt != null &&
        ownerSignedAt.toString().trim().isNotEmpty;
    final contractId = (c['id'] ?? '').toString().trim();
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isAr ? 'عقد التسويق' : 'Marketing contract',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            '${_isAr ? 'الحالة' : 'Status'}: ${_trMarketingStatusForContract(st)}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: cs.primary,
            ),
          ),
          if (st == 'draft')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(ListingWorkflowCopy.ownerDraftContractHint(_isAr)),
            ),
          if (st == 'pending_marketer')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(ListingWorkflowCopy.ownerAwaitingMarketerEdit(_isAr)),
            ),
          if (st == 'signed')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(ListingWorkflowCopy.contractSignedDone(_isAr)),
            ),
          if (st == 'cancelled')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(ListingWorkflowCopy.contractCancelledDone(_isAr)),
            ),
          if (isMarketer &&
              contractId.isNotEmpty &&
              (st == 'draft' || st == 'pending_marketer')) ...[
            const SizedBox(height: 12),
            if (_contractBusy)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: AppLogoLoading(),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _showReviewContractDialog(c),
                    icon: const Icon(Icons.article_outlined),
                    label: Text(
                      _isAr ? 'مراجعة نص العقد' : 'Review contract text',
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _runSendContractToOwner(contractId),
                    icon: const Icon(Icons.send_outlined),
                    label: Text(
                      st == 'pending_marketer'
                          ? ListingWorkflowCopy.btnResendContract(_isAr)
                          : ListingWorkflowCopy.btnSendContract(_isAr),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _promptCancelContract(contractId),
                    icon: Icon(Icons.cancel_outlined, color: cs.error),
                    label: Text(
                      ListingWorkflowCopy.btnCancelContract(_isAr),
                      style: TextStyle(color: cs.error),
                    ),
                  ),
                ],
              ),
          ],
          if (contractId.isNotEmpty &&
              st != 'cancelled' &&
              (isOwner || isMarketer)) ...[
            const SizedBox(height: 10),
            if (st == 'signed' && isOwner)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _isAr
                      ? 'تم توقيع العقد. يُكمّل المسوّق إصدار التصريح ثم نشر الإعلان — يمكنك فتح نسخة PDF أدناه.'
                      : 'Contract signed. The marketer completes the permit and publishes the ad. Open the PDF below.',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // بعد التوقيع: تُخفى «محادثة العقد» لكلا الطرفين.
                // التواصل ينتقل إلى دردشة الإعلان (أيقونة على البطاقة في
                // تبويب «تصاريح 72 ساعة»).
                if (st != 'signed' && (isOwner || isMarketer))
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context, rootNavigator: true).push<void>(
                        MaterialPageRoute<void>(
                          fullscreenDialog: true,
                          builder: (_) => ListingContractChatPage(
                            contractId: contractId,
                            lang: widget.lang,
                            embedAppBar: false,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.chat_outlined),
                    label: Text(_isAr ? 'محادثة العقد' : 'Contract chat'),
                  ),
                OutlinedButton.icon(
                  onPressed: _contractIsSigned(c) ||
                          (c['contract_pdf_url'] ?? '')
                              .toString()
                              .trim()
                              .isNotEmpty
                      ? () => _openContractPdfAction(contractId, c)
                      : null,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(_isAr ? 'عقد PDF' : 'Contract PDF'),
                ),
              ],
            ),
          ],
          if (isOwner && st == 'pending_owner' && !ownerAlreadySigned) ...[
            const SizedBox(height: 12),
            if (_contractBusy)
              const Center(
                  child: Padding(
                padding: EdgeInsets.all(12),
                child: AppLogoLoading(),
              ))
            else ...[
              LayoutBuilder(
                builder: (ctx, cts) {
                  final wide = cts.maxWidth >= 560;
                  final reviewBtn = SizedBox(
                    width: wide ? double.infinity : null,
                    child: OutlinedButton.icon(
                      onPressed: contractId.isEmpty
                          ? null
                          : () => _showReviewContractDialog(c),
                      icon: const Icon(Icons.article_outlined),
                      label: Text(ListingWorkflowCopy.btnReviewContract(_isAr)),
                    ),
                  );
                  final signBtn = SizedBox(
                    width: wide ? double.infinity : null,
                    child: FilledButton.icon(
                      onPressed: contractId.isEmpty
                          ? null
                          : () => _confirmSignContract(contractId),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.draw_outlined),
                      label: Text(ListingWorkflowCopy.btnSignContract(_isAr)),
                    ),
                  );
                  if (wide) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: reviewBtn),
                            const SizedBox(width: 10),
                            Expanded(child: signBtn),
                          ],
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: contractId.isEmpty
                              ? null
                              : () => _promptReturnContract(contractId),
                          icon: const Icon(Icons.undo_outlined),
                          label: Text(
                              ListingWorkflowCopy.btnReturnContract(_isAr)),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: contractId.isEmpty
                              ? null
                              : () => _promptCancelContract(contractId),
                          icon: Icon(Icons.cancel_outlined, color: cs.error),
                          label: Text(
                            ListingWorkflowCopy.btnCancelContract(_isAr),
                            style: TextStyle(color: cs.error),
                          ),
                        ),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      reviewBtn,
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: contractId.isEmpty
                            ? null
                            : () => _promptReturnContract(contractId),
                        icon: const Icon(Icons.undo_outlined),
                        label: Text(
                            ListingWorkflowCopy.btnReturnContract(_isAr)),
                      ),
                      const SizedBox(height: 8),
                      signBtn,
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: contractId.isEmpty
                            ? null
                            : () => _promptCancelContract(contractId),
                        icon: Icon(Icons.cancel_outlined, color: cs.error),
                        label: Text(
                          ListingWorkflowCopy.btnCancelContract(_isAr),
                          style: TextStyle(color: cs.error),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ],
          if (_canPublishFromContract(row, c)) ...[
            const SizedBox(height: 12),
            if (_contractBusy)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: AppLogoLoading(),
                ),
              )
            else
              FilledButton.icon(
                onPressed: contractId.isEmpty
                    ? null
                    : () => _runPublishFromContract(contractId),
                style: FilledButton.styleFrom(
                  backgroundColor: cs.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.public_outlined),
                label: Text(ListingWorkflowCopy.btnPublishFromContract(_isAr)),
              ),
          ],
        ],
      ),
    );
  }

  String _trMarketingStatusForContract(String st) {
    switch (st) {
      case 'draft':
        return _isAr ? 'مسودة' : 'Draft';
      case 'pending_owner':
        return _isAr ? 'بانتظار مراجعتك' : 'Awaiting your review';
      case 'pending_marketer':
        return _isAr ? 'بانتظار تعديل المسوق' : 'Awaiting marketer';
      case 'signed':
        return _isAr ? 'موقَّع' : 'Signed';
      case 'cancelled':
        return _isAr ? 'ملغى' : 'Cancelled';
      default:
        return st;
    }
  }

  Map<String, dynamic> _syntheticRowForLabels() {
    final row = Map<String, dynamic>.from(_row!);
    final pay = _payloadDetail;
    final prop = _propPreview;

    void copyIfEmpty(String colKey, dynamic v) {
      if ((row[colKey] ?? '').toString().trim().isNotEmpty) return;
      if (v == null) return;
      final s = v.toString().trim();
      if (s.isNotEmpty) row[colKey] = v;
    }

    copyIfEmpty('title', pay['title']);
    copyIfEmpty('city', pay['city']);
    copyIfEmpty('description', pay['description']);

    if (prop != null) {
      row['preview_title'] = prop['title'];
      row['preview_city'] = prop['city'];
      row['preview_price'] = prop['price'];
      row['preview_area'] = prop['area'];
      row['preview_type'] = prop['type'];
      row['preview_purpose'] = prop['purpose'];
      row['preview_is_auction'] = prop['is_auction'];
    }
    if (pay.isNotEmpty) {
      row['payload_json'] = pay;
    }
    if (_ownerDisplayName.trim().isNotEmpty) {
      row['preview_owner_name'] = _ownerDisplayName;
      row['request_owner_name'] = _ownerDisplayName;
    }
    return row;
  }

  double _pickNumeric(dynamic a, dynamic b, dynamic c) {
    for (final v in [a, b, c]) {
      if (v is num && v.toDouble() > 0) return v.toDouble();
      final n = num.tryParse('${v ?? ''}');
      if (n != null && n.toDouble() > 0) return n.toDouble();
    }
    return 0;
  }

  String _formatMoney(double value, String currency) {
    final f = NumberFormat('#,###', 'en');
    final cur = currency.trim().isEmpty ? 'SAR' : currency.trim();
    final sym = cur.toUpperCase() == 'SAR'
        ? AppMoney.saudiRiyalSignUnicode
        : cur.toUpperCase();
    if (value <= 0) return '';
    return '${normalizeAsciiDigits(f.format(value))} $sym';
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

  String _pickDeedNumber(Map<String, dynamic> syn) {
    for (final src in <dynamic>[
      _propPreview?['deed_number'],
      syn['deed_number'],
      _payloadDetail['deed_number'],
      _payloadDetail['preview_deed_number'],
      _row?['deed_number'],
    ]) {
      final v = normalizeAsciiDigits((src ?? '').toString().trim());
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  String _pickDeedDate(Map<String, dynamic> syn) {
    for (final src in <dynamic>[
      _propPreview?['deed_date'],
      syn['deed_date'],
      _payloadDetail['deed_date'],
      _payloadDetail['preview_deed_date'],
      _row?['deed_date'],
    ]) {
      final v = _fmtDeedDate(src);
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  Widget _heroImageBlock(ColorScheme cs) {
    final urls = _heroImageUrls;
    final screenW = MediaQuery.sizeOf(context).width;
    final heroH = (screenW * 0.52).clamp(180.0, 300.0);

    Widget fallback() => Container(
          height: heroH,
          width: double.infinity,
          color: cs.primary.withValues(alpha: 0.08),
          alignment: Alignment.center,
          child: BrandingLogoImage(
            size: (heroH * 0.55).clamp(96.0, 160.0),
            fit: BoxFit.contain,
            errorIcon: Icons.apartment_rounded,
          ),
        );

    if (urls.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: fallback(),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: heroH,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              urls.first,
              fit: BoxFit.cover,
              width: double.infinity,
              height: heroH,
              errorBuilder: (_, __, ___) => fallback(),
            ),
            if (urls.length > 1)
              PositionedDirectional(
                bottom: 10,
                end: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: Text(
                      _isAr
                          ? '+${urls.length - 1} صور'
                          : '+${urls.length - 1} photos',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final row = _row!;
    final cs = Theme.of(context).colorScheme;
    final syn = _syntheticRowForLabels();
    final wfCtx = ListingWorkflowUiContext.fromListingRequest(
      Map<String, dynamic>.from(row),
    );
    final uiDecision = ListingPostPublishUiHelper.decideFromRequestRow(
        Map<String, dynamic>.from(row));
    final isPublished =
        uiDecision.kind == ListingUiEntityKind.publishedProperty;
    final previewPropertyId = (_publishedPropertyId ?? '').trim();

    final title = (syn['title'] ?? row['title'] ?? '').toString().trim();
    final displayTitle =
        title.isEmpty ? (_isAr ? 'طلب تسويق' : 'Marketing request') : title;

    final city = (syn['city'] ?? row['city'] ?? '').toString().trim();
    final currency = (() {
      final c1 = (_propPreview?['currency'] ?? '').toString().trim();
      if (c1.isNotEmpty) return c1;
      final c2 = (_payloadDetail['currency'] ?? '').toString().trim();
      if (c2.isNotEmpty) return c2;
      return 'SAR';
    })();

    final priceVal = _pickNumeric(
      _propPreview?['price'],
      row['price'],
      _payloadDetail['price'],
    );
    final priceLine = _formatMoney(priceVal, currency);

    final areaVal = _pickNumeric(
      _propPreview?['area'],
      _payloadDetail['area'],
      _payloadDetail['sqm'],
    );
    final areaLine = areaVal > 0
        ? (_isAr
            ? '${normalizeAsciiDigits(areaVal.toStringAsFixed(areaVal == areaVal.roundToDouble() ? 0 : 2))} م²'
            : '${normalizeAsciiDigits(areaVal.toStringAsFixed(areaVal == areaVal.roundToDouble() ? 0 : 2))} m²')
        : '';

    final typeLabel = PropertyListingDisplay.typeLabelForRequestRow(syn, _isAr);
    final purposeLabel =
        PropertyListingDisplay.purposeLabelForRequestRow(syn, _isAr);
    final usageTuples =
        PropertyListingDisplay.usageTuplesFromPayload(_payloadDetail, _isAr);

    final address =
        (_propPreview?['address_line'] ??
                _payloadDetail['address_line'] ??
                row['address_line'] ??
                row['location'] ??
                '')
            .toString()
            .trim();

    final description =
        (syn['description'] ?? row['description'] ?? '').toString().trim();

    final deedNo = _pickDeedNumber(syn);
    final deedDate = _pickDeedDate(syn);
    final publicCode = (row['listing_request_public_code'] ??
            _propPreview?['listing_public_code'] ??
            '')
        .toString()
        .trim();
    final roundLabel = ListingWorkflowCopy.marketingRoundLabel(
      _isAr,
      row['marketing_round'],
    );
    final titleFs = MediaQuery.sizeOf(context).width < 360 ? 18.0 : 22.0;

    final chips = <Widget>[];
    if (typeLabel.trim().isNotEmpty) {
      chips.add(
        Chip(
          label: Text(typeLabel),
          visualDensity: VisualDensity.compact,
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
      );
    }
    if (purposeLabel.trim().isNotEmpty) {
      chips.add(
        Chip(
          label: Text(purposeLabel),
          visualDensity: VisualDensity.compact,
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
      );
    }
    for (final t in usageTuples) {
      chips.add(
        Chip(
          avatar: Icon(t.$1, size: 18, color: cs.primary),
          label: Text(t.$2),
          visualDensity: VisualDensity.compact,
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
      );
    }

    final summaryRows = <RequestSummaryRow>[
      if (publicCode.isNotEmpty)
        RequestSummaryRow(
          label: _isAr ? 'رقم الطلب' : 'Request no.',
          value: normalizeAsciiDigits(publicCode),
        ),
      if (city.isNotEmpty)
        RequestSummaryRow(
          label: _isAr ? 'المدينة' : 'City',
          value: city,
        ),
      if (priceLine.isNotEmpty)
        RequestSummaryRow(
          label: _isAr ? 'السعر' : 'Price',
          value: priceLine,
          emphasize: true,
        ),
      if (areaLine.isNotEmpty)
        RequestSummaryRow(
          label: _isAr ? 'المساحة' : 'Area',
          value: areaLine,
        ),
      if (typeLabel.isNotEmpty)
        RequestSummaryRow(
          label: _isAr ? 'نوع العقار' : 'Property type',
          value: typeLabel,
        ),
      if (purposeLabel.isNotEmpty)
        RequestSummaryRow(
          label: _isAr ? 'الغرض' : 'Purpose',
          value: purposeLabel,
        ),
      if (address.isNotEmpty)
        RequestSummaryRow(
          label: _isAr ? 'العنوان' : 'Address',
          value: address,
        ),
      if (_ownerDisplayName.trim().isNotEmpty)
        RequestSummaryRow(
          label: _isAr ? 'الشريك المعلن' : 'Listing partner',
          value: _ownerDisplayName.trim(),
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
        label: _isAr ? 'حالة الطلب' : 'Request status',
        value: _isAr ? wfCtx.statusLabelAr : wfCtx.statusLabelEn,
      ),
    ];

    final topSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heroImageBlock(cs),
        const SizedBox(height: 14),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            displayTitle,
            maxLines: 2,
            style: TextStyle(
              fontSize: titleFs,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips,
          ),
        ],
        const SizedBox(height: 12),
        RequestSummaryTable(
          title: _isAr ? 'ملخص الطلب' : 'Request summary',
          rows: summaryRows,
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            _isAr ? 'الوصف' : 'Description',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: TextStyle(
              height: 1.4,
              color: cs.onSurface.withValues(alpha: 0.92),
            ),
          ),
        ],
      ],
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          topSection,
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isPublished
                      ? ListingWorkflowCopy.publishedBannerTitle(_isAr)
                      : (_isAr
                          ? 'الحالة: ${wfCtx.statusLabelAr}'
                          : 'Status: ${wfCtx.statusLabelEn}'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                if (isPublished) ...[
                  Text(
                    ListingWorkflowCopy.publishedBannerSubtitle(_isAr),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: previewPropertyId.isEmpty
                        ? null
                        : () =>
                            _openPublishedPropertyDetails(previewPropertyId),
                    icon: const Icon(Icons.open_in_full),
                    label: Text(
                        ListingWorkflowCopy.btnOpenPublishedProperty(_isAr)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ] else ...[
                  ListingWorkflowProgressStrip(
                    stage: wfCtx.stage,
                    compact: false,
                    dense: true,
                    deadline: wfCtx.primaryDeadline,
                    permitSoundContextId: widget.requestId,
                  ),
                ],
              ],
            ),
          ),
          if (_hasMarketingEscalationRequest(row)) ...[
            const SizedBox(height: 12),
            _buildMarketingEscalationBanner(row, cs),
          ],
          if (_needsComplianceBanner(row)) ...[
            const SizedBox(height: 12),
            _buildComplianceReviewBanner(row, cs),
          ],
          if (_contract != null) ...[
            const SizedBox(height: 14),
            _buildOwnerContractSection(row, _contract!),
          ],
          if (!isPublished) ...[
            const SizedBox(height: 14),
            Builder(builder: (_) {
              final uid = (_sb.auth.currentUser?.id ?? '').trim();
              final isOwner = _isOwner(row);
              final isMarketer = _isPartyMarketer(row);
              final wf = wfCtx.stage;

              final mid =
                  (row['selected_marketer_id'] ?? row['marketer_id'] ?? '')
                      .toString()
                      .trim();
              final canPublishAfterPermit =
                  uid.isNotEmpty && uid == mid;

              if (wf == ListingWorkflowStage.contractSigned && isMarketer) {
                return FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context, rootNavigator: true)
                        .pushNamed(
                      AppRoutes.submitPermits,
                      arguments: {
                        'requestId': widget.requestId,
                        'lang': widget.lang,
                      },
                    ).then((_) {
                      if (mounted) _load();
                    });
                  },
                  // `Icons.edit_document_outlined` غير متوفر في Flutter الحالي،
                  // لذلك نستخدم أيقونة بديلة موجودة.
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(ListingWorkflowCopy.btnEnterPermitDetails(_isAr)),
                );
              }

              if (wf == ListingWorkflowStage.permitPending) {
                final regaReady = _regaPermitPackageReady(_latestPermit);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      ListingWorkflowCopy.txtPermitPending(_isAr),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    if (!regaReady) ...[
                      const SizedBox(height: 8),
                      Text(
                        ListingWorkflowCopy.txtWaitingRegaProof(_isAr),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    if (isOwner) ...[
                      if (regaReady)
                        FilledButton.icon(
                          onPressed: _permitBusy ? null : _runIssuePermit,
                          icon: const Icon(Icons.verified_outlined),
                          label:
                              Text(ListingWorkflowCopy.btnIssuePermit(_isAr)),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        )
                      else
                        Tooltip(
                          message: ListingWorkflowCopy.errRegaPackageIncomplete(
                              _isAr),
                          child: OutlinedButton.icon(
                            onPressed: _permitBusy
                                ? null
                                : () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          ListingWorkflowCopy
                                              .errRegaPackageIncomplete(_isAr),
                                        ),
                                      ),
                                    );
                                  },
                            icon: const Icon(Icons.verified_outlined),
                            label:
                                Text(ListingWorkflowCopy.btnIssuePermit(_isAr)),
                          ),
                        ),
                    ],
                  ],
                );
              }

              if (wf == ListingWorkflowStage.permitIssued) {
                final regaReady = _regaPermitPackageReady(_latestPermit);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      ListingWorkflowCopy.txtPermitIssued(_isAr),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    if (!regaReady) ...[
                      const SizedBox(height: 8),
                      Text(
                        ListingWorkflowCopy.errRegaPackageIncomplete(_isAr),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    if (canPublishAfterPermit) ...[
                      if (regaReady)
                        FilledButton.icon(
                          onPressed:
                              _permitBusy ? null : _runPublishAfterPermit,
                          icon: const Icon(Icons.public_outlined),
                          label: Text(ListingWorkflowCopy.btnPublishAd(_isAr)),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        )
                      else
                        Tooltip(
                          message: ListingWorkflowCopy.errRegaPackageIncomplete(
                              _isAr),
                          child: OutlinedButton.icon(
                            onPressed: _permitBusy
                                ? null
                                : () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          ListingWorkflowCopy
                                              .errRegaPackageIncomplete(_isAr),
                                        ),
                                      ),
                                    );
                                  },
                            icon: const Icon(Icons.public_outlined),
                            label:
                                Text(ListingWorkflowCopy.btnPublishAd(_isAr)),
                          ),
                        ),
                    ],
                  ],
                );
              }

              // For other stages, permit section is hidden.
              return const SizedBox.shrink();
            }),
          ],
          const SizedBox(height: 14),
          if (wfCtx.showOwnerOffersEntry && !_ownerPastContractSign(row))
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context, rootNavigator: true).pushNamed(
                  AppRoutes.ownerOffers,
                  arguments: {
                    'requestId': widget.requestId,
                    'lang': widget.lang,
                  },
                ).then((_) {
                  if (mounted) _load();
                });
              },
              icon: const Icon(Icons.local_offer_outlined),
              label: Text(_isAr ? 'عروض المسوقين' : 'Marketer offers'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          if (_canRelistForMarketing()) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _relistBusy ? null : _relistForMarketing,
              icon: _relistBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_outlined),
              label:
                  Text(_isAr ? 'إعادة طرحه للتسويق' : 'Relist for marketing'),
            ),
          ],
          if (_isOwner(row) &&
              !isPublished &&
              !_hasMarketingEscalationRequest(row) &&
              !_ownerPastContractSign(row)) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _contractBusy ? null : _promptMarketingAdminEscalation,
              icon: const Icon(Icons.support_agent_outlined),
              label: Text(_isAr ? 'طلب مراجعة إدارية' : 'Request admin review'),
            ),
          ],
          if (!_ownerPastContractSign(row)) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context, rootNavigator: true)
                  .pushNamed(AppRoutes.inAppNotifications),
              icon: const Icon(Icons.notifications_active_outlined),
              label: Text(
                  _isAr ? 'الإشعارات داخل التطبيق' : 'In-app notifications'),
            ),
          ],
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: () => unawaited(
                PostAuthNavigation.openDashboard(context),
              ),
            icon: const Icon(Icons.home_outlined),
            label: Text(_isAr ? 'العودة للرئيسية' : 'Back to Home'),
          ),
        ],
      ),
    );
  }

  Future<void> _openPublishedPropertyDetails(String propertyId) async {
    try {
      final uid = _sb.auth.currentUser?.id ?? 'guest';
      final data = await _sb
          .from('properties')
          .select(SupabaseSchemaSelects.propertiesListing)
          .eq('id', propertyId)
          .maybeSingle();

      if (data == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isAr
                ? 'تعذر فتح الإعلان المنشور'
                : 'Failed to open published listing'),
          ),
        );
        return;
      }

      final p = Property.fromJson(Map<String, dynamic>.from(data));

      if (!mounted) return;
      final row = _row;
      final isPartyMk = row != null &&
          _isPartyMarketer(row) &&
          uid != 'guest' &&
          uid != p.ownerId;

      final String? ownerForDetails;
      if (uid == 'guest') {
        ownerForDetails = null;
      } else if (uid == p.ownerId) {
        final raw = (p.ownerDisplayName ?? '').trim();
        ownerForDetails = raw.isNotEmpty ? p.ownerDisplayName : null;
      } else if (isPartyMk &&
          p.effectiveWorkflowStage != ListingWorkflowStage.published) {
        final od = (p.ownerDisplayName ?? '').trim();
        final fb = _ownerDisplayName.trim();
        ownerForDetails = od.isNotEmpty
            ? p.ownerDisplayName
            : (fb.isNotEmpty ? _ownerDisplayName : null);
      } else {
        final vis = p.visibleAdvertiserName.trim();
        ownerForDetails = vis.isNotEmpty ? p.visibleAdvertiserName : null;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => details.PropertyDetailsPage(
            property: p,
            isAr: _isAr,
            currentUserId: uid,
            ownerUsername: ownerForDetails,
            isFavorite: false,
            canManageProperty: false,
            showOwnerLegalNameToViewer: isPartyMk &&
                uid != 'guest' &&
                p.effectiveWorkflowStage != ListingWorkflowStage.published,
            onToggleFavorite: () async {},
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ListingWorkflowCopy.rpcFailed(_isAr, e)),
        ),
      );
    }
  }
}
