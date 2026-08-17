import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// رمز استجابة سريعة قابل للمسح بسهولة (منطقة هادئة + حجم كافٍ + تباين عالٍ).
/// يُستخدم في الإيصالات والتقارير وأي شاشة تعرض QR.
class AppReadableQr extends StatelessWidget {
  const AppReadableQr({
    super.key,
    required this.data,
    this.size = 200,
    this.isAr = true,
    this.title,
    this.hint,
    this.caption,
    this.brandColor = const Color(0xFF00695C),
    this.moduleColor = const Color(0xFF004D40),
  });

  final String data;
  final double size;
  final bool isAr;
  final String? title;
  final String? hint;
  final String? caption;
  final Color brandColor;
  final Color moduleColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedTitle =
        title ?? (isAr ? 'رمز الاستجابة السريعة' : 'QR verification code');
    final resolvedHint = hint ??
        (isAr
            ? 'امسح الرمز للتحقق من صحة المستند.'
            : 'Scan to verify this document.');

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                resolvedTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE0E0E0)),
                ),
                child: Padding(
                  // quiet zone — هام لسهولة المسح
                  padding: const EdgeInsets.all(16),
                  child: QrImageView(
                    data: data,
                    version: QrVersions.auto,
                    size: size,
                    gapless: true,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                    eyeStyle: QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: brandColor,
                    ),
                    dataModuleStyle: QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: moduleColor,
                    ),
                  ),
                ),
              ),
              if ((caption ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                SelectableText(
                  caption!.trim(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    letterSpacing: 0.2,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                resolvedHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
