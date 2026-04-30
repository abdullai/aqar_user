// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

String readWebUserAgent() => html.window.navigator.userAgent ?? '';
