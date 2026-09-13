import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/listing/in_app_tour.dart';
import '../core/utils/app_money.dart';
import '../core/utils/rpc_user_message.dart';
import '../l10n/app_localizations.dart';
import '../main.dart' show suspendAutoLock;
import '../services/photographer_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/app_page_close_button.dart';
import '../widgets/aqar_text_field.dart';
import '../widgets/in_app_tour_builder_sheet.dart';

/// تسليم جلسة تصوير: صور + فيديو + جولة داخلية من شاشة المصور.
class PhotographerDeliverPage extends StatefulWidget {
  const PhotographerDeliverPage({
    super.key,
    required this.request,
    required this.lang,
  });

  final PhotoShootRequest request;
  final String lang;

  @override
  State<PhotographerDeliverPage> createState() =>
      _PhotographerDeliverPageState();
}

class _PhotographerDeliverPageState extends State<PhotographerDeliverPage> {
  final _svc = PhotographerService(Supabase.instance.client);
  final _notes = TextEditingController();
  final _photoBytes = <Uint8List>[];
  Uint8List? _videoBytes;
  String _videoExt = 'mp4';
  InAppTour? _tour;
  var _busy = false;

  bool get _isAr => widget.lang != 'en';

  bool get _wantsPhotos => widget.request.shootKinds.contains('photos');
  bool get _wantsVideo => widget.request.shootKinds.contains('video');
  bool get _wantsTour =>
      widget.request.shootKinds.contains('tour') ||
      widget.request.shootKinds.contains('tour_3d') ||
      widget.request.includeTour;

  bool get _ready {
    if (_wantsPhotos && _photoBytes.isEmpty) return false;
    if (_wantsVideo && _videoBytes == null) return false;
    if (_wantsTour && (_tour == null || _tour!.isEmpty)) return false;
    if (!_wantsPhotos &&
        !_wantsVideo &&
        !_wantsTour &&
        _photoBytes.isEmpty &&
        _videoBytes == null &&
        (_tour == null || _tour!.isEmpty)) {
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  String _guessVideoMime(String ext) {
    switch (ext.toLowerCase()) {
      case 'mov':
        return 'video/quicktime';
      case 'mkv':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';
      case 'mp4':
      default:
        return 'video/mp4';
    }
  }

  Future<void> _pickPhotos() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isEmpty) return;
    final cap = widget.request.maxPhotos;
    final out = <Uint8List>[];
    for (final f in picked.take(cap)) {
      out.add(Uint8List.fromList(await f.readAsBytes()));
    }
    if (!mounted) return;
    setState(() {
      _photoBytes
        ..clear()
        ..addAll(out);
      _tour = null;
    });
  }

  Future<void> _pickVideo() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.video,
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final bytes = f.bytes;
    if (bytes == null || bytes.isEmpty) return;
    setState(() {
      _videoBytes = bytes;
      _videoExt = (f.extension ?? 'mp4').toLowerCase();
    });
  }

  Future<void> _buildTour() async {
    if (_photoBytes.isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.photographerDeliverNeedPhotos)),
      );
      return;
    }
    final refs = [for (var i = 0; i < _photoBytes.length; i++) '$i'];
    final bytes = <String, Uint8List>{
      for (var i = 0; i < _photoBytes.length; i++) '$i': _photoBytes[i],
    };
    final tour = await showInAppTourBuilderSheet(
      context: context,
      isAr: _isAr,
      imageRefs: refs,
      initial: _tour,
      previewBytes: bytes,
    );
    if (tour != null && mounted) setState(() => _tour = tour);
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (widget.request.propertyId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.photographerNeedListing)),
      );
      return;
    }
    if (_wantsPhotos && _photoBytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.photographerDeliverNeedPhotos)),
      );
      return;
    }
    if (_wantsVideo && _videoBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.photographerDeliverNeedVideo)),
      );
      return;
    }
    if (_wantsTour && (_tour == null || _tour!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.photographerDeliverNeedTour)),
      );
      return;
    }
    if (_photoBytes.length > widget.request.maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.photographerPhotoLimit(widget.request.maxPhotos)),
        ),
      );
      return;
    }
    if (!_ready) return;

    setState(() => _busy = true);
    suspendAutoLock.value = true;
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id ?? 'anon';
      final paths = <String>[];
      for (final bytes in _photoBytes) {
        final path =
            'photographer/$uid/shoots/${widget.request.id}/${const Uuid().v4()}.jpg';
        await Supabase.instance.client.storage
            .from('property-images')
            .uploadBinary(
              path,
              bytes,
              fileOptions: const FileOptions(
                upsert: true,
                contentType: 'image/jpeg',
              ),
            );
        paths.add(path);
      }
      String? videoPath;
      final video = _videoBytes;
      if (video != null) {
        videoPath =
            'photographer/$uid/shoots/${widget.request.id}/${const Uuid().v4()}.$_videoExt';
        await Supabase.instance.client.storage
            .from('property-videos')
            .uploadBinary(
              videoPath,
              video,
              fileOptions: FileOptions(
                upsert: true,
                contentType: _guessVideoMime(_videoExt),
              ),
            );
      }
      final mapped =
          _tour != null && paths.isNotEmpty ? _tour!.remapped(paths) : _tour;
      await _svc.deliver(
        requestId: widget.request.id,
        imagePaths: paths,
        videoPath: videoPath,
        inAppTour: mapped?.toJson(),
        coverImagePath: paths.isNotEmpty ? paths.first : null,
        technicalNotes: _notes.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(RpcUserMessage.of(e, isAr: _isAr))),
      );
    } finally {
      suspendAutoLock.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final kinds = widget.request.shootKinds
        .map((k) {
          switch (k) {
            case 'video':
              return l10n.photographerKindVideo;
            case 'tour':
              return l10n.photographerKindTour;
            default:
              return l10n.photographerKindPhotos;
          }
        })
        .join(' · ');

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: AppPageCloseButton(isArabic: _isAr),
          title: Text(l10n.photographerDeliverTitle),
        ),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                Text(
                  widget.request.locationText.trim().isEmpty
                      ? l10n.photographerShootFallback
                      : widget.request.locationText,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const SizedBox(height: 4),
                Text(kinds, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (widget.request.quotedAmountSar != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${l10n.photographerQuoteAgreed}: ${AppMoney.sarPhrase(widget.request.quotedAmountSar!.toStringAsFixed(0), isAr: _isAr)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
                Text(
                  l10n.photographerDeliverCaps(
                    widget.request.maxPhotos,
                    widget.request.maxVideos,
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.inAppTourEngineHint,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                if (_wantsPhotos)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pickPhotos,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(
                      _photoBytes.isEmpty
                          ? l10n.photographerPickPhotos
                          : l10n.photographerFilesCount(_photoBytes.length),
                    ),
                  ),
                if (_wantsVideo) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pickVideo,
                    icon: const Icon(Icons.videocam_outlined),
                    label: Text(
                      _videoBytes == null
                          ? l10n.photographerPickVideo
                          : l10n.photographerVideoPicked,
                    ),
                  ),
                ],
                if (_wantsTour) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _buildTour,
                    icon: const Icon(Icons.threed_rotation_outlined),
                    label: Text(
                      _tour == null || _tour!.isEmpty
                          ? l10n.inAppTourBuild
                          : l10n.photographerTourReady,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                AqarTextField(
                  controller: _notes,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: l10n.photographerTechnicalNotes,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy || !_ready ? null : _submit,
                  icon: const Icon(Icons.cloud_done_outlined),
                  label: Text(l10n.photographerDeliverConfirm),
                ),
              ],
            ),
            if (_busy)
              const ColoredBox(
                color: Color(0x66000000),
                child: Center(child: AppLogoLoading()),
              ),
          ],
        ),
      ),
    );
  }
}
