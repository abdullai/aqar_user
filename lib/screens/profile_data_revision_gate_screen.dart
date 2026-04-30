import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/profile/profile_gate_revision.dart';
import '../l10n/app_localizations.dart';
import '../services/org_team_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/field_group_frame.dart';

/// يظهر عندما يطلب إصدار التطبيق مراجعة/تأكيد بيانات أعلى من المخزّن في الملف.
class ProfileDataRevisionGateScreen extends StatefulWidget {
  const ProfileDataRevisionGateScreen({
    super.key,
    required this.lang,
    required this.onDone,
  });

  final String lang;
  final VoidCallback onDone;

  @override
  State<ProfileDataRevisionGateScreen> createState() =>
      _ProfileDataRevisionGateScreenState();
}

class _ProfileDataRevisionGateScreenState
    extends State<ProfileDataRevisionGateScreen> {
  bool _busy = false;
  String? _err;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  Future<void> _ack() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await OrgTeamService(Supabase.instance.client)
          .ackProfileDataRevision(kAppRequiredProfileDataRevision);
      if (!mounted) return;
      widget.onDone();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _err = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t?.profileRevisionGateTitle ?? ''),
        ),
        body: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: FieldGroupFrame(
                    title: t?.profileRevisionGateTitle,
                    subtitle: t?.profileRevisionGateBody,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_err != null) ...[
                          Text(
                            _err!,
                            style: TextStyle(color: cs.error),
                          ),
                          const SizedBox(height: 14),
                        ],
                        FilledButton(
                          onPressed: _busy ? null : _ack,
                          child: _busy
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: AppLogoLoading(
                                      compact: true, size: 22),
                                )
                              : Text(t?.profileRevisionGateConfirm ?? ''),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
