import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../core/government/wathq_models.dart';

/// خدمة Wathq المركزية
/// تتعامل مع جميع APIs الحكومية:
/// - السجل التجاري
/// - العنوان الوطني
/// - بيانات الموظف
/// - الصكوك العقارية

class WathqService {
  static const String _baseUrl = 'https://api.wathq.sa';
  static const Duration _timeout = Duration(seconds: 30);

  final String apiKey;
  final int maxRetries;
  final int cacheExpiryDays;

  late http.Client _httpClient;

  WathqService({
    required this.apiKey,
    this.maxRetries = 3,
    this.cacheExpiryDays = 30,
  }) {
    _httpClient = http.Client();
  }

  // ========================================
  // 1. السجل التجاري - Commercial Registration
  // ========================================

  /// الحصول على بيانات السجل التجاري الكاملة
  /// [crNumber]: رقم السجل التجاري أو الرقم الموحد
  /// [language]: 'ar' أو 'en'
  Future<CommercialRegistrationData> getCommercialRegistration({
    required String crNumber,
    String language = 'ar',
  }) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/sandbox/commercial-registration/fullinfo/$crNumber?language=$language',
      );

      final response = await _makeRequest(url).timeout(
        _timeout,
        onTimeout: () => throw TimeoutException('Commercial Registration API timeout'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return CommercialRegistrationData.fromJson(data);
      } else if (response.statusCode == 404) {
        throw Exception('السجل التجاري غير موجود');
      } else {
        throw Exception('خطأ في جلب بيانات السجل التجاري: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error in getCommercialRegistration: $e');
      rethrow;
    }
  }

  // ========================================
  // 2. العنوان الوطني - SPL National Address
  // ========================================

  /// الحصول على العناوين الوطنية للشركة
  /// [crNumber]: رقم السجل التجاري أو الرقم الموحد
  Future<List<NationalAddressData>> getNationalAddress({
    required String crNumber,
  }) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/spl/national/address/info/$crNumber',
      );

      final response = await _makeRequest(url).timeout(
        _timeout,
        onTimeout: () => throw TimeoutException('National Address API timeout'),
      );

      if (response.statusCode == 200) {
        final dataList = jsonDecode(response.body) as List;
        return dataList
            .map((item) => NationalAddressData.fromJson(item))
            .toList();
      } else if (response.statusCode == 404) {
        return []; // لا توجد عناوين
      } else {
        throw Exception('خطأ في جلب العناوين الوطنية: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error in getNationalAddress: $e');
      rethrow;
    }
  }

  // ========================================
  // 3. بيانات الموظف - Employee Information
  // ========================================

  /// الحصول على بيانات الموظف والعمل
  /// [nationalId] أو [iqamaNumber]: رقم الهوية أو الإقامة (10 أرقام)
  Future<EmployeeInformationData> getEmployeeInfo({
    required String nationalId,
  }) async {
    try {
      if (nationalId.length != 10 || !RegExp(r'^\d+$').hasMatch(nationalId)) {
        throw ArgumentError('رقم الهوية يجب أن يكون 10 أرقام');
      }

      final url = Uri.parse('$_baseUrl/masdr/employee/v2/info');

      final response = await _makeRequest(
        url,
        method: 'GET',
        headers: {
          'Authorization': 'Bearer $apiKey',
          'id': nationalId,
        },
      ).timeout(
        _timeout,
        onTimeout: () => throw TimeoutException('Employee Information API timeout'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return EmployeeInformationData.fromJson(data);
      } else if (response.statusCode == 404) {
        throw Exception('الموظف غير موجود في النظام');
      } else if (response.statusCode == 400) {
        throw Exception('رقم الهوية غير صحيح');
      } else {
        throw Exception('خطأ في جلب بيانات الموظف: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error in getEmployeeInfo: $e');
      rethrow;
    }
  }

  // ========================================
  // 4. الصك العقاري - Real Estate Deed
  // ========================================

  /// الحصول على بيانات الصك العقاري
  /// [deedNumber]: رقم الصك
  /// [idNumber]: رقم الهوية / الجواز / إلخ
  /// [idType]: نوع الهوية ('National_ID', 'Passport', 'CR_NO', إلخ)
  Future<RealEstateDeedData> getRealEstateDeed({
    required String deedNumber,
    required String idNumber,
    required String idType,
  }) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/moj/real-estate/deed/$deedNumber/$idNumber/$idType',
      );

      final response = await _makeRequest(url).timeout(
        _timeout,
        onTimeout: () => throw TimeoutException('Real Estate Deed API timeout'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final deedDetails = data['deedDetails'] ?? data;
        return RealEstateDeedData.fromJson(deedDetails);
      } else if (response.statusCode == 404) {
        throw Exception('الصك العقاري غير موجود');
      } else {
        throw Exception('خطأ في جلب بيانات الصك: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error in getRealEstateDeed: $e');
      rethrow;
    }
  }

  /// جلب جميع الصكوك العقارية لمالك معين
  /// (إن كانت الخدمة تدعم البحث بدون رقم صك محدد)
  Future<List<RealEstateDeedData>> getRealEstateDeeds({
    required String idNumber,
    required String idType,
  }) async {
    try {
      // ملاحظة: هذه الدالة تحتاج دعم من API لكي تعيد قائمة
      // حالياً نعيد قائمة فارغة، ويمكن التوسع عند توفر الخدمة
      debugPrint('⚠️ getRealEstateDeeds: يحتاج دعم API إضافي');
      return [];
    } catch (e) {
      debugPrint('❌ Error in getRealEstateDeeds: $e');
      rethrow;
    }
  }

  // ========================================
  // التحقق المتكامل - Integrated Verification
  // ========================================

  /// التحقق الشامل من بيانات المستخدم بناءً على نوعه
  /// يحدد تلقائياً ما إذا كان الرقم لفرد أو شركة
  Future<WathqVerificationResult> verifyUserData({
    required String unifiedId,
  }) async {
    try {
      debugPrint('🔍 بدء التحقق الشامل للمستخدم: $unifiedId');

      final result = WathqVerificationResult(
        isVerified: false,
        userType: 'unknown',
        unifiedId: unifiedId,
        verifiedAt: DateTime.now(),
        verificationStatusMap: {},
      );

      // محاولة التحقق من السجل التجاري أولاً (للشركات)
      try {
        debugPrint('🔄 فحص ما إذا كان رقم سجل تجاري...');
        result.commercialData = await getCommercialRegistration(
          crNumber: unifiedId,
        );
        result.userType = 'company';

        // جلب العنوان الوطني
        debugPrint('🔄 جلب العنوان الوطني...');
        result.companyAddresses = await getNationalAddress(
          crNumber: unifiedId,
        );

        result.isVerified = true;
        debugPrint('✅ تم التحقق: شركة');
      } catch (e) {
        debugPrint('⚠️ ليس سجل تجاري: $e');

        // محاولة التحقق من بيانات الموظف (للأفراد)
        try {
          debugPrint('🔄 فحص ما إذا كان رقم هوية فرد...');
          result.employeeData = await getEmployeeInfo(
            nationalId: unifiedId,
          );
          result.userType = 'individual';

          // محاولة جلب الصكوك العقارية
          debugPrint('🔄 جلب الصكوك العقارية...');
          result.realEstateDeeds = await getRealEstateDeeds(
            idNumber: unifiedId,
            idType: 'National_ID',
          );

          result.isVerified = true;
          debugPrint('✅ تم التحقق: فرد');
        } catch (e2) {
          debugPrint('❌ فشل التحقق: $e2');
          result.verificationNotes = 'فشل التحقق من البيانات';
        }
      }

      result.expiresAt = DateTime.now().add(
        Duration(days: cacheExpiryDays),
      );

      return result;
    } catch (e) {
      debugPrint('❌ Error in verifyUserData: $e');
      rethrow;
    }
  }

  /// التحقق المتقدم مع معلومات تفصيلية
  Future<WathqVerificationResult> verifyUserDataDetailed({
    required String unifiedId,
    bool includeRealEstate = true,
    bool includeEmployment = true,
  }) async {
    try {
      final result = await verifyUserData(unifiedId: unifiedId);

      // يمكن إضافة منطق إضافي هنا للتحقق المتقدم
      if (!includeRealEstate) {
        result.realEstateDeeds = [];
      }
      if (!includeEmployment) {
        result.employeeData = null;
      }

      return result;
    } catch (e) {
      debugPrint('❌ Error in verifyUserDataDetailed: $e');
      rethrow;
    }
  }

  // ========================================
  // دوال مساعدة - Helper Functions
  // ========================================

  /// إرسال الطلب مع إعادة المحاولة
  Future<http.Response> _makeRequest(
    Uri url, {
    String method = 'GET',
    Map<String, String>? headers,
    dynamic body,
    int retriesLeft = -1,
  }) async {
    if (retriesLeft == -1) {
      retriesLeft = maxRetries;
    }

    headers ??= {};
    headers['Authorization'] = 'Bearer $apiKey';
    headers['Content-Type'] = 'application/json';
    headers['Accept'] = 'application/json';

    try {
      late http.Response response;

      if (method == 'POST') {
        response = await _httpClient.post(
          url,
          headers: headers,
          body: body is String ? body : jsonEncode(body),
        );
      } else if (method == 'PUT') {
        response = await _httpClient.put(
          url,
          headers: headers,
          body: body is String ? body : jsonEncode(body),
        );
      } else {
        response = await _httpClient.get(url, headers: headers);
      }

      debugPrint('📡 $method $url -> ${response.statusCode}');

      // إعادة المحاولة في حالة الأخطاء المؤقتة
      if ((response.statusCode == 429 || response.statusCode >= 500) &&
          retriesLeft > 0) {
        await Future.delayed(const Duration(seconds: 2));
        return _makeRequest(
          url,
          method: method,
          headers: headers,
          body: body,
          retriesLeft: retriesLeft - 1,
        );
      }

      return response;
    } catch (e) {
      if (retriesLeft > 0) {
        debugPrint('⚠️ Retrying... ($retriesLeft left)');
        await Future.delayed(const Duration(seconds: 2));
        return _makeRequest(
          url,
          method: method,
          headers: headers,
          body: body,
          retriesLeft: retriesLeft - 1,
        );
      }
      rethrow;
    }
  }

  /// تحديد نوع الرقم (رقم هوية / رقم سجل تجاري / إلخ)
  String determineIdType(String id) {
    if (id.length == 10 && RegExp(r'^\d+$').hasMatch(id)) {
      return 'National_ID';
    } else if (RegExp(r'^[0-9]{10}$').hasMatch(id)) {
      return 'CR_NO';
    } else {
      return 'Unknown';
    }
  }

  /// صيغة معرّف موحد صحيح
  bool isValidUnifiedId(String id) {
    return id.length >= 10 && id.length <= 20 && RegExp(r'^[0-9]+$').hasMatch(id);
  }

  void dispose() {
    _httpClient.close();
  }
}
