import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// تشخيص مراحل إقلاع الويب — يظهر في Console بـ `[AqarWebDiag]`.
///
/// على الويب يُطبَع دائماً (حتى release) لتسهيل تتبّع التجمّد بعد الدخول.
abstract final class WebBootstrapDiag {
  static final Map<String, Stopwatch> _active = {};
  static final Map<String, Timer> _watchdogs = {};
  static bool _frameTimingArmed = false;
  static DateTime? _lastSlowFrameLog;

  static void log(String phase, [String? detail]) {
    if (!kIsWeb) return;
    final extra = detail == null || detail.isEmpty ? '' : ' — $detail';
    // ignore: avoid_print
    print('[AqarWebDiag] $phase$extra');
  }

  static void start(String phase) {
    if (!kIsWeb) return;
    final sw = Stopwatch()..start();
    _active[phase] = sw;
    log('▶ $phase');
    armFreezeWatchdog(phase, after: const Duration(seconds: 25));
  }

  static void end(String phase, [String? detail]) {
    if (!kIsWeb) return;
    disarmFreezeWatchdog(phase);
    final sw = _active.remove(phase);
    final ms = sw?.elapsedMilliseconds;
    final timing = ms == null ? '' : ' (${ms}ms)';
    final extra = detail == null || detail.isEmpty ? '' : ' — $detail';
    log('✓ $phase$timing$extra');
  }

  static void warn(String phase, String detail) {
    if (!kIsWeb) return;
    log('⚠ $phase — $detail');
  }

  /// إن لم يُستدعَ [end]/[disarmFreezeWatchdog] خلال [after] يُسجَّل اشتباه تجمّد.
  static void armFreezeWatchdog(
    String phase, {
    Duration after = const Duration(seconds: 20),
  }) {
    if (!kIsWeb) return;
    _watchdogs.remove(phase)?.cancel();
    _watchdogs[phase] = Timer(after, () {
      _watchdogs.remove(phase);
      if (_active.containsKey(phase) || phase.startsWith('guest.')) {
        warn(
          'FREEZE?',
          '$phase still open after ${after.inSeconds}s — UI may be stuck',
        );
      }
    });
  }

  static void disarmFreezeWatchdog(String phase) {
    _watchdogs.remove(phase)?.cancel();
  }

  /// يسجّل الإطارات البطيئة (>120ms) بعد الدخول — مرة كل ثانيتين كحد أقصى.
  static void ensureFrameTimingProbe() {
    if (!kIsWeb || _frameTimingArmed) return;
    _frameTimingArmed = true;
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final t in timings) {
        final totalMs = t.totalSpan.inMilliseconds;
        if (totalMs < 120) continue;
        final now = DateTime.now();
        if (_lastSlowFrameLog != null &&
            now.difference(_lastSlowFrameLog!) < const Duration(seconds: 2)) {
          continue;
        }
        _lastSlowFrameLog = now;
        warn(
          'slow.frame',
          '${totalMs}ms build=${t.buildDuration.inMilliseconds}ms',
        );
      }
    });
    log('frame.probe', 'armed');
  }
}
