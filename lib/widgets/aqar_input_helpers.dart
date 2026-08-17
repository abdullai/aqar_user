import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/input/locale_text_input_guard.dart';

/// دمج [InputDecoration] مع ثيم التطبيق — حدود موحّدة دون تضارب ألوان.
InputDecoration aqarMergeInputDecoration(
  BuildContext context,
  InputDecoration? decoration,
) {
  final themed = (decoration ?? const InputDecoration())
      .applyDefaults(Theme.of(context).inputDecorationTheme);
  return themed.copyWith(
    enabledBorder: Theme.of(context).inputDecorationTheme.enabledBorder,
    focusedBorder: Theme.of(context).inputDecorationTheme.focusedBorder,
    errorBorder: Theme.of(context).inputDecorationTheme.errorBorder,
    focusedErrorBorder: Theme.of(context).inputDecorationTheme.focusedErrorBorder,
    disabledBorder: Theme.of(context).inputDecorationTheme.disabledBorder,
  );
}

List<TextInputFormatter> aqarLocaleInputFormatters(
  BuildContext context, {
  AqarLocaleScript? localeScript,
  List<TextInputFormatter>? existing,
}) {
  final script = localeScript ?? AqarLocaleScript.any;
  if (script == AqarLocaleScript.any) return existing ?? const [];
  final isAr = Localizations.localeOf(context).languageCode != 'en';
  return mergeLocaleFormatters(
    script: script,
    existing: existing,
    onRejected: () {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.clearSnackBars();
      messenger?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            localeInputRejectionMessage(isAr: isAr, script: script),
          ),
        ),
      );
    },
  );
}
