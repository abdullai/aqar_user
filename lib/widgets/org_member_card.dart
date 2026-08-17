import 'package:flutter/material.dart';

/// بطاقة عضو مبسطة لقوائم الإدارة.
class OrgMemberCard extends StatelessWidget {
  const OrgMemberCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: subtitle == null || subtitle!.isEmpty
            ? null
            : Text(subtitle!, maxLines: 3),
        trailing: trailing,
      ),
    );
  }
}
