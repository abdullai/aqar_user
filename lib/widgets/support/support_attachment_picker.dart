import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_localizations.dart';
import '../../services/support_ticket_service.dart';

/// مرفقات الشكوى: ملفات على ويندوز/ويب سطح المكتب، وكاميرا+معرض+ملفات على الجوال.
class SupportAttachmentPicker extends StatelessWidget {
  const SupportAttachmentPicker({
    super.key,
    required this.files,
    required this.onChanged,
    this.enabled = true,
  });

  final List<SupportLocalAttachment> files;
  final ValueChanged<List<SupportLocalAttachment>> onChanged;
  final bool enabled;

  bool get _isMobileFamily =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _addBytes({
    required String name,
    required Uint8List bytes,
    String mime = 'application/octet-stream',
  }) async {
    if (bytes.isEmpty) return;
    onChanged([
      ...files,
      SupportLocalAttachment(name: name, bytes: bytes, mime: mime),
    ]);
  }

  Future<void> _pickFiles(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const [
          'jpg',
          'jpeg',
          'png',
          'webp',
          'gif',
          'pdf',
          'heic',
        ],
      );
      if (res == null) return;
      final next = [...files];
      for (final f in res.files) {
        final b = f.bytes;
        if (b == null || b.isEmpty) continue;
        next.add(
          SupportLocalAttachment(
            name: f.name,
            bytes: b,
            mime: _mimeFromName(f.name),
          ),
        );
      }
      onChanged(next);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.supportAttachFailed)),
      );
    }
  }

  Future<void> _pickGallery(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final picker = ImagePicker();
      final shots = await picker.pickMultiImage(imageQuality: 88);
      final next = [...files];
      for (final x in shots) {
        final b = await x.readAsBytes();
        if (b.isEmpty) continue;
        next.add(
          SupportLocalAttachment(
            name: x.name.isNotEmpty
                ? x.name
                : 'image_${DateTime.now().millisecondsSinceEpoch}.jpg',
            bytes: b,
            mime: 'image/jpeg',
          ),
        );
      }
      onChanged(next);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.supportAttachFailed)),
      );
    }
  }

  Future<void> _pickCamera(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
      );
      if (x == null) return;
      final b = await x.readAsBytes();
      await _addBytes(
        name: x.name.isNotEmpty
            ? x.name
            : 'camera_${DateTime.now().millisecondsSinceEpoch}.jpg',
        bytes: b,
        mime: 'image/jpeg',
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.supportAttachFailed)),
      );
    }
  }

  static String _mimeFromName(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.gif')) return 'image/gif';
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.supportAttachmentsLabel,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.supportAttachmentsHint,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            height: 1.35,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: enabled ? () => _pickFiles(context) : null,
              icon: const Icon(Icons.attach_file_rounded, size: 18),
              label: Text(l10n.supportAttachFile),
            ),
            if (_isMobileFamily) ...[
              OutlinedButton.icon(
                onPressed: enabled ? () => _pickGallery(context) : null,
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: Text(l10n.supportAttachGallery),
              ),
              OutlinedButton.icon(
                onPressed: enabled ? () => _pickCamera(context) : null,
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: Text(l10n.supportAttachCamera),
              ),
            ],
          ],
        ),
        if (files.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (var i = 0; i < files.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                files[i].mime.contains('pdf')
                    ? Icons.picture_as_pdf_outlined
                    : Icons.image_outlined,
                color: cs.primary,
              ),
              title: Text(
                files[i].name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: l10n.supportAttachRemove,
                onPressed: enabled
                    ? () {
                        final next = [...files]..removeAt(i);
                        onChanged(next);
                      }
                    : null,
                icon: const Icon(Icons.close_rounded),
              ),
            ),
        ],
      ],
    );
  }
}
