import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/input/saudi_input_formatters.dart';
import '../core/permissions/runtime_permission_helper.dart';
import '../l10n/app_localizations.dart';
import '../models/fal_license_verify_result.dart';
import '../services/commercial_reg_service.dart';
import '../services/fal_license_service.dart';
import '../services/org_team_service.dart';
import '../services/verification_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/email_domain_suggestions_field.dart';
import '../widgets/field_group_frame.dart';
import '../core/navigation/post_auth_navigation.dart';

class VerificationRequestScreen extends StatefulWidget {
  const VerificationRequestScreen({super.key});

  @override
  State<VerificationRequestScreen> createState() =>
      _VerificationRequestScreenState();
}

class _VerificationRequestScreenState extends State<VerificationRequestScreen> {
  bool _busy = false;
  String? _err;
  String? _doc1;
  String? _doc2;

  final _falLicense = TextEditingController();
  final _officeName = TextEditingController();
  final _crNo = TextEditingController();
  final _note = TextEditingController();

  final _brokerName = TextEditingController();
  final _brokerEmail = TextEditingController();
  final _brokerPhone = TextEditingController();
  final _city = TextEditingController();
  final _district = TextEditingController();
  final _region = TextEditingController();
  final _licenseType = TextEditingController();
  final _licenseStatus = TextEditingController();

  final _teamJoinCode = TextEditingController();
  final _unifiedCr = TextEditingController();

  bool _falLookupBusy = false;
  bool _commercialBusy = false;
  Map<String, dynamic>? _commercialSnapshot;
  FalLicenseVerifyResult? _falResult;
  bool _partOfTeam = false;

  DateTime? _lastLatinSnackAt;

  late final FalLicenseService _falSvc =
      FalLicenseService(Supabase.instance.client);
  late final CommercialRegService _commercialSvc =
      CommercialRegService(Supabase.instance.client);
  late final OrgTeamService _orgSvc =
      OrgTeamService(Supabase.instance.client);

  @override
  void dispose() {
    _falLicense.dispose();
    _officeName.dispose();
    _crNo.dispose();
    _note.dispose();
    _brokerName.dispose();
    _brokerEmail.dispose();
    _brokerPhone.dispose();
    _city.dispose();
    _district.dispose();
    _region.dispose();
    _licenseType.dispose();
    _licenseStatus.dispose();
    _teamJoinCode.dispose();
    _unifiedCr.dispose();
    super.dispose();
  }

  void _latinBlockedSnack() {
    final now = DateTime.now();
    if (_lastLatinSnackAt != null &&
        now.difference(_lastLatinSnackAt!) < const Duration(milliseconds: 900)) {
      return;
    }
    _lastLatinSnackAt = now;
    if (!mounted) return;
    final msg = AppLocalizations.of(context)?.latinCharsNotAllowedSnackbar ??
        'هذا الحقل لا يقبل أحرفاً إنجليزية.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static bool _needsFal(String type) =>
      const {'marketer', 'office', 'institution', 'company'}.contains(type);

  static bool _isOrg(String type) =>
      const {'office', 'institution', 'company'}.contains(type);

  String _screenTitle(AppLocalizations t, String type) {
    switch (type) {
      case 'office':
        return t.verScreenTitleOffice;
      case 'institution':
        return t.verScreenTitleInstitution;
      case 'company':
        return t.verScreenTitleCompany;
      case 'marketer':
      default:
        return t.verScreenTitleMarketer;
    }
  }

  Future<void> _runMcLookup(AppLocalizations t) async {
    setState(() {
      _err = null;
      _commercialBusy = true;
      _commercialSnapshot = null;
    });
    final res = await _commercialSvc.lookupUnified(_unifiedCr.text);
    if (!mounted) return;
    setState(() => _commercialBusy = false);
    if (!res.ok) {
      setState(() => _err = res.error ?? t.falRenewalInvalid);
      return;
    }
    if (!res.validForActive) {
      setState(() => _err = t.verMcRegistryNotActive);
      return;
    }
    _commercialSnapshot = {
      'entity_name_ar': res.entityNameAr,
      'registry_status_ar': res.registryStatusAr,
      'commercial_reg_no': res.commercialRegNo,
      'issue_date': res.issueDate,
      'activity_ar': res.activityAr,
      'capital': res.capital,
      'valid_for_active': true,
      'source': res.source,
    };
    if (res.entityNameAr != null && res.entityNameAr!.trim().isNotEmpty) {
      _officeName.text = res.entityNameAr!.trim();
    }
    if (res.commercialRegNo != null && res.commercialRegNo!.trim().isNotEmpty) {
      _crNo.text = res.commercialRegNo!.replaceAll(RegExp(r'\D'), '');
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t.verMcLookupSuccess),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _runFalLookup(AppLocalizations t) async {
    setState(() {
      _err = null;
      _falLookupBusy = true;
      _falResult = null;
    });
    final res = await _falSvc.verify(_falLicense.text);
    if (!mounted) return;
    setState(() {
      _falLookupBusy = false;
      _falResult = res;
    });

    if (!res.valid) {
      setState(() {
        _err = res.isExpired
            ? t.falRenewalExpired
            : (res.errorMessage ??
                '${t.falRenewalInvalid} (${res.status})');
      });
      return;
    }

    _brokerName.text = res.brokerName ?? '';
    _brokerEmail.text = res.email ?? '';
    _brokerPhone.text = res.mobile ?? '';
    _city.text = res.city ?? '';
    _district.text = res.district ?? '';
    _region.text = res.region ?? '';
    _licenseType.text = res.licenseType ?? '';
    _licenseStatus.text = res.licenseStatusText ?? '';
    if (res.licenseNo != null && res.licenseNo!.isNotEmpty) {
      _falLicense.text = res.licenseNo!;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t.verFalDataLoadedSnackbar),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final requestedType =
        (ModalRoute.of(context)?.settings.arguments as String?) ?? 'marketer';
    final isOrg = _isOrg(requestedType);
    final needsFal = _needsFal(requestedType);

    return Scaffold(
      appBar: AppBar(title: Text(_screenTitle(t, requestedType))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            if (_err != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: cs.error.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  _err!,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: cs.error,
                  ),
                ),
              ),

            const SizedBox(height: 12),

            if (needsFal) ...[
              FieldGroupFrame(
                title: t.fieldGroupVerificationFalTitle,
                subtitle: t.fieldGroupVerificationFalSubtitle,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AqarTextField(
                      controller: _falLicense,
                      keyboardType: TextInputType.number,
                      maxLength: 10,
                      inputFormatters: [
                        ArabicDigitsToLatinFormatter(),
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: t.verFalLicenseLabel,
                        hintText: t.verFalLicenseHint,
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _falLookupBusy || _busy
                            ? null
                            : () => _runFalLookup(t),
                        icon: _falLookupBusy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.search),
                        label: Text(
                          _falLookupBusy
                              ? t.verFalLookupBusy
                              : t.verFalLookupButton,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    if (_falResult != null && _falResult!.valid) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${t.badgeVerifiedShort} · ${_falResult!.status == 'active' ? 'OK' : _falResult!.status}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: AqarTextField(
                            controller: _brokerName,
                            decoration: InputDecoration(
                              labelText: t.verBrokerNameLabel,
                              hintText: t.verBrokerNameHint,
                            ),
                            inputFormatters: [
                              BlockLatinLettersFormatter(_latinBlockedSnack),
                            ],
                          ),
                        ),
                        if (_falResult != null && _falResult!.valid) ...[
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Chip(
                              avatar:
                                  const Icon(Icons.verified, size: 18),
                              label: Text(t.badgeVerifiedShort),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    EmailDomainSuggestionsField(
                      controller: _brokerEmail,
                      labelText: t.verBrokerEmailLabel,
                      hintText: t.verBrokerEmailHint,
                    ),
                    const SizedBox(height: 12),
                    AqarTextField(
                      controller: _brokerPhone,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        ArabicDigitsToLatinFormatter(),
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: t.verPhoneLabel,
                        hintText: t.verBrokerPhoneHint,
                      ),
                    ),
                    const SizedBox(height: 12),
                    AqarTextField(
                      controller: _city,
                      decoration: InputDecoration(
                        labelText: t.verCityLabel,
                        hintText: t.verCityHint,
                      ),
                      inputFormatters: [
                        BlockLatinLettersFormatter(_latinBlockedSnack),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AqarTextField(
                      controller: _district,
                      decoration: InputDecoration(
                        labelText: t.verDistrictLabel,
                        hintText: t.verDistrictHint,
                      ),
                      inputFormatters: [
                        BlockLatinLettersFormatter(_latinBlockedSnack),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AqarTextField(
                      controller: _region,
                      decoration: InputDecoration(
                        labelText: t.verRegionLabel,
                        hintText: t.verRegionHint,
                      ),
                      inputFormatters: [
                        BlockLatinLettersFormatter(_latinBlockedSnack),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AqarTextField(
                      controller: _licenseType,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: t.verLicenseTypeLabel,
                      ),
                    ),
                    const SizedBox(height: 12),
                    AqarTextField(
                      controller: _licenseStatus,
                      readOnly: true,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: t.verLicenseStatusLabel,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (isOrg)
              FieldGroupFrame(
                title: t.fieldGroupVerificationOrgTitle,
                subtitle: t.fieldGroupVerificationOrgSubtitle,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AqarTextField(
                      controller: _officeName,
                      decoration: InputDecoration(
                        labelText: t.verOfficeNameLabel,
                        hintText: t.verOfficeNameHint,
                      ),
                      inputFormatters: [
                        BlockLatinLettersFormatter(_latinBlockedSnack),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AqarTextField(
                      controller: _crNo,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        ArabicDigitsToLatinFormatter(),
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: t.verCrLabel,
                        hintText: t.verCrHint,
                      ),
                    ),
                    const SizedBox(height: 12),
                    AqarTextField(
                      controller: _unifiedCr,
                      keyboardType: TextInputType.number,
                      maxLength: 10,
                      inputFormatters: [
                        ArabicDigitsToLatinFormatter(),
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: t.verUnifiedCrLabel,
                        hintText: t.verUnifiedCrHint,
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _commercialBusy || _busy
                            ? null
                            : () => _runMcLookup(t),
                        icon: _commercialBusy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.business_center_outlined),
                        label: Text(
                          t.verMcLookupButton,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            if (!needsFal && !isOrg) ...[
              FieldGroupFrame(
                title: t.fieldGroupVerificationOptionalLicenseTitle,
                subtitle: t.fieldGroupVerificationOptionalLicenseSubtitle,
                child: AqarTextField(
                  controller: _falLicense,
                  decoration: InputDecoration(
                    labelText: t.verFalLicenseLabel,
                    hintText: t.verFalLicenseHint,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            const SizedBox(height: 12),

            FieldGroupFrame(
              title: t.fieldGroupVerificationMoreTitle,
              subtitle: t.fieldGroupVerificationMoreSubtitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t.verTeamSwitchTitle),
                    subtitle: Text(t.verTeamSwitchSubtitle),
                    value: _partOfTeam,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                              _partOfTeam = v;
                              if (!v) _teamJoinCode.clear();
                            }),
                  ),
                  if (_partOfTeam) ...[
                    const SizedBox(height: 8),
                    AqarTextField(
                      controller: _teamJoinCode,
                      keyboardType: TextInputType.number,
                      maxLength: 10,
                      inputFormatters: [
                        ArabicDigitsToLatinFormatter(),
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: t.verTeamCodeHint,
                        hintText: t.verTeamCodeHint,
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t.verTeamPendingNote,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  AqarTextField(
                    controller: _note,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: t.verNoteHint,
                      hintText: t.verNoteHint,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            FieldGroupFrame(
              title: t.fieldGroupVerificationDocumentsTitle,
              subtitle: t.fieldGroupVerificationDocumentsSubtitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _fileRow(
                    title: 'المستند 1 (PDF/صورة)',
                    value: _doc1,
                    onPick: () async => _pickVerificationDoc(
                      folderName: 'doc1',
                      assign: (p) => _doc1 = p,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _fileRow(
                    title: 'المستند 2 (اختياري)',
                    value: _doc2,
                    onPick: () async => _pickVerificationDoc(
                      folderName: 'doc2',
                      assign: (p) => _doc2 = p,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _busy
                          ? null
                          : () => _submit(
                                context,
                                requestedType: requestedType,
                                isOrg: isOrg,
                                needsFal: needsFal,
                              ),
                      child: _busy
                          ? const SizedBox(
                              width: 28,
                              height: 28,
                              child: AppLogoLoading(
                                  compact: true, size: 26),
                            )
                          : const Text(
                              'إرسال طلب التوثيق',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickVerificationDoc({
    required String folderName,
    required void Function(String path) assign,
  }) async {
    final t = AppLocalizations.of(context);
    if (t != null &&
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      final ok = await RuntimePermissionHelper.ensurePhotos(context, t: t);
      if (!ok || !mounted) return;
    }
    setState(() => _err = null);
    final p = await VerificationService.pickFileBytesAndUpload(
      folderName: folderName,
    );
    if (p != null && mounted) setState(() => assign(p));
  }

  Widget _fileRow({
    required String title,
    required String? value,
    required VoidCallback onPick,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value == null ? title : '$title\nتم الرفع: ${value.split('/').last}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : onPick,
            icon: const Icon(Icons.upload_file),
            label: const Text('اختيار'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit(
    BuildContext context, {
    required String requestedType,
    required bool isOrg,
    required bool needsFal,
  }) async {
    final t = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _err = null;
    });

    try {
      if (_doc1 == null) {
        throw 'المستند 1 مطلوب.';
      }
      if (isOrg && _officeName.text.trim().isEmpty) {
        throw 'اسم المكتب/المؤسسة/الشركة مطلوب.';
      }
      if (isOrg && _crNo.text.trim().isEmpty) {
        throw 'السجل التجاري مطلوب.';
      }

      if (isOrg) {
        final u = _unifiedCr.text.replaceAll(RegExp(r'\D'), '');
        if (u.isNotEmpty) {
          if (u.length != 10) {
            throw t.loginIdentifierMustBe10;
          }
          if (_commercialSnapshot == null) {
            throw t.verMcPleaseLookup;
          }
        }
        if (_commercialSnapshot != null &&
            _commercialSnapshot!['valid_for_active'] != true) {
          throw t.verMcRegistryNotActive;
        }
      }

      if (needsFal) {
        final digits = _falLicense.text.replaceAll(RegExp(r'\D'), '');
        if (digits.length != 10) {
          throw 'أدخل رقم رخصة فال المكوّن من 10 أرقام ثم اضغط «استعلام».';
        }
        if (_falResult == null || !_falResult!.valid) {
          throw 'اضغط «استعلام عن الرخصة» وتأكد أن الرخصة سارية قبل الإرسال.';
        }
        if (_falResult!.isExpired) {
          throw 'انتهت صلاحية الرخصة — لا يمكن إرسال الطلب.';
        }
        if (_brokerName.text.trim().isEmpty) {
          throw 'اسم الوسيط مطلوب.';
        }
      }

      if (_partOfTeam) {
        final code = _teamJoinCode.text.replaceAll(RegExp(r'\D'), '');
        if (code.length != 10) {
          throw 'رقم تعريف فريق العمل يجب أن يكون 10 أرقام.';
        }
      }

      final licenseNo = _falLicense.text.replaceAll(RegExp(r'\D'), '');
      final regaMap = _falResult != null
          ? {
              'valid': _falResult!.valid,
              'status': _falResult!.status,
              'broker_name': _falResult!.brokerName,
              'email': _falResult!.email,
              'mobile': _falResult!.mobile,
              'city': _falResult!.city,
              'district': _falResult!.district,
              'region': _falResult!.region,
              'license_type': _falResult!.licenseType,
              'license_no': _falResult!.licenseNo ?? licenseNo,
              'license_status_text': _falResult!.licenseStatusText,
              'end_date': _falResult!.endDateIso,
              'source': _falResult!.source,
            }
          : null;

      final extra = <String, dynamic>{
        if (regaMap != null) 'rega_fal': regaMap,
        if (isOrg && _commercialSnapshot != null)
          'commercial_reg': _commercialSnapshot,
        if (_partOfTeam)
          'team_join_code': _teamJoinCode.text.replaceAll(RegExp(r'\D'), ''),
        'broker_submitted': {
          'broker_name': _brokerName.text.trim(),
          'email': _brokerEmail.text.trim(),
          'mobile': _brokerPhone.text.trim(),
          'city': _city.text.trim(),
          'district': _district.text.trim(),
          'region': _region.text.trim(),
          'license_type': _licenseType.text.trim(),
          'license_status': _licenseStatus.text.trim(),
        },
      };

      final snap = <String, dynamic>{
        if (regaMap != null) ...Map<String, dynamic>.from(regaMap),
        'broker_submitted': extra['broker_submitted'],
      };

      String? falExpIso;
      if (needsFal && _falResult?.endDateIso != null) {
        final d = DateTime.tryParse(_falResult!.endDateIso!);
        if (d != null) falExpIso = d.toUtc().toIso8601String();
      }

      final unifiedDigits = _unifiedCr.text.replaceAll(RegExp(r'\D'), '');

      final reqId = await VerificationService.createVerificationRequest(
        requestedAccountType: requestedType,
        officeName: isOrg ? _officeName.text.trim() : null,
        licenseNo: licenseNo.isEmpty ? null : licenseNo,
        commercialRegNo: isOrg ? _crNo.text.trim() : null,
        docPath1: _doc1,
        docPath2: _doc2,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        extraPayload: extra,
        contactEmail:
            _brokerEmail.text.trim().isEmpty ? null : _brokerEmail.text.trim(),
        contactPhone:
            _brokerPhone.text.trim().isEmpty ? null : _brokerPhone.text.trim(),
        regaFalSnapshot: needsFal ? snap : null,
        falLicenseExpiresAtIso: falExpIso,
        unifiedCommercialRegNo:
            isOrg && unifiedDigits.length == 10 ? unifiedDigits : null,
        commercialRegSnapshot: isOrg ? _commercialSnapshot : null,
      );

      if (_partOfTeam) {
        final code = _teamJoinCode.text.replaceAll(RegExp(r'\D'), '');
        final jr = await _orgSvc.submitJoinRequest(
          recruitCode: code,
          verificationRequestId: reqId,
        );
        if (jr['ok'] != true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'تم إرسال طلب التوثيق، لكن طلب الانضمام للفريق: ${jr['error'] ?? 'تعذر التسجيل'}',
              ),
            ),
          );
        }
      }

      if (!mounted) return;
      unawaited(PostAuthNavigation.openDashboard(context));
    } catch (e) {
      setState(() {
        _err = '$e';
        _busy = false;
      });
    }
  }
}
