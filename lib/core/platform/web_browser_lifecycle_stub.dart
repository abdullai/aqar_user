import 'package:flutter/widgets.dart';

/// على المنصات غير الويب: لا اعتراض F5.
void installWebBrowserLifecycle({
  required bool Function() shouldOfferRefresh,
  required Future<bool> Function() onRefreshPrompt,
}) {}

void disposeWebBrowserLifecycle() {}

void suppressWebBeforeUnloadBriefly() {}

Widget wrapWebBrowserRefreshShortcuts({
  required Widget child,
  required Future<bool> Function() onRefreshPrompt,
  bool Function()? shouldOfferRefresh,
}) {
  return child;
}
