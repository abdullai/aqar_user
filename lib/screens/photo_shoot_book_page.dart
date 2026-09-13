import 'package:flutter/material.dart';
import 'package:aqar_user/core/gestures/app_keyboard_popups.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/app_money.dart';
import '../core/utils/date_helper.dart';
import '../core/utils/rpc_user_message.dart';
import '../l10n/app_localizations.dart';
import '../services/photographer_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/app_page_close_button.dart';
import '../widgets/certified_photographer_name.dart';

class PhotoShootBookPage extends StatefulWidget {
  const PhotoShootBookPage({
    super.key,
    required this.lang,
    this.propertyId,
    this.listingRequestId,
    this.locationText,
    this.latitude,
    this.longitude,
    this.onQueued,
  });

  final String lang;
  final String? propertyId;
  final String? listingRequestId;
  final String? locationText;
  final double? latitude;
  final double? longitude;

  /// إن لم يُحفظ الإعلان بعد: يُرجع مسودة الطلب للتخزين المحلي ثم الإرسال بعد النشر.
  final void Function(Map<String, dynamic> draft)? onQueued;

  @override
  State<PhotoShootBookPage> createState() => _PhotoShootBookPageState();
}

class _PhotoShootBookPageState extends State<PhotoShootBookPage> {
  final _svc = PhotographerService(Supabase.instance.client);
  List<PhotographerProfile> _list = const [];
  var _loading = true;
  final _kinds = <String>{'photos'};
  DateTime? _when;

  bool get _isAr => widget.lang != 'en';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _svc.verifiedDirectory();
      final city = (widget.locationText ?? '').split('·').first.trim();
      final sorted = PhotographerService.sortNearest(
        rows,
        fromLat: widget.latitude,
        fromLng: widget.longitude,
        city: city,
      );
      if (!mounted) return;
      setState(() {
        _list = sorted;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _quoteFor(PhotographerProfile p) {
    var t = 0.0;
    if (_kinds.contains('photos')) t += p.photoRateSar ?? 0;
    if (_kinds.contains('video')) t += p.videoRateSar ?? 0;
    if (_kinds.contains('tour') || _kinds.contains('tour_3d')) {
      t += p.tourRateSar ?? 0;
    }
    return t;
  }

  Future<void> _book(PhotographerProfile p) async {
    final l10n = AppLocalizations.of(context)!;
    final quote = _quoteFor(p);
    final kinds = [
      for (final k in _kinds)
        if (k == 'tour_3d') 'tour' else k,
    ];
    if (kinds.isEmpty) kinds.add('photos');
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.photographerQuoteTitle),
        content: Text(
          l10n.photographerQuoteBody(
            p.displayName,
            quote <= 0
                ? '—'
                : AppMoney.sarPhrase(quote.toStringAsFixed(0), isAr: _isAr),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.photographerDialogCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.photographerSendRequest),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final draft = <String, dynamic>{
      'photographer_id': p.userId,
      'property_id': widget.propertyId,
      'listing_request_id': widget.listingRequestId,
      'shoot_kinds': kinds,
      'location_text': widget.locationText,
      'latitude': widget.latitude,
      'longitude': widget.longitude,
      'preferred_at': _when?.toUtc().toIso8601String(),
      'quoted_amount_sar': quote > 0 ? quote : null,
      'max_photos': 30,
      'max_videos': kinds.contains('video') ? 1 : 0,
      'include_tour': kinds.contains('tour'),
    };
    final pid = (widget.propertyId ?? '').trim();
    if (pid.isEmpty && widget.onQueued != null) {
      widget.onQueued!(draft);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.photographerQueuedUntilPublish)),
      );
      Navigator.pop(context, draft);
      return;
    }
    try {
      await _svc.createShoot(
        photographerId: p.userId,
        propertyId: widget.propertyId,
        listingRequestId: widget.listingRequestId,
        kinds: kinds,
        locationText: widget.locationText,
        latitude: widget.latitude,
        longitude: widget.longitude,
        preferredAt: _when,
        quotedAmountSar: quote > 0 ? quote : null,
        maxPhotos: 30,
        maxVideos: kinds.contains('video') ? 1 : 0,
        includeTour: kinds.contains('tour'),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.photographerRequestSent)),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(RpcUserMessage.of(e, isAr: _isAr))),
      );
    }
  }

  String _rateLine(PhotographerProfile p, AppLocalizations l10n) {
    final bits = <String>[];
    if (p.photoRateSar != null) {
      bits.add(
        '${l10n.photographerKindPhotos}: ${AppMoney.sarPhrase(p.photoRateSar!.toStringAsFixed(0), isAr: _isAr)}',
      );
    }
    if (p.videoRateSar != null) {
      bits.add(
        '${l10n.photographerKindVideo}: ${AppMoney.sarPhrase(p.videoRateSar!.toStringAsFixed(0), isAr: _isAr)}',
      );
    }
    if (p.tourRateSar != null) {
      bits.add(
        '${l10n.photographerKindTour}: ${AppMoney.sarPhrase(p.tourRateSar!.toStringAsFixed(0), isAr: _isAr)}',
      );
    }
    return bits.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: AppPageCloseButton(isArabic: _isAr),
          title: Text(l10n.photographerBookTitle),
        ),
        body: _loading
            ? const Center(child: AppLogoLoading())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        selected: _kinds.contains('photos'),
                        label: Text(l10n.photographerKindPhotos),
                        onSelected: (v) => setState(() {
                          v ? _kinds.add('photos') : _kinds.remove('photos');
                          if (_kinds.isEmpty) _kinds.add('photos');
                        }),
                      ),
                      FilterChip(
                        selected: _kinds.contains('video'),
                        label: Text(l10n.photographerKindVideo),
                        onSelected: (v) => setState(() {
                          v ? _kinds.add('video') : _kinds.remove('video');
                        }),
                      ),
                      FilterChip(
                        selected: _kinds.contains('tour') ||
                            _kinds.contains('tour_3d'),
                        label: Text(l10n.photographerKindTour),
                        onSelected: (v) => setState(() {
                          _kinds.remove('tour_3d');
                          v ? _kinds.add('tour') : _kinds.remove('tour');
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.photographerBookFlowHint,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().add(const Duration(days: 1)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 180)),
                      );
                      if (d == null || !mounted) return;
                      final t = await showTimePicker(
                        context: context,
                        initialTime: const TimeOfDay(hour: 10, minute: 0),
                      );
                      if (t == null || !mounted) return;
                      setState(() {
                        _when = DateTime(d.year, d.month, d.day, t.hour, t.minute);
                      });
                    },
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      _when == null
                          ? l10n.photographerPickSlot
                          : DateHelper.fmtCivilDateTime(
                              _when!.toLocal(),
                              isAr: _isAr,
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Text(
                        l10n.photographerDirectoryEmpty,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  for (final p in _list)
                    Card(
                      child: ListTile(
                        title: CertifiedPhotographerName(
                          name: p.displayName,
                          verified: p.isVerified,
                        ),
                        subtitle: Text(
                          [
                            if (p.city.trim().isNotEmpty) p.city,
                            if (PhotographerService.distanceKm(
                                  p: p,
                                  fromLat: widget.latitude,
                                  fromLng: widget.longitude,
                                ) !=
                                null)
                              l10n.photographerDistanceKm(
                                PhotographerService.distanceKm(
                                  p: p,
                                  fromLat: widget.latitude,
                                  fromLng: widget.longitude,
                                )!.toStringAsFixed(1),
                              ),
                            if (p.ratingCount > 0)
                              l10n.photographerRatingLine(
                                p.ratingAvg.toStringAsFixed(1),
                                p.ratingCount,
                              ),
                            _rateLine(p, l10n),
                          ].where((s) => s.trim().isNotEmpty).join('\n'),
                        ),
                        isThreeLine: true,
                        trailing: FilledButton(
                          onPressed: () => _book(p),
                          child: Text(l10n.photographerSendRequest),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
