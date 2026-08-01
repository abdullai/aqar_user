import 'package:flutter/material.dart';

import '../main.dart' show langNotifier;
import 'account_status_screen.dart';
import 'become_independent_screen.dart';
import 'join_new_organization_screen.dart';

/// مركز «تغيير حسابي» من قائمة الخيارات.
class SwitchAccountScreen extends StatelessWidget {
  const SwitchAccountScreen({super.key});

  bool get _isAr => langNotifier.value != 'en';

  @override
  Widget build(BuildContext context) {
    final lang = _isAr ? 'ar' : 'en';
    return Scaffold(
      appBar: AppBar(
        title: Text(_isAr ? 'تغيير حسابي' : 'Switch account'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.group_add_outlined),
            title: Text(_isAr ? 'طلب انضمام لفريق جديد' : 'Join a new team'),
            subtitle: Text(
              _isAr
                  ? 'قد يتطلّب مغادرة الفريق الحالي وفق إعدادات المنصّة.'
                  : 'May require leaving your current team per platform rules.',
            ),
            onTap: () {
              showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(_isAr ? 'تأكيد' : 'Confirm'),
                  content: Text(
                    _isAr
                        ? 'تقديم طلب لإدارة جديدة قد يخرجك من إدارتك الحالية. المتابعة؟'
                        : 'A new join request may end your current org membership. Continue?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(_isAr ? 'إلغاء' : 'Cancel'),
                    ),
                    FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.push<void>(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                JoinNewOrganizationScreen(lang: lang),
                          ),
                        );
                      },
                      child: Text(_isAr ? 'متابعة' : 'Continue'),
                    ),
                  ],
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(_isAr ? 'طلب الاستقلال' : 'Become independent'),
            onTap: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => BecomeIndependentScreen(lang: lang),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: Text(_isAr ? 'تغيير نوع الحساب' : 'Change account type'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _isAr
                        ? 'يتطلّب موافقة إدارة المنصّة — سجّل الطلب أدناه.'
                        : 'Requires platform review — submit the request below.',
                  ),
                ),
              );
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => BecomeIndependentScreen(
                    lang: lang,
                    mode: AccountChangeMode.changeType,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(_isAr ? 'حالة حسابي' : 'Account status'),
            onTap: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => AccountStatusScreen(lang: lang),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
