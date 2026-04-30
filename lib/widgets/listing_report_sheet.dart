import 'package:aqar_user/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/notifications/in_app_notification_catalog.dart';
import '../core/notifications/in_app_notification_writer.dart';
import '../models/market_property_request_row.dart';
import '../models/property.dart';
import '../services/user_listing_preferences_service.dart';
import 'app_confirm_dialog.dart';

/// بلاغ مفتوح سابق لنفس المستخدم على نفس العقار (فهرس فريد في الخادم).
class DuplicateOpenListingReportException implements Exception {}

Map<String, String> _bilingualMarketerListingNotif(bool suppressed) {
  final ar = lookupAppLocalizations(const Locale('ar'));
  final en = lookupAppLocalizations(const Locale('en'));
  if (suppressed) {
    return {
      'title_ar': ar.inAppNotifListingReportEscalatedTitle,
      'title_en': en.inAppNotifListingReportEscalatedTitle,
      'body_ar': ar.inAppNotifListingReportEscalatedBody,
      'body_en': en.inAppNotifListingReportEscalatedBody,
    };
  }
  return {
    'title_ar': ar.inAppNotifListingReportTitle,
    'title_en': en.inAppNotifListingReportTitle,
    'body_ar': ar.inAppNotifListingReportBody,
    'body_en': en.inAppNotifListingReportBody,
  };
}

Map<String, String> _bilingualOwnerEscalatedNotif() {
  final ar = lookupAppLocalizations(const Locale('ar'));
  final en = lookupAppLocalizations(const Locale('en'));
  return {
    'title_ar': ar.inAppNotifListingReportOwnerEscalatedTitle,
    'title_en': en.inAppNotifListingReportOwnerEscalatedTitle,
    'body_ar': ar.inAppNotifListingReportOwnerEscalatedBody,
    'body_en': en.inAppNotifListingReportOwnerEscalatedBody,
  };
}

/// أسباب بلاغ — المفاتيح ثابتة للخادم؛ العناوين من [AppLocalizations].
class ListingReportReasons {
  static const String misleadingInfo = 'misleading_info';
  static const String duplicateSpam = 'duplicate_spam';
  static const String wrongPriceTerms = 'wrong_price_terms';
  static const String impersonation = 'impersonation';
  static const String licenseMismatch = 'license_mismatch';
  static const String harassment = 'harassment';
  static const String other = 'other';

  static const List<String> orderedKeys = <String>[
    misleadingInfo,
    duplicateSpam,
    wrongPriceTerms,
    impersonation,
    licenseMismatch,
    harassment,
    other,
  ];

  static String label(AppLocalizations l10n, String key) {
    switch (key) {
      case misleadingInfo:
        return l10n.listingReportReasonMisleading;
      case duplicateSpam:
        return l10n.listingReportReasonDuplicateSpam;
      case wrongPriceTerms:
        return l10n.listingReportReasonWrongPrice;
      case impersonation:
        return l10n.listingReportReasonImpersonation;
      case licenseMismatch:
        return l10n.listingReportReasonLicenseMismatch;
      case harassment:
        return l10n.listingReportReasonHarassment;
      case other:
        return l10n.listingReportReasonOther;
      default:
        return key;
    }
  }
}

Future<void> showPropertyListingReportSheet(
  BuildContext context, {
  required SupabaseClient sb,
  required Property property,
  VoidCallback? onDone,
}) async {
  final l10n = AppLocalizations.of(context);
  if (l10n == null) return;

  final gate = await UserListingPreferencesService.evaluateListingReportGate(l10n);
  if (!context.mounted) return;
  if (!gate.allow) {
    final msg = gate.blockMessage ?? l10n.listingReportCannotSubmitGeneric;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    return;
  }
  if (gate.sternWarning != null) {
    final ok = await showAppConfirmDialog(
      context: context,
      title: l10n.listingReportImportantNoticeTitle,
      message: gate.sternWarning!,
      confirmLabel: l10n.listingReportContinueToReport,
      cancelLabel: l10n.listingReportDialogCancel,
      isDanger: true,
    );
    if (!ok || !context.mounted) return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _ReportFormSheet(
      l10n: l10n,
      title: l10n.listingReportPropertySheetTitle,
      subtitle: l10n.listingReportPropertySheetSubtitle,
      onSubmit: (keys, note) async {
        final reporter = sb.auth.currentUser?.id ?? '';
        final marketer = (property.publishedByMarketerId ?? '').trim();
        final owner = property.ownerId.trim();
        final target = marketer.isNotEmpty ? marketer : owner;

        Map<String, dynamic>? inserted;
        try {
          inserted = await sb
              .from('listing_user_reports')
              .insert({
                'property_id': property.id,
                'reporter_user_id': reporter.isEmpty ? null : reporter,
                'reason_keys': keys,
                'note': note.trim().isEmpty ? null : note.trim(),
                'status': 'pending',
                'created_at': DateTime.now().toUtc().toIso8601String(),
              })
              .select('id')
              .maybeSingle();
        } on PostgrestException catch (e) {
          if (e.code == '23505') {
            throw DuplicateOpenListingReportException();
          }
          rethrow;
        }

        final rid = (inserted?['id'] ?? '').toString().trim();
        if (rid.isNotEmpty) {
          await UserListingPreferencesService.setPendingPropertyReportRow(
            property.id,
            rid,
          );
        }
        await UserListingPreferencesService.recordPropertyReportSubmitted(
          property.id,
        );

        Map<String, dynamic>? mod;
        try {
          mod = await sb
              .from('properties')
              .select('home_feed_suppressed,report_distinct_reporters_7d')
              .eq('id', property.id)
              .maybeSingle();
        } catch (_) {}

        final suppressed = mod?['home_feed_suppressed'] == true;
        final distinct =
            (mod?['report_distinct_reporters_7d'] as num?)?.toInt() ?? 0;

        if (target.isNotEmpty && target != reporter) {
          final notifType = suppressed
              ? InAppNotifTypes.listingReportEscalated
              : InAppNotifTypes.listingReported;
          final copy = _bilingualMarketerListingNotif(suppressed);
          await InAppNotificationWriter.insert(
            sb,
            userId: target,
            type: notifType,
            entityType: InAppEntityTypes.property,
            entityId: property.id,
            data: {
              ...copy,
              'property_id': property.id,
              'reporter_user_id': reporter,
              'reason_keys': keys,
              'distinct_reporters_7d': distinct,
              if (note.trim().isNotEmpty) 'reporter_note': note.trim(),
              'deep_route': InAppDeepRoutes.inAppNotifications,
            },
          );
        }

        if (suppressed &&
            owner.isNotEmpty &&
            owner != reporter &&
            owner != target &&
            marketer.isNotEmpty) {
          final copy = _bilingualOwnerEscalatedNotif();
          await InAppNotificationWriter.insert(
            sb,
            userId: owner,
            type: InAppNotifTypes.listingReportEscalated,
            entityType: InAppEntityTypes.property,
            entityId: property.id,
            data: {
              ...copy,
              'property_id': property.id,
              'distinct_reporters_7d': distinct,
              'deep_route': InAppDeepRoutes.inAppNotifications,
            },
          );
        }

        await UserListingPreferencesService.addHiddenProperty(property.id);
      },
      onDone: onDone,
    ),
  );
}

Future<void> showMarketRequestReportSheet(
  BuildContext context, {
  required SupabaseClient sb,
  required MarketPropertyRequestRow request,
  VoidCallback? onDone,
}) async {
  final l10n = AppLocalizations.of(context);
  if (l10n == null) return;

  final gate = await UserListingPreferencesService.evaluateListingReportGate(l10n);
  if (!context.mounted) return;
  if (!gate.allow) {
    final msg = gate.blockMessage ?? l10n.listingReportCannotSubmitGeneric;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    return;
  }
  if (gate.sternWarning != null) {
    final ok = await showAppConfirmDialog(
      context: context,
      title: l10n.listingReportImportantNoticeTitle,
      message: gate.sternWarning!,
      confirmLabel: l10n.listingReportContinueToReport,
      cancelLabel: l10n.listingReportDialogCancel,
      isDanger: true,
    );
    if (!ok || !context.mounted) return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _ReportFormSheet(
      l10n: l10n,
      title: l10n.listingReportRequestSheetTitle,
      subtitle: l10n.listingReportRequestSheetSubtitle,
      onSubmit: (keys, note) async {
        await UserListingPreferencesService.addHiddenMarketRequest(request.id);
        try {
          await sb.from('market_request_user_reports').insert({
            'request_id': request.id,
            'reporter_user_id': sb.auth.currentUser?.id,
            'reason_keys': keys,
            'note': note.trim().isEmpty ? null : note.trim(),
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });
          await UserListingPreferencesService.recordMarketRequestReportSubmitted(
            request.id,
          );
        } catch (_) {}
      },
      onDone: onDone,
    ),
  );
}

class _ReportFormSheet extends StatefulWidget {
  const _ReportFormSheet({
    required this.l10n,
    required this.title,
    required this.subtitle,
    required this.onSubmit,
    this.onDone,
  });

  final AppLocalizations l10n;
  final String title;
  final String subtitle;
  final Future<void> Function(List<String> keys, String note) onSubmit;
  final VoidCallback? onDone;

  @override
  State<_ReportFormSheet> createState() => _ReportFormSheetState();
}

class _ReportFormSheetState extends State<_ReportFormSheet> {
  final _note = TextEditingController();
  final _selected = <String>{};
  bool _busy = false;

  AppLocalizations get _l => widget.l10n;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_l.listingReportPickAtLeastOneReason)),
      );
      return;
    }
    if (_selected.contains(ListingReportReasons.other) &&
        _note.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_l.listingReportOtherDetailsRequired)),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onSubmit(_selected.toList(), _note.text);
      if (mounted) Navigator.of(context).pop();
      widget.onDone?.call();
    } on DuplicateOpenListingReportException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_l.listingReportDuplicateOpen)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: mq.viewInsets.bottom + mq.padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            widget.subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: mq.size.height * 0.45),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final key in ListingReportReasons.orderedKeys)
                    CheckboxListTile(
                      value: _selected.contains(key),
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selected.add(key);
                          } else {
                            _selected.remove(key);
                          }
                        });
                      },
                      title: Text(
                        ListingReportReasons.label(_l, key),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                  if (_selected.contains(ListingReportReasons.other)) ...[
                    const SizedBox(height: 6),
                    TextField(
                      controller: _note,
                      minLines: 2,
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: _l.listingReportDetailsLabel,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _busy ? null : _send,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_l.listingReportSubmit),
          ),
        ],
      ),
    );
  }
}
