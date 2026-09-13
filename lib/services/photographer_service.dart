import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

class PhotographerProfile {
  const PhotographerProfile({
    required this.userId,
    required this.status,
    this.displayName = '',
    this.nationalId = '',
    this.commercialRegister = '',
    this.bio = '',
    this.city = '',
    this.photoRateSar,
    this.videoRateSar,
    this.tourRateSar,
    this.maxAcceptsPerDay = 5,
    this.ratingAvg = 0,
    this.ratingCount = 0,
    this.certificates = const [],
    this.portfolio = const [],
    this.reviewNote = '',
    this.createdAt,
    this.latitude,
    this.longitude,
  });

  final String userId;
  final String status;
  final String displayName;
  final String nationalId;
  final String commercialRegister;
  final String bio;
  final String city;
  final double? photoRateSar;
  final double? videoRateSar;
  final double? tourRateSar;
  final int maxAcceptsPerDay;
  final double ratingAvg;
  final int ratingCount;
  final List<dynamic> certificates;
  final List<dynamic> portfolio;
  final String reviewNote;
  final DateTime? createdAt;
  final double? latitude;
  final double? longitude;

  bool get isPending => status == 'pending';
  bool get joinSlaOverdue {
    final at = createdAt;
    if (at == null || !isPending) return false;
    return DateTime.now().toUtc().difference(at.toUtc()) >
        const Duration(hours: 24);
  }
  bool get isVerified => status == 'verified';
  bool get isRejected => status == 'rejected';

  factory PhotographerProfile.fromMap(Map<String, dynamic> m) {
    return PhotographerProfile(
      userId: (m['user_id'] ?? '').toString(),
      status: (m['status'] ?? '').toString(),
      displayName: (m['display_name'] ?? '').toString(),
      nationalId: (m['national_id'] ?? '').toString(),
      commercialRegister: (m['commercial_register'] ?? '').toString(),
      bio: (m['bio'] ?? '').toString(),
      city: (m['city'] ?? '').toString(),
      photoRateSar: (m['photo_rate_sar'] as num?)?.toDouble(),
      videoRateSar: (m['video_rate_sar'] as num?)?.toDouble(),
      tourRateSar: (m['tour_rate_sar'] as num?)?.toDouble(),
      maxAcceptsPerDay: (m['max_accepts_per_day'] as num?)?.toInt() ?? 5,
      ratingAvg: (m['rating_avg'] as num?)?.toDouble() ?? 0,
      ratingCount: (m['rating_count'] as num?)?.toInt() ?? 0,
      certificates: m['certificates'] is List
          ? List<dynamic>.from(m['certificates'] as List)
          : const [],
      portfolio: m['portfolio'] is List
          ? List<dynamic>.from(m['portfolio'] as List)
          : const [],
      reviewNote: (m['review_note'] ?? '').toString(),
      createdAt: DateTime.tryParse('${m['created_at'] ?? ''}'),
      latitude: (m['latitude'] as num?)?.toDouble(),
      longitude: (m['longitude'] as num?)?.toDouble(),
    );
  }
}

class PhotoShootRequest {
  const PhotoShootRequest({
    required this.id,
    required this.photographerId,
    required this.requesterId,
    required this.status,
    this.propertyId = '',
    this.listingRequestId = '',
    this.shootKinds = const ['photos'],
    this.locationText = '',
    this.preferredAt,
    this.rejectReason = '',
    this.technicalNotes = '',
    this.coverImagePath = '',
    this.createdAt,
    this.acceptedAt,
    this.deliveredAt,
    this.quotedAmountSar,
    this.maxPhotos = 30,
    this.maxVideos = 1,
    this.includeTour = false,
  });

  final String id;
  final String photographerId;
  final String requesterId;
  final String status;
  final String propertyId;
  final String listingRequestId;
  final List<String> shootKinds;
  final String locationText;
  final DateTime? preferredAt;
  final String rejectReason;
  final String technicalNotes;
  final String coverImagePath;
  final DateTime? createdAt;
  final DateTime? acceptedAt;
  final DateTime? deliveredAt;
  final double? quotedAmountSar;
  final int maxPhotos;
  final int maxVideos;
  final bool includeTour;

  DateTime? get respondDeadline =>
      createdAt?.toUtc().add(const Duration(hours: 24));

  Duration? get acceptWindowLeft {
    if (status != 'pending') return null;
    final d = respondDeadline;
    if (d == null) return null;
    return d.difference(DateTime.now().toUtc());
  }

  bool get acceptWindowExpired {
    final left = acceptWindowLeft;
    return left != null && left.isNegative;
  }

  factory PhotoShootRequest.fromMap(Map<String, dynamic> m) {
    final kinds = <String>[];
    final raw = m['shoot_kinds'];
    if (raw is List) {
      for (final e in raw) {
        final s = e.toString().trim();
        if (s.isNotEmpty) kinds.add(s);
      }
    }
    return PhotoShootRequest(
      id: (m['id'] ?? '').toString(),
      photographerId: (m['photographer_id'] ?? '').toString(),
      requesterId: (m['requester_id'] ?? '').toString(),
      status: (m['status'] ?? '').toString(),
      propertyId: (m['property_id'] ?? '').toString(),
      listingRequestId: (m['listing_request_id'] ?? '').toString(),
      shootKinds: kinds.isEmpty ? const ['photos'] : kinds,
      locationText: (m['location_text'] ?? '').toString(),
      preferredAt: DateTime.tryParse('${m['preferred_at'] ?? ''}'),
      rejectReason: (m['reject_reason'] ?? '').toString(),
      technicalNotes: (m['technical_notes'] ?? '').toString(),
      coverImagePath: (m['cover_image_path'] ?? '').toString(),
      createdAt: DateTime.tryParse('${m['created_at'] ?? ''}'),
      acceptedAt: DateTime.tryParse('${m['accepted_at'] ?? ''}'),
      deliveredAt: DateTime.tryParse('${m['delivered_at'] ?? ''}'),
      quotedAmountSar: (m['quoted_amount_sar'] as num?)?.toDouble(),
      maxPhotos: (m['max_photos'] as num?)?.toInt() ?? 30,
      maxVideos: (m['max_videos'] as num?)?.toInt() ?? 1,
      includeTour: m['include_tour'] == true ||
          kinds.contains('tour') ||
          kinds.contains('tour_3d'),
    );
  }
}

class PhotographerService {
  PhotographerService(this._sb);

  final SupabaseClient _sb;

  Future<PhotographerProfile?> myProfile() async {
    final uid = _sb.auth.currentUser?.id ?? '';
    if (uid.isEmpty) return null;
    final row = await _sb
        .from('photographer_profiles')
        .select()
        .eq('user_id', uid)
        .maybeSingle();
    if (row == null) return null;
    return PhotographerProfile.fromMap(Map<String, dynamic>.from(row));
  }

  Future<List<PhotographerProfile>> verifiedDirectory() async {
    final rows = await _sb.rpc('list_verified_photographers');
    return [
      for (final r in (rows as List))
        PhotographerProfile.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  }

  Future<List<PhotographerProfile>> staffPending() async {
    final rows = await _sb
        .from('photographer_profiles')
        .select()
        .eq('status', 'pending')
        .order('created_at');
    return [
      for (final r in (rows as List))
        PhotographerProfile.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  }

  Future<void> submitJoin({
    required String displayName,
    required String nationalId,
    String? commercialRegister,
    String? bio,
    String? city,
    double? photoRate,
    double? videoRate,
    double? tourRate,
    List<String> certificates = const [],
    double? latitude,
    double? longitude,
  }) async {
    await _sb.rpc(
      'submit_photographer_join',
      params: {
        'p_display_name': displayName,
        'p_national_id': nationalId,
        'p_commercial_register': commercialRegister,
        'p_bio': bio,
        'p_city': city,
        'p_photo_rate_sar': photoRate,
        'p_video_rate_sar': videoRate,
        'p_tour_rate_sar': tourRate,
        'p_certificates': certificates,
        'p_accept_policy': true,
        'p_latitude': latitude,
        'p_longitude': longitude,
      },
    );
  }

  Future<void> staffReview({
    required String userId,
    required bool approve,
    String? note,
  }) async {
    await _sb.rpc(
      'staff_review_photographer',
      params: {
        'p_user_id': userId,
        'p_approve': approve,
        'p_note': note,
      },
    );
  }

  Future<String> createShoot({
    required String photographerId,
    String? propertyId,
    String? listingRequestId,
    List<String> kinds = const ['photos'],
    String? locationText,
    double? latitude,
    double? longitude,
    DateTime? preferredAt,
    double? quotedAmountSar,
    int maxPhotos = 30,
    int maxVideos = 1,
    bool includeTour = false,
  }) async {
    final normalized = [
      for (final k in kinds)
        if (k == 'tour_3d' || k == '3d' || k == 'virtual_tour') 'tour' else k,
    ];
    final raw = await _sb.rpc(
      'create_photo_shoot_request',
      params: {
        'p_photographer_id': photographerId,
        'p_property_id': (propertyId ?? '').trim().isEmpty ? null : propertyId,
        'p_listing_request_id':
            (listingRequestId ?? '').trim().isEmpty ? null : listingRequestId,
        'p_shoot_kinds': normalized,
        'p_location_text': locationText,
        'p_latitude': latitude,
        'p_longitude': longitude,
        'p_preferred_at': preferredAt?.toUtc().toIso8601String(),
        'p_quoted_amount_sar': quotedAmountSar,
        'p_max_photos': maxPhotos,
        'p_max_videos': maxVideos,
        'p_include_tour': includeTour || normalized.contains('tour'),
      },
    );
    return raw.toString();
  }

  Future<int> expireStaleShoots() async {
    try {
      final raw = await _sb.rpc('expire_stale_photo_shoot_requests');
      if (raw is num) return raw.toInt();
      return int.tryParse('$raw') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<List<PhotoShootRequest>> myShootsAsPhotographer() async {
    await expireStaleShoots();
    final uid = _sb.auth.currentUser?.id ?? '';
    if (uid.isEmpty) return const [];
    final rows = await _sb
        .from('photo_shoot_requests')
        .select()
        .eq('photographer_id', uid)
        .order('created_at', ascending: false);
    return [
      for (final r in (rows as List))
        PhotoShootRequest.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  }

  Future<List<PhotoShootRequest>> myShootsAsRequester() async {
    await expireStaleShoots();
    final uid = _sb.auth.currentUser?.id ?? '';
    if (uid.isEmpty) return const [];
    final rows = await _sb
        .from('photo_shoot_requests')
        .select()
        .eq('requester_id', uid)
        .order('created_at', ascending: false);
    return [
      for (final r in (rows as List))
        PhotoShootRequest.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  }

  Future<void> respond({
    required String requestId,
    required bool accept,
    String? rejectReason,
  }) async {
    await _sb.rpc(
      'photographer_respond_shoot',
      params: {
        'p_request_id': requestId,
        'p_accept': accept,
        'p_reject_reason': rejectReason,
      },
    );
  }

  Future<void> deliver({
    required String requestId,
    List<String> imagePaths = const [],
    String? videoPath,
    Map<String, dynamic>? inAppTour,
    String? coverImagePath,
    String? technicalNotes,
  }) async {
    await _sb.rpc(
      'photographer_deliver_shoot',
      params: {
        'p_request_id': requestId,
        'p_image_paths': imagePaths,
        'p_video_path': videoPath,
        'p_in_app_tour': inAppTour,
        'p_cover_image_path': coverImagePath,
        'p_technical_notes': technicalNotes,
      },
    );
  }

  Future<void> rate({
    required String requestId,
    required int stars,
    String? comment,
  }) async {
    await _sb.rpc(
      'owner_rate_photographer',
      params: {
        'p_request_id': requestId,
        'p_stars': stars,
        'p_comment': comment,
      },
    );
  }

  Future<void> setDailyCap(int max) async {
    await _sb.rpc('photographer_set_daily_cap', params: {'p_max': max});
  }

  static double? distanceKm({
    required PhotographerProfile p,
    double? fromLat,
    double? fromLng,
  }) {
    final a = p.latitude;
    final b = p.longitude;
    if (a == null || b == null || fromLat == null || fromLng == null) {
      return null;
    }
    const r = 6371.0;
    final dLat = _rad(fromLat - a);
    final dLng = _rad(fromLng - b);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(a)) * math.cos(_rad(fromLat)) *
            math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(h.clamp(0, 1)));
  }

  static double _rad(double d) => d * math.pi / 180;

  static List<PhotographerProfile> sortNearest(
    List<PhotographerProfile> input, {
    double? fromLat,
    double? fromLng,
    String city = '',
  }) {
    final cityKey = city.trim().toLowerCase();
    final copy = [...input];
    copy.sort((a, b) {
      final da = distanceKm(p: a, fromLat: fromLat, fromLng: fromLng);
      final db = distanceKm(p: b, fromLat: fromLat, fromLng: fromLng);
      if (da != null && db != null) return da.compareTo(db);
      if (da != null) return -1;
      if (db != null) return 1;
      if (cityKey.isNotEmpty) {
        final ac = a.city.trim().toLowerCase() == cityKey;
        final bc = b.city.trim().toLowerCase() == cityKey;
        if (ac != bc) return ac ? -1 : 1;
      }
      return b.ratingAvg.compareTo(a.ratingAvg);
    });
    return copy;
  }

  Future<void> submitDeveloperInterest({
    required String fullName,
    required String email,
    required String developmentType,
  }) async {
    await _sb.rpc(
      'submit_developer_interest',
      params: {
        'p_full_name': fullName,
        'p_email': email,
        'p_development_type': developmentType,
      },
    );
  }
}
