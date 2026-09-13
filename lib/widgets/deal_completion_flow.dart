import 'package:flutter/material.dart';

import '../core/deals/open_accepted_deal.dart';
import '../core/gestures/app_keyboard_popups.dart';
import '../l10n/app_localizations.dart';
import 'aqar_text_field.dart';

enum DealEnterPromptChoice { yesDone, stillOpen }

/// تذكير عند دخول المشروع: هل اكتمل إتمام الصفقة خارج التطبيق؟
Future<DealEnterPromptChoice?> showDealEnterCompletionPrompt({
  required BuildContext context,
  required OpenAcceptedDeal deal,
}) {
  final t = AppLocalizations.of(context)!;
  return showAppDialog<DealEnterPromptChoice>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        icon: Icon(
          Icons.handshake_outlined,
          color: Theme.of(ctx).colorScheme.primary,
        ),
        title: Text(t.dealEnterPromptTitle),
        content: SingleChildScrollView(
          child: Text(
            t.dealEnterPromptBody(deal.title.isEmpty ? '—' : deal.title),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, DealEnterPromptChoice.stillOpen),
            child: Text(t.dealEnterStillOpen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, DealEnterPromptChoice.yesDone),
            child: Text(t.dealEnterYesDone),
          ),
        ],
      );
    },
  );
}

/// تفاصيل مبسّطة قبل إرسال إتمام الصفقة.
Future<String?> showDealCompletionNoteSheet({
  required BuildContext context,
}) {
  final t = AppLocalizations.of(context)!;
  final ctrl = TextEditingController();
  return showAppDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        title: Text(t.dealCompleteNoteTitle),
        content: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.dealCompleteNoteHint),
              const SizedBox(height: 12),
              AqarTextField(
                controller: ctrl,
                minLines: 3,
                maxLines: 6,
                decoration: InputDecoration(
                  hintText: t.dealCompleteNoteFieldHint,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.dealCompleteCancel),
          ),
          FilledButton(
            onPressed: () {
              final note = ctrl.text.trim();
              if (note.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(t.dealCompleteNoteRequired)),
                );
                return;
              }
              Navigator.pop(ctx, note);
            },
            child: Text(t.dealCompleteSend),
          ),
        ],
      );
    },
  ).whenComplete(ctrl.dispose);
}

Future<void> showDealSlotCapDialog({
  required BuildContext context,
  required int used,
  required int max,
}) {
  final t = AppLocalizations.of(context)!;
  return showAppDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(
        Icons.inventory_2_outlined,
        color: Theme.of(ctx).colorScheme.primary,
      ),
      title: Text(t.dealSlotCapTitle),
      content: Text(t.dealSlotCapBody(used, max)),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(t.dealSlotCapOk),
        ),
      ],
    ),
  );
}

Future<void> showInventorySlotCapDialog({
  required BuildContext context,
  required int used,
  required int max,
}) {
  final t = AppLocalizations.of(context)!;
  return showAppDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(
        Icons.layers_outlined,
        color: Theme.of(ctx).colorScheme.primary,
      ),
      title: Text(t.inventorySlotCapTitle),
      content: Text(t.inventorySlotCapBody(used, max)),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(t.dealSlotCapOk),
        ),
      ],
    ),
  );
}
