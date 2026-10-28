// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;

void Function({required bool isForward, required bool leavingOrigin})?
    _onTraverse;
StreamSubscription<html.Event>? _sub;
int _idx = 0;
int _hold = 0;
int? _programmaticBackTarget;
Timer? _programmaticBackTimer;

void installWebInAppHistory({
  required void Function({required bool isForward, required bool leavingOrigin})
      onTraverse,
}) {
  _onTraverse = onTraverse;
  _sub?.cancel();
  _programmaticBackTimer?.cancel();
  _programmaticBackTimer = null;
  _programmaticBackTarget = null;
  _hold = 0;
  try {
    html.window.history.scrollRestoration = 'manual';
  } catch (_) {}
  try {
    final state = html.window.history.state;
    final currentIndex = _readIndex(state);
    if (currentIndex != null && currentIndex > 0) {
      _idx = currentIndex;
    } else {
      _idx = 0;
      html.window.history.replaceState(
        _stateWithIndex(state, 0),
        '',
        html.window.location.href,
      );
      html.window.history.pushState(
        _stateWithIndex(state, 1),
        '',
        html.window.location.href,
      );
      _idx = 1;
    }
  } catch (_) {}
  _sub = html.window.onPopState.listen(_onPopState);
}

void disposeWebInAppHistory() {
  _sub?.cancel();
  _sub = null;
  _onTraverse = null;
  _programmaticBackTimer?.cancel();
  _programmaticBackTimer = null;
  _programmaticBackTarget = null;
  _hold = 0;
}

void webInAppHistoryPushEntry() {
  try {
    final nextIndex = _idx + 1;
    html.window.history.pushState(
      _stateWithIndex(html.window.history.state, nextIndex),
      '',
      html.window.location.href,
    );
    _idx = nextIndex;
  } catch (_) {}
}

void webInAppHistoryGoBack() {
  // لا نغادر أصل التطبيق عند إغلاق صفحة داخلية (تفاصيل/خريطة).
  if (_idx <= 1) return;
  final previousIndex = _idx - 1;
  _programmaticBackTimer?.cancel();
  _programmaticBackTarget = previousIndex;
  _programmaticBackTimer = Timer(const Duration(seconds: 2), () {
    _programmaticBackTarget = null;
    _programmaticBackTimer = null;
  });
  final currentIndex = _idx;
  _idx = previousIndex;
  try {
    html.window.history.back();
  } catch (_) {
    _idx = currentIndex;
    _clearProgrammaticBack();
  }
}

void webInAppHistoryTrapLeaving() {
  try {
    html.window.history.pushState(
      _stateWithIndex(html.window.history.state, _idx),
      '',
      html.window.location.href,
    );
  } catch (_) {}
}

void webInAppHistoryHold() {
  _hold++;
}

void webInAppHistoryRelease() {
  if (_hold > 0) _hold--;
}

/// بعد الخروج: نُثبّت عنوان الدخول ونُعيد مصيدة التاريخ حتى لا يعيد السهم الأيمن الشاشة السابقة.
void webInAppHistorySealAuth({String hash = '#/login'}) {
  _programmaticBackTimer?.cancel();
  _programmaticBackTimer = null;
  _programmaticBackTarget = null;
  _idx = 0;
  try {
    final loc = html.window.location;
    final h = hash.startsWith('#') ? hash : '#$hash';
    final next = '${loc.pathname}${loc.search}$h';
    final state = html.window.history.state;
    html.window.history.replaceState(_stateWithIndex(state, 0), '', next);
    html.window.history.pushState(
      _stateWithIndex(state, 1),
      '',
      html.window.location.href,
    );
    _idx = 1;
  } catch (_) {}
}

void _onPopState(html.Event _) {
  final i = _readIndex(html.window.history.state);
  if (i != null && _programmaticBackTarget == i) {
    _idx = i;
    _clearProgrammaticBack();
    return;
  }
  if (_programmaticBackTarget != null) {
    _clearProgrammaticBack();
  }
  if (_hold > 0) {
    webInAppHistoryTrapLeaving();
    return;
  }

  if (i == null) {
    // hash sync قد يمسح الحالة — أعد المصيدة ولا تُغلق الجلسة.
    if (_idx < 1) _idx = 1;
    webInAppHistoryTrapLeaving();
    return;
  }

  if (i < _idx) {
    _idx = i;
    if (i <= 0) {
      _idx = 1;
      webInAppHistoryTrapLeaving();
      _onTraverse?.call(isForward: false, leavingOrigin: true);
      return;
    }
    _onTraverse?.call(isForward: false, leavingOrigin: false);
    return;
  }

  if (i > _idx) {
    _idx = i;
    _onTraverse?.call(isForward: true, leavingOrigin: false);
  }
}

int? _readIndex(dynamic state) {
  if (state is! Map) return null;
  final value = state['aqar'];
  return value is num ? value.toInt() : null;
}

Map<String, dynamic> _stateWithIndex(dynamic state, int index) {
  final result = <String, dynamic>{};
  if (state is Map) {
    for (final entry in state.entries) {
      if (entry.key is String && entry.key != 'aqar') {
        result[entry.key as String] = entry.value;
      }
    }
  } else if (state != null) {
    result['aqarPreviousState'] = state;
  }
  result['aqar'] = index;
  return result;
}

void _clearProgrammaticBack() {
  _programmaticBackTimer?.cancel();
  _programmaticBackTimer = null;
  _programmaticBackTarget = null;
}
