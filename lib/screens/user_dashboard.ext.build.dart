// lib/screens/user_dashboard.ext.build.dart
part of 'user_dashboard.dart';

// === ملف: user_dashboard.ext.build.dart ===
// الهدف: تجميع منطق build المساعد (Back handling) خارج ui.dart بدون تغيير سلوك التطبيق الحالي.

extension _UserDashboardStateBuildExt on _UserDashboardState {
  Future<bool> _handleDashboardBack() async {
    // ✅ الحفاظ على نفس السلوك الموجود سابقاً داخل ui.dart:
    // - الضيف: نعيده للصفحة الرئيسية '/' ولا نسمح بالرجوع للخلف
    // - المستخدم المسجل: لا نسمح بالرجوع للخلف (يبقى داخل الداشبورد)
    if (_isGuest) {
      if (!mounted) return false;
      Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
      return false;
    }
    return false;
  }
}