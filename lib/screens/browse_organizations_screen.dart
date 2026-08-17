import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../services/org_team_service.dart';
import '../widgets/app_logo_loading.dart';
import 'organization_profile_screen.dart';

/// تصفّح المنشآت وإرسال طلب انضمام (بعد تسجيل الدخول).
class BrowseOrganizationsScreen extends StatefulWidget {
  const BrowseOrganizationsScreen({super.key, required this.lang});

  final String lang;

  @override
  State<BrowseOrganizationsScreen> createState() =>
      _BrowseOrganizationsScreenState();
}

class _BrowseOrganizationsScreenState extends State<BrowseOrganizationsScreen> {
  final _svc = OrgTeamService(Supabase.instance.client);
  final _message = TextEditingController();
  bool _loading = true;
  bool _submitting = false;
  List<Map<String, dynamic>> _rows = [];

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final rows = await _svc.browsePublicOrganizations(limit: 60);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  String _name(Map<String, dynamic> r) {
    final ar = (r['display_name_ar'] ?? '').toString().trim();
    final en = (r['display_name_en'] ?? '').toString().trim();
    if (_isAr) return ar.isNotEmpty ? ar : en;
    return en.isNotEmpty ? en : ar;
  }

  Future<void> _submit(String orgId) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isAr ? 'سجّل الدخول أولاً' : 'Sign in first'),
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    final res = await _svc.submitJoinRequestByOrgId(
      orgId: orgId,
      message: _message.text.trim().isEmpty ? null : _message.text.trim(),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (res['ok'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isAr ? 'تم إرسال الطلب' : 'Request sent')),
      );
    } else {
      final err = '${res['error'] ?? ''}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            err.contains('already_pending')
                ? (_isAr ? 'لديك طلب معلّق' : 'You already have a pending request')
                : err.contains('already_member')
                    ? (_isAr ? 'أنت عضو مسبقاً' : 'Already a member')
                    : err.contains('banned')
                        ? (_isAr ? 'لا يمكن التقديم لهذه المنشأة' : 'Cannot apply to this org')
                        : (_isAr ? 'تعذر الإرسال' : 'Could not submit'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.orgBrowseTitle),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: AqarTextField(
              controller: _message,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: t.orgJoinMessageHint,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: AppLogoLoading())
                : RefreshIndicator(
                    onRefresh: _reload,
                    child: _rows.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.sizeOf(context).height * 0.25,
                              ),
                              Center(child: Text(t.orgBrowseEmpty)),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _rows.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final r = _rows[i];
                              final id = '${r['id'] ?? ''}';
                              final name = _name(r);
                              final logo =
                                  (r['logo_url'] ?? '').toString().trim();
                              return Card(
                                child: ListTile(
                                  leading: logo.isNotEmpty
                                      ? ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: CachedNetworkImage(
                                            imageUrl: logo,
                                            width: 48,
                                            height: 48,
                                            fit: BoxFit.cover,
                                          ),
                                        )
                                      : const Icon(Icons.business_outlined),
                                  title: Text(
                                    name.isEmpty ? id : name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    t.orgMembersCount(
                                      int.tryParse('${r['member_count']}') ??
                                          0,
                                    ),
                                  ),
                                  trailing: FilledButton(
                                    onPressed:
                                        _submitting || id.isEmpty ? null : () => _submit(id),
                                    child: Text(t.orgJoinSubmit),
                                  ),
                                  onTap: id.isEmpty
                                      ? null
                                      : () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute<void>(
                                              builder: (_) =>
                                                  OrganizationProfileScreen(
                                                orgId: id,
                                                lang: widget.lang,
                                              ),
                                            ),
                                          );
                                        },
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
