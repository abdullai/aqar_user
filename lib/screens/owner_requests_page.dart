// lib/screens/owner_requests_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../routes.dart';
import '../services/marketing_flow_service.dart';
import '../widgets/app_logo_loading.dart';

class OwnerRequestsPage extends StatefulWidget {
  final String lang;
  const OwnerRequestsPage({super.key, required this.lang});

  @override
  State<OwnerRequestsPage> createState() => _OwnerRequestsPageState();
}

class _OwnerRequestsPageState extends State<OwnerRequestsPage> {
  final _svc = MarketingFlowService(Supabase.instance.client);

  bool _loading = true;
  String? _err;
  List<Map<String, dynamic>> _items = const [];

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final rows = await _svc.ownerMyRequests();
      setState(() => _items = rows);
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isAr ? 'طلباتي' : 'My Requests'),
          actions: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () => Navigator.pushNamed(context, AppRoutes.inAppNotifications),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: AppLogoLoading())
            : _err != null
                ? Center(child: Text(_err!))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final r = _items[i];
                        final id = (r['id'] ?? '').toString();
                        final title = (r['title'] ?? (_isAr ? 'طلب' : 'Request')).toString();
                        final status = (r['status'] ?? '').toString();

                        return ListTile(
                          title: Text(title),
                          subtitle: Text((_isAr ? 'الحالة: ' : 'Status: ') + status),
                          onTap: () {
                            Navigator.pushNamed(
                              context,
                              AppRoutes.listingRequestStatus,
                              arguments: {'requestId': id, 'lang': widget.lang},
                            );
                          },
                          trailing: IconButton(
                            icon: const Icon(Icons.local_offer_outlined),
                            onPressed: () {
                              Navigator.pushNamed(
                                context,
                                AppRoutes.ownerOffers,
                                arguments: {'requestId': id, 'lang': widget.lang},
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.pushNamed(context, AppRoutes.createListingRequest, arguments: {'lang': widget.lang}),
          label: Text(_isAr ? 'إنشاء طلب' : 'New Request'),
          icon: const Icon(Icons.add),
        ),
      ),
    );
  }
}