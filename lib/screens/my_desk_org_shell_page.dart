import 'package:flutter/material.dart';

import 'my_organization_screen.dart';

/// توافق خلفي مع المسارات القديمة — يفضّل استخدام [MyOrganizationScreen].
class MyDeskOrgShellPage extends StatelessWidget {
  const MyDeskOrgShellPage({super.key, required this.lang});

  final String lang;

  @override
  Widget build(BuildContext context) => MyOrganizationScreen(lang: lang);
}
