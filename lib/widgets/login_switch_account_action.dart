import 'package:flutter/material.dart';

import '../core/haptics/app_haptics.dart';

/// رمز صغير تحت حقل كلمة المرور لتغيير الحساب — بأسلوب التطبيقات المصرفية.
class LoginSwitchAccountAction extends StatelessWidget {
  const LoginSwitchAccountAction({
    super.key,
    required this.isAr,
    required this.onPressed,
    this.accent = const Color(0xFF0F766E),
  });

  final bool isAr;
  final VoidCallback? onPressed;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final label = isAr ? 'تغيير الحساب' : 'Switch account';

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Center(
        child: Tooltip(
          message: label,
          child: InkWell(
            onTap: enabled
                ? () {
                    AppHaptics.selection();
                    onPressed!();
                  }
                : null,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: enabled ? 0.10 : 0.05),
                      border: Border.all(
                        color: accent.withValues(alpha: enabled ? 0.45 : 0.18),
                        width: 1.2,
                      ),
                    ),
                    child: Icon(
                      Icons.person_outline_rounded,
                      size: 22,
                      color: enabled
                          ? accent
                          : cs.onSurface.withValues(alpha: 0.38),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isAr ? 'مستخدم آخر' : 'Another user',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      color: enabled
                          ? accent
                          : cs.onSurface.withValues(alpha: 0.38),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
