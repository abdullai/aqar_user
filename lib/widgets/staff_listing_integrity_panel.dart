import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// لوحة الموظفين: مراجعة تشابه صور الإعلانات والإعلانات المُصعَّدة بالبلاغات.
/// الإخفاء لا يتم إلا بقرار بشري صريح.
class StaffListingIntegrityPanel extends StatefulWidget {
  const StaffListingIntegrityPanel({super.key, required this.isAr});

  final bool isAr;

  @override
  State<StaffListingIntegrityPanel> createState() =>
      _StaffListingIntegrityPanelState();
}

class _StaffListingIntegrityPanelState
    extends State<StaffListingIntegrityPanel> {
  final _db = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _flags = const [];
  List<Map<String, dynamic>> _escalations = const [];
  final Set<String> _busy = {};

  bool get _ar => widget.isAr;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final f = await _db.rpc('platform_staff_list_image_flags');
      final e = await _db.rpc('platform_staff_list_escalations');
      if (!mounted) return;
      setState(() {
        _flags = _rows(f);
        _escalations = _rows(e);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _rows(dynamic v) {
    if (v is! List) return const [];
    return v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  Future<String?> _askNote(String title) async {
    final ctrl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          maxLength: 300,
          decoration: InputDecoration(
            hintText:
                _ar ? 'ملاحظة القرار (اختياري)' : 'Decision note (optional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_ar ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(_ar ? 'تأكيد' : 'Confirm'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return res;
  }

  Future<void> _run(String key, Future<dynamic> Function() call) async {
    setState(() => _busy.add(key));
    String msg;
    try {
      final r = await call();
      final ok = r is Map && r['ok'] == true;
      msg = ok
          ? (_ar ? 'تم تنفيذ القرار' : 'Decision saved')
          : (_ar ? 'تعذر التنفيذ: ${r is Map ? r['error'] : ''}' : 'Failed');
    } catch (e) {
      msg = '$e';
    }
    if (!mounted) return;
    setState(() => _busy.remove(key));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    await _load();
  }

  Future<void> _reviewFlag(Map<String, dynamic> f, String decision) async {
    final note = await _askNote(
      decision == 'confirmed'
          ? (_ar ? 'تأكيد التشابه وإخفاء الإعلان' : 'Confirm and hide listing')
          : (_ar ? 'رفض العلامة (لا تشابه)' : 'Dismiss flag'),
    );
    if (note == null) return;
    final id = '${f['id']}';
    await _run(
      'flag-$id',
      () => _db.rpc(
        'platform_staff_review_image_flag',
        params: {'p_flag_id': id, 'p_decision': decision, 'p_note': note},
      ),
    );
  }

  Future<void> _resolve(Map<String, dynamic> e, bool hide) async {
    final note = await _askNote(
      hide
          ? (_ar ? 'إخفاء الإعلان' : 'Hide listing')
          : (_ar ? 'إبقاء الإعلان ظاهرًا' : 'Keep listing visible'),
    );
    if (note == null) return;
    final id = '${e['property_id']}';
    await _run(
      'esc-$id',
      () => _db.rpc(
        'platform_staff_resolve_listing_escalation',
        params: {'p_property_id': id, 'p_hide': hide, 'p_note': note},
      ),
    );
  }

  String _short(Object? id) {
    final s = '${id ?? ''}';
    return s.length > 8 ? s.substring(0, 8) : s;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _ar ? 'سلامة الإعلانات' : 'Listing integrity',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: _ar ? 'تحديث' : 'Refresh',
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _ar
                    ? 'تعذر التحميل. تأكد من تطبيق آخر الترحيلات.\n$_error'
                    : 'Load failed: $_error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          _section(
            _ar ? 'صور مشابهة بانتظار المراجعة' : 'Similar images to review',
            Icons.image_search_outlined,
            _flags.length,
          ),
          if (_flags.isEmpty) _empty(),
          ..._flags.map(_flagCard),
          const SizedBox(height: 16),
          _section(
            _ar ? 'إعلانات مُصعَّدة بالبلاغات' : 'Escalated by reports',
            Icons.flag_outlined,
            _escalations.length,
          ),
          if (_escalations.isEmpty) _empty(),
          ..._escalations.map(_escalationCard),
        ],
      ),
    );
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(_ar ? 'لا توجد حالات مفتوحة.' : 'No open cases.'),
      );

  Widget _section(String t, IconData i, int n) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Row(
          children: [
            Icon(i, size: 20),
            const SizedBox(width: 6),
            Text(t, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(width: 6),
            Chip(
              label: Text('$n'),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      );

  Widget _flagCard(Map<String, dynamic> f) {
    final busy = _busy.contains('flag-${f['id']}');
    final exact = (f['exact_images'] as num?)?.toInt() ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _ar
                  ? 'إعلان ${_short(f['property_id'])} يشبه إعلانًا آخر (${_short(f['matched_property_id'])})'
                  : 'Listing ${_short(f['property_id'])} resembles ${_short(f['matched_property_id'])}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              _ar
                  ? 'صور متطابقة: ${f['matched_images']} · مطابقة حرفية: $exact · أقل فرق: ${f['min_distance']}'
                  : 'Matched: ${f['matched_images']} · exact: $exact · min distance: ${f['min_distance']}',
              style: const TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: busy ? null : () => _reviewFlag(f, 'dismissed'),
                  child: Text(_ar ? 'لا تشابه' : 'Dismiss'),
                ),
                FilledButton(
                  onPressed: busy ? null : () => _reviewFlag(f, 'confirmed'),
                  child: Text(_ar ? 'تأكيد وإخفاء' : 'Confirm & hide'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _escalationCard(Map<String, dynamic> e) {
    final busy = _busy.contains('esc-${e['property_id']}');
    final title = '${e['title'] ?? ''}'.trim();
    final hidden = e['staff_hidden'] == true || e['suppressed'] == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.isEmpty ? _short(e['property_id']) : title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              _ar
                  ? 'مبلّغون مختلفون (7 أيام): ${e['distinct_reporters_7d']} · ${hidden ? 'مخفي حاليًا' : 'ظاهر حاليًا'}'
                  : 'Distinct reporters (7d): ${e['distinct_reporters_7d']} · ${hidden ? 'hidden' : 'visible'}',
              style: const TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: busy ? null : () => _resolve(e, false),
                  child: Text(_ar ? 'إبقاء ظاهرًا' : 'Keep visible'),
                ),
                FilledButton(
                  onPressed: busy ? null : () => _resolve(e, true),
                  child: Text(_ar ? 'إخفاء' : 'Hide'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
