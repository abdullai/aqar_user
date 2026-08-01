import 'dart:async';

import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/haptics/app_haptics.dart';
import '../core/notifications/chat_message_sound.dart';
import '../core/notifications/hub_workflow_sound.dart';
import '../services/contract_pdf_service.dart';
import '../services/marketing_flow_service.dart';
import '../widgets/app_logo_loading.dart';

// نفس ألوان واتساب المستخدمة في [ChatPage] للاتساق
const Color _kWaChatBg = Color(0xFFECE5DD);
const Color _kWaBubbleSent = Color(0xFFDCF8C6);
const Color _kWaBubbleReceived = Color(0xFFFFFFFF);
const Color _kWaTimeColor = Color(0xFF667781);

DateTime? _listingContractParseTs(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v.toLocal();
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s)?.toLocal();
}

bool listingContractOptimisticMatchesServer(
  Map<String, dynamic> optimistic,
  Map<String, dynamic> server,
) {
  final oid = (optimistic['id'] ?? '').toString();
  if (!oid.startsWith('__opt__')) return false;
  if ((optimistic['sender_id'] ?? '').toString() !=
      (server['sender_id'] ?? '').toString()) {
    return false;
  }
  if ((optimistic['body'] ?? '').toString().trim() !=
      (server['body'] ?? '').toString().trim()) {
    return false;
  }
  if ((optimistic['message_type'] ?? 'chat').toString() !=
      (server['message_type'] ?? 'chat').toString()) {
    return false;
  }
  final optMs = optimistic['_opt_ms'];
  if (optMs is! int) return false;
  final sdt = _listingContractParseTs(server['created_at']);
  if (sdt == null) return false;
  final diff = sdt.millisecondsSinceEpoch - optMs;
  return diff >= -5000 && diff < 120000;
}

List<Map<String, dynamic>> listingContractMergeOptimistic(
  List<Map<String, dynamic>> streamRows,
  List<Map<String, dynamic>> optimistic,
  String contractId,
) {
  final cid = contractId.trim();
  final forConv = optimistic
      .where((m) => (m['contract_id'] ?? '').toString().trim() == cid)
      .toList();
  if (forConv.isEmpty) return streamRows;
  final matched = <String>{};
  for (final r in streamRows) {
    for (final o in forConv) {
      if (listingContractOptimisticMatchesServer(o, r)) {
        matched.add((o['id'] ?? '').toString());
      }
    }
  }
  final pending = forConv
      .where((o) => !matched.contains((o['id'] ?? '').toString()))
      .map(Map<String, dynamic>.from)
      .toList();
  if (pending.isEmpty) return streamRows;
  return <Map<String, dynamic>>[...pending, ...streamRows];
}

String _friendlyContractLoadError(Object e, {required bool isAr}) {
  final s = e.toString().toLowerCase();
  if (s.contains('rls') ||
      s.contains('permission') ||
      s.contains('policy') ||
      s.contains('42501') ||
      s.contains('pgrst')) {
    return isAr
        ? 'تعذر تحميل العقد. تحقق من صلاحيات الحساب أو حاول لاحقاً.'
        : 'Could not load the contract. Check permissions or try again.';
  }
  return isAr ? 'تعذر تحميل العقد.' : 'Could not load the contract.';
}

String _listingContractFmtTime(String raw) {
  final dt = DateTime.tryParse(raw)?.toLocal();
  if (dt == null) return '';
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// دردشة مرتبطة بعقد تسويق (طلب تعديل/فسخ عبر اختيار نوع الرسالة).
class ListingContractChatPage extends StatefulWidget {
  final String contractId;
  final String lang;

  /// قراءة فقط صارمة (مثلاً من تفاصيل العقار): لا إدخال ولا طلب تعديل/إلغاء.
  final bool strictReadOnly;

  /// بعد توقيع المالك يُقفل الإدخال للحفاظ على سجل قانوني ثابت.
  final bool lockAfterOwnerSigns;

  /// داخل لوحة المستخدم: بدون [AppBar] ثانٍ (الشريط الخارجي للوحة).
  final bool embedAppBar;

  const ListingContractChatPage({
    super.key,
    required this.contractId,
    required this.lang,
    this.strictReadOnly = false,
    this.lockAfterOwnerSigns = true,
    this.embedAppBar = false,
  });

  @override
  State<ListingContractChatPage> createState() =>
      _ListingContractChatPageState();
}

class _ListingContractChatPageState extends State<ListingContractChatPage> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _loading = true;
  bool _sending = false;
  String? _err;
  String _snippet = '';
  Map<String, dynamic>? _contract;

  late Stream<List<Map<String, dynamic>>> _contractMsgStream;
  final List<Map<String, dynamic>> _optimisticContractMsgs =
      <Map<String, dynamic>>[];
  int _listingScrollBumpLen = 0;

  bool _incomingSoundPrimed = false;
  String? _lastTopMessageId;
  bool _signCompleteSnackShown = false;
  bool _ownerLockChimePlayed = false;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  bool _ownerHasSigned(Map<String, dynamic>? c) {
    if (c == null) return false;
    final o = c['owner_signed_at'];
    return o != null && o.toString().trim().isNotEmpty;
  }

  bool get _inputLocked =>
      widget.strictReadOnly ||
      (widget.lockAfterOwnerSigns && _ownerHasSigned(_contract));

  /// يُصدَّر PDF يتضمّن كتلة التوقيعات فقط بعد اكتمال الطرفين (بيانات العقد).
  bool _rowFullySigned(Map<String, dynamic>? c) {
    if (c == null) return false;
    final o = c['owner_signed_at'];
    final m = c['marketer_signed_at'];
    final os = o != null && o.toString().trim().isNotEmpty;
    final ms = m != null && m.toString().trim().isNotEmpty;
    return os && ms;
  }

  bool get _contractFullySigned => _rowFullySigned(_contract);

  @override
  void initState() {
    super.initState();
    _bindContractMsgStream();
    _loadContractOnly();
  }

  void _bindContractMsgStream() {
    final cid = widget.contractId.trim();
    if (cid.isEmpty) {
      _contractMsgStream =
          Stream.value(const <Map<String, dynamic>>[]);
      return;
    }
    _contractMsgStream = Supabase.instance.client
        .from('listing_contract_messages')
        .stream(primaryKey: const ['id'])
        .eq('contract_id', cid)
        .order('created_at', ascending: false);
  }

  @override
  void didUpdateWidget(covariant ListingContractChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contractId != widget.contractId) {
      _bindContractMsgStream();
      _optimisticContractMsgs.clear();
      _listingScrollBumpLen = 0;
      _incomingSoundPrimed = false;
      _lastTopMessageId = null;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadContractOnly() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final flow = MarketingFlowService(Supabase.instance.client);
      final c = await flow.contractById(widget.contractId);
      final body = (c?['contract_body'] ?? c?['contract_text'] ?? '')
          .toString()
          .trim();
      if (!mounted) return;
      final priorContract = _contract;
      final prevSigned = _rowFullySigned(priorContract);
      final prevOwnerSigned = _ownerHasSigned(priorContract);
      final nextMap = c == null ? null : Map<String, dynamic>.from(c);
      final nextSigned = _rowFullySigned(nextMap);
      final nextOwnerSigned = _ownerHasSigned(nextMap);
      setState(() {
        _snippet = body;
        _contract = nextMap;
        _loading = false;
      });
      if (!mounted) return;
      final lockedNow = widget.strictReadOnly ||
          (widget.lockAfterOwnerSigns && nextOwnerSigned);
      if (lockedNow &&
          priorContract != null &&
          !prevOwnerSigned &&
          nextOwnerSigned &&
          widget.lockAfterOwnerSigns &&
          !widget.strictReadOnly &&
          !_ownerLockChimePlayed) {
        _ownerLockChimePlayed = true;
        playHubWorkflowSound(HubWorkflowSoundKind.contractSuccess);
        AppHaptics.medium();
      }
      if (nextSigned && !prevSigned && !_signCompleteSnackShown) {
        _signCompleteSnackShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _isAr
                    ? 'اكتمل توقيع العقد. يمكنك تصدير نسخة PDF كاملة.'
                    : 'Contract is fully signed. You can export the complete PDF.',
              ),
              action: SnackBarAction(
                label: 'PDF',
                onPressed: _exportPdf,
              ),
            ),
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _err = _friendlyContractLoadError(e, isAr: _isAr);
      });
    }
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(0);
  }

  void _onMessagesSnapshot(List<Map<String, dynamic>> rows, String uid) {
    if (rows.isEmpty) return;
    // Stream ordered newest-first; same convention as [ChatPage._ChatThread].
    final top = rows.first;
    final id = top['id']?.toString() ?? '';
    if (id.isEmpty || id.startsWith('__opt__')) return;
    final sender = top['sender_id']?.toString() ?? '';
    if (!_incomingSoundPrimed) {
      _incomingSoundPrimed = true;
      _lastTopMessageId = id;
      return;
    }
    if (id == _lastTopMessageId) return;
    _lastTopMessageId = id;
    if (sender != uid) {
      playChatIncomingMessageSound();
      AppHaptics.medium();
    }
  }

  Future<void> _send(String type) async {
    if (_inputLocked) return;
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (uid.isEmpty) return;

    final optId = '__opt__${const Uuid().v4()}';
    final optMs = DateTime.now().millisecondsSinceEpoch;
    final optRow = <String, dynamic>{
      'id': optId,
      'contract_id': widget.contractId,
      'sender_id': uid,
      'body': t,
      'message_type': type,
      'created_at': DateTime.fromMillisecondsSinceEpoch(optMs, isUtc: true)
          .toIso8601String(),
      '_opt_ms': optMs,
    };

    setState(() {
      _optimisticContractMsgs.insert(0, optRow);
      _sending = true;
    });
    _ctrl.clear();

    try {
      final row = await MarketingFlowService(Supabase.instance.client)
          .sendListingContractMessage(
        contractId: widget.contractId,
        body: t,
        messageType: type,
      );
      if (!mounted) return;
      if (row != null) {
        setState(() {
          _optimisticContractMsgs.removeWhere(
            (m) =>
                (m['id'] ?? '').toString() == optId ||
                listingContractOptimisticMatchesServer(
                    m, Map<String, dynamic>.from(row)),
          );
        });
      } else {
        setState(() {
          _optimisticContractMsgs.removeWhere((m) => m['id'] == optId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isAr ? 'فشل الإرسال' : 'Send failed'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _optimisticContractMsgs.removeWhere((m) => m['id'] == optId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _exportPdf() async {
    if (!_contractFullySigned) return;
    try {
      final sb = Supabase.instance.client;
      final co = _contract;
      final ownerId = (co?['owner_id'] ?? '').toString().trim();
      final mkId = (co?['marketer_id'] ?? '').toString().trim();
      final ownerSig = ownerId.isNotEmpty
          ? await ContractPdfService.downloadUserSignaturePng(sb, ownerId)
          : null;
      final mkSig = mkId.isNotEmpty
          ? await ContractPdfService.downloadUserSignaturePng(sb, mkId)
          : null;
      final verifyTok =
          (co?['verify_public_token'] ?? '').toString().trim();
      final bytes = await ContractPdfService.buildListingContractFullPdf(
        contractId: widget.contractId,
        isAr: _isAr,
        contractBody: _snippet,
        ownerSignedAtIso: co?['owner_signed_at']?.toString(),
        marketerSignedAtIso: co?['marketer_signed_at']?.toString(),
        marketerSignaturePng: mkSig,
        ownerSignaturePng: ownerSig,
        verifyQrToken: verifyTok.isEmpty ? null : verifyTok,
      );
      final name = 'listing_contract_${widget.contractId}.pdf';
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: 'application/pdf',
            name: name,
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

  @override
  Widget build(BuildContext context) {
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';

    final appBarActions = <Widget>[
      IconButton(
        tooltip: _contractFullySigned
            ? (_isAr ? 'تصدير PDF' : 'Export PDF')
            : (_isAr
                ? 'بعد اكتمال توقيع المالك والمسوّق'
                : 'Available after owner and marketer sign'),
        onPressed: _loading || !_contractFullySigned ? null : _exportPdf,
        icon: const Icon(Icons.picture_as_pdf_outlined),
      ),
      IconButton(
        tooltip: _isAr ? 'تحديث' : 'Refresh',
        onPressed: _loading ? null : _loadContractOnly,
        icon: const Icon(Icons.refresh),
      ),
    ];

    final embedTop = widget.embedAppBar
        ? Material(
            elevation: 0.5,
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.55),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: kToolbarHeight,
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding:
                            const EdgeInsetsDirectional.only(start: 12, end: 8),
                        child: Text(
                          _isAr ? 'محادثة العقد' : 'Contract chat',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    ...appBarActions,
                  ],
                ),
              ),
            ),
          )
        : null;

    return Scaffold(
      appBar: widget.embedAppBar
          ? null
          : AppBar(
              title: Text(_isAr ? 'محادثة العقد' : 'Contract chat'),
              actions: appBarActions,
            ),
      body: Column(
        children: [
          if (embedTop != null) embedTop,
          if (_err != null)
            MaterialBanner(
              content: Text(_err!),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _err = null),
                  child: Text(_isAr ? 'إخفاء' : 'Dismiss'),
                ),
              ],
            ),
          Expanded(
            child: ColoredBox(
              color: _kWaChatBg,
              child: _loading
                  ? const Center(child: AppLogoLoading())
                  : StreamBuilder<List<Map<String, dynamic>>>(
                      key: ValueKey<String>(widget.contractId),
                      stream: _contractMsgStream,
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return Center(
                            child: Text(
                              _isAr
                                  ? 'تعذر تحميل الرسائل'
                                  : 'Failed to load messages',
                            ),
                          );
                        }
                        final rows =
                            snap.data ?? const <Map<String, dynamic>>[];
                        final optFor = _optimisticContractMsgs
                            .where((m) =>
                                (m['contract_id'] ?? '').toString().trim() ==
                                widget.contractId.trim())
                            .toList();
                        final waiting =
                            snap.connectionState == ConnectionState.waiting;
                        final hasEmitted = snap.hasData;
                        if (waiting && !hasEmitted && optFor.isEmpty) {
                          return const Center(child: AppLogoLoading());
                        }

                        final merged = listingContractMergeOptimistic(
                          rows,
                          _optimisticContractMsgs,
                          widget.contractId,
                        );

                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          _onMessagesSnapshot(merged, uid);
                          if (merged.length > _listingScrollBumpLen) {
                            _listingScrollBumpLen = merged.length;
                            _scrollToBottom();
                          } else {
                            _listingScrollBumpLen = merged.length;
                          }
                        });

                        if (merged.isEmpty) {
                          return Center(
                            child: Text(
                              _isAr
                                  ? 'ابدأ المحادثة الآن'
                                  : 'Start the conversation',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: _kWaTimeColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          );
                        }

                        return ListView.builder(
                          controller: _scroll,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          itemCount: merged.length,
                          itemBuilder: (ctx, i) {
                            final m = merged[i];
                            final mine =
                                (m['sender_id'] ?? '').toString().trim() == uid;
                            final body = (m['body'] ?? '').toString();
                            final typ =
                                (m['message_type'] ?? 'chat').toString();
                            final at = (m['created_at'] ?? '').toString();
                            final timeLabel = _listingContractFmtTime(at);
                            final bubbleColor =
                                mine ? _kWaBubbleSent : _kWaBubbleReceived;
                            final br = BorderRadius.only(
                              topLeft: const Radius.circular(10),
                              topRight: const Radius.circular(10),
                              bottomLeft: Radius.circular(mine ? 10 : 2),
                              bottomRight: Radius.circular(mine ? 2 : 10),
                            );
                            return Align(
                              alignment: mine
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding:
                                    const EdgeInsets.fromLTRB(10, 8, 8, 8),
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.82,
                                ),
                                decoration: BoxDecoration(
                                  color: bubbleColor,
                                  borderRadius: br,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.06,
                                      ),
                                      blurRadius: 2,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      typ == 'chat'
                                          ? (_isAr ? 'رسالة' : 'Message')
                                          : typ,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    SelectableText(
                                      body,
                                      style: const TextStyle(
                                        color: Color(0xFF111B21),
                                        fontWeight: FontWeight.w600,
                                        height: 1.35,
                                      ),
                                    ),
                                    if (timeLabel.isNotEmpty)
                                      Align(
                                        alignment:
                                            AlignmentDirectional.centerEnd,
                                        child: Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                            timeLabel,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                              color: _kWaTimeColor,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _inputLocked
                  ? Material(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 22,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                widget.strictReadOnly
                                    ? (_isAr
                                        ? 'عرض قراءة فقط — لا يمكن إرسال رسائل أو مرفقات من هنا.'
                                        : 'Read-only preview — sending is disabled.')
                                    : (_isAr
                                        ? 'بعد توقيع المالك أصبحت محادثة العقد للقراءة فقط للحفاظ على السجل القانوني.'
                                        : 'After the owner signed, contract chat is read-only to preserve the legal record.'),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      height: 1.35,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AqarTextField(
                          controller: _ctrl,
                          minLines: 1,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText:
                                _isAr ? 'اكتب رسالتك…' : 'Type a message…',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton(
                              onPressed:
                                  _sending ? null : () => _send('chat'),
                              child: Text(_isAr ? 'إرسال' : 'Send'),
                            ),
                            OutlinedButton(
                              onPressed: _sending
                                  ? null
                                  : () => _send('request_change'),
                              child: Text(
                                  _isAr ? 'طلب تعديل' : 'Request change'),
                            ),
                            OutlinedButton(
                              onPressed: _sending
                                  ? null
                                  : () => _send('request_cancel'),
                              child: Text(
                                  _isAr ? 'طلب إلغاء' : 'Request cancel'),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
