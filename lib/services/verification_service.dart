import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VerificationService {
  static final _sb = Supabase.instance.client;

  static Future<String?> pickFileBytesAndUpload({
    required String folderName, // e.g. 'doc1'
  }) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) throw 'No session';

    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result == null || result.files.isEmpty) return null;

    final f = result.files.first;
    final Uint8List? bytes = f.bytes;
    if (bytes == null) throw 'No bytes';

    final ext = (f.extension ?? 'bin').toLowerCase();
    final path = '$uid/$folderName/${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _sb.storage.from('kyc').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: _contentType(ext),
            upsert: false,
          ),
        );

    return path;
  }

  static String _contentType(String ext) {
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      default:
        return 'application/octet-stream';
    }
  }

  /// Returns the new [verification_requests] row id.
  static Future<String> createVerificationRequest({
    required String requestedAccountType, // marketer/office/institution/company
    String? officeName,
    String? licenseNo,
    String? commercialRegNo,
    String? docPath1,
    String? docPath2,
    String? note,
    Map<String, dynamic>? extraPayload,
    String? contactEmail,
    String? contactPhone,
    Map<String, dynamic>? regaFalSnapshot,
    String? falLicenseExpiresAtIso,
    String? unifiedCommercialRegNo,
    Map<String, dynamic>? commercialRegSnapshot,
  }) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) throw 'No session';

    final row = <String, dynamic>{
      'user_id': uid,
      'requested_account_type': requestedAccountType,
      'status': 'pending',
      'office_name': officeName,
      'license_no': licenseNo,
      'commercial_reg_no': commercialRegNo,
      'doc_url_1': docPath1,
      'doc_url_2': docPath2,
      'note': note,
    };
    if (extraPayload != null) row['extra_payload'] = extraPayload;

    Map<String, dynamic> inserted;
    try {
      final res = await _sb.from('verification_requests').insert(row).select('id').single();
      inserted = Map<String, dynamic>.from(res);
    } on PostgrestException catch (e) {
      final msg = e.message;
      if (extraPayload != null &&
          (msg.contains('extra_payload') ||
              msg.contains('schema cache') ||
              e.code == 'PGRST204')) {
        row.remove('extra_payload');
        final res = await _sb.from('verification_requests').insert(row).select('id').single();
        inserted = Map<String, dynamic>.from(res);
      } else {
        rethrow;
      }
    }

    final id = inserted['id']?.toString();
    if (id == null || id.isEmpty) throw 'insert_failed';

    final profile = <String, dynamic>{
      'account_type': requestedAccountType,
      'verification_status': 'pending',
      'office_name': officeName,
      'license_no': licenseNo,
      'commercial_reg_no': commercialRegNo,
    };
    if (contactEmail != null && contactEmail.trim().isNotEmpty) {
      profile['contact_email'] = contactEmail.trim();
    }
    if (contactPhone != null && contactPhone.trim().isNotEmpty) {
      profile['contact_phone'] = contactPhone.trim();
    }
    if (regaFalSnapshot != null) {
      profile['rega_fal_snapshot'] = regaFalSnapshot;
    }
    if (falLicenseExpiresAtIso != null && falLicenseExpiresAtIso.isNotEmpty) {
      profile['fal_license_expires_at'] = falLicenseExpiresAtIso;
    }
    if (unifiedCommercialRegNo != null &&
        unifiedCommercialRegNo.trim().isNotEmpty) {
      profile['unified_commercial_reg_no'] = unifiedCommercialRegNo.trim();
    }
    if (commercialRegSnapshot != null) {
      profile['commercial_reg_snapshot'] = commercialRegSnapshot;
    }

    try {
      await _sb.from('users_profiles').update(profile).eq('user_id', uid);
    } on PostgrestException catch (e) {
      final msg = e.message;
      if (msg.contains('contact_email') ||
          msg.contains('contact_phone') ||
          msg.contains('rega_fal_snapshot') ||
          msg.contains('fal_license_expires_at') ||
          msg.contains('unified_commercial_reg_no') ||
          msg.contains('commercial_reg_snapshot') ||
          e.code == 'PGRST204') {
        profile.remove('contact_email');
        profile.remove('contact_phone');
        profile.remove('rega_fal_snapshot');
        profile.remove('fal_license_expires_at');
        profile.remove('unified_commercial_reg_no');
        profile.remove('commercial_reg_snapshot');
        await _sb.from('users_profiles').update(profile).eq('user_id', uid);
      } else {
        rethrow;
      }
    }

    return id;
  }
}
