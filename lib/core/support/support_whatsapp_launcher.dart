import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'support_whatsapp_config.dart';

/// فتح واتساب لجميع خطوط الدعم دفعة واحدة (بدون اختيار رقم).
///
/// **مهم:** واتساب لا يسمح بإرسال رسالة تلقائياً لعدة أرقام من المتصفح
/// بدون WhatsApp Business API. الحل العملي:
/// 1) حفظ الطلب في التطبيق/قاعدة البيانات (يصل للإدارة)
/// 2) نسخ النص
/// 3) فتح محادثة جاهزة مع **كل** رقم — يضغط المستخدم «إرسال» في كل نافذة
abstract final class SupportWhatsappLauncher {
  static Future<void> openAllSupportLines({
    required BuildContext context,
    required bool isAr,
    required String message,
    VoidCallback? onEachOpened,
  }) async {
    if (message.trim().isEmpty) return;

    await Clipboard.setData(ClipboardData(text: message));

    if (!context.mounted) return;

    final lines = SupportWhatsappConfig.lines;
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          icon: const Icon(Icons.chat_rounded, color: Color(0xFF25D366)),
          title: Text(
            isAr ? 'إرسال لجميع خطوط الدعم' : 'Send to all support lines',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          content: Text(
            isAr
                ? 'سيتم:\n'
                    '• حفظ طلبك في النظام (يصل لفريق الدعم)\n'
                    '• نسخ النص\n'
                    '• فتح ${lines.length} محادثات واتساب (${lines.map((e) => e.display).join('، ')})\n\n'
                    'في كل محادثة اضغط «إرسال». على الويب يُفتح واتساب ويب إن لم يكن التطبيق مثبتاً.'
                : 'We will:\n'
                    '• Save your request in the system\n'
                    '• Copy the message\n'
                    '• Open ${lines.length} WhatsApp chats (${lines.map((e) => e.display).join(', ')})\n\n'
                    'Tap Send in each chat. On web, WhatsApp Web opens if the app is not installed.',
            style: const TextStyle(height: 1.45, fontWeight: FontWeight.w600),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(isAr ? 'إلغاء' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(isAr ? 'متابعة — فتح الكل' : 'Continue — open all'),
            ),
          ],
        );
      },
    );

    if (proceed != true || !context.mounted) return;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final uri = Uri.parse(
        'https://wa.me/${line.e164}?text=${Uri.encodeComponent(message)}',
      );
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          onEachOpened?.call();
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[SupportWhatsappLauncher] $e');
      }
      if (i < lines.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
      }
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          content: Text(isAr
              ? 'تم فتح ${lines.length} محادثات — اضغط «إرسال» في كل منها. النص مُنسَخ أيضاً.'
              : 'Opened ${lines.length} chats — tap Send in each. Message copied too.'),
        ),
      );
    }
  }
}
