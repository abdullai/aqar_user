import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:aqar_user/core/gestures/app_keyboard_popups.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/listing/in_app_tour.dart';
import '../core/listing/listing_media_urls.dart';
import 'aqar_text_field.dart';

Future<InAppTour?> showInAppTourBuilderSheet({
  required BuildContext context,
  required bool isAr,
  required List<String> imageRefs,
  InAppTour? initial,
  Map<String, Uint8List> previewBytes = const {},
}) {
  return showAppModalBottomSheet<InAppTour>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _InAppTourBuilder(
      isAr: isAr,
      imageRefs: imageRefs,
      initial: initial,
      previewBytes: previewBytes,
    ),
  );
}

class _InAppTourBuilder extends StatefulWidget {
  const _InAppTourBuilder({
    required this.isAr,
    required this.imageRefs,
    this.initial,
    this.previewBytes = const {},
  });

  final bool isAr;
  final List<String> imageRefs;
  final InAppTour? initial;
  final Map<String, Uint8List> previewBytes;

  @override
  State<_InAppTourBuilder> createState() => _InAppTourBuilderState();
}

class _InAppTourBuilderState extends State<_InAppTourBuilder> {
  late List<InAppTourScene> _scenes;
  var _scene = 0;
  late final TextEditingController _titleCtrl;

  Widget _preview(String ref, {BoxFit fit = BoxFit.cover}) {
    final bytes = widget.previewBytes[ref];
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(bytes, fit: fit);
    }
    final url = ListingMediaUrls.storagePublicUrl(
      Supabase.instance.client,
      ref,
    );
    if (url != null) {
      return CachedNetworkImage(imageUrl: url, fit: fit);
    }
    return const ColoredBox(color: Colors.black12);
  }

  @override
  void initState() {
    super.initState();
    if (widget.initial != null && widget.initial!.isNotEmpty) {
      _scenes = List<InAppTourScene>.from(widget.initial!.scenes);
    } else {
      _scenes = [
        for (final r in widget.imageRefs)
          if (r.trim().isNotEmpty) InAppTourScene(imageRef: r.trim()),
      ];
    }
    _titleCtrl = TextEditingController(
      text: _scenes.isEmpty ? '' : _scenes.first.title,
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ar = widget.isAr;
    final h = MediaQuery.sizeOf(context).height * 0.88;
    return SizedBox(
      height: h,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ar ? 'بناء جولة داخلية' : 'Build in-app tour',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 6),
            Text(
              ar
                  ? 'رتّب الصور ثم أضف نقاطاً تفاعلية للغرف. اضغط للانتقال بين المشاهد. هذه جولة داخل التطبيق وليست محرك Matterport سحابي.'
                  : 'Reorder photos, then add hotspots. Tap a hotspot to jump rooms. This is the in-app walkthrough, not a cloud Matterport engine.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            if (_scenes.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    ar
                        ? 'أضف صوراً أولاً ثم ابنِ الجولة.'
                        : 'Add photos first, then build the tour.',
                  ),
                ),
              )
            else ...[
              SizedBox(
                height: 72,
                child: ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _scenes.length,
                  onReorder: (a, b) {
                    setState(() {
                      var to = b;
                      if (to > a) to -= 1;
                      final item = _scenes.removeAt(a);
                      _scenes.insert(to, item);
                      _scene = to;
                      _titleCtrl.text = item.title;
                    });
                  },
                  itemBuilder: (context, i) {
                    return Padding(
                      key: ValueKey('scene-$i-${_scenes[i].imageRef}'),
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: InkWell(
                        onTap: () => setState(() {
                          _scene = i;
                          _titleCtrl.text = _scenes[i].title;
                        }),
                        child: Container(
                          width: 72,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: _scene == i
                                  ? const Color(0xFF0F766E)
                                  : Colors.transparent,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _preview(_scenes[i].imageRef),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              AqarTextField(
                controller: _titleCtrl,
                onChanged: (v) {
                  final s = _scenes[_scene];
                  _scenes[_scene] = InAppTourScene(
                    imageRef: s.imageRef,
                    title: v,
                    hotspots: s.hotspots,
                  );
                },
                decoration: InputDecoration(
                  labelText: ar ? 'عنوان المشهد' : 'Scene title',
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    return GestureDetector(
                      onTapDown: (d) async {
                        final nx = (d.localPosition.dx / c.maxWidth).clamp(0, 1);
                        final ny =
                            (d.localPosition.dy / c.maxHeight).clamp(0, 1);
                        final label = TextEditingController();
                        final note = TextEditingController();
                        var target = _scene;
                        final ok = await showAppDialog<bool>(
                          context: context,
                          builder: (dctx) => StatefulBuilder(
                            builder: (dctx, setD) {
                              return AlertDialog(
                                title: Text(ar ? 'نقطة تفاعل' : 'Hotspot'),
                                content: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AqarTextField(
                                        controller: label,
                                        decoration: InputDecoration(
                                          labelText: ar ? 'الاسم' : 'Label',
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      AqarTextField(
                                        controller: note,
                                        maxLines: 3,
                                        decoration: InputDecoration(
                                          labelText: ar
                                              ? 'تفاصيل الغرفة'
                                              : 'Room details',
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Align(
                                        alignment:
                                            AlignmentDirectional.centerStart,
                                        child: Text(
                                          ar
                                              ? 'الانتقال إلى مشهد'
                                              : 'Jump to scene',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        children: [
                                          for (var i = 0;
                                              i < _scenes.length;
                                              i++)
                                            ChoiceChip(
                                              selected: target == i,
                                              label: Text(
                                                _scenes[i].title.trim().isEmpty
                                                    ? '${i + 1}'
                                                    : '${i + 1}',
                                              ),
                                              onSelected: (_) =>
                                                  setD(() => target = i),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dctx, false),
                                    child: Text(ar ? 'إلغاء' : 'Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(dctx, true),
                                    child: Text(ar ? 'إضافة' : 'Add'),
                                  ),
                                ],
                              );
                            },
                          ),
                        );
                        if (ok != true || !mounted) return;
                        setState(() {
                          final s = _scenes[_scene];
                          _scenes[_scene] = InAppTourScene(
                            imageRef: s.imageRef,
                            title: s.title,
                            hotspots: [
                              ...s.hotspots,
                              InAppTourHotspot(
                                label: label.text.trim(),
                                note: note.text.trim(),
                                targetScene: target,
                                nx: nx.toDouble(),
                                ny: ny.toDouble(),
                              ),
                            ],
                          );
                        });
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _preview(_scenes[_scene].imageRef),
                          ..._scenes[_scene].hotspots.asMap().entries.map(
                            (e) => Align(
                              alignment: Alignment(
                                (e.value.nx * 2) - 1,
                                (e.value.ny * 2) - 1,
                              ),
                              child: GestureDetector(
                                onLongPress: () {
                                  setState(() {
                                    final s = _scenes[_scene];
                                    final next = [...s.hotspots]..removeAt(e.key);
                                    _scenes[_scene] = s.copyWith(hotspots: next);
                                  });
                                },
                                child: const Icon(
                                  Icons.place,
                                  color: Color(0xFF0F766E),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                ar
                    ? 'اضغط على الصورة لإضافة نقطة. اضغط مطوّلاً لحذفها. اسحب المصغّرات لإعادة الترتيب.'
                    : 'Tap the photo to add a hotspot. Long-press to delete. Drag thumbnails to reorder.',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _scenes.isEmpty
                  ? null
                  : () => Navigator.pop(context, InAppTour(scenes: _scenes)),
              child: Text(ar ? 'حفظ الجولة' : 'Save tour'),
            ),
          ],
        ),
      ),
    );
  }
}
