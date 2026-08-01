import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/account_type_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/field_group_frame.dart';
import '../core/navigation/post_auth_navigation.dart';
import 'browse_organizations_screen.dart';

class AccountTypeSetupScreen extends StatefulWidget {
  const AccountTypeSetupScreen({super.key});

  @override
  State<AccountTypeSetupScreen> createState() => _AccountTypeSetupScreenState();
}

class _AccountTypeSetupScreenState extends State<AccountTypeSetupScreen> {
  bool _busy = true;
  String? _accountType;
  String? _verStatus;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final p = await AccountTypeService.myProfile();
      setState(() {
        _accountType = (p?['account_type'] as String?) ?? 'individual_seller';
        _verStatus = (p?['verification_status'] as String?) ?? 'none';
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _err = '$e';
        _busy = false;
      });
    }
  }

  Future<void> _setSimple(String type) async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await AccountTypeService.setAccountType(
        accountType: type,
        verificationStatus: 'none',
      );
      if (!mounted) return;
      setState(() {
        _accountType = type;
        _verStatus = 'none';
        _busy = false;
      });
      unawaited(PostAuthNavigation.openDashboard(context));
    } catch (e) {
      setState(() {
        _err = '$e';
        _busy = false;
      });
    }
  }

  void _goVerify(String type) {
    Navigator.pushNamed(context, '/verificationRequest', arguments: type);
  }

  /// تصفّح المنشآت للانضمام كعضو فريق — لا يحتاج توثيق فردي مستقل،
  /// لأن المنشأة الأم هي صاحبة الرخصة (الموافقة بيد المدير).
  void _openBrowseOrganizations() {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            BrowseOrganizationsScreen(lang: WidgetsBinding.instance
                        .platformDispatcher.locale.languageCode
                        .startsWith('ar')
                ? 'ar'
                : 'en'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('نوع الحساب'),
      ),
      body: _busy
          ? const Center(child: AppLogoLoading())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (uid == null)
                    const Text('لا توجد جلسة دخول.')
                  else ...[
                    if (_err != null)
                      Container(
                        width: double.infinity,
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
                            fontWeight: FontWeight.w700,
                            color: cs.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),

                    _statusCard(),
                    const SizedBox(height: 14),

                    Expanded(
                      child: FieldGroupFrame(
                        title: 'اختر نوع الحساب',
                        subtitle: 'يمكنك تغيير مسار التوثيق لاحقاً من الإعدادات إن توفرت',
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                        child: ListView(
                          children: [
                            // 1) فرد / مالك — لنشر عقار شخصي.
                            _tile(
                              title: 'فرد / مالك',
                              subtitle: 'لنشر عقارك الشخصي — الاسم الرباعي والجوال والبريد',
                              icon: Icons.home_outlined,
                              onTap: () => _setSimple('individual_seller'),
                            ),
                            // 2) عضو ضمن فريق — للانضمام إلى منشأة قائمة (مكتب/مؤسسة/شركة).
                            _tile(
                              title: 'عضو ضمن فريق',
                              subtitle: 'انضم إلى منشأة قائمة بإذن من المدير',
                              icon: Icons.group_outlined,
                              onTap: _openBrowseOrganizations,
                            ),
                            // 3) مسوّق عقاري فردي (يتطلب رخصة فال).
                            _tile(
                              title: 'مسوّق عقاري (يتطلب توثيق)',
                              subtitle: 'رخصة فال + هوية وطنية + توثيق الهيئة',
                              icon: Icons.verified_outlined,
                              onTap: () => _goVerify('marketer'),
                            ),
                            // 4) مكتب عقاري (يتطلب فال + سجل تجاري).
                            _tile(
                              title: 'مكتب عقاري (يتطلب توثيق)',
                              subtitle: 'رخصة فال + الرقم الموحّد للسجل التجاري',
                              icon: Icons.storefront_outlined,
                              onTap: () => _goVerify('office'),
                            ),
                            // 5) مؤسسة عقارية (يتطلب فال + سجل تجاري).
                            _tile(
                              title: 'مؤسسة عقارية (يتطلب توثيق)',
                              subtitle: 'رخصة فال + الرقم الموحّد للسجل التجاري',
                              icon: Icons.apartment_outlined,
                              onTap: () => _goVerify('institution'),
                            ),
                            // 6) شركة عقارية (يتطلب فال + سجل تجاري).
                            _tile(
                              title: 'شركة عقارية (يتطلب توثيق)',
                              subtitle: 'رخصة فال + الرقم الموحّد للسجل التجاري',
                              icon: Icons.corporate_fare_outlined,
                              onTap: () => _goVerify('company'),
                            ),
                            const SizedBox(height: 8),
                            // الخيار الأقل بروزاً — تصفّح فقط للمستخدم العادي.
                            _tile(
                              title: 'مستخدم (تصفح فقط)',
                              subtitle: 'لا يمكن نشر إعلان — للتصفح فقط',
                              icon: Icons.person_outline,
                              onTap: () => _setSimple('user'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _statusCard() {
    return Builder(
      builder: (context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: FieldGroupTheme.boxDecoration(context),
        child: Row(
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'الحالي: ${_accountType ?? '-'}\nالتوثيق: ${_verStatus ?? '-'}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(subtitle),
        onTap: _busy ? null : onTap,
      ),
    );
  }
}