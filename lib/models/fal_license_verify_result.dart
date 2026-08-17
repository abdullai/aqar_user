class FalLicenseVerifyResult {
  FalLicenseVerifyResult({
    required this.valid,
    required this.status,
    this.brokerName,
    this.email,
    this.mobile,
    this.city,
    this.district,
    this.region,
    this.licenseType,
    this.licenseNo,
    this.licenseStatusText,
    this.startDateIso,
    this.endDateIso,
    this.nationalId,
    this.source,
    this.errorMessage,
  });

  final bool valid;
  final String status;
  final String? brokerName;
  final String? email;
  final String? mobile;
  final String? nationalId;
  final String? city;
  final String? district;
  final String? region;
  final String? licenseType;
  final String? licenseNo;
  final String? licenseStatusText;
  final String? startDateIso;
  final String? endDateIso;
  final String? source;
  final String? errorMessage;

  bool get isExpired => status == 'expired';

  static FalLicenseVerifyResult fromJson(Map<String, dynamic> j) {
    return FalLicenseVerifyResult(
      valid: j['valid'] == true,
      status: '${j['status'] ?? 'unknown'}',
      brokerName: j['broker_name']?.toString(),
      email: j['email']?.toString(),
      mobile: j['mobile']?.toString(),
      city: j['city']?.toString(),
      district: j['district']?.toString(),
      region: j['region']?.toString(),
      licenseType: j['license_type']?.toString(),
      licenseNo: j['license_no']?.toString(),
      licenseStatusText: j['license_status_text']?.toString(),
      startDateIso: j['start_date']?.toString(),
      endDateIso: j['end_date']?.toString(),
      nationalId: j['national_id']?.toString() ??
          j['broker_national_id']?.toString() ??
          j['nid']?.toString(),
      source: j['source']?.toString(),
      errorMessage: j['error']?.toString(),
    );
  }
}
