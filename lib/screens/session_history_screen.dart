import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart' show langNotifier;
import '../services/session_tracking_service.dart';
import '../widgets/session_tile.dart';

class SessionHistoryScreen extends StatefulWidget {
  const SessionHistoryScreen({super.key});

  @override
  State<SessionHistoryScreen> createState() => _SessionHistoryScreenState();
}

class _SessionHistoryScreenState extends State<SessionHistoryScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String _deviceFilter = '';
  DateTime? _from;
  DateTime? _to;
  String? _currentTrackedId;

  bool get _isAr => langNotifier.value != 'en';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final sid = await SessionTrackingService.currentTrackedSessionId();
    if (mounted) setState(() => _currentTrackedId = sid);
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // تنظيف تلقائي للجلسات الأقدم من 90 يوماً لتخفيف الحمل.
      try {
        await Supabase.instance.client.rpc(
          'purge_my_old_user_sessions',
          params: {'p_days': 90},
        );
      } catch (_) {}

      dynamic raw =
          await Supabase.instance.client.rpc('list_my_user_sessions');
      if (raw is String) {
        try {
          raw = jsonDecode(raw);
        } catch (_) {}
      }
      List<Map<String, dynamic>> list = [];
      if (raw is List) {
        list = raw
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else if (raw is Map && raw['ok'] == false) {
        list = [];
      }
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Iterable<Map<String, dynamic>> get _filtered sync* {
    for (final e in _items) {
      final q = _deviceFilter.trim().toLowerCase();
      if (q.isNotEmpty) {
        final blob =
            '${e['device_info']} ${e['browser_info']} ${e['os_info']}'
                .toLowerCase();
        if (!blob.contains(q)) continue;
      }
      if (_from != null) {
        final t = DateTime.tryParse('${e['login_at']}');
        if (t == null || t.isBefore(_from!)) continue;
      }
      if (_to != null) {
        final t = DateTime.tryParse('${e['login_at']}');
        if (t == null || t.isAfter(_to!.add(const Duration(days: 1)))) {
          continue;
        }
      }
      yield e;
    }
  }

  Future<void> _revokeOthers() async {
    final res = await SessionTrackingService.revokeOtherSessions(
      Supabase.instance.client,
      keepSessionId: _currentTrackedId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${res['closed'] ?? res}')),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered.toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(_isAr ? 'سجل الجلسات' : 'Session history'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 600;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: narrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _filterChildren(),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: _filterChildren()),
                      ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: rows.length,
                        itemBuilder: (_, i) {
                          final s = rows[i];
                          final id = '${s['id'] ?? ''}';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SessionTile(
                              isArabic: _isAr,
                              session: s,
                              isCurrent: id.isNotEmpty &&
                                  id == _currentTrackedId,
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _filterChildren() {
    return [
      SizedBox(
        width: 200,
        child: AqarTextField(
          decoration: InputDecoration(
            labelText: _isAr ? 'فلتر جهاز' : 'Device filter',
            isDense: true,
          ),
          onChanged: (v) => setState(() => _deviceFilter = v),
        ),
      ),
      const SizedBox(width: 8, height: 8),
      FilledButton.tonal(
        onPressed: () async {
          final now = DateTime.now();
          final f = await showDatePicker(
            context: context,
            initialDate: _from ?? now,
            firstDate: DateTime(now.year - 2),
            lastDate: now,
          );
          if (f != null) setState(() => _from = f);
        },
        child: Text(_isAr ? 'من تاريخ' : 'From'),
      ),
      const SizedBox(width: 8, height: 8),
      FilledButton.tonal(
        onPressed: () async {
          final now = DateTime.now();
          final f = await showDatePicker(
            context: context,
            initialDate: _to ?? now,
            firstDate: DateTime(now.year - 2),
            lastDate: now,
          );
          if (f != null) setState(() => _to = f);
        },
        child: Text(_isAr ? 'إلى تاريخ' : 'To'),
      ),
      const SizedBox(width: 8, height: 8),
      TextButton(
        onPressed: () => setState(() {
          _from = null;
          _to = null;
          _deviceFilter = '';
        }),
        child: Text(_isAr ? 'مسح' : 'Clear'),
      ),
      const SizedBox(width: 8, height: 8),
      FilledButton.icon(
        onPressed: _revokeOthers,
        icon: const Icon(Icons.phonelink_erase_outlined),
        label: Text(
          _isAr ? 'إنهاء الجلسات الأخرى' : 'End other sessions',
        ),
      ),
    ];
  }
}
