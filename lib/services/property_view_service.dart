import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/app_shimmer.dart';

/// تسجيل ومشاهدة إحصائيات المشاهدات — يتطلب تنفيذ
/// `supabase/sql/20260336_property_listing_views.sql`.
abstract final class PropertyViewService {
  static final Map<String, DateTime> _lastRecorded = {};

  static Future<void> recordView(SupabaseClient sb, String propertyId) async {
    final id = propertyId.trim();
    if (id.isEmpty) return;
    final uid = sb.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return;

    final now = DateTime.now();
    final prev = _lastRecorded[id];
    if (prev != null && now.difference(prev) < const Duration(seconds: 40)) {
      return;
    }
    _lastRecorded[id] = now;

    try {
      await sb.rpc('record_property_listing_view', params: {'p_property_id': id});
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> fetchAggregates(
    SupabaseClient sb,
    String propertyId,
  ) async {
    final id = propertyId.trim();
    if (id.isEmpty) return [];

    try {
      final raw = await sb.rpc(
        'property_listing_view_aggregates',
        params: {'p_property_id': id},
      );
      if (raw is List) {
        return raw
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false);
      }
    } catch (_) {}
    return [];
  }

  /// للمالك أو المسوّق المنشّر: قائمة المشاهدين. لغيرهم: عدد فقط.
  static Future<void> showSheet({
    required BuildContext context,
    required SupabaseClient sb,
    required String propertyId,
    required int viewsCount,
    required bool isOwner,
    required bool isAr,
    bool isPublishingMarketer = false,
  }) async {
    if (!isOwner && !isPublishingMarketer) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAr
                ? 'عدد المشاهدات: $viewsCount'
                : 'Views: $viewsCount',
          ),
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return _OwnerViewersSheet(
          sb: sb,
          propertyId: propertyId,
          viewsCount: viewsCount,
          isAr: isAr,
        );
      },
    );
  }
}

class _OwnerViewersSheet extends StatefulWidget {
  final SupabaseClient sb;
  final String propertyId;
  final int viewsCount;
  final bool isAr;

  const _OwnerViewersSheet({
    required this.sb,
    required this.propertyId,
    required this.viewsCount,
    required this.isAr,
  });

  @override
  State<_OwnerViewersSheet> createState() => _OwnerViewersSheetState();
}

class _OwnerViewersSheetState extends State<_OwnerViewersSheet> {
  bool _loading = true;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await PropertyViewService.fetchAggregates(
      widget.sb,
      widget.propertyId,
    );
    if (!mounted) return;
    setState(() {
      _rows = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat.yMMMd().add_Hm();
    final t = widget.isAr;

    final maxH = MediaQuery.sizeOf(context).height * 0.55;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t ? 'مشاهدات إعلانك' : 'Listing views',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 6),
          Text(
            t
                ? 'إجمالي العداد على الإعلان: ${widget.viewsCount}'
                : 'Counter on listing: ${widget.viewsCount}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20, horizontal: 8),
              child: PropertyCardSkeleton(),
            )
          else if (_rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                t
                    ? 'لا توجد تفاصيل مشاهدات مسجّلة بعد (نفّذ SQL التتبع في Supabase).'
                    : 'No per-viewer data yet (run the SQL migration).',
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxH),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = _rows[i];
                  final name = (r['viewer_label'] ?? '—').toString();
                  final cnt = (r['view_count'] as num?)?.toInt() ?? 0;
                  final mkt = r['is_marketer'] == true;
                  final rawAt = r['last_viewed_at'];
                  final at = rawAt != null
                      ? DateTime.tryParse(rawAt.toString())
                      : null;
                  final when = at != null ? df.format(at.toLocal()) : '—';

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      t
                          ? 'آخر مشاهدة: $when • العدد: $cnt${mkt ? ' • مسوّق' : ''}'
                          : 'Last: $when • Count: $cnt${mkt ? ' • Marketer' : ''}',
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
