import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// بث «جاري الكتابة» فوري عبر قناة Realtime (مثل واتساب).
class ChatTypingSession {
  ChatTypingSession({
    required this.sb,
    required this.conversationId,
    required this.myUserId,
  });

  final SupabaseClient sb;
  final String conversationId;
  final String myUserId;

  final ValueNotifier<bool> peerTyping = ValueNotifier<bool>(false);

  RealtimeChannel? _ch;
  Timer? _idle;
  Timer? _peerIdle;
  bool _lastSent = false;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    final cid = conversationId.trim();
    final me = myUserId.trim();
    if (cid.isEmpty || me.isEmpty) return;
    _started = true;
    try {
      final ch = sb.channel('chat_live_$cid');
      ch.onBroadcast(
        event: 'typing',
        callback: (payload) {
          var map = Map<String, dynamic>.from(payload);
          final inner = map['payload'];
          if (inner is Map) {
            map = Map<String, dynamic>.from(inner);
          }
          final uid = (map['uid'] ?? '').toString().trim();
          if (uid.isEmpty || uid == me) return;
          final on = map['on'] == true || map['on'] == 'true';
          peerTyping.value = on;
          _peerIdle?.cancel();
          if (on) {
            _peerIdle = Timer(const Duration(seconds: 4), () {
              peerTyping.value = false;
            });
          }
        },
      );
      ch.subscribe();
      _ch = ch;
    } catch (_) {
      _started = false;
    }
  }

  void onComposerChanged(String text) {
    final typing = text.trim().isNotEmpty;
    if (typing == _lastSent) {
      if (typing) _bumpIdle();
      return;
    }
    _lastSent = typing;
    unawaited(_send(typing));
    if (typing) {
      _bumpIdle();
    } else {
      _idle?.cancel();
    }
  }

  void _bumpIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(milliseconds: 1600), () {
      if (!_lastSent) return;
      _lastSent = false;
      unawaited(_send(false));
    });
  }

  Future<void> _send(bool on) async {
    final ch = _ch;
    if (ch == null) return;
    try {
      await ch.sendBroadcastMessage(
        event: 'typing',
        payload: <String, dynamic>{
          'uid': myUserId,
          'on': on,
        },
      );
    } catch (_) {}
  }

  Future<void> dispose() async {
    _idle?.cancel();
    _peerIdle?.cancel();
    if (_lastSent) {
      await _send(false);
    }
    peerTyping.value = false;
    try {
      await _ch?.unsubscribe();
    } catch (_) {}
    _ch = null;
    peerTyping.dispose();
  }
}
