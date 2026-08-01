import 'package:flutter/material.dart';

import '../models/property.dart';
import 'listing_formatted_spec_panel.dart';

/// ورقة سفلية تعرض [ListingFormattedSpecPanel] مع عنوان وإغلاق.
class ListingPublicSpecSheet extends StatelessWidget {
  const ListingPublicSpecSheet({
    super.key,
    required this.property,
    required this.isAr,
  });

  final Property property;
  final bool isAr;

  static Future<void> show({
    required BuildContext context,
    required Property property,
    required bool isAr,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        return Directionality(
          textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.86,
            minChildSize: 0.45,
            maxChildSize: 0.96,
            builder: (_, __) {
              return ListingPublicSpecSheet(
                property: property,
                isAr: isAr,
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        16 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isAr ? 'البيانات التنظيمية للإعلان' : 'Structured listing data',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: ListingFormattedSpecPanel(
                property: property,
                isAr: isAr,
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context),
            child: Text(isAr ? 'إغلاق' : 'Close'),
          ),
        ],
      ),
    );
  }
}
