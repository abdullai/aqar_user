import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/branding/aqar_brand_colors.dart';
import '../core/presence/presence_display_prefs.dart';
import '../services/chat_peer_service.dart';
import 'presence_feature_info_button.dart';

/// سطر صغير: متصل الآن / آخر ظهور — يحدّث عبر Realtime عند توفره.
///
/// على الويب: جلب خفيف + تحديث كل 12 ثانية.
/// على الجوال: Realtime + استطلاع كل 15 ثانية.
class UserPresenceStrip extends StatefulWidget {
  const UserPresenceStrip({
    super.key,
    required this.userId,
    required this.isAr,
    this.compact = true,
    this.fallbackTimestamp,
    this.surface = PresenceDisplaySurface.listingCards,
    this.showInfoButton = true,
  });

  final String userId;
  final bool isAr;
  final bool compact;
  final DateTime? fallbackTimestamp;
  final PresenceDisplaySurface surface;
  final bool showInfoButton;

  @override
  State<UserPresenceStrip> createState() => _UserPresenceStripState();
}

class _UserPresenceStripState extends State<UserPresenceStrip> {
  final _sb = Supabase.instance.client;
  Map<String, dynamic>? _row;
  bool _bootstrapped = false;
  RealtimeChannel? _ch;
  Timer? _poll;

  static final Map<String, ({Map<String, dynamic>? row, DateTime at})> _cache =
      {};

  @override
  void initState() {
    super.initState();
    unawaited(PresenceDisplayPrefs.instance.ensureLoaded());
    PresenceDisplayPrefs.instance.addListener(_onPrefs);
    unawaited(_bootstrap());
  }

  void _onPrefs() {
    if (mounted) setState(() {});
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

    final cached = _cache[id];
    if (cached != null &&
        DateTime.now().difference(cached.at) < const Duration(seconds: 20)) {
      if (mounted) {
        setState(() {
          _row = cached.row;
          _bootstrapped = true;
        });
      }
    }

    await _pull();
    if (!kIsWeb) {
      _subscribe(id);
    }
    _poll?.cancel();
    _poll = Timer.periodic(
      Duration(seconds: kIsWeb ? 12 : 15),
      (_) => _pull(),
    );
  }

  Future<void> _pull() async {
    final id = widget.userId.trim();
    if (id.isEmpty) return;
    try {
      final res = await _sb
          .rpc(
            'get_user_presence_summary',
            params: {'p_user_id': id},
          )
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      Map<String, dynamic>? row;
      if (res is Map) {
        final m = Map<String, dynamic>.from(
          res.map((k, v) => MapEntry(k.toString(), v)),
        );
        if (m['ok'] == true) {
          row = <String, dynamic>{
            'chat_last_seen_at': m['last_seen_at'],
            'chat_last_seen_hidden': m['hidden'] == true,
            '_online_now_hint': m['online_now'] == true,
          };
        }
      }
      _cache[id] = (row: row, at: DateTime.now());
      setState(() {
        _row = row;
        _bootstrapped = true;
      });
    } catch (_) {
      if (_sb.auth.currentSession == null) {
        if (mounted) setState(() => _bootstrapped = true);
        return;
      }
      try {
        final r = await _sb
            .from('users_profiles')
            .select('chat_last_seen_at, chat_last_seen_hidden')
            .eq('user_id', id)
            .maybeSingle();
        if (!mounted) return;
        final row = r == null ? null : Map<String, dynamic>.from(r);
        _cache[id] = (row: row, at: DateTime.now());
        setState(() {
          _row = row;
          _bootstrapped = true;
        });
      } catch (_) {
        if (mounted) setState(() => _bootstrapped = true);
      }
    }
  }

  void _subscribe(String id) {
    if (_sb.auth.currentSession == null) return;
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
              final row = Map<String, dynamic>.from(rec);
              _cache[id] = (row: row, at: DateTime.now());
              setState(() => _row = row);
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
    PresenceDisplayPrefs.instance.removeListener(_onPrefs);
    _disposeChannel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.userId.trim();
    if (id.isEmpty) return const SizedBox.shrink();
    if (!PresenceDisplayPrefs.instance.isVisible(widget.surface)) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    final line = _bootstrapped
        ? ChatPeerService.formatPresenceLine(
            _row,
            widget.isAr,
            fallbackTimestamp: widget.fallbackTimestamp,
          )
        : (widget.isAr ? 'جاري التحديث…' : 'Updating…');
    final online = line == (widget.isAr ? 'متصل الآن' : 'Online');
    final isDark = cs.brightness == Brightness.dark;

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 8 : 10,
                vertical: widget.compact ? 4 : 5,
              ),
              decoration: BoxDecoration(
                color: online
                    ? const Color(0xFF16A34A)
                        .withValues(alpha: isDark ? 0.22 : 0.12)
                    : (isDark
                        ? cs.surfaceContainerHighest.withValues(alpha: 0.55)
                        : cs.surfaceContainerHighest.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: online
                      ? const Color(0xFF16A34A).withValues(alpha: 0.45)
                      : AqarBrandColors.gold.withValues(alpha: 0.28),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: widget.compact ? 7 : 8,
                    height: widget.compact ? 7 : 8,
                    decoration: BoxDecoration(
                      color:
                          online ? const Color(0xFF16A34A) : cs.outlineVariant,
                      shape: BoxShape.circle,
                      boxShadow: online
                          ? [
                              BoxShadow(
                                color: const Color(0xFF16A34A)
                                    .withValues(alpha: 0.4),
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
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Cairo',
                        color: online
                            ? (isDark
                                ? const Color(0xFF86EFAC)
                                : const Color(0xFF15803D))
                            : (isDark
                                ? cs.onSurface
                                : const Color(0xFF0A1F1A)),
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.showInfoButton)
            PresenceFeatureInfoButton(
              isAr: widget.isAr,
              compact: widget.compact,
            ),
        ],
      ),
    );
  }
}
