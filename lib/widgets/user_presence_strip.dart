import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/chat_peer_service.dart';

/// سطر صغير: متصل الآن / آخر ظهور — يحدّث عبر Realtime عند توفره.
class UserPresenceStrip extends StatefulWidget {
  const UserPresenceStrip({
    super.key,
    required this.userId,
    required this.isAr,
    this.compact = true,
  });

  final String userId;
  final bool isAr;
  final bool compact;

  @override
  State<UserPresenceStrip> createState() => _UserPresenceStripState();
}

class _UserPresenceStripState extends State<UserPresenceStrip> {
  final _sb = Supabase.instance.client;
  Map<String, dynamic>? _row;
  RealtimeChannel? _ch;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void didUpdateWidget(covariant UserPresenceStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _disposeChannel();
      unawaited(_bootstrap());
    }
  }

  Future<void> _bootstrap() async {
    final id = widget.userId.trim();
    if (id.isEmpty) return;
    await _pull();
    _subscribe(id);
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 50), (_) => _pull());
  }

  Future<void> _pull() async {
    final id = widget.userId.trim();
    if (id.isEmpty) return;
    try {
      final r = await _sb
          .from('users_profiles')
          .select('chat_last_seen_at, chat_last_seen_hidden')
          .eq('user_id', id)
          .maybeSingle();
      if (!mounted) return;
      setState(() => _row = r == null ? null : Map<String, dynamic>.from(r));
    } catch (_) {}
  }

  void _subscribe(String id) {
    try {
      _ch = _sb
          .channel('presence_strip_$id')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'users_profiles',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: id,
            ),
            callback: (payload) {
              final rec = payload.newRecord;
              if (!mounted) return;
              setState(() => _row = Map<String, dynamic>.from(rec));
            },
          )
          ..subscribe();
    } catch (_) {}
  }

  void _disposeChannel() {
    _poll?.cancel();
    _poll = null;
    try {
      _ch?.unsubscribe();
    } catch (_) {}
    _ch = null;
  }

  @override
  void dispose() {
    _disposeChannel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.userId.trim();
    if (id.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final line = ChatPeerService.formatPresenceLine(_row, widget.isAr);
    final online = line == (widget.isAr ? 'متصل الآن' : 'Online');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: widget.compact ? 7 : 8,
          height: widget.compact ? 7 : 8,
          decoration: BoxDecoration(
            color: online ? const Color(0xFF16A34A) : cs.outlineVariant,
            shape: BoxShape.circle,
            boxShadow: online
                ? [
                    BoxShadow(
                      color: const Color(0xFF16A34A).withValues(alpha: 0.35),
                      blurRadius: 5,
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            line,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: widget.compact ? 11 : 12,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
