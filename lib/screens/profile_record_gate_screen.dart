import 'package:flutter/material.dart';

import '../core/auth/safe_sign_out_service.dart';
import '../widgets/app_logo_loading.dart';

/// عند غياب صف [users_profiles] أو فشل تحميله — لا يُسمح باستخدام التطبيق قبل الإصلاح.
class ProfileRecordGateScreen extends StatefulWidget {
  const ProfileRecordGateScreen({
    super.key,
    required this.lang,
    required this.onRetry,
  });

  final String lang;
  final Future<void> Function() onRetry;

  @override
  State<ProfileRecordGateScreen> createState() =>
      _ProfileRecordGateScreenState();
}

class _ProfileRecordGateScreenState extends State<ProfileRecordGateScreen> {
  bool _busy = false;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  Future<void> _signOut() async {
    if (!mounted) return;
    await SafeSignOutService.signOutAndNavigateToLogin(context);
  }

  Future<void> _retry() async {
    setState(() => _busy = true);
    try {
      await widget.onRetry();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.warning_amber_rounded, size: 56, color: cs.error),
                const SizedBox(height: 16),
                Text(
                  _isAr
                      ? 'الملف التعريفي غير مكتمل أو تعذّر تحميله'
                      : 'Profile record missing or could not be loaded',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  _isAr
                      ? 'لضمان الامتثال (توقيع، رخصة فال، بيانات صحيحة) يجب أن يكون لديك صف ملف في النظام. '
                          'إن استمر التعذر، تواصل مع الدعم أو سجّل الخروج ثم الدخول من جديد.'
                      : 'For compliance (signature, FAL license, valid data) your profile row must exist. '
                          'If this persists, contact support or sign out and sign in again.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.45,
                        color: cs.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                if (_busy)
                  const Center(child: AppLogoLoading(size: 56))
                else ...[
                  FilledButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(
                      _isAr ? 'إعادة المحاولة' : 'Retry',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout_rounded),
                    label: Text(
                      _isAr ? 'تسجيل الخروج' : 'Sign out',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
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
