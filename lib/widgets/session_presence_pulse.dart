import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/session/app_session.dart';
import '../l10n/app_localizations.dart';
import '../services/chat_presence_service.dart';

/// زر في شريط التطبيق: يحدّث نبض «متصل» للدردشة — بدون لوحة عائمة تغطي المحتوى.
class SessionPresenceToolbarButton extends StatefulWidget {
  const SessionPresenceToolbarButton({super.key});

  @override
  State<SessionPresenceToolbarButton> createState() =>
      _SessionPresenceToolbarButtonState();
}

class _SessionPresenceToolbarButtonState extends State<SessionPresenceToolbarButton>
    with WidgetsBindingObserver {
  Timer? _timer;
  final _sb = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ChatPresenceService.ping(_sb));
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 45), (_) {
      unawaited(ChatPresenceService.ping(_sb));
    });
    unawaited(ChatPresenceService.ping(_sb));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppSession>(
      builder: (context, session, _) {
        if (!session.isLoggedIn) return const SizedBox.shrink();
        final t = AppLocalizations.of(context);
        final cs = Theme.of(context).colorScheme;
        return IconButton(
          tooltip:
              t?.globalPresenceOnlineTooltip ?? 'Active while app is open',
          padding: const EdgeInsets.all(10),
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          onPressed: () {},
          icon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.35),
                      blurRadius: 5,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Icon(Icons.chat_bubble_outline, size: 20, color: cs.primary),
            ],
          ),
        );
      },
    );
  }
}
