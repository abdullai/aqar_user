import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/permissions/runtime_permission_helper.dart';
import '../core/utils/signature_blue_ink.dart';
import '../l10n/app_localizations.dart';
import '../services/profile_compliance_service.dart';
import '../widgets/app_logo_loading.dart';

/// توقيع إجباري: رسم داخل مربع أو رفع صورة (للعقود والملف).
class ProfileSignatureGateScreen extends StatefulWidget {
  const ProfileSignatureGateScreen({
    super.key,
    required this.lang,
    required this.onDone,
  });

  final String lang;
  final VoidCallback onDone;

  @override
  State<ProfileSignatureGateScreen> createState() =>
      _ProfileSignatureGateScreenState();
}

class _ProfileSignatureGateScreenState extends State<ProfileSignatureGateScreen>
    with SingleTickerProviderStateMixin {
  static const Color _bankColor = Color(0xFF0F766E);

  late TabController _tabs;
  late SignatureController _signatureController;

  bool _busy = false;
  String? _err;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _signatureController = SignatureController(
      penStrokeWidth: 3,
      penColor: const Color.fromARGB(255, kSignatureInkR, kSignatureInkG, kSignatureInkB),
      exportBackgroundColor: Colors.white,
      exportPenColor: const Color.fromARGB(255, kSignatureInkR, kSignatureInkG, kSignatureInkB),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  Future<void> _saveDrawn() async {
    if (_signatureController.isEmpty) {
      setState(() {
        _err = AppLocalizations.of(context)?.profileSignatureEmpty ??
            (_isAr ? 'ارسم توقيعك داخل المربع' : 'Draw your signature in the box');
      });
      return;
    }

    setState(() {
      _busy = true;
      _err = null;
    });

    Uint8List? bytes;
    try {
      bytes = await _signatureController.toPngBytes();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _err = '$e';
        });
      }
      return;
    }

    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        setState(() {
          _busy = false;
          _err = AppLocalizations.of(context)?.profileSignatureNoBytes ?? '';
        });
      }
      return;
    }

    try {
      await ProfileComplianceService.uploadSignatureRasterBytes(
        Supabase.instance.client,
        bytes,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _err = '$e';
        });
      }
      return;
    }

    if (!mounted) return;
    setState(() => _busy = false);
    widget.onDone();
  }

  Future<void> _pickAndUpload() async {
    final t = AppLocalizations.of(context);
    if (Supabase.instance.client.auth.currentUser == null) return;

    if (t != null &&
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      final ok = await RuntimePermissionHelper.ensurePhotos(context, t: t);
      if (!ok || !mounted) return;
    }

    setState(() {
      _busy = true;
      _err = null;
    });

    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg'],
    );
    if (result == null || result.files.isEmpty) {
      if (mounted) setState(() => _busy = false);
      return;
    }

    final f = result.files.first;
    final Uint8List? bytes = f.bytes;
    if (bytes == null) {
      if (mounted) {
        setState(() {
          _busy = false;
          _err = t?.profileSignatureNoBytes ?? 'No file data';
        });
      }
      return;
    }

    try {
      await ProfileComplianceService.uploadSignatureRasterBytes(
        Supabase.instance.client,
        bytes,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _err = '$e';
        });
      }
      return;
    }

    if (!mounted) return;
    setState(() => _busy = false);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t?.profileSignatureTitle ?? 'التوقيع'),
          bottom: TabBar(
            controller: _tabs,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: t?.profileSignatureTabDraw ?? 'Draw'),
              Tab(text: t?.profileSignatureTabUpload ?? 'Upload'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            _buildDrawTab(context, t),
            _buildUploadTab(context, t),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawTab(BuildContext context, AppLocalizations? t) {
    final errColor = Theme.of(context).colorScheme.error;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          t?.profileSignatureDrawHint ??
              (_isAr
                  ? 'وقع داخل المربع بإصبعك أو القلم. يُحفظ كصورة للعقود.'
                  : 'Sign inside the box. Saved as an image for contracts.'),
          style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4),
        ),
        const SizedBox(height: 16),
        if (_err != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_err!, style: TextStyle(color: errColor)),
          ),
        AspectRatio(
          aspectRatio: 1.35,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color.fromARGB(180, kSignatureInkR, kSignatureInkG, kSignatureInkB),
                width: 2,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Signature(
                key: const ValueKey<String>('sig_pad'),
                controller: _signatureController,
                backgroundColor: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      _signatureController.clear();
                      setState(() => _err = null);
                    },
              child: Text(t?.profileSignatureClear ?? 'Clear'),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _busy ? null : _saveDrawn,
              style: FilledButton.styleFrom(backgroundColor: _bankColor),
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: AppLogoLoading(compact: true, size: 18),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(t?.profileSignatureSaveDraw ?? 'Save signature'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUploadTab(BuildContext context, AppLocalizations? t) {
    final errColor = Theme.of(context).colorScheme.error;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          t?.profileSignatureBody ??
              'Upload a clear signature image (PNG or JPG) on a light background.',
          style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4),
        ),
        const SizedBox(height: 24),
        if (_err != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_err!, style: TextStyle(color: errColor)),
          ),
        FilledButton.icon(
          onPressed: _busy ? null : _pickAndUpload,
          style: FilledButton.styleFrom(backgroundColor: _bankColor),
          icon: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: AppLogoLoading(compact: true, size: 20),
                )
              : const Icon(Icons.upload_file),
          label: Text(t?.profileSignaturePick ?? 'Choose image'),
        ),
      ],
    );
  }
}
