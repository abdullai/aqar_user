import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// طلب معاينة العقار: المهتم يقترح وقتاً، والمعلن يؤكد أو يعتذر أو يقترح وقتاً بديلاً.
/// كل خطوة تُسجَّل وتُشعِر الطرف الآخر داخل التطبيق (الخادم هو المرجع في التحقق).
class PropertyViewingPanel extends StatefulWidget {
  const PropertyViewingPanel({
    super.key,
    required this.propertyId,
    required this.ownerId,
    required this.currentUserId,
    required this.isAr,
  });

  final String propertyId;
  final String ownerId;
  final String currentUserId;
  final bool isAr;

  @override
  State<PropertyViewingPanel> createState() => _PropertyViewingPanelState();
}

class _PropertyViewingPanelState extends State<PropertyViewingPanel> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  bool _busy = false;

  SupabaseClient get _sb => Supabase.instance.client;
  bool get _isOwner =>
      widget.currentUserId.trim().isNotEmpty &&
      widget.currentUserId.trim() == widget.ownerId.trim();
  bool get _ar => widget.isAr;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _sb
          .from('property_viewing_requests')
          .select()
          .eq('property_id', widget.propertyId)
          .order('created_at', ascending: false)
          .limit(30);
      if (!mounted) return;
      setState(() {
        _rows = (data as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  DateTime? _dt(dynamic v) =>
      DateTime.tryParse((v ?? '').toString())?.toLocal();

  String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}  ${two(d.hour)}:${two(d.minute)}';
  }

  Future<DateTime?> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 17, minute: 0),
    );
    if (time == null) return null;
    final dt =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (dt.isBefore(now.add(const Duration(hours: 1)))) {
      _toast(_ar
          ? 'اختر موعداً بعد ساعة على الأقل من الآن.'
          : 'Pick a time at least one hour from now.');
      return null;
    }
    return dt;
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  String _err(Object e) {
    final s = e.toString();
    if (s.contains('viewing_already_active')) {
      return _ar
          ? 'لديك طلب معاينة نشط لهذا العقار بالفعل.'
          : 'You already have an active request.';
    }
    if (s.contains('viewing_rate_limited')) {
      return _ar
          ? 'وصلت للحد اليومي لطلبات المعاينة، حاول غداً.'
          : 'Daily request limit reached.';
    }
    if (s.contains('invalid_viewing_time')) {
      return _ar ? 'الموعد غير صالح.' : 'Invalid time.';
    }
    if (s.contains('cannot_request_own_property')) {
      return _ar ? 'لا يمكنك طلب معاينة عقارك.' : 'This is your own listing.';
    }
    return _ar ? 'تعذر تنفيذ العملية الآن.' : 'Could not complete the action.';
  }

  Future<void> _run(Future<void> Function() fn, String okMsg) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await fn();
      _toast(okMsg);
      await _load();
    } catch (e) {
      _toast(_err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _request() async {
    final dt = await _pickDateTime();
    if (dt == null || !mounted) return;
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_ar ? 'تأكيد طلب المعاينة' : 'Confirm viewing request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${_ar ? 'الموعد المقترح' : 'Proposed'}: ${_fmt(dt)}'),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              maxLength: 300,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: _ar ? 'ملاحظة للمعلن (اختياري)' : 'Note (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_ar ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_ar ? 'إرسال الطلب' : 'Send'),
          ),
        ],
      ),
    );
    final note = noteCtrl.text;
    noteCtrl.dispose();
    if (ok != true) return;
    await _run(
      () => _sb.rpc('request_property_viewing', params: {
        'p_property_id': widget.propertyId,
        'p_proposed_at': dt.toUtc().toIso8601String(),
        'p_note': note,
      }),
      _ar
          ? 'أُرسل طلب المعاينة، وسيصلك إشعار عند رد المعلن.'
          : 'Request sent. You will be notified.',
    );
  }

  Future<void> _owner(String id, String action, {DateTime? counter}) {
    return _run(
      () => _sb.rpc('respond_property_viewing', params: {
        'p_request_id': id,
        'p_action': action,
        'p_counter_at': counter?.toUtc().toIso8601String(),
      }),
      _ar ? 'تم إرسال ردك للمهتم.' : 'Response sent.',
    );
  }

  Future<void> _requester(String id, String action) {
    return _run(
      () => _sb.rpc('requester_respond_property_viewing', params: {
        'p_request_id': id,
        'p_action': action,
      }),
      _ar ? 'تم تحديث الطلب.' : 'Request updated.',
    );
  }

  ({String label, Color color}) _status(String s) {
    switch (s) {
      case 'confirmed':
        return (label: _ar ? 'مؤكد' : 'Confirmed', color: Colors.green);
      case 'counter_proposed':
        return (
          label: _ar ? 'موعد بديل مقترح' : 'Counter proposed',
          color: Colors.orange
        );
      case 'declined':
        return (label: _ar ? 'معتذر عنه' : 'Declined', color: Colors.red);
      case 'cancelled':
        return (label: _ar ? 'ملغى' : 'Cancelled', color: Colors.grey);
      default:
        return (label: _ar ? 'بانتظار الرد' : 'Pending', color: Colors.blue);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final mine = _rows
        .where((r) => r['requester_id']?.toString() == widget.currentUserId)
        .toList();
    final visible = _isOwner ? _rows : mine;
    final active = mine.any(
        (r) => r['status'] == 'pending' || r['status'] == 'counter_proposed');
    if (_isOwner && visible.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: .6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.event_available_rounded, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isOwner
                        ? (_ar ? 'طلبات المعاينة' : 'Viewing requests')
                        : (_ar ? 'معاينة العقار' : 'Property viewing'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final r in visible.take(_isOwner ? 10 : 3)) _row(r, cs),
            if (!_isOwner && !active) ...[
              const SizedBox(height: 6),
              FilledButton.icon(
                onPressed: _busy ? null : _request,
                icon: const Icon(Icons.calendar_month_rounded),
                label: Text(_ar ? 'اطلب معاينة' : 'Request a viewing'),
              ),
              const SizedBox(height: 6),
              Text(
                _ar
                    ? 'اقترح وقتاً يناسبك وسيؤكده المعلن أو يقترح بديلاً. التواصل والمعاينة داخل التطبيق دون أي دفع.'
                    : 'Propose a time; the advertiser confirms or suggests another.',
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(Map<String, dynamic> r, ColorScheme cs) {
    final id = r['id'].toString();
    final status = r['status']?.toString() ?? 'pending';
    final st = _status(status);
    final proposed = _dt(r['proposed_at']);
    final counter = _dt(r['counter_at']);
    final shown = status == 'confirmed'
        ? (_dt(r['confirmed_at']) ?? proposed)
        : (status == 'counter_proposed' ? counter : proposed);
    final note = (r['requester_note'] ?? '').toString().trim();

    final actions = <Widget>[];
    if (_isOwner && status == 'pending') {
      actions.addAll([
        FilledButton(
          onPressed: _busy ? null : () => _owner(id, 'confirm'),
          child: Text(_ar ? 'تأكيد' : 'Confirm'),
        ),
        OutlinedButton(
          onPressed: _busy
              ? null
              : () async {
                  final d = await _pickDateTime();
                  if (d != null) await _owner(id, 'counter', counter: d);
                },
          child: Text(_ar ? 'اقتراح وقت آخر' : 'Suggest other time'),
        ),
        TextButton(
          onPressed: _busy ? null : () => _owner(id, 'decline'),
          child: Text(_ar ? 'اعتذار' : 'Decline'),
        ),
      ]);
    } else if (!_isOwner && status == 'counter_proposed') {
      actions.addAll([
        FilledButton(
          onPressed: _busy ? null : () => _requester(id, 'accept'),
          child: Text(_ar ? 'قبول الموعد' : 'Accept'),
        ),
        TextButton(
          onPressed: _busy ? null : () => _requester(id, 'decline'),
          child: Text(_ar ? 'إلغاء الطلب' : 'Cancel request'),
        ),
      ]);
    } else if (!_isOwner && (status == 'pending' || status == 'confirmed')) {
      actions.add(TextButton(
        onPressed: _busy ? null : () => _requester(id, 'cancel'),
        child: Text(_ar ? 'إلغاء الطلب' : 'Cancel request'),
      ));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: st.color.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: st.color.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    st.label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: st.color,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (shown != null)
                  Expanded(
                    child: Text(
                      _fmt(shown),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
              ],
            ),
            if (note.isNotEmpty && _isOwner) ...[
              const SizedBox(height: 4),
              Text(note, style: const TextStyle(fontSize: 12)),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 4, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}
