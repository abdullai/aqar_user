import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:aqar_user/core/gestures/app_keyboard_popups.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/listing/in_app_tour.dart';
import '../core/listing/listing_media_urls.dart';
import '../l10n/app_localizations.dart';
import 'app_page_close_button.dart';

Future<void> openInAppTourViewer({
  required BuildContext context,
  required InAppTour tour,
  required bool isAr,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: isAr ? 'إغلاق' : 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.86),
    useRootNavigator: true,
    pageBuilder: (ctx, _, __) {
      return InAppTourViewer(tour: tour, isAr: isAr);
    },
  );
}

class InAppTourViewer extends StatefulWidget {
  const InAppTourViewer({
    super.key,
    required this.tour,
    required this.isAr,
  });

  final InAppTour tour;
  final bool isAr;

  @override
  State<InAppTourViewer> createState() => _InAppTourViewerState();
}

class _InAppTourViewerState extends State<InAppTourViewer>
    with SingleTickerProviderStateMixin {
  late final PageController _pages;
  late final AnimationController _pulse;
  var _index = 0;

  @override
  void initState() {
    super.initState();
    _pages = PageController();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _go(int i) {
    final n = widget.tour.scenes.length;
    if (n == 0) return;
    final next = i.clamp(0, n - 1);
    _pages.animateToPage(
      next,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sb = Supabase.instance.client;
    final scenes = widget.tour.scenes;
    final ar = widget.isAr;
    final l10n = AppLocalizations.of(context);
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Material(
        color: Colors.black,
        child: SafeArea(
          child: Stack(
            children: [
              PageView.builder(
                controller: _pages,
                itemCount: scenes.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final scene = scenes[i];
                  final url = ListingMediaUrls.storagePublicUrl(
                    sb,
                    scene.imageRef,
                  );
                  return InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (url != null)
                          CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.contain,
                          )
                        else
                          const Center(
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              color: Colors.white54,
                              size: 48,
                            ),
                          ),
                        ...scene.hotspots.map((h) {
                          return Align(
                            alignment: Alignment(
                              (h.nx * 2) - 1,
                              (h.ny * 2) - 1,
                            ),
                            child: GestureDetector(
                              onTap: () {
                                if (h.note.trim().isNotEmpty) {
                                  showAppDialog<void>(
                                    context: context,
                                    builder: (d) => AlertDialog(
                                      title: Text(
                                        h.label.trim().isEmpty
                                            ? (ar ? 'تفاصيل' : 'Details')
                                            : h.label,
                                      ),
                                      content: Text(h.note),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(d),
                                          child: Text(ar ? 'حسناً' : 'OK'),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                if (h.targetScene != i) _go(h.targetScene);
                              },
                              child: ScaleTransition(
                                scale: Tween<double>(begin: 0.92, end: 1.08)
                                    .animate(
                                  CurvedAnimation(
                                    parent: _pulse,
                                    curve: Curves.easeInOut,
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const CircleAvatar(
                                      radius: 16,
                                      backgroundColor: Color(0xFF0F766E),
                                      child: Icon(
                                        Icons.place,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                    if (h.label.trim().isNotEmpty)
                                      Container(
                                        margin: const EdgeInsets.only(top: 4),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        color: Colors.black54,
                                        child: Text(
                                          h.label,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                },
              ),
              PositionedDirectional(
                top: 4,
                start: 4,
                child: AppPageCloseButton(
                  isArabic: ar,
                  color: Colors.white,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              if (scenes.length > 1) ...[
                Positioned(
                  left: 4,
                  top: 0,
                  bottom: 96,
                  child: Center(
                    child: IconButton(
                      color: Colors.white,
                      onPressed: _index <= 0 ? null : () => _go(_index - 1),
                      icon: const Icon(Icons.chevron_left, size: 32),
                    ),
                  ),
                ),
                Positioned(
                  right: 4,
                  top: 0,
                  bottom: 96,
                  child: Center(
                    child: IconButton(
                      color: Colors.white,
                      onPressed: _index >= scenes.length - 1
                          ? null
                          : () => _go(_index + 1),
                      icon: const Icon(Icons.chevron_right, size: 32),
                    ),
                  ),
                ),
              ],
              Positioned(
                left: 12,
                right: 12,
                bottom: 16,
                child: Column(
                  children: [
                    if (l10n != null)
                      Text(
                        l10n.inAppTourPanHint,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (scenes[_index].title.trim().isNotEmpty)
                      Text(
                        scenes[_index].title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 44,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: scenes.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (context, i) {
                          final selected = i == _index;
                          return ChoiceChip(
                            selected: selected,
                            label: Text('${i + 1}'),
                            onSelected: (_) => _go(i),
                            selectedColor: const Color(0xFF0F766E),
                            labelStyle: TextStyle(
                              color: selected ? Colors.white : Colors.white70,
                              fontWeight: FontWeight.w800,
                            ),
                            backgroundColor: Colors.white12,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_index + 1} / ${scenes.length}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
