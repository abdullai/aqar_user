import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/support/support_whatsapp_config.dart';
import '../../core/utils/phone_display.dart';
import '../../l10n/app_localizations.dart';

/// بريد قابل للفتح على الجوال والويب وويندوز، مع نسخ احتياطي.
class SupportEmailTile extends StatelessWidget {
  const SupportEmailTile({
    super.key,
    required this.email,
    required this.subject,
    required this.accentColor,
  });

  final String email;
  final String subject;
  final Color accentColor;

  static Future<void> openMailto({
    required BuildContext context,
    required String email,
    required String subject,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final query = 'subject=${Uri.encodeComponent(subject)}';
    final u = Uri.parse('mailto:$email?$query');
    var launched = false;
    try {
      launched = await launchUrl(u, mode: LaunchMode.platformDefault);
    } catch (_) {
      launched = false;
    }
    if (!launched) {
      try {
        launched = await launchUrl(u, mode: LaunchMode.externalApplication);
      } catch (_) {
        launched = false;
      }
    }
    if (launched) return;
    await Clipboard.setData(ClipboardData(text: email));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.supportEmailCopied)),
    );
  }

  Future<void> _copy(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    await Clipboard.setData(ClipboardData(text: email));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.supportEmailCopied)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.email_outlined, color: accentColor),
      title: Text(l10n.supportEmailLabel),
      subtitle: Text(
        email,
        textDirection: TextDirection.ltr,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      trailing: IconButton(
        tooltip: l10n.supportCopyTooltip,
        onPressed: () => unawaited(_copy(context)),
        icon: const Icon(Icons.copy_rounded),
      ),
      onTap: () => unawaited(
        openMailto(context: context, email: email, subject: subject),
      ),
    );
  }
}

/// رقم دعم: 05XXXXXXXX + نسخ + واتساب.
class SupportPhoneLineTile extends StatelessWidget {
  const SupportPhoneLineTile({
    super.key,
    required this.line,
    required this.accentColor,
    this.whatsAppMessage = '',
  });

  final ({String display, String e164}) line;
  final Color accentColor;
  final String whatsAppMessage;

  static Future<void> openWhatsApp({
    required String e164,
    String message = '',
  }) async {
    final uri = Uri.parse(
      message.trim().isEmpty
          ? 'https://wa.me/$e164'
          : 'https://wa.me/$e164?text=${Uri.encodeComponent(message)}',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (_) {}
    }
  }

  Future<void> _copy(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final shown = PhoneDisplay.localTenDigits(line.display);
    await Clipboard.setData(ClipboardData(text: shown));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.supportPhoneCopied)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final shown = PhoneDisplay.localTenDigits(line.display);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.phone_outlined, color: accentColor),
      title: Text(l10n.supportPhoneLabel),
      subtitle: Text(
        PhoneDisplay.forUi(shown, isAr: true),
        textDirection: TextDirection.ltr,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: l10n.supportCopyTooltip,
            onPressed: () => unawaited(_copy(context)),
            icon: const Icon(Icons.copy_rounded),
          ),
          IconButton(
            tooltip: l10n.supportWhatsAppTooltip,
            onPressed: () => unawaited(
              openWhatsApp(e164: line.e164, message: whatsAppMessage),
            ),
            icon: const Icon(Icons.chat_rounded, color: Color(0xFF25D366)),
          ),
        ],
      ),
    );
  }
}

/// قائمة أرقام الدعم المتفق عليها فقط.
class SupportPhoneLinesColumn extends StatelessWidget {
  const SupportPhoneLinesColumn({
    super.key,
    required this.accentColor,
    this.whatsAppMessage = '',
  });

  final Color accentColor;
  final String whatsAppMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final line in SupportWhatsappConfig.lines)
          SupportPhoneLineTile(
            line: line,
            accentColor: accentColor,
            whatsAppMessage: whatsAppMessage,
          ),
      ],
    );
  }
}
