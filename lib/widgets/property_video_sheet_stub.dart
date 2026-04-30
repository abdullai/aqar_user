// lib/widgets/property_video_sheet_stub.dart
import 'package:flutter/material.dart';

Future<void> openPropertyVideoSheetImpl(
  BuildContext context, {
  required bool isAr,
  required String title,
  required String videoUrl,
}) async {
  // ✅ على الويب: لا نستدعي chewie/video_player نهائياً (حتى لا يفشل البناء)
  // نعرض BottomSheet بسيط مع نسخ الرابط.
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final h = MediaQuery.of(ctx).size.height * 0.45;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
          child: SizedBox(
            height: h,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isAr
                      ? 'الفيديو غير مدعوم على الويب داخل التطبيق'
                      : 'Video is disabled on Web build',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                Text(
                  isAr
                      ? 'انسخ رابط الفيديو وافتحه في المتصفح.'
                      : 'Copy the video link and open it in a browser.',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  videoUrl,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        behavior: SnackBarBehavior.floating,
                        content: Text(
                          isAr ? 'تم نسخ الرابط (يدويًا من النص)' : 'Copy the link from the text',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(isAr ? 'إغلاق' : 'Close'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}