/// هل حالة التحقق في [users_profiles.verification_status] تعني اكتمال التحقق؟
bool isProfileVerificationComplete(String? status) {
  final v = (status ?? '').trim().toLowerCase();
  if (v.isEmpty || v == 'none' || v == 'pending' || v == 'rejected') {
    return false;
  }
  return v == 'verified' ||
      v == 'approved' ||
      v == 'complete' ||
      v == 'verified_identity' ||
      v == 'verified_business';
}
