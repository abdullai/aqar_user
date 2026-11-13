import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/government/nafath_models.dart';
import '../core/government/wathq_models.dart';
import 'wathq_service.dart';
import 'nafath_auth_service.dart';

/// خدمة التحقق المتكاملة
/// تربط نفاذ مع Wathq APIs لإنشاء نظام تسجيل دخول متكامل

class IntegratedVerificationService {
  final supabase = Supabase.instance.client;
  final WathqService wathqService;
  final NafathAuthService nafathService;

  late final Map<String, UserProfile> _userCache = {};
  late final Map<String, WathqVerificationResult> _verificationCache = {};

  IntegratedVerificationService({
    required this.wathqService,
    required this.nafathService,
  });

  // ========================================
  // 1. إنشاء/تحديث المستخدم من نفاذ
  // ========================================

  /// إنشاء أو تحديث حساب المستخدم بعد التحقق من نفاذ
  /// يجمع بيانات نفاذ مع بيانات Wathq
  Future<UserProfile> createOrUpdateUserFromNafath({
    required String nationalId,
    required String userType, // 'individual' or 'company'
    required NafathUserData nafathData,
  }) async {
    try {
      debugPrint('🔄 بدء إنشاء/تحديث المستخدم: $nationalId');

      // 1. التحقق من وجود المستخدم
      var existingUser = await _findUserByNationalId(nationalId);

      // 2. جلب بيانات Wathq
      debugPrint('🔍 جلب بيانات Wathq...');
      final wathqVerification = await wathqService.verifyUserData(
        unifiedId: nationalId,
      );

      // 3. إنشاء/تحديث بيانات المستخدم
      final userProfile = UserProfile(
        id: existingUser?.id,
        email: existingUser?.email,
        phone: nafathData.fullName, // يمكن تحديثها
        fullName: nafathData.fullName,
        profilePhotoUrl: existingUser?.profilePhotoUrl,
        nationalId: nationalId,
        nafathVerifiedAt: DateTime.now(),
        nafathData: nafathData.toJson(),
        wathqUnifiedId: nationalId,
        wathqUserType: userType,
        wathqData: wathqVerification.toJson(),
        wathqVerifiedAt: DateTime.now(),
        wathqIntegrationStatus: wathqVerification.isVerified ? 'verified' : 'failed',
        authMethod: 'nafath',
      );

      // 4. حفظ في قاعدة البيانات
      if (existingUser != null) {
        await _updateUserProfile(userProfile);
        debugPrint('✅ تم تحديث بيانات المستخدم');
      } else {
        await _createUserProfile(userProfile);
        debugPrint('✅ تم إنشاء حساب جديد');
      }

      // 5. حفظ البيانات الإضافية حسب نوع المستخدم
      if (wathqVerification.userType == 'company') {
        await _saveCompanyData(userProfile.id!, wathqVerification);
      } else if (wathqVerification.userType == 'individual') {
        await _saveIndividualData(userProfile.id!, wathqVerification);
      }

      return userProfile;
    } catch (e) {
      debugPrint('❌ خطأ في createOrUpdateUserFromNafath: $e');
      rethrow;
    }
  }

  // ========================================
  // 2. التحقق الكامل عند الدخول
  // ========================================

  /// التحقق الشامل من بيانات المستخدم عند تسجيل الدخول
  /// يتحقق من صحة البيانات وينسقها
  Future<void> verifyUserDataOnLogin(String userId) async {
    try {
      debugPrint('🔐 بدء التحقق من بيانات المستخدم: $userId');

      final user = await supabase
          .from('users_profiles')
          .select()
          .eq('id', userId)
          .single();

      final nationalId = user['national_id'] as String?;
      if (nationalId == null) {
        throw Exception('رقم الهوية غير موجود في الملف');
      }

      // جلب بيانات Wathq
      final verification = await wathqService.verifyUserData(
        unifiedId: nationalId,
      );

      // تحديث حالة التحقق
      await supabase
          .from('users_profiles')
          .update({
            'wathq_verified_at': DateTime.now().toIso8601String(),
            'wathq_data': verification.toJson(),
            'wathq_integration_status':
                verification.isVerified ? 'verified' : 'failed',
          })
          .eq('id', userId);

      debugPrint('✅ تم التحقق بنجاح من البيانات');
    } catch (e) {
      debugPrint('⚠️ تحذير في التحقق من البيانات: $e');
      // لا نرفع الخطأ لأن الدخول يجب أن يستمر
      // لكن نسجل التحذير
    }
  }

  // ========================================
  // 3. مزامنة البيانات مع Wathq
  // ========================================

  /// مزامنة بيانات المستخدم مع Wathq
  /// يجلب أحدث البيانات من الخدمات الحكومية
  Future<void> syncUserDataWithWathq(String userId) async {
    try {
      debugPrint('🔄 بدء مزامنة البيانات مع Wathq: $userId');

      final user = await supabase
          .from('users_profiles')
          .select()
          .eq('id', userId)
          .single();

      final nationalId = user['wathq_unified_id'] as String?;
      final userType = user['wathq_user_type'] as String?;

      if (nationalId == null || userType == null) {
        throw Exception('بيانات المزامنة غير موجودة');
      }

      // جلب البيانات الجديدة
      final verification = await wathqService.verifyUserData(
        unifiedId: nationalId,
      );

      if (!verification.isVerified) {
        throw Exception('فشل التحقق من البيانات');
      }

      // تحديث البيانات
      await supabase
          .from('users_profiles')
          .update({
            'wathq_data': verification.toJson(),
            'wathq_verified_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);

      // تحديث البيانات الإضافية
      if (userType == 'company') {
        await _updateCompanyData(userId, verification);
      } else if (userType == 'individual') {
        await _updateIndividualData(userId, verification);
      }

      debugPrint('✅ تمت المزامنة بنجاح');
    } catch (e) {
      debugPrint('❌ خطأ في مزامنة البيانات: $e');
      rethrow;
    }
  }

  // ========================================
  // 4. حفظ بيانات الشركات
  // ========================================

  Future<void> _saveCompanyData(
    String userId,
    WathqVerificationResult verification,
  ) async {
    try {
      if (verification.commercialData == null) return;

      final comData = verification.commercialData!;

      // حفظ بيانات الشركة
      await supabase.from('company_profiles').upsert({
        'user_id': userId,
        'cr_number': comData.crNumber,
        'cr_national_number': comData.crNationalNumber,
        'company_name_ar': comData.name,
        'company_name_en': comData.nameEn,
        'company_type': comData.companyType,
        'headquarters_city': comData.headquarterCity,
        'capital': comData.capital,
        'company_duration': comData.companyDuration,
        'status': comData.status,
        'has_ecommerce': comData.hasEcommerce,
        'issue_date': comData.issueDate?.toIso8601String(),
        'wathq_data': comData.toJson(),
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      // حفظ العناوين
      if (verification.companyAddresses != null &&
          verification.companyAddresses!.isNotEmpty) {
        for (final address in verification.companyAddresses!) {
          await supabase.from('company_addresses').insert({
            'company_id': userId,
            'address_ar': address.addressAr,
            'address_en': address.addressEn,
            'building_number': address.buildingNumber,
            'street_name': address.street,
            'district': address.district,
            'city': address.city,
            'postal_code': address.postalCode,
            'latitude': address.latitude,
            'longitude': address.longitude,
            'is_primary_address': address.isPrimaryAddress,
            'wathq_data': address.toJson(),
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
      }

      debugPrint('✅ تم حفظ بيانات الشركة');
    } catch (e) {
      debugPrint('❌ خطأ في حفظ بيانات الشركة: $e');
      rethrow;
    }
  }

  Future<void> _updateCompanyData(
    String userId,
    WathqVerificationResult verification,
  ) async {
    try {
      if (verification.commercialData == null) return;

      final comData = verification.commercialData!;

      // تحديث بيانات الشركة
      await supabase
          .from('company_profiles')
          .update({
            'company_name_ar': comData.name,
            'company_name_en': comData.nameEn,
            'capital': comData.capital,
            'status': comData.status,
            'wathq_data': comData.toJson(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', userId);

      debugPrint('✅ تم تحديث بيانات الشركة');
    } catch (e) {
      debugPrint('⚠️ خطأ في تحديث بيانات الشركة: $e');
    }
  }

  // ========================================
  // 5. حفظ بيانات الأفراد
  // ========================================

  Future<void> _saveIndividualData(
    String userId,
    WathqVerificationResult verification,
  ) async {
    try {
      // حفظ بيانات الموظف
      if (verification.employeeData != null) {
        final empData = verification.employeeData!;
        await supabase.from('employee_information').insert({
          'user_id': userId,
          'national_id': empData.nationalId,
          'employer_name': empData.employerName,
          'job_title': empData.jobTitle,
          'employment_date': empData.employmentDate?.toIso8601String(),
          'salary': empData.salary,
          'employment_type': empData.employmentType,
          'employment_status': empData.employmentStatus,
          'company_sector': empData.companySector,
          'wathq_data': empData.toJson(),
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      // حفظ بيانات الصكوك العقارية
      if (verification.realEstateDeeds != null &&
          verification.realEstateDeeds!.isNotEmpty) {
        for (final deed in verification.realEstateDeeds!) {
          await supabase.from('real_estate_deeds').insert({
            'user_id': userId,
            'deed_number': deed.deedNumber,
            'deed_serial': deed.deedSerial,
            'property_type': deed.propertyType,
            'location': deed.location,
            'area': deed.area,
            'deed_date': deed.deedDate?.toIso8601String(),
            'property_owner_id': deed.propertyOwnerId,
            'owner_type': deed.ownerIdType,
            'property_status': deed.propertyStatus,
            'municipality_sector': deed.municipalitySector,
            'wathq_data': deed.toJson(),
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
      }

      debugPrint('✅ تم حفظ بيانات الفرد');
    } catch (e) {
      debugPrint('❌ خطأ في حفظ بيانات الفرد: $e');
      rethrow;
    }
  }

  Future<void> _updateIndividualData(
    String userId,
    WathqVerificationResult verification,
  ) async {
    try {
      if (verification.employeeData != null) {
        final empData = verification.employeeData!;
        await supabase
            .from('employee_information')
            .update({
              'employer_name': empData.employerName,
              'job_title': empData.jobTitle,
              'salary': empData.salary,
              'wathq_data': empData.toJson(),
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('user_id', userId);
      }

      debugPrint('✅ تم تحديث بيانات الفرد');
    } catch (e) {
      debugPrint('⚠️ خطأ في تحديث بيانات الفرد: $e');
    }
  }

  // ========================================
  // 6. دوال مساعدة
  // ========================================

  Future<UserProfile?> _findUserByNationalId(String nationalId) async {
    try {
      final result = await supabase
          .from('users_profiles')
          .select()
          .eq('national_id', nationalId)
          .maybeSingle();

      if (result == null) return null;
      return UserProfile.fromJson(result);
    } catch (e) {
      return null;
    }
  }

  Future<void> _createUserProfile(UserProfile profile) async {
    try {
      await supabase.from('users_profiles').insert(profile.toJson());
    } catch (e) {
      debugPrint('❌ خطأ في إنشاء ملف المستخدم: $e');
      rethrow;
    }
  }

  Future<void> _updateUserProfile(UserProfile profile) async {
    try {
      await supabase
          .from('users_profiles')
          .update(profile.toJson())
          .eq('id', profile.id!);
    } catch (e) {
      debugPrint('❌ خطأ في تحديث ملف المستخدم: $e');
      rethrow;
    }
  }

  // ========================================
  // 7. إدارة الـ Cache
  // ========================================

  void cacheVerificationResult(
    String userId,
    WathqVerificationResult result,
  ) {
    _verificationCache[userId] = result;
  }

  WathqVerificationResult? getCachedVerificationResult(String userId) {
    final cached = _verificationCache[userId];
    if (cached != null && cached.expiresAt!.isAfter(DateTime.now())) {
      return cached;
    }
    _verificationCache.remove(userId);
    return null;
  }

  void clearCache() {
    _userCache.clear();
    _verificationCache.clear();
  }
}

// ========================================
// 8. نموذج ملف المستخدم المحدّث
// ========================================

class UserProfile {
  String? id;
  String? email;
  String? phone;
  String? fullName;
  String? profilePhotoUrl;

  // بيانات نفاذ
  String? nationalId;
  DateTime? nafathVerifiedAt;
  Map<String, dynamic>? nafathData;

  // بيانات Wathq
  String? wathqUnifiedId;
  String? wathqUserType; // 'individual', 'company'
  Map<String, dynamic>? wathqData;
  DateTime? wathqVerifiedAt;
  String? wathqIntegrationStatus; // 'pending', 'verified', 'failed'

  // معلومات الحساب
  String? authMethod; // 'traditional', 'nafath'
  DateTime? createdAt;
  DateTime? updatedAt;

  UserProfile({
    this.id,
    this.email,
    this.phone,
    this.fullName,
    this.profilePhotoUrl,
    this.nationalId,
    this.nafathVerifiedAt,
    this.nafathData,
    this.wathqUnifiedId,
    this.wathqUserType,
    this.wathqData,
    this.wathqVerifiedAt,
    this.wathqIntegrationStatus,
    this.authMethod,
    this.createdAt,
    this.updatedAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'],
      email: json['email'],
      phone: json['phone'],
      fullName: json['full_name'],
      profilePhotoUrl: json['profile_photo_url'],
      nationalId: json['national_id'],
      nafathVerifiedAt: json['nafath_verified_at'] != null
          ? DateTime.parse(json['nafath_verified_at'])
          : null,
      nafathData: json['nafath_data'],
      wathqUnifiedId: json['wathq_unified_id'],
      wathqUserType: json['wathq_user_type'],
      wathqData: json['wathq_data'],
      wathqVerifiedAt: json['wathq_verified_at'] != null
          ? DateTime.parse(json['wathq_verified_at'])
          : null,
      wathqIntegrationStatus: json['wathq_integration_status'],
      authMethod: json['auth_method'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'phone': phone,
        'full_name': fullName,
        'profile_photo_url': profilePhotoUrl,
        'national_id': nationalId,
        'nafath_verified_at': nafathVerifiedAt?.toIso8601String(),
        'nafath_data': nafathData,
        'wathq_unified_id': wathqUnifiedId,
        'wathq_user_type': wathqUserType,
        'wathq_data': wathqData,
        'wathq_verified_at': wathqVerifiedAt?.toIso8601String(),
        'wathq_integration_status': wathqIntegrationStatus,
        'auth_method': authMethod,
        'created_at': createdAt?.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
      };
}
