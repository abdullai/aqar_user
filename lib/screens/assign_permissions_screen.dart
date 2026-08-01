import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../main.dart' show langNotifier;
import '../services/compliance_audit_service.dart';
import '../services/org_permission_manager.dart';
import '../services/org_team_service.dart';

/// تعديل صلاحيات عضو (المالك).
class AssignPermissionsScreen extends StatefulWidget {
  const AssignPermissionsScreen({
    super.key,
    required this.memberUserId,
    required this.initial,
  });

  final String memberUserId;
  final Map<String, dynamic> initial;

  @override
  State<AssignPermissionsScreen> createState() =>
      _AssignPermissionsScreenState();
}

class _AssignPermissionsScreenState extends State<AssignPermissionsScreen> {
  final _svc = OrgTeamService(Supabase.instance.client);
  late Map<String, bool> _p;
  bool _busy = false;

  bool get _isAr => langNotifier.value != 'en';

  @override
  void initState() {
    super.initState();
    bool g(String k) {
      final v = widget.initial[k];
      return v == true || v == 'true' || v == 1 || v == '1';
    }

    _p = {
      for (final k in OrgPermissionKeys.allPermissionKeys) k: g(k),
    };
  }

  void _applyDeskFlags(Map<String, dynamic> m) {
    bool on(String k) => _p[k] == true;
    final desk = on(OrgPermissionKeys.manageTeam) ||
        on(OrgPermissionKeys.viewAnalytics) ||
        on(OrgPermissionKeys.viewReports) ||
        on(OrgPermissionKeys.addProperties) ||
        on(OrgPermissionKeys.addAds) ||
        on(OrgPermissionKeys.viewMemberActivity) ||
        on(OrgPermissionKeys.editOrgSettings) ||
        on(OrgPermissionKeys.inviteMembers) ||
        on(OrgPermissionKeys.manageChatRooms) ||
        on(OrgPermissionKeys.manageSubscription) ||
        on(OrgPermissionKeys.exportData);
    final middle = on(OrgPermissionKeys.addProperties) ||
        on(OrgPermissionKeys.addAds) ||
        on(OrgPermissionKeys.addListingRequests) ||
        on(OrgPermissionKeys.viewMarket) ||
        on(OrgPermissionKeys.editProperties);
    m['desk'] = desk;
    m['middle_nav'] = middle;
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final m = <String, dynamic>{};
      _p.forEach((k, v) => m[k] = v);
      if (_p[OrgPermissionKeys.viewProfile] == true ||
          _p[OrgPermissionKeys.accessChat] == true) {
        _applyDeskFlags(m);
      } else {
        m['desk'] = false;
        m['middle_nav'] = false;
      }
      await _svc.updateMemberPermissions(
        memberUserId: widget.memberUserId,
        permissions: m,
      );
      unawaited(
        ComplianceAuditService.instance.log('permissions.changed', {
          'target_user_id': widget.memberUserId,
        }),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isAr ? 'تم الحفظ' : 'Saved')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showHelp(String body) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(body, textAlign: TextAlign.start),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_isAr ? 'حسناً' : 'OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    Widget permTile(String key, String title, String helpBody) {
      return SwitchListTile(
        value: _p[key] ?? false,
        onChanged: _busy
            ? null
            : (v) {
                setState(() => _p[key] = v);
              },
        title: Text(title),
        secondary: IconButton(
          icon: const Icon(Icons.info_outline),
          onPressed: _busy ? null : () => _showHelp(helpBody),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(t.orgAssignPermissionsTitle)),
      body: ListView(
        children: [
          permTile(
            OrgPermissionKeys.manageTeam,
            t.permManageTeam,
            t.permManageTeamHelp,
          ),
          permTile(
            OrgPermissionKeys.addProperties,
            t.permAddProperties,
            t.permAddPropertiesHelp,
          ),
          permTile(
            OrgPermissionKeys.addListingRequests,
            t.permAddListingRequests,
            t.permAddListingRequestsHelp,
          ),
          permTile(
            OrgPermissionKeys.editProperties,
            t.permEditProperties,
            t.permEditPropertiesHelp,
          ),
          permTile(
            OrgPermissionKeys.addAds,
            t.permAddAds,
            t.permAddAdsHelp,
          ),
          permTile(
            OrgPermissionKeys.viewMarket,
            t.permViewMarket,
            t.permViewMarketHelp,
          ),
          permTile(
            OrgPermissionKeys.viewProfile,
            t.permViewProfile,
            t.permViewProfileHelp,
          ),
          permTile(
            OrgPermissionKeys.accessChat,
            t.permAccessChat,
            t.permAccessChatHelp,
          ),
          permTile(
            OrgPermissionKeys.viewAnalytics,
            t.permViewAnalytics,
            t.permViewAnalyticsHelp,
          ),
          permTile(
            OrgPermissionKeys.viewReports,
            _isAr ? 'التقارير المتقدمة' : 'Advanced reports',
            _isAr
                ? 'عرض لوحة التقارير والتصدير (إضافة إلى الإحصائيات).'
                : 'Access reports dashboard and exports (in addition to analytics).',
          ),
          permTile(
            OrgPermissionKeys.editOrgSettings,
            t.permEditOrgSettings,
            t.permEditOrgSettingsHelp,
          ),
          permTile(
            OrgPermissionKeys.manageSubscription,
            t.permManageSubscription,
            t.permManageSubscriptionHelp,
          ),
          permTile(
            OrgPermissionKeys.exportData,
            t.permExportData,
            t.permExportDataHelp,
          ),
          permTile(
            OrgPermissionKeys.inviteMembers,
            t.permInviteMembers,
            t.permInviteMembersHelp,
          ),
          permTile(
            OrgPermissionKeys.manageChatRooms,
            t.permManageChatRooms,
            t.permManageChatRoomsHelp,
          ),
          permTile(
            OrgPermissionKeys.viewMemberActivity,
            t.permViewMemberActivity,
            t.permViewMemberActivityHelp,
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_isAr ? 'حفظ' : 'Save'),
            ),
          ),
        ],
      ),
    );
  }
}
