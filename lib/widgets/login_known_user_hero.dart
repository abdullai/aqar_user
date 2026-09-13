import 'package:flutter/material.dart';

import '../core/branding/app_branding.dart';
import '../core/branding/branding_logo_image.dart';
import '../core/l10n/locale_content.dart';

/// شعار العلامة في شاشات الدخول — حجم متجاوب حسب الشاشة.
class LoginBrandHero extends StatelessWidget {
  const LoginBrandHero({super.key});

  @override
  Widget build(BuildContext context) {
    final size = AppBranding.loginHeroLogoSize(context);
    final frameH = size * 0.72;
    return Semantics(
      label: AppBranding.displayNameForContext(
        context,
        isAr: Directionality.of(context) == TextDirection.rtl,
      ),
      image: true,
      child: SizedBox(
        width: size,
        height: frameH,
        child: BrandingLogoImage(
          width: size,
          height: frameH,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorIcon: Icons.home_work_outlined,
        ),
      ),
    );
  }
}

/// بطاقة هوية بأسلوب مصرفي: ترحيب + الاسم الرباعي.
class LoginKnownUserHero extends StatelessWidget {
  const LoginKnownUserHero({
    super.key,
    required this.isAr,
    required this.displayName,
    this.accent = const Color(0xFF0F766E),
    this.compact = false,
    this.showPasswordPrompt = true,
  });

  final bool isAr;
  final String displayName;
  final Color accent;
  final bool compact;
  final bool showPasswordPrompt;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = LocaleContent.forUi(displayName.trim(), isAr: isAr);

    return Column(
      children: [
        Text(
          isAr ? 'أهلاً بك' : 'Welcome',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: compact ? 13.5 : 14.5,
            fontWeight: FontWeight.w800,
            color: cs.onSurfaceVariant,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              name.isEmpty ? (isAr ? 'مستخدم موثوق' : 'Mawthuq user') : name,
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: compact ? 18 : 20.5,
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
                height: 1.15,
              ),
            ),
          ),
        ),
        if (showPasswordPrompt) ...[
          const SizedBox(height: 4),
          Text(
            isAr ? 'أدخل كلمة المرور للمتابعة' : 'Enter your password to continue',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compact ? 11.5 : 12.5,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant.withValues(alpha: 0.9),
              height: 1.15,
            ),
          ),
        ],
      ],
    );
  }
}
