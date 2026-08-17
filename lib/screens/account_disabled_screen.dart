import 'package:flutter/material.dart';

import '../core/auth/safe_sign_out_service.dart';
import '../main.dart' show langNotifier;
import '../widgets/ban_status_widget.dart';
import 'join_new_organization_screen.dart';

/// تظهر عند تفعيل `blocks_app` في سجل حظر المنصّة.
class AccountDisabledScreen extends StatelessWidget {
  const AccountDisabledScreen({super.key, required this.ban});

  final Map<String, dynamic> ban;

  bool get _isAr => langNotifier.value != 'en';

  Future<void> _signOut(BuildContext context) async {
    await SafeSignOutService.signOutAndNavigateToLogin(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canJoin = ban['can_join_other_orgs'] == true;

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: BanStatusWidget(
                  ban: ban,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _isAr ? 'تم تعطيل حسابك' : 'Your account is disabled',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: cs.error,
                            ),
                      ),
                      const SizedBox(height: 20),
                      if (canJoin)
                        FilledButton.tonalIcon(
                          onPressed: () {
                            Navigator.push<void>(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => JoinNewOrganizationScreen(
                                  fromBannedFlow: true,
                                  lang: _isAr ? 'ar' : 'en',
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.business_outlined),
                          label: Text(
                            _isAr
                                ? 'طلب الانضمام لإدارة أخرى'
                                : 'Request to join another organization',
                          ),
                        ),
                      if (canJoin) const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => _signOut(context),
                        icon: const Icon(Icons.logout),
                        label: Text(_isAr ? 'تسجيل الخروج' : 'Sign out'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
