// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'web_bootstrap_diag.dart';

/// يحدّث شريط العنوان إلى `#/userDashboard` بدون إطلاق hashchange
/// وبدون [Navigator] — حتى لا يُعاد بناء اللوحة (كان يجمّد المتصفح).
void syncWebDashboardHashInAddressBar() {
  try {
    final loc = html.window.location;
    final hash = (loc.hash ?? '').replaceFirst('#', '').trim().toLowerCase();
    if (hash == '/userdashboard' || hash == 'userdashboard') return;
    final next = '${loc.pathname}${loc.search}#/userDashboard';
    html.window.history.replaceState(null, '', next);
    WebBootstrapDiag.log('url.hash', 'synced #/userDashboard (replaceState)');
  } catch (e) {
    WebBootstrapDiag.warn('url.hash', '$e');
  }
}
