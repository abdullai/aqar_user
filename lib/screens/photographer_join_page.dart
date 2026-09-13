import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/permissions/runtime_permission_helper.dart';
import '../core/utils/rpc_user_message.dart';
import '../l10n/app_localizations.dart';
import '../services/photographer_service.dart';
import '../services/saudi_locations_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/app_page_close_button.dart';
import '../widgets/aqar_text_field.dart';

class PhotographerJoinPage extends StatefulWidget {
  const PhotographerJoinPage({
    super.key,
    required this.lang,
    this.embedAppBar = false,
  });

  final String lang;
  final bool embedAppBar;

  @override
  State<PhotographerJoinPage> createState() => _PhotographerJoinPageState();
}

class _PhotographerJoinPageState extends State<PhotographerJoinPage> {
  final _svc = PhotographerService(Supabase.instance.client);
  final _name = TextEditingController();
  final _nid = TextEditingController();
  final _cr = TextEditingController();
  final _bio = TextEditingController();
  final _city = TextEditingController();
  final _photo = TextEditingController();
  final _video = TextEditingController();
  final _tour = TextEditingController();
  final _certs = <String>[];
  var _policy = false;
  var _busy = false;
  var _loading = true;
  PhotographerProfile? _mine;

  bool get _isAr => widget.lang != 'en';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final p = await _svc.myProfile();
      if (!mounted) return;
      setState(() {
        _mine = p;
        _loading = false;
        if (p != null) {
          _name.text = p.displayName;
          _nid.text = p.nationalId;
          _cr.text = p.commercialRegister;
          _bio.text = p.bio;
          _city.text = p.city;
          if (p.photoRateSar != null) _photo.text = '${p.photoRateSar}';
          if (p.videoRateSar != null) _video.text = '${p.videoRateSar}';
          if (p.tourRateSar != null) _tour.text = '${p.tourRateSar}';
          _certs
            ..clear()
            ..addAll(p.certificates.map((e) => e.toString()));
          _policy = true;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _nid.dispose();
    _cr.dispose();
    _bio.dispose();
    _city.dispose();
    _photo.dispose();
    _video.dispose();
    _tour.dispose();
    super.dispose();
  }

  Future<void> _pickCert({required ImageSource source}) async {
    final t = AppLocalizations.of(context);
    if (t != null) {
      final ok = source == ImageSource.camera
          ? await RuntimePermissionHelper.ensureCamera(context, t: t)
          : await RuntimePermissionHelper.ensurePhotos(context, t: t);
      if (!ok || !mounted) return;
    }
    final picked = await ImagePicker().pickImage(source: source);
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id ?? 'anon';
      final bytes = Uint8List.fromList(await picked.readAsBytes());
      final path = 'photographer/$uid/certs/${const Uuid().v4()}.jpg';
      await Supabase.instance.client.storage.from('property-images').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
          );
      if (!mounted) return;
      setState(() => _certs.add(path));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(RpcUserMessage.of(e, isAr: _isAr))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_policy) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.photographerPolicyRequired)),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      double? lat;
      double? lng;
      final city = _city.text.trim();
      if (city.isNotEmpty) {
        try {
          final loc = await SaudiLocationsService.instance.findByCity(city);
          if (loc != null && loc.lat != 0 && loc.lng != 0) {
            lat = loc.lat;
            lng = loc.lng;
          }
        } catch (_) {}
      }
      await _svc.submitJoin(
        displayName: _name.text.trim(),
        nationalId: _nid.text.trim(),
        commercialRegister: _cr.text.trim().isEmpty ? null : _cr.text.trim(),
        bio: _bio.text.trim().isEmpty ? null : _bio.text.trim(),
        city: city.isEmpty ? null : city,
        photoRate: double.tryParse(_photo.text.trim()),
        videoRate: double.tryParse(_video.text.trim()),
        tourRate: double.tryParse(_tour.text.trim()),
        certificates: _certs,
        latitude: lat,
        longitude: lng,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.photographerJoinSubmitted)),
      );
      await _boot();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(RpcUserMessage.of(e, isAr: _isAr))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final body = _loading
        ? const Center(child: AppLogoLoading())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_mine != null)
                Card(
                  color: cs.secondaryContainer.withValues(alpha: 0.45),
                  child: ListTile(
                    leading: Icon(
                      _mine!.isVerified
                          ? Icons.verified
                          : Icons.hourglass_top_outlined,
                    ),
                    title: Text(
                      _mine!.isVerified
                          ? l10n.photographerStatusVerified
                          : _mine!.isRejected
                              ? l10n.photographerStatusRejected
                              : l10n.photographerStatusPending,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      _mine!.isRejected && _mine!.reviewNote.isNotEmpty
                          ? _mine!.reviewNote
                          : l10n.photographerReviewSla,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                l10n.photographerJoinIntro,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              AqarTextField(
                controller: _name,
                decoration: InputDecoration(labelText: l10n.photographerDisplayName),
              ),
              const SizedBox(height: 8),
              AqarTextField(
                controller: _nid,
                decoration: InputDecoration(labelText: l10n.photographerNationalId),
              ),
              const SizedBox(height: 8),
              AqarTextField(
                controller: _cr,
                decoration:
                    InputDecoration(labelText: l10n.photographerCommercialRegister),
              ),
              const SizedBox(height: 8),
              AqarTextField(
                controller: _city,
                decoration: InputDecoration(labelText: l10n.photographerCity),
              ),
              const SizedBox(height: 8),
              AqarTextField(
                controller: _bio,
                maxLines: 3,
                decoration: InputDecoration(labelText: l10n.photographerBio),
              ),
              const SizedBox(height: 8),
              AqarTextField(
                controller: _photo,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l10n.photographerPhotoRate),
              ),
              const SizedBox(height: 8),
              AqarTextField(
                controller: _video,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l10n.photographerVideoRate),
              ),
              const SizedBox(height: 8),
              AqarTextField(
                controller: _tour,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l10n.photographerTourRate),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _pickCert(source: ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(l10n.photographerCaptureWithCamera),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _pickCert(source: ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(l10n.photographerPickFromGallery),
              ),
              if (_certs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(l10n.photographerFilesCount(_certs.length)),
                ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _policy,
                onChanged: (v) => setState(() => _policy = v == true),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(l10n.photographerAcceptPolicy),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: AppLogoLoading(compact: true, size: 20),
                      )
                    : Text(l10n.photographerSubmitJoin),
              ),
            ],
          );

    if (widget.embedAppBar) return body;
    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: AppPageCloseButton(isArabic: _isAr),
          title: Text(l10n.photographerJoinTitle),
        ),
        body: body,
      ),
    );
  }
}
