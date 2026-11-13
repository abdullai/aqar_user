import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aqar_user/models/national_address_model.dart';
import 'package:aqar_user/services/national_address_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('enforces the Saudi geofence and minimum free-text length', () {
    expect(
      NationalAddressService.isWithinSaudiArabia(16, 34.5),
      isTrue,
    );
    expect(
      NationalAddressService.isWithinSaudiArabia(15.99, 46),
      isFalse,
    );
    expect(
      NationalAddressService.isWithinSaudiArabia(24, 56.01),
      isFalse,
    );
    expect(NationalAddressService.isValidSearchTerm('abc'), isFalse);
    expect(NationalAddressService.isValidSearchTerm('مكة المكرمة'), isTrue);
    expect(NationalAddressService.isValidSearchTerm('RNMA7272'), isTrue);
  });

  test('parses SPL address fields and ObjLatLng coordinates', () {
    final results = NationalAddressModel.fromResponse({
      'Addresses': [
        {
          'ShortAddress': 'RNMA7272',
          'BuildingNumber': '1234',
          'StreetName': 'King Road',
          'District': 'Al Olaya',
          'City': 'Riyadh',
          'ZipCode': '12345',
          'AdditionalNumber': '6789',
          'ObjLatLng': {'x': 46.6753, 'y': 24.7136},
        },
      ],
    });

    expect(results, hasLength(1));
    expect(results.single.shortAddress, 'RNMA7272');
    expect(results.single.buildingNumber, '1234');
    expect(results.single.latitude, 24.7136);
    expect(results.single.longitude, 46.6753);
  });

  test('does not call SPL for coordinates outside Saudi Arabia', () async {
    var networkCalls = 0;
    final service = NationalAddressService(
      apiKey: 'test-key',
      client: MockClient((_) async {
        networkCalls++;
        return http.Response('{}', 200);
      }),
    );

    expect(
      () => service.reverseGeocode(latitude: 15.9, longitude: 46),
      throwsA(isA<NationalAddressServiceException>()),
    );
    expect(networkCalls, 0);
    service.dispose();
  });

  test('uses the SPL search and detailed verification endpoints', () async {
    final requests = <http.Request>[];
    final service = NationalAddressService(
      apiKey: 'test-key',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('{}', 200);
      }),
    );

    await service.search('King Road');
    await service.verifyAddress(
      buildingNumber: '1234',
      streetName: 'King Road',
      district: 'Al Olaya',
      city: 'Riyadh',
      postalCode: '12345',
      additionalNumber: '6789',
    );
    service.dispose();

    expect(requests, hasLength(2));
    expect(requests[0].url.path, '/Address/address-free-text');
    expect(requests[0].url.queryParameters['querystring'], 'King Road');
    expect(requests[1].url.path, '/Address/address-verify');
    expect(requests[1].url.queryParameters['buildingnumber'], '1234');
    expect(requests[1].url.queryParameters['streetname'], 'King Road');
    expect(requests[1].url.queryParameters['district'], 'Al Olaya');
    expect(requests[1].url.queryParameters['city'], 'Riyadh');
    expect(requests[1].url.queryParameters['zipcode'], '12345');
    expect(requests[1].url.queryParameters['additionalnumber'], '6789');
    for (final request in requests) {
      expect(request.url.queryParameters['api_key'], 'test-key');
      expect(request.url.queryParameters['language'], 'A');
      expect(request.url.queryParameters['format'], 'JSON');
      expect(request.url.queryParameters['encode'], 'utf8');
    }
  });

  test('reverse geocode uses a four-decimal persistent cache', () async {
    var networkCalls = 0;
    final firstService = NationalAddressService(
      apiKey: 'test-key',
      client: MockClient((request) async {
        networkCalls++;
        expect(request.url.host, 'address.gov.sa');
        expect(request.url.path, '/Address/address-geocode');
        expect(request.url.queryParameters['language'], 'A');
        expect(request.url.queryParameters['format'], 'JSON');
        expect(request.url.queryParameters['encode'], 'utf8');
        expect(request.url.queryParameters['api_key'], 'test-key');
        return http.Response(
          jsonEncode({
            'Addresses': [
              {
                'ShortAddress': 'RNMA7272',
                'ObjLatLng': {'x': 46.6753, 'y': 24.7136},
              },
            ],
          }),
          200,
        );
      }),
    );
    final first = await firstService.reverseGeocode(
      latitude: 24.71362,
      longitude: 46.67534,
    );
    firstService.dispose();

    final cachedService = NationalAddressService(
      apiKey: '',
      client: MockClient((_) async {
        throw StateError('The cached result should avoid another request.');
      }),
    );
    final cached = await cachedService.reverseGeocode(
      latitude: 24.71361,
      longitude: 46.67531,
    );
    cachedService.dispose();

    expect(first?.single.shortAddress, 'RNMA7272');
    expect(cached?.single.shortAddress, 'RNMA7272');
    expect(networkCalls, 1);
  });
}
