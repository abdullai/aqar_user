import 'package:flutter/material.dart';

import '../shared/core/app_flags.dart';
import 'platform_staff_desk_screen.dart';
import 'user_dashboard.dart';

/// بعد الدخول:
/// - ويندوز الأصلي / `IS_ADMIN_APP` → لوحة التشغيل فقط (غير الموظف يُرفض).
/// - ويب وجوال → سوق المستخدم دائماً (حتى لو كان موظفاً).
class PostLoginHome extends StatelessWidget {
  const PostLoginHome({
    super.key,
    required this.lang,
    this.dashboardKey,
  });

  final String lang;
  final Key? dashboardKey;

  @override
  Widget build(BuildContext context) {
    if (kIsOpsDesktopSurface) {
      return PlatformStaffDeskScreen(lang: lang, opsLocked: true);
    }
    return UserDashboard(
      key: dashboardKey ?? const ValueKey('dashboard'),
      lang: lang,
    );
  }
}
