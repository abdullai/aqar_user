/// نماذج بيانات Wathq APIs
/// تشمل جميع البيانات المجلوبة من الخدمات الحكومية
library;

// ============================================
// 1. السجل التجاري - Commercial Registration
// ============================================

class CommercialRegistrationData {
  String crNumber;
  String crNationalNumber; // الرقم الموحد
  String name;
  String? nameEn;
  String? status; // 'فعال', 'معلق', إلخ
  String? companyType; // 'ذات مسؤولية محدودة', 'شركة مساهمة', إلخ
  DateTime? issueDate;
  String? issueHijriDate;
  int? capital;
  int? companyDuration; // بالسنوات
  String? headquarterCity;
  bool? hasEcommerce;
  bool? isMain;
  String? mainCrNationalNumber; // إذا كانت فرع
  String? mainCrNumber;
  bool? inLiquidationProcess;
  bool? isLicenseBased;
  String? licenseIssuerName;
  List<Partner>? partners;
  List<Activity>? activities;
  DateTime? confirmationDate;
  String? versionNo;

  CommercialRegistrationData({
    required this.crNumber,
    required this.crNationalNumber,
    required this.name,
    this.nameEn,
    this.status,
    this.companyType,
    this.issueDate,
    this.issueHijriDate,
    this.capital,
    this.companyDuration,
    this.headquarterCity,
    this.hasEcommerce,
    this.isMain,
    this.mainCrNationalNumber,
    this.mainCrNumber,
    this.inLiquidationProcess,
    this.isLicenseBased,
    this.licenseIssuerName,
    this.partners,
    this.activities,
    this.confirmationDate,
    this.versionNo,
  });

  factory CommercialRegistrationData.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    final confirmationDate = json['confirmationDate'];
    final issueDate = json['issueDateGregorian'] ?? json['issueDate'];
    return CommercialRegistrationData(
      crNumber: json['crNumber'] ?? '',
      crNationalNumber: json['crNationalNumber'] ?? '',
      name: json['name'] ?? '',
      nameEn: json['nameEn'],
      status: status is Map ? status['name'] as String? : status as String?,
      companyType: json['entityType']?['formName'],
      issueDate: issueDate != null ? DateTime.parse(issueDate as String) : null,
      issueHijriDate:
          (json['issueDateHijri'] ?? json['issueHijriDate']) as String?,
      capital: json['crCapital'],
      companyDuration: json['companyDuration'],
      headquarterCity: json['headquarterCityName'],
      hasEcommerce: json['hasEcommerce'],
      isMain: json['isMain'],
      mainCrNationalNumber: json['mainCrNationalNumber'],
      mainCrNumber: json['mainCrNumber'],
      inLiquidationProcess: json['inLiquidationProcess'],
      isLicenseBased: json['isLicenseBased'],
      licenseIssuerName: json['licenseIssuerName'],
      partners: (json['partners'] as List?)
          ?.map((p) => Partner.fromJson(p))
          .toList(),
      activities: (json['activities'] as List?)
          ?.map((a) => Activity.fromJson(a))
          .toList(),
      confirmationDate: switch (confirmationDate) {
        Map() when confirmationDate['gregorian'] != null =>
          DateTime.parse(confirmationDate['gregorian'] as String),
        String() => DateTime.parse(confirmationDate),
        _ => null,
      },
      versionNo: json['versionNo'],
    );
  }

  Map<String, dynamic> toJson() => {
        'crNumber': crNumber,
        'crNationalNumber': crNationalNumber,
        'name': name,
        'nameEn': nameEn,
        'status': status,
        'companyType': companyType,
        'issueDate': issueDate?.toIso8601String(),
        'issueHijriDate': issueHijriDate,
        'capital': capital,
        'companyDuration': companyDuration,
        'headquarterCity': headquarterCity,
        'hasEcommerce': hasEcommerce,
        'isMain': isMain,
        'mainCrNationalNumber': mainCrNationalNumber,
        'mainCrNumber': mainCrNumber,
        'inLiquidationProcess': inLiquidationProcess,
        'isLicenseBased': isLicenseBased,
        'licenseIssuerName': licenseIssuerName,
        'partners': partners?.map((p) => p.toJson()).toList(),
        'activities': activities?.map((a) => a.toJson()).toList(),
        'confirmationDate': confirmationDate?.toIso8601String(),
        'versionNo': versionNo,
      };
}

class Partner {
  String? name;
  String? nationalId;
  String? nationality;
  String? partnerType;

  Partner({
    this.name,
    this.nationalId,
    this.nationality,
    this.partnerType,
  });

  factory Partner.fromJson(Map<String, dynamic> json) {
    return Partner(
      name: json['name'],
      nationalId: json['nationalId'],
      nationality: json['nationality'],
      partnerType: json['partnerType'],
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'nationalId': nationalId,
        'nationality': nationality,
        'partnerType': partnerType,
      };
}

class Activity {
  String? code;
  String? description;
  String? descriptionEn;
  bool? isPrimary;

  Activity({
    this.code,
    this.description,
    this.descriptionEn,
    this.isPrimary,
  });

  factory Activity.fromJson(Map<String, dynamic> json) {
    return Activity(
      code: json['code'],
      description: json['description'],
      descriptionEn: json['descriptionEn'],
      isPrimary: json['isPrimary'],
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'description': description,
        'descriptionEn': descriptionEn,
        'isPrimary': isPrimary,
      };
}

// ================================================
// 2. العنوان الوطني - SPL National Address
// ================================================

class NationalAddressData {
  String title;
  String addressAr;
  String? addressEn;
  String? address2;
  String city;
  String? cityId;
  String? district;
  String? districtId;
  String? region;
  String? regionId;
  String? buildingNumber;
  String? street;
  String? postalCode;
  String? additionalNumber;
  String? unitNumber;
  double? latitude;
  double? longitude;
  bool isPrimaryAddress;
  String? status;
  String? pkAddressId;

  NationalAddressData({
    required this.title,
    required this.addressAr,
    this.addressEn,
    this.address2,
    required this.city,
    this.cityId,
    this.district,
    this.districtId,
    this.region,
    this.regionId,
    this.buildingNumber,
    this.street,
    this.postalCode,
    this.additionalNumber,
    this.unitNumber,
    this.latitude,
    this.longitude,
    required this.isPrimaryAddress,
    this.status,
    this.pkAddressId,
  });

  factory NationalAddressData.fromJson(Map<String, dynamic> json) {
    return NationalAddressData(
      title: json['title'] ?? '',
      addressAr: json['address'] ?? '',
      addressEn: json['addressEn'],
      address2: json['address2'],
      city: json['city'] ?? '',
      cityId: json['cityId'],
      district: json['district'],
      districtId: json['districtId'],
      region: json['regionName'],
      regionId: json['regionId'],
      buildingNumber: json['buildingNumber'],
      street: json['street'],
      postalCode: json['postCode'],
      additionalNumber: json['additionalNumber'],
      unitNumber: json['unitNumber'],
      latitude: json['latitude'] != null
          ? double.tryParse(json['latitude'].toString())
          : null,
      longitude: json['longitude'] != null
          ? double.tryParse(json['longitude'].toString())
          : null,
      isPrimaryAddress: json['isPrimaryAddress'] ?? false,
      status: json['status'],
      pkAddressId: json['pkAddressId'],
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'addressAr': addressAr,
        'addressEn': addressEn,
        'address2': address2,
        'city': city,
        'cityId': cityId,
        'district': district,
        'districtId': districtId,
        'region': region,
        'regionId': regionId,
        'buildingNumber': buildingNumber,
        'street': street,
        'postalCode': postalCode,
        'additionalNumber': additionalNumber,
        'unitNumber': unitNumber,
        'latitude': latitude,
        'longitude': longitude,
        'isPrimaryAddress': isPrimaryAddress,
        'status': status,
        'pkAddressId': pkAddressId,
      };
}

// ================================================
// 3. بيانات الموظف - Employee Information
// ================================================

class EmployeeInformationData {
  String? nationalId;
  String? iqamaNumber;
  String? employerName;
  String? jobTitle;
  String? jobTitleEn;
  DateTime? employmentDate;
  DateTime? contractEndDate;
  double? salary;
  String? employmentType; // full_time, contract, seasonal
  String? employmentStatus; // active, inactive, suspended
  String? companySector;
  String? companyNameAr;
  String? companyNameEn;
  String? workLocation;
  bool? isCurrentlyEmployed;
  String? contractType;
  double? workingHours;
  String? insuranceNumber;

  EmployeeInformationData({
    this.nationalId,
    this.iqamaNumber,
    this.employerName,
    this.jobTitle,
    this.jobTitleEn,
    this.employmentDate,
    this.contractEndDate,
    this.salary,
    this.employmentType,
    this.employmentStatus,
    this.companySector,
    this.companyNameAr,
    this.companyNameEn,
    this.workLocation,
    this.isCurrentlyEmployed,
    this.contractType,
    this.workingHours,
    this.insuranceNumber,
  });

  factory EmployeeInformationData.fromJson(Map<String, dynamic> json) {
    return EmployeeInformationData(
      nationalId: json['nationalId'] ?? json['id'],
      iqamaNumber: json['iqamaNumber'],
      employerName: json['employerName'],
      jobTitle: json['jobTitle'],
      jobTitleEn: json['jobTitleEn'],
      employmentDate: json['employmentDate'] != null
          ? DateTime.parse(json['employmentDate'])
          : null,
      contractEndDate: json['contractEndDate'] != null
          ? DateTime.parse(json['contractEndDate'])
          : null,
      salary: json['salary'] != null
          ? double.tryParse(json['salary'].toString())
          : null,
      employmentType: json['employmentType'],
      employmentStatus: json['employmentStatus'],
      companySector: json['companySector'],
      companyNameAr: json['companyNameAr'],
      companyNameEn: json['companyNameEn'],
      workLocation: json['workLocation'],
      isCurrentlyEmployed: json['isCurrentlyEmployed'],
      contractType: json['contractType'],
      workingHours: json['workingHours'] != null
          ? double.tryParse(json['workingHours'].toString())
          : null,
      insuranceNumber: json['insuranceNumber'],
    );
  }

  Map<String, dynamic> toJson() => {
        'nationalId': nationalId,
        'iqamaNumber': iqamaNumber,
        'employerName': employerName,
        'jobTitle': jobTitle,
        'jobTitleEn': jobTitleEn,
        'employmentDate': employmentDate?.toIso8601String(),
        'contractEndDate': contractEndDate?.toIso8601String(),
        'salary': salary,
        'employmentType': employmentType,
        'employmentStatus': employmentStatus,
        'companySector': companySector,
        'companyNameAr': companyNameAr,
        'companyNameEn': companyNameEn,
        'workLocation': workLocation,
        'isCurrentlyEmployed': isCurrentlyEmployed,
        'contractType': contractType,
        'workingHours': workingHours,
        'insuranceNumber': insuranceNumber,
      };
}

// ================================================
// 4. الصك العقاري - Real Estate Deed
// ================================================

class RealEstateDeedData {
  String deedNumber;
  String? deedSerial;
  String propertyType;
  String? propertyTypeEn;
  String location;
  String? locationEn;
  double? area; // بالمتر المربع
  DateTime? deedDate;
  String? deedDateHijri;
  String propertyOwnerName;
  String propertyOwnerId;
  String? ownerIdType; // National_ID, CR_NO, etc
  String? ownerNationality;
  String? propertyStatus;
  String? municipalitySector;
  String? city;
  String? district;
  List<Beneficiary>? beneficiaries;
  String? mortgageStatus;
  bool? hasCharges;
  DateTime? registrationDate;
  String? registrationAuthority;

  RealEstateDeedData({
    required this.deedNumber,
    this.deedSerial,
    required this.propertyType,
    this.propertyTypeEn,
    required this.location,
    this.locationEn,
    this.area,
    this.deedDate,
    this.deedDateHijri,
    required this.propertyOwnerName,
    required this.propertyOwnerId,
    this.ownerIdType,
    this.ownerNationality,
    this.propertyStatus,
    this.municipalitySector,
    this.city,
    this.district,
    this.beneficiaries,
    this.mortgageStatus,
    this.hasCharges,
    this.registrationDate,
    this.registrationAuthority,
  });

  factory RealEstateDeedData.fromJson(Map<String, dynamic> json) {
    return RealEstateDeedData(
      deedNumber: json['deedNumber'] ?? '',
      deedSerial: json['deedSerial'],
      propertyType: json['propertyType'] ?? '',
      propertyTypeEn: json['propertyTypeEn'],
      location: json['location'] ?? '',
      locationEn: json['locationEn'],
      area: json['area'] != null
          ? double.tryParse(json['area'].toString())
          : null,
      deedDate: json['deedDate'] != null
          ? DateTime.parse(json['deedDate'])
          : null,
      deedDateHijri: json['deedDateHijri'],
      propertyOwnerName: json['propertyOwnerName'] ?? '',
      propertyOwnerId: json['propertyOwnerId'] ?? '',
      ownerIdType: json['ownerIdType'],
      ownerNationality: json['ownerNationality'],
      propertyStatus: json['propertyStatus'],
      municipalitySector: json['municipalitySector'],
      city: json['city'],
      district: json['district'],
      beneficiaries: (json['beneficiaries'] as List?)
          ?.map((b) => Beneficiary.fromJson(b))
          .toList(),
      mortgageStatus: json['mortgageStatus'],
      hasCharges: json['hasCharges'],
      registrationDate: json['registrationDate'] != null
          ? DateTime.parse(json['registrationDate'])
          : null,
      registrationAuthority: json['registrationAuthority'],
    );
  }

  Map<String, dynamic> toJson() => {
        'deedNumber': deedNumber,
        'deedSerial': deedSerial,
        'propertyType': propertyType,
        'propertyTypeEn': propertyTypeEn,
        'location': location,
        'locationEn': locationEn,
        'area': area,
        'deedDate': deedDate?.toIso8601String(),
        'deedDateHijri': deedDateHijri,
        'propertyOwnerName': propertyOwnerName,
        'propertyOwnerId': propertyOwnerId,
        'ownerIdType': ownerIdType,
        'ownerNationality': ownerNationality,
        'propertyStatus': propertyStatus,
        'municipalitySector': municipalitySector,
        'city': city,
        'district': district,
        'beneficiaries': beneficiaries?.map((b) => b.toJson()).toList(),
        'mortgageStatus': mortgageStatus,
        'hasCharges': hasCharges,
        'registrationDate': registrationDate?.toIso8601String(),
        'registrationAuthority': registrationAuthority,
      };
}

class Beneficiary {
  String? name;
  String? idNumber;
  String? idType;
  String? relationship;

  Beneficiary({
    this.name,
    this.idNumber,
    this.idType,
    this.relationship,
  });

  factory Beneficiary.fromJson(Map<String, dynamic> json) {
    return Beneficiary(
      name: json['name'],
      idNumber: json['idNumber'],
      idType: json['idType'],
      relationship: json['relationship'],
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'idNumber': idNumber,
        'idType': idType,
        'relationship': relationship,
      };
}

// ================================================
// 5. نتيجة التحقق الشاملة - Verification Result
// ================================================

class WathqVerificationResult {
  bool isVerified;
  String userType; // 'individual', 'company', 'other'
  String unifiedId; // الرقم الموحد
  DateTime verifiedAt;
  DateTime? expiresAt;

  // بيانات الشركة
  CommercialRegistrationData? commercialData;
  List<NationalAddressData>? companyAddresses;

  // بيانات الفرد
  EmployeeInformationData? employeeData;
  List<RealEstateDeedData>? realEstateDeeds;

  // حالة التحقق
  Map<String, VerificationStatus>? verificationStatusMap;
  String? verificationNotes;

  WathqVerificationResult({
    required this.isVerified,
    required this.userType,
    required this.unifiedId,
    required this.verifiedAt,
    this.expiresAt,
    this.commercialData,
    this.companyAddresses,
    this.employeeData,
    this.realEstateDeeds,
    this.verificationStatusMap,
    this.verificationNotes,
  });

  factory WathqVerificationResult.fromJson(Map<String, dynamic> json) {
    return WathqVerificationResult(
      isVerified: json['isVerified'] ?? false,
      userType: json['userType'] ?? 'unknown',
      unifiedId: json['unifiedId'] ?? '',
      verifiedAt: json['verifiedAt'] != null
          ? DateTime.parse(json['verifiedAt'])
          : DateTime.now(),
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'])
          : null,
      commercialData: json['commercialData'] != null
          ? CommercialRegistrationData.fromJson(json['commercialData'])
          : null,
      companyAddresses: (json['companyAddresses'] as List?)
          ?.map((a) => NationalAddressData.fromJson(a))
          .toList(),
      employeeData: json['employeeData'] != null
          ? EmployeeInformationData.fromJson(json['employeeData'])
          : null,
      realEstateDeeds: (json['realEstateDeeds'] as List?)
          ?.map((d) => RealEstateDeedData.fromJson(d))
          .toList(),
      verificationNotes: json['verificationNotes'],
    );
  }

  Map<String, dynamic> toJson() => {
        'isVerified': isVerified,
        'userType': userType,
        'unifiedId': unifiedId,
        'verifiedAt': verifiedAt.toIso8601String(),
        'expiresAt': expiresAt?.toIso8601String(),
        'commercialData': commercialData?.toJson(),
        'companyAddresses': companyAddresses?.map((a) => a.toJson()).toList(),
        'employeeData': employeeData?.toJson(),
        'realEstateDeeds': realEstateDeeds?.map((d) => d.toJson()).toList(),
        'verificationNotes': verificationNotes,
      };
}

class VerificationStatus {
  String status; // 'pending', 'verified', 'failed', 'skipped'
  DateTime? checkedAt;
  String? errorMessage;
  dynamic data;

  VerificationStatus({
    required this.status,
    this.checkedAt,
    this.errorMessage,
    this.data,
  });
}
