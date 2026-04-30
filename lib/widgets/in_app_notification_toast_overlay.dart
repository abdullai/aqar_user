import 'dart:async';

import 'package:flutter/material.dart';

import '../services/in_app_notification_hub.dart';
import '../services/in_app_notification_router.dart';

/// يركّب فوق [child] شريط إشعار علوي يختفي تلقائياً أو بالضغط.
class InAppNotificationToastHost extends StatefulWidget {
  final String lang;
  final Widget child;

  const InAppNotificationToastHost({
    super.key,
    required this.lang,
    required this.child,
  });

  @override
  State<InAppNotificationToastHost> createState() =>
      _InAppNotificationToastHostState();
}

class _InAppNotificationToastHostState extends State<InAppNotificationToastHost> {
  Timer? _autoHide;

  @override
  void initState() {
    super.initState();
    InAppNotificationHub.toast.addListener(_onToastChanged);
  }

  @override
  void dispose() {
    InAppNotificationHub.toast.removeListener(_onToastChanged);
    _autoHide?.cancel();
    super.dispose();
  }

  void _onToastChanged() {
    _autoHide?.cancel();
    if (InAppNotificationHub.toast.value != null) {
      _autoHide = Timer(const Duration(seconds: 14), () {
        if (mounted && InAppNotificationHub.toast.value != null) {
          InAppNotificationHub.dismiss();
        }
      });
    }
    if (mounted) setState(() {});
  }

  bool get _isAr => widget.lang != 'en';

  @override
  Widget build(BuildContext context) {
    final payload = InAppNotificationHub.toast.value;

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (payload != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                  child: _InAppToastCard(
                    payload: payload,
                    lang: widget.lang,
                    onOpen: () async {
                      final nav = Navigator.maybeOf(context);
                      if (nav == null) return;
                      final row = Map<String, dynamic>.from(payload.rawRow);
                      InAppNotificationHub.dismiss();
                      await InAppNotificationRouter.open(
                        context,
                        row,
                        lang: widget.lang,
                        markAsRead: true,
                      );
                    },
                    onDismiss: () {
                      InAppNotificationHub.dismiss();
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InAppToastCard extends StatelessWidget {
  final InAppNotificationPayload payload;
  final String lang;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  const _InAppToastCard({
    required this.payload,
    required this.lang,
    required this.onOpen,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ent =
        (payload.rawRow['entity_type'] ?? '').toString();
    final accent =
        InAppNotificationHub.accentForType(payload.type, entityType: ent);
    final icon =
        InAppNotificationHub.iconForType(payload.type, entityType: ent);
    final title = payload.titleForLang(lang);
    final body = payload.bodyForLang(lang);
    final isAr = lang != 'en';

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) < -120) onDismiss();
        },
        child: Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                blurRadius: 18,
                offset: const Offset(0, 6),
                color: Colors.black.withOpacity(0.14),
              ),
            ],
            border: Border.all(color: accent.withOpacity(0.35)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: accent, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        if (body.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            body,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: onOpen,
                              icon: const Icon(Icons.open_in_new_rounded, size: 18),
                              label: Text(isAr ? 'فتح' : 'Open'),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: isAr ? 'إغلاق' : 'Close',
                              onPressed: onDismiss,
                              icon: const Icon(Icons.close_rounded),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
