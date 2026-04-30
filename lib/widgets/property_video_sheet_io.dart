// lib/widgets/property_video_sheet_io.dart
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

Future<void> openPropertyVideoSheetImpl(
  BuildContext context, {
  required bool isAr,
  required String title,
  required String videoUrl,
}) async {
  VideoPlayerController? vp;
  ChewieController? chewie;

  try {
    vp = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
    await vp.initialize();

    chewie = ChewieController(
      videoPlayerController: vp,
      autoPlay: true,
      looping: false,
      allowFullScreen: true,
      allowPlaybackSpeedChanging: true,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final h = MediaQuery.of(ctx).size.height * 0.70;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            child: SizedBox(
              height: h,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    isAr ? 'فيديو العقار' : 'Property video',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        color: Colors.black,
                        child: Chewie(controller: chewie!),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  } catch (_) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(isAr ? 'تعذر تشغيل الفيديو' : 'Failed to play video'),
      ),
    );
  } finally {
    chewie?.dispose();
    vp?.dispose();
  }
}