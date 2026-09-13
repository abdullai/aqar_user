import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/gestures/app_keyboard_popups.dart';
import '../l10n/app_localizations.dart';
import '../services/photographer_service.dart';
import 'aqar_text_field.dart';

Future<void> showDeveloperComingSoonDialog({
  required BuildContext context,
}) async {
  final t = AppLocalizations.of(context)!;
  final name = TextEditingController();
  final email = TextEditingController();
  final type = TextEditingController();
  try {
    final saved = await showAppDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(t.developerComingSoonTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.developerComingSoonBody),
                const SizedBox(height: 12),
                AqarTextField(
                  controller: name,
                  keyboardType: TextInputType.name,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: t.developerInterestName),
                ),
                const SizedBox(height: 8),
                AqarTextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration:
                      InputDecoration(labelText: t.developerInterestEmail),
                ),
                const SizedBox(height: 8),
                AqarTextField(
                  controller: type,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  decoration:
                      InputDecoration(labelText: t.developerInterestType),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t.developerInterestSkip),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t.developerInterestSubmit),
            ),
          ],
        );
      },
    );
    if (saved != true || !context.mounted) return;
    final n = name.text.trim();
    final e = email.text.trim();
    final d = type.text.trim();
    if (n.isEmpty || e.isEmpty) return;
    await PhotographerService(Supabase.instance.client).submitDeveloperInterest(
      fullName: n,
      email: e,
      developmentType: d,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.developerInterestSaved)),
    );
  } finally {
    name.dispose();
    email.dispose();
    type.dispose();
  }
}
