// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;

void Function({required bool isForward, required bool leavingOrigin})? _onTraverse;
StreamSubscription<html.Event>? _sub;
int _ignoreCount = 0;
int _idx = 0;
int _hold = 0;

void installWebInAppHistory({
  required void Function({required bool isForward, required bool leavingOrigin})
      onTraverse,
}) {
  _onTraverse = onTraverse;
  _sub?.cancel();
  try {
    html.window.history.scrollRestoration = 'manual';
  } catch (_) {}
  _idx = 0;
  try {
    html.window.history.replaceState({'aqar': 0}, '', html.window.location.href);
    html.window.history.pushState({'aqar': 1}, '', html.window.location.href);
    _idx = 1;
  } catch (_) {}
  _sub = html.window.onPopState.listen(_onPopState);
}

void disposeWebInAppHistory() {
  _sub?.cancel();
  _sub = null;
  _onTraverse = null;
}

void webInAppHistoryPushEntry() {
  if (_ignoreCount > 0) return;
  _idx++;
  try {
    html.window.history.pushState({'aqar': _idx}, '', html.window.location.href);
  } catch (_) {}
}

void webInAppHistoryGoBack() {
  // لا نغادر أصل التطبيق عند إغلاق صفحة داخلية (تفاصيل/خريطة).
  if (_idx <= 1) return;
  _ignoreCount++;
  _idx -= 1;
  try {
    html.window.history.back();
  } catch (_) {
    if (_ignoreCount > 0) _ignoreCount--;
  }
}

void webInAppHistoryTrapLeaving() {
  try {
    html.window.history.pushState({'aqar': _idx}, '', html.window.location.href);
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
  _ignoreCount++;
  _idx = 0;
  try {
    final loc = html.window.location;
    final h = hash.startsWith('#') ? hash : '#$hash';
    final next = '${loc.pathname}${loc.search}$h';
    html.window.history.replaceState({'aqar': 0}, '', next);
    html.window.history.pushState({'aqar': 1}, '', html.window.location.href);
    _idx = 1;
  } catch (_) {}
  if (_ignoreCount > 0) _ignoreCount--;
}

void _onPopState(html.Event _) {
  if (_ignoreCount > 0) {
    _ignoreCount--;
    return;
  }
  if (_hold > 0) {
    webInAppHistoryTrapLeaving();
    return;
  }
  int? i;
  try {
    final st = html.window.history.state;
    if (st is Map) {
      final v = st['aqar'];
      if (v is int) i = v;
      if (v is num) i = v.toInt();
    }
  } catch (_) {}

  if (i == null) {
    // hash sync قد يمسح الحالة — أعد المصيدة ولا تُغلق الجلسة.
    webInAppHistoryTrapLeaving();
    if (_idx < 1) _idx = 1;
    return;
  }

  if (i < _idx) {
    _idx = i;
    if (i <= 0) {
      webInAppHistoryTrapLeaving();
      _idx = 1;
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
