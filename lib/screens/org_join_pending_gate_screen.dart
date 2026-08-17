import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// يظهر للمستخدم الذي قدّم طلب انضمام لمؤسسة ولم تُعالَج بعد.
class OrgJoinPendingGateScreen extends StatelessWidget {
  const OrgJoinPendingGateScreen({
    super.key,
    required this.lang,
    required this.pending,
    required this.onSignedOut,
    required this.onRecheck,
  });

  final String lang;
  final Map<String, dynamic> pending;
  final Future<void> Function() onSignedOut;
  final Future<void> Function() onRecheck;

  bool get _isAr => lang.toLowerCase() != 'en';

  String _orgKindLabel(AppLocalizations? t) {
    final k = (pending['org_account_type'] ?? '').toString().toLowerCase().trim();
    switch (k) {
      case 'office':
        return t?.orgKindOffice ?? (_isAr ? 'مكتب عقاري' : 'Real estate office');
      case 'institution':
        return t?.orgKindInstitution ?? (_isAr ? 'مؤسسة' : 'Institution');
      case 'company':
        return t?.orgKindCompany ?? (_isAr ? 'شركة عقارية' : 'Real estate company');
      case 'marketer':
        return t?.accountKindMarketer ??
            (_isAr ? 'مسوق عقاري' : 'Real estate marketer');
      default:
        return t?.orgKindGeneric ?? (_isAr ? 'مؤسستك' : 'the organization');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final orgLabel = _orgKindLabel(t);

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                Icon(Icons.groups_outlined, size: 56, color: cs.primary),
                const SizedBox(height: 20),
                Text(
                  t?.orgJoinPendingTitle ??
                      (_isAr ? 'طلب الانضمام قيد المراجعة' : 'Join request pending'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  t != null
                      ? t.orgJoinPendingBody(orgLabel)
                      : (_isAr
                          ? 'لم تُوافَق بعد على طلب انضمامك إلى $orgLabel. بعد موافقة المدير اضغط تحديث الحالة.'
                          : 'Your request to join $orgLabel is still pending. After approval, tap refresh.'),
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    color: cs.onSurface.withValues(alpha: 0.85),
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => unawaited(onRecheck()),
                  icon: const Icon(Icons.refresh),
                  label: Text(
                    t?.orgJoinPendingRecheck ??
                        (_isAr ? 'تحديث الحالة' : 'Refresh status'),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => unawaited(onSignedOut()),
                  child: Text(t?.logoutLabel ?? (_isAr ? 'تسجيل الخروج' : 'Sign out')),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
