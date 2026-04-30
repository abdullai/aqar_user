import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/haptics/app_haptics.dart';
import '../core/notifications/chat_message_sound.dart';
import '../services/contract_pdf_service.dart';
import '../services/marketing_flow_service.dart';
import '../widgets/app_logo_loading.dart';

// نفس ألوان واتساب المستخدمة في [ChatPage] للاتساق
const Color _kWaChatBg = Color(0xFFECE5DD);
const Color _kWaBubbleSent = Color(0xFFDCF8C6);
const Color _kWaBubbleReceived = Color(0xFFFFFFFF);
const Color _kWaTimeColor = Color(0xFF667781);

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

  const ListingContractChatPage({
    super.key,
    required this.contractId,
    required this.lang,
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

  bool _incomingSoundPrimed = false;
  String? _lastTopMessageId;
  bool _signCompleteSnackShown = false;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

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
    _loadContractOnly();
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
      final prevSigned = _rowFullySigned(_contract);
      final nextMap = c == null ? null : Map<String, dynamic>.from(c);
      final nextSigned = _rowFullySigned(nextMap);
      setState(() {
        _snippet = body;
        _contract = nextMap;
        _loading = false;
      });
      if (!mounted) return;
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
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _onMessagesSnapshot(List<Map<String, dynamic>> rows, String uid) {
    if (rows.isEmpty) return;
    // Stream ordered newest-first; same convention as [ChatPage._ChatThread].
    final top = rows.first;
    final id = top['id']?.toString() ?? '';
    if (id.isEmpty) return;
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
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    setState(() => _sending = true);
    try {
      await MarketingFlowService(Supabase.instance.client)
          .sendListingContractMessage(
        contractId: widget.contractId,
        body: t,
        messageType: type,
      );
      _ctrl.clear();
    } catch (e) {
      if (mounted) {
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
      final bytes = await ContractPdfService.buildListingContractFullPdf(
        contractId: widget.contractId,
        isAr: _isAr,
        contractBody: _snippet,
        ownerSignedAtIso: co?['owner_signed_at']?.toString(),
        marketerSignedAtIso: co?['marketer_signed_at']?.toString(),
        marketerSignaturePng: mkSig,
        ownerSignaturePng: ownerSig,
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

    return Scaffold(
      appBar: AppBar(
        title: Text(_isAr ? 'محادثة العقد' : 'Contract chat'),
        actions: [
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
        ],
      ),
      body: Column(
        children: [
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
                      stream: Supabase.instance.client
                          .from('listing_contract_messages')
                          .stream(primaryKey: ['id'])
                          .eq('contract_id', widget.contractId)
                          .order('created_at', ascending: false),
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
                        final rows = snap.data ?? const <Map<String, dynamic>>[];
                        if (snap.connectionState == ConnectionState.waiting &&
                            rows.isEmpty) {
                          return const Center(child: AppLogoLoading());
                        }

                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          _onMessagesSnapshot(rows, uid);
                        });

                        if (rows.isEmpty) {
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

                        WidgetsBinding.instance
                            .addPostFrameCallback((_) => _scrollToBottom());

                        return ListView.builder(
                          controller: _scroll,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          itemCount: rows.length,
                          itemBuilder: (ctx, i) {
                            final m = rows[i];
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _ctrl,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: _isAr ? 'اكتب رسالتك…' : 'Type a message…',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _sending ? null : () => _send('chat'),
                        child: Text(_isAr ? 'إرسال' : 'Send'),
                      ),
                      OutlinedButton(
                        onPressed:
                            _sending ? null : () => _send('request_change'),
                        child: Text(_isAr ? 'طلب تعديل' : 'Request change'),
                      ),
                      OutlinedButton(
                        onPressed:
                            _sending ? null : () => _send('request_cancel'),
                        child: Text(_isAr ? 'طلب إلغاء' : 'Request cancel'),
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
