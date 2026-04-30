import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/property.dart';
import '../shared/core/supabase_schema_selects.dart';
import '../widgets/app_logo_loading.dart';
import 'property_details_page.dart';

/// يحمّل عقارًا بالمعرّف ثم يعرض [PropertyDetailsPage] (زائر أو مستخدم مسجّل).
class ListingLoaderPage extends StatefulWidget {
  final String propertyId;
  final String lang;

  const ListingLoaderPage({
    super.key,
    required this.propertyId,
    required this.lang,
  });

  @override
  State<ListingLoaderPage> createState() => _ListingLoaderPageState();
}

class _ListingLoaderPageState extends State<ListingLoaderPage> {
  final _sb = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _go());
  }

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  Future<void> _go() async {
    final id = widget.propertyId.trim();
    if (id.isEmpty) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }

    try {
      final row = await _sb
          .from('properties')
          .select(SupabaseSchemaSelects.propertiesListing)
          .eq('id', id)
          .maybeSingle();

      if (!mounted) return;

      if (row == null) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(_isAr ? 'غير موجود' : 'Not found'),
            content: Text(
              _isAr
                  ? 'تعذر العثور على هذا الإعلان أو لا يمكن عرضه.'
                  : 'This listing could not be found or is not available.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(_isAr ? 'حسنًا' : 'OK'),
              ),
            ],
          ),
        );
        if (mounted) Navigator.of(context).maybePop();
        return;
      }

      final property = Property.fromJson(Map<String, dynamic>.from(row));

      final uid = (_sb.auth.currentUser?.id ?? '').trim();
      final currentUserId = uid.isNotEmpty ? uid : 'guest';

      if (!mounted) return;

      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => PropertyDetailsPage(
            property: property,
            isAr: _isAr,
            currentUserId: currentUserId,
            ownerUsername: null,
            isFavorite: false,
            canManageProperty: false,
            onToggleFavorite: () async {},
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(_isAr ? 'خطأ' : 'Error'),
          content: Text(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(_isAr ? 'حسنًا' : 'OK'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isAr ? 'جاري فتح الإعلان…' : 'Opening listing…'),
        ),
        body: const Center(
          child: AppLogoLoading(size: 88),
        ),
      ),
    );
  }
}
