// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../navigation/app_web_soft_refresh.dart';

bool Function()? _shouldOfferRefresh;
Future<bool> Function()? _onRefreshPrompt;

/// على الويب: لا نعترض F5/Ctrl+R ولا beforeunload — كان يمنع التحديث القوي
/// ويُبقي التبويب «لا يستجيب» عند تعليق [_reloadAll].
void installWebBrowserLifecycle({
  required bool Function() shouldOfferRefresh,
  required Future<bool> Function() onRefreshPrompt,
}) {
  _shouldOfferRefresh = shouldOfferRefresh;
  _onRefreshPrompt = onRefreshPrompt;
}

void disposeWebBrowserLifecycle() {
  _shouldOfferRefresh = null;
  _onRefreshPrompt = null;
}

/// اختصارات Flutter (اختياري — لا تمنع التحديث الأصلي للمتصفح).
class _WebSoftRefreshIntent extends Intent {
  const _WebSoftRefreshIntent();
}

Widget wrapWebBrowserRefreshShortcuts({
  required Widget child,
  required Future<bool> Function() onRefreshPrompt,
  bool Function()? shouldOfferRefresh,
}) {
  if (!kIsWeb) return child;
  return Shortcuts(
    shortcuts: const <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.f5): _WebSoftRefreshIntent(),
      SingleActivator(LogicalKeyboardKey.keyR, control: true):
          _WebSoftRefreshIntent(),
      SingleActivator(LogicalKeyboardKey.keyR, meta: true):
          _WebSoftRefreshIntent(),
    },
    child: Actions(
      actions: <Type, Action<Intent>>{
        _WebSoftRefreshIntent: CallbackAction<_WebSoftRefreshIntent>(
          onInvoke: (_) {
            unawaited(() async {
              final gate = shouldOfferRefresh ?? _shouldOfferRefresh;
              if (gate != null && !gate()) return;
              if (AppWebSoftRefresh.hasHandler) {
                await AppWebSoftRefresh.invoke();
                return;
              }
              final prompt = _onRefreshPrompt ?? onRefreshPrompt;
              if (await prompt()) {
                await AppWebSoftRefresh.invoke();
              }
            }());
            return null;
          },
        ),
      },
      child: child,
    ),
  );
}

/// للتوافق مع استدعاءات الخروج البرمجي.
void suppressWebBeforeUnloadBriefly() {}
