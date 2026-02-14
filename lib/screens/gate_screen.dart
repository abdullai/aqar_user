import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/session/app_session.dart';

// ✅ Internet guard
import '../services/connectivity_guard.dart';
import '../shared/widgets/no_internet_dialog.dart';

class GateScreen extends StatelessWidget {
  const GateScreen({super.key});

  // Gate غالباً عربي – اربطه بـ langNotifier لاحقاً إن رغبت
  bool get _isAr => true;

  /// فحص الإنترنت + تنبيه
  Future<bool> _ensureInternet(BuildContext context) async {
    final ok = await ConnectivityGuard.hasInternet();
    if (!ok && context.mounted) {
      await showNoInternetDialog(context, isAr: _isAr);
    }
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isAr ? 'بوابة الدخول' : 'Entry Gate'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // =========================
                // دخول كمستخدم
                // =========================
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      // ❌ لا انتقال بدون إنترنت
                      final ok = await _ensureInternet(context);
                      if (!ok) return;

                      Navigator.of(context).pushNamed('/login');
                    },
                    child: Text(_isAr ? 'تسجيل الدخول' : 'Login'),
                  ),
                ),

                const SizedBox(height: 12),

                // =========================
                // دخول كضيف
                // =========================
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () async {
                      // ❌ لا دخول كضيف بدون إنترنت
                      // (لأن الداشبورد يعتمد على بيانات عامة)
                      final ok = await _ensureInternet(context);
                      if (!ok) return;

                      final session = context.read<AppSession>();
                      await session.setGuest();

                      if (!context.mounted) return;

                      // العودة لنقطة البداية المنطقية
                      Navigator.of(context).pushNamedAndRemoveUntil(
                        '/',
                        (r) => false,
                      );
                    },
                    child: Text(_isAr ? 'الدخول كضيف' : 'Continue as guest'),
                  ),
                ),

                const SizedBox(height: 16),

                Text(
                  _isAr
                      ? 'ملاحظة: بعض الميزات (إضافة إعلان / رقم المعلن / الحجز / الدردشة) تتطلب تسجيل الدخول.'
                      : 'Note: Some features require login.',
                  textAlign: TextAlign.center,
                ),

                if (kIsWeb) ...[
                  const SizedBox(height: 12),
                  Text(
                    _isAr
                        ? 'على الويب قد يتم نقلك لشاشة الاختيار (مستخدم/ضيف) حسب إعدادات البداية.'
                        : 'On web, you may be routed to the entry choice screen depending on start rules.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
