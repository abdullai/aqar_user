import '../../services/account_completion_service.dart';
import '../../services/profile_compliance_service.dart';
import '../profile/profile_gate_revision.dart';

/// ترتيب بوابات ما بعد تسجيل الدخول (OTP) — **مصدر واحد للحقيقة** يطابق [PostAuthShell].
///
/// الخادم والـ RLS: أعمدة `users_profiles` + RPCs موثّقة في
/// `supabase/sql/20260415_post_auth_gate_contract_doc.sql` وملفات
/// `20260323_org_teams_legal_devices.sql`, `20260409_ack_profile_data_revision_rpc.sql`.
///
/// **ليس هنا:** إعداد نوع الحساب/طلب KYC (`/accountTypeSetup`) — مسار تنقّل يدوي حتى
/// قرار منتج بدمجه في هذا الترتيب.
enum PostAuthShellStep {
  /// جلب `myProfileGates` / `activeLegalVersion`
  checkingLoading,

  /// `terms_version_accepted` ≠ النسخة النشطة
  legalTerms,

  /// `must_change_password`
  mandatoryPassword,

  /// `registerTrustedDevice` → `device_limit`
  deviceLimitBlocked,

  /// انتظار تسجيل الجهاز الموثوق
  deviceRegistering,

  /// لا صف `users_profiles` أو تعذّر التحميل — يجب عدم تجاوز باقي الفحوصات
  profileRecordMissing,

  /// طلب انضمام لمؤسسة بانتظار موافقة المدير (رمز العمل)
  pendingOrgJoinApproval,

  /// تسويق بدون رقم وطني موحّد صالح
  mandatoryUnifiedNational,

  /// `profile_data_revision` أقل من إصدار التطبيق المطلوب
  profileDataRevision,

  /// بيانات قديمة ناقصة في الملف الشخصي أو عقارات المستخدم
  legacyDataQualityRequired,

  /// فال منتهية / تجميد امتثال
  falBlockedExpired,

  /// توقيع ملف مفقود عند الاقتضاء
  signatureRequired,

  /// لوحة رئيسية + شريط تحذير فال (≤7 أيام)
  readyWithFalWeekBanner,

  /// الدخول للتطبيق (مع [FastLoginOfferHost])
  ready,
}

/// يحلّ أول خطوة حاجزة؛ يُستدعى بعد تحديث حالة الجهاز والامتثال.
abstract final class PostAuthGatePipeline {
  static PostAuthShellStep resolve({
    required bool loading,
    required bool showTerms,
    required Object? legal,
    required bool needPassword,
    required bool deviceBlocked,
    required bool deviceReady,
    required Map<String, dynamic>? complianceRow,
    required bool dataQualityRequired,
    Map<String, dynamic>? pendingOrgJoin,
  }) {
    if (loading) return PostAuthShellStep.checkingLoading;
    if (showTerms && legal != null) return PostAuthShellStep.legalTerms;
    if (needPassword) return PostAuthShellStep.mandatoryPassword;
    if (deviceBlocked) return PostAuthShellStep.deviceLimitBlocked;
    if (!deviceReady) return PostAuthShellStep.deviceRegistering;

    if (complianceRow == null) {
      return PostAuthShellStep.profileRecordMissing;
    }

    final joinRid = (pendingOrgJoin?['request_id'] ?? '').toString().trim();
    if (joinRid.isNotEmpty) {
      return PostAuthShellStep.pendingOrgJoinApproval;
    }

    if (AccountCompletionService.needsUnifiedNationalCompletion(
      complianceRow,
    )) {
      return PostAuthShellStep.mandatoryUnifiedNational;
    }
    if (profileDataRevisionNeedsAck(complianceRow)) {
      return PostAuthShellStep.profileDataRevision;
    }
    if (dataQualityRequired) {
      return PostAuthShellStep.legacyDataQualityRequired;
    }

    final fal = ProfileComplianceService.evaluateFal(complianceRow);
    if (fal == FalComplianceLevel.blockedExpired) {
      return PostAuthShellStep.falBlockedExpired;
    }
    if (ProfileComplianceService.needsSignature(complianceRow)) {
      return PostAuthShellStep.signatureRequired;
    }
    if (fal == FalComplianceLevel.warnWeek) {
      return PostAuthShellStep.readyWithFalWeekBanner;
    }
    return PostAuthShellStep.ready;
  }
}
