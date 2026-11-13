import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/national_address_config.dart';
import '../models/national_address_model.dart';

class NationalAddressServiceException implements Exception {
  const NationalAddressServiceException(
    this.messageAr, [
    this.messageEn = 'The national address request could not be completed.',
  ]);

  final String messageAr;
  final String messageEn;

  String localized(bool isAr) => isAr ? messageAr : messageEn;

  @override
  String toString() => messageAr;
}

class NationalAddressService {
  NationalAddressService({
    String? apiKey,
    http.Client? client,
  })  : _apiKey = (apiKey ?? splApiKey).trim(),
        _client = client ?? http.Client();

  static const String _cachePreferenceKey = 'spl_address_cache_v1';
  static const int _maxCacheEntries = 120;
  static final RegExp _shortAddressPattern = RegExp(r'^[A-Za-z]{4}\d{4}$');

  final String _apiKey;
  final http.Client _client;
  final LinkedHashMap<String, List<NationalAddressModel>> _cache =
      LinkedHashMap<String, List<NationalAddressModel>>();

  Future<void>? _cacheLoad;
  Completer<void>? _abortTrigger;
  bool _disposed = false;

  static bool isWithinSaudiArabia(double latitude, double longitude) =>
      latitude >= 16 &&
      latitude <= 32.5 &&
      longitude >= 34.5 &&
      longitude <= 56;

  static bool isValidSearchTerm(String query) {
    final value = query.trim();
    return _shortAddressPattern.hasMatch(value) || value.length >= 4;
  }

  Future<List<NationalAddressModel>?> search(String query) async {
    final value = query.trim();
    if (!isValidSearchTerm(value)) {
      throw const NationalAddressServiceException(
        'أدخل العنوان المختصر الصحيح أو أربعة أحرف على الأقل للبحث.',
        'Enter a valid short address or at least four characters.',
      );
    }
    final key = 'text:${value.toLowerCase()}';
    return _cachedGet(
      key,
      _uri('address-free-text', {'querystring': value}),
    );
  }

  Future<List<NationalAddressModel>?> reverseGeocode({
    required double latitude,
    required double longitude,
  }) {
    if (!isWithinSaudiArabia(latitude, longitude)) {
      throw const NationalAddressServiceException(
        'الموقع خارج نطاق تغطية العنوان الوطني.',
        'The location is outside National Address coverage.',
      );
    }
    final latKey = latitude.toStringAsFixed(4);
    final lngKey = longitude.toStringAsFixed(4);
    return _cachedGet(
      'geo:$latKey:$lngKey',
      _uri('address-geocode', {
        'lat': latitude.toString(),
        'long': longitude.toString(),
      }),
    );
  }

  Future<List<NationalAddressModel>?> verifyAddress({
    required String buildingNumber,
    required String streetName,
    required String district,
    required String city,
    required String postalCode,
    required String additionalNumber,
  }) {
    final fields = {
      'buildingnumber': buildingNumber.trim(),
      'streetname': streetName.trim(),
      'district': district.trim(),
      'city': city.trim(),
      'zipcode': postalCode.trim(),
      'additionalnumber': additionalNumber.trim(),
    };
    if (fields.values.any((value) => value.isEmpty)) {
      throw const NationalAddressServiceException(
        'أكمل حقول العنوان التفصيلي قبل التحقق.',
        'Complete all detailed address fields before verifying.',
      );
    }
    final key = 'verify:${fields.values.map((e) => e.toLowerCase()).join('|')}';
    return _cachedGet(key, _uri('address-verify', fields));
  }

  Uri _uri(String path, Map<String, String> parameters) {
    return Uri.https('address.gov.sa', '/Address/$path', {
      'api_key': _apiKey,
      'language': 'A',
      'format': 'JSON',
      'encode': 'utf8',
      ...parameters,
    });
  }

  Future<List<NationalAddressModel>?> _cachedGet(
    String cacheKey,
    Uri uri,
  ) async {
    if (_disposed) {
      throw StateError('NationalAddressService is disposed.');
    }
    await _ensureCacheLoaded();
    final cached = _cache.remove(cacheKey);
    if (cached != null) {
      _cache[cacheKey] = cached;
      return List<NationalAddressModel>.unmodifiable(cached);
    }
    if (_apiKey.isEmpty || _apiKey == splApiKeyPlaceholder) {
      throw const NationalAddressServiceException(
        'خدمة العنوان الوطني غير مهيأة. أضف SPL_API_KEY لإجراء البحث.',
        'National Address is not configured. Provide SPL_API_KEY to search.',
      );
    }

    final response = await _send(uri);
    if (response == null) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NationalAddressServiceException(
        'تعذر الاتصال بخدمة العنوان الوطني (HTTP ${response.statusCode}).',
        'National Address request failed (HTTP ${response.statusCode}).',
      );
    }

    dynamic body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      throw const NationalAddressServiceException(
        'استجابة خدمة العنوان الوطني غير صالحة.',
        'National Address returned an invalid response.',
      );
    }
    final results = NationalAddressModel.fromResponse(body);
    _cache[cacheKey] = results;
    while (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    await _persistCache();
    return results;
  }

  Future<http.Response?> _send(Uri uri) async {
    cancelPending();
    final abort = Completer<void>();
    _abortTrigger = abort;
    try {
      final request = http.AbortableRequest(
        'GET',
        uri,
        abortTrigger: abort.future,
      );
      return await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 15));
    } on http.RequestAbortedException {
      return null;
    } on TimeoutException {
      cancelPending();
      throw const NationalAddressServiceException(
        'انتهت مهلة الاتصال بخدمة العنوان الوطني.',
        'The National Address request timed out.',
      );
    } finally {
      if (identical(_abortTrigger, abort)) _abortTrigger = null;
    }
  }

  void cancelPending() {
    final trigger = _abortTrigger;
    if (trigger != null && !trigger.isCompleted) trigger.complete();
    _abortTrigger = null;
  }

  Future<void> _ensureCacheLoaded() => _cacheLoad ??= _readCache();

  Future<void> _readCache() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_cachePreferenceKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('Cache is not a map.');
      for (final entry in decoded.entries) {
        if (entry.value is! List) continue;
        final values = (entry.value as List)
            .whereType<Map>()
            .map((value) => NationalAddressModel.fromJson(
                  Map<String, dynamic>.from(value),
                ))
            .toList(growable: false);
        _cache['${entry.key}'] = values;
      }
      while (_cache.length > _maxCacheEntries) {
        _cache.remove(_cache.keys.first);
      }
    } on FormatException catch (error) {
      debugPrint('Ignoring invalid SPL address cache: $error');
      await preferences.remove(_cachePreferenceKey);
    }
  }

  Future<void> _persistCache() async {
    final preferences = await SharedPreferences.getInstance();
    final values = {
      for (final entry in _cache.entries)
        entry.key: entry.value.map((address) => address.toJson()).toList(),
    };
    final saved = await preferences.setString(
      _cachePreferenceKey,
      jsonEncode(values),
    );
    if (!saved) {
      debugPrint('Could not persist SPL address cache.');
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancelPending();
    _client.close();
  }
}
