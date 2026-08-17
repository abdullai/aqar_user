import '../core/branding/app_branding.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// نافذة «عن التطبيق / المنصّة» الموحّدة مع أرقام للاتصال أو واتساب.
abstract final class AppAboutCredits {
  AppAboutCredits._();

  static String _digitsOnly(String raw) =>
      raw.replaceAll(RegExp(r'\D'), '');

  /// رقم واتساب دولي بدون + (مثال: 966555317770).
  static String whatsappInternationalDigits(String saOrIntl) {
    var d = _digitsOnly(saOrIntl);
    if (d.isEmpty) return '';
    if (d.startsWith('0')) return '966${d.substring(1)}';
    if (d.startsWith('966')) return d;
    return '966$d';
  }

  static Future<void> showPhoneChannelSheet(
    BuildContext context, {
    required bool isAr,
    required String phoneDisplay,
  }) async {
    final raw = _digitsOnly(phoneDisplay);
    if (raw.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.call_outlined),
                title: Text(isAr ? 'اتصال صوتي' : 'Voice call'),
                subtitle: Text(
                  phoneDisplay,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final u = Uri.parse('tel:$raw');
                  try {
                    await launchUrl(u);
                  } catch (_) {}
                },
              ),
              ListTile(
                leading: const Icon(Icons.chat_outlined, color: Color(0xFF25D366)),
                title: Text(isAr ? 'مراسلة عبر واتساب' : 'WhatsApp message'),
                subtitle: Text(
                  isAr
                      ? 'يفتح تطبيق واتساب أو واتساب ويب حسب الجهاز.'
                      : 'Opens WhatsApp app or WhatsApp Web.',
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final wa = whatsappInternationalDigits(phoneDisplay);
                  if (wa.isEmpty) return;
                  final u = Uri.parse('https://wa.me/$wa');
                  try {
                    await launchUrl(u, mode: LaunchMode.externalApplication);
                  } catch (_) {}
                },
              ),
            ],
          ),
        );
      },
    );
  }

  static void show(
    BuildContext context, {
    required bool isAr,
    String versionLine = '',
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final title = isAr
            ? (AppBranding.usesEstablishmentDisplayName ? 'عن المنصّة' : 'عن التطبيق')
            : (AppBranding.usesEstablishmentDisplayName
                ? 'About this platform'
                : 'About this app');
        final establishment = AppBranding.usesEstablishmentDisplayName;
        final intro = isAr
            ? (establishment
                ? 'هذه المنصّة جزء من منظومة ${AppBranding.legalName(isAr: true)}.'
                : 'هذا التطبيق جزء من منظومة ${AppBranding.brandNameAr}.')
            : (establishment
                ? 'This platform is part of the ${AppBranding.legalName(isAr: false)} suite.'
                : 'This app is part of the ${AppBranding.brandNameEn} suite.');

        return AlertDialog(
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  intro,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                if (versionLine.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SelectableText(
                    isAr
                        ? '${AppBranding.usesEstablishmentDisplayName ? 'منصّة' : 'تطبيق جوّال'} — الإصدار: $versionLine'
                        : '${AppBranding.usesEstablishmentDisplayName ? 'Platform' : 'Mobile app'} — Version: $versionLine',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: cs.primary,
                      height: 1.25,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  isAr ? 'فكرة ومتابعة:' : 'Concept and supervision:',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isAr
                      ? 'الأستاذ / عبداللطيف بن سلطان المطيري'
                      : 'Mr. Abdullatif bin Sultan Al-Mutairi',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                _PhoneLink(
                  isAr: isAr,
                  phone: '0555317770',
                ),
                const SizedBox(height: 16),
                Text(
                  isAr ? 'التنفيذ والبرمجة:' : 'Implementation and engineering:',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isAr
                      ? 'المهندس / عبدالله بن عيسى أبوحيه'
                      : 'Eng. Abdullah bin Isa Abu Hayah',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                _PhoneLink(
                  isAr: isAr,
                  phone: '0501967955',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(isAr ? 'إغلاق' : 'Close'),
            ),
          ],
        );
      },
    );
  }
}

class _PhoneLink extends StatelessWidget {
  const _PhoneLink({required this.isAr, required this.phone});

  final bool isAr;
  final String phone;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => AppAboutCredits.showPhoneChannelSheet(
        context,
        isAr: isAr,
        phoneDisplay: phone,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          children: [
            Icon(Icons.phone_in_talk_outlined, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            Text(
              phone,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: cs.primary,
                decoration: TextDecoration.underline,
                decorationColor: cs.primary,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.arrow_drop_down, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
