import 'package:flutter/foundation.dart';

@immutable
class NationalAddressModel {
  const NationalAddressModel({
    this.shortAddress,
    this.buildingNumber,
    this.street,
    this.district,
    this.city,
    this.region,
    this.governorate,
    this.postalCode,
    this.additionalNumber,
    this.latitude,
    this.longitude,
  });

  final String? shortAddress;
  final String? buildingNumber;
  final String? street;
  final String? district;
  final String? city;
  final String? region;
  final String? governorate;
  final String? postalCode;
  final String? additionalNumber;
  final double? latitude;
  final double? longitude;

  String get displayAddress => [
        street,
        district,
        city,
        region,
      ]
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .join('، ');

  NationalAddressModel copyWith({
    String? shortAddress,
    String? buildingNumber,
    String? street,
    String? district,
    String? city,
    String? region,
    String? governorate,
    String? postalCode,
    String? additionalNumber,
    double? latitude,
    double? longitude,
  }) {
    return NationalAddressModel(
      shortAddress: shortAddress ?? this.shortAddress,
      buildingNumber: buildingNumber ?? this.buildingNumber,
      street: street ?? this.street,
      district: district ?? this.district,
      city: city ?? this.city,
      region: region ?? this.region,
      governorate: governorate ?? this.governorate,
      postalCode: postalCode ?? this.postalCode,
      additionalNumber: additionalNumber ?? this.additionalNumber,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }

  Map<String, dynamic> toJson() => {
        'short_address': shortAddress,
        'building_number': buildingNumber,
        'street': street,
        'district': district,
        'city': city,
        'region': region,
        'governorate': governorate,
        'postal_code': postalCode,
        'additional_number': additionalNumber,
        'latitude': latitude,
        'longitude': longitude,
      };

  factory NationalAddressModel.fromJson(Map<String, dynamic> json) {
    final (latitude, longitude) = _coordinates(json);
    return NationalAddressModel(
      shortAddress: _text(json, const [
        'shortaddress',
        'short_address',
        'nationaladdress',
        'addresscode',
      ]),
      buildingNumber: _text(json, const ['buildingnumber', 'building_number']),
      street: _text(json, const ['streetname', 'street', 'street_name']),
      district:
          _text(json, const ['district', 'districtname', 'district_name']),
      city: _text(json, const ['city', 'cityname', 'city_name']),
      region: _text(json, const ['region', 'regionname', 'region_name']),
      governorate: _text(
          json, const ['governorate', 'governoratename', 'governorate_name']),
      postalCode: _text(
          json, const ['zipcode', 'postalcode', 'postal_code', 'zip_code']),
      additionalNumber:
          _text(json, const ['additionalnumber', 'additional_number']),
      latitude: latitude,
      longitude: longitude,
    );
  }

  static List<NationalAddressModel> fromResponse(dynamic value) {
    return _records(value)
        .map(NationalAddressModel.fromJson)
        .where((address) =>
            address.displayAddress.isNotEmpty ||
            (address.shortAddress ?? '').trim().isNotEmpty ||
            (address.latitude != null && address.longitude != null))
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> _records(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    }
    if (value is! Map) return const [];
    final map = Map<String, dynamic>.from(value);
    for (final key in const [
      'addresses',
      'address',
      'data',
      'results',
      'result',
      'response',
    ]) {
      final nested = _lookup(map, [key]);
      if (nested == null) continue;
      final found = _records(nested);
      if (found.isNotEmpty) return found;
    }
    return map.isEmpty ? const [] : [map];
  }

  static (double?, double?) _coordinates(Map<String, dynamic> json) {
    final directLat = _number(json, const ['latitude', 'lat']);
    final directLng = _number(json, const ['longitude', 'long', 'lng']);
    if (directLat != null && directLng != null) {
      return (directLat, directLng);
    }

    final object = _lookup(json, const ['objlatlng', 'coordinates']);
    if (object is Map) {
      final coordinates = Map<String, dynamic>.from(object);
      final lat = _number(coordinates, const ['latitude', 'lat', 'y']);
      final lng = _number(coordinates, const ['longitude', 'long', 'lng', 'x']);
      return (lat, lng);
    }
    if (object is List && object.length >= 2) {
      return _orderedPair(object[0], object[1]);
    }
    if (object is String) {
      final values = object
          .split(RegExp(r'[,;\s]+'))
          .map(double.tryParse)
          .whereType<double>()
          .toList(growable: false);
      if (values.length >= 2) return _orderedPair(values[0], values[1]);
    }
    return (null, null);
  }

  static (double?, double?) _orderedPair(dynamic first, dynamic second) {
    final a = _asDouble(first);
    final b = _asDouble(second);
    if (a == null || b == null) return (null, null);
    if (_isSaudiLatitude(a) && _isSaudiLongitude(b)) return (a, b);
    if (_isSaudiLatitude(b) && _isSaudiLongitude(a)) return (b, a);
    return (a, b);
  }

  static bool _isSaudiLatitude(double value) => value >= 16 && value <= 32.5;

  static bool _isSaudiLongitude(double value) => value >= 34.5 && value <= 56;

  static String? _text(Map<String, dynamic> map, List<String> keys) {
    final value = _lookup(map, keys);
    if (value == null) return null;
    final text = '$value'.trim();
    return text.isEmpty ? null : text;
  }

  static double? _number(Map<String, dynamic> map, List<String> keys) =>
      _asDouble(_lookup(map, keys));

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value'.trim());
  }

  static dynamic _lookup(Map map, List<String> keys) {
    final wanted = keys.map(_normalizeKey).toSet();
    for (final entry in map.entries) {
      if (wanted.contains(_normalizeKey('${entry.key}'))) return entry.value;
    }
    return null;
  }

  static String _normalizeKey(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}
