import 'package:flutter/foundation.dart';

const bool kIsAdminApp =
    bool.fromEnvironment('IS_ADMIN_APP', defaultValue: false);
const bool kIsProd = bool.fromEnvironment('PROD', defaultValue: false);

/// ويندوز الأصلي أو بناء `IS_ADMIN_APP`: سطح تشغيل المنصة فقط (لا سوق).
bool get kIsOpsDesktopSurface {
  if (kIsAdminApp) return true;
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.windows;
}
