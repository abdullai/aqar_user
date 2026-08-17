/// عند إضافة حقول إجبارية جديدة: زِد هذا الرقم في التطبيق وطبّق migration يضيف/يحدّث العمود
/// [users_profiles.profile_data_revision] ثم شغّل UPDATE لخفض المراجعة للمستخدمين إن لزم.
const int kAppRequiredProfileDataRevision = 1;

bool profileDataRevisionNeedsAck(Map<String, dynamic>? row) {
  if (row == null) return false;
  final v = row['profile_data_revision'];
  final n = v is int ? v : int.tryParse('$v') ?? 1;
  return n < kAppRequiredProfileDataRevision;
}
