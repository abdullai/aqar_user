import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/marketing/marketer_owner_chat_intro_ar.dart';
import '../../core/utils/app_money.dart';
import '../../core/utils/display_ids.dart';
import '../../core/haptics/app_haptics.dart';
import '../../core/workflow/listing_workflow_copy.dart';
import '../../widgets/listing_media_gallery.dart';

/// شاشة كاملة من «السوق العقاري»: معاينة + مقاييس + (اختياري) مراسلة واتساب + تقديم عرض.
class MarketerMarketOfferHubPage extends StatelessWidget {
  const MarketerMarketOfferHubPage({
    super.key,
    required this.isAr,
    required this.heroImageUrls,
    required this.title,
    required this.locationLine,
    required this.ownerDisplayName,
    required this.ownerPhoneRaw,
    required this.listingNoTenDigit,
    required this.priceSar,
    required this.areaM2,
    required this.onSubmitOffer,
    this.onMessageOwner,
    this.hideOwnerContactActions = false,
    this.workflowStageLabel,
    this.requestSubmittedAt,
    this.marketingRound,
    this.onOpenTracking,
  });

  final bool isAr;
  final List<String> heroImageUrls;
  final String title;
  final String locationLine;
  final String ownerDisplayName;
  final String ownerPhoneRaw;
  final String listingNoTenDigit;
  final double priceSar;
  final double areaM2;
  final Future<void> Function()? onMessageOwner;
  final Future<void> Function() onSubmitOffer;

  /// في تبويب «السوق العقاري» (مرحلة جمع العروض): لا مراسلة/واتساب/اتصال.
  final bool hideOwnerContactActions;

  /// مرحلة الطلب الحالية (مثل: بانتظار عروض المسوقين).
  final String? workflowStageLabel;

  /// تاريخ ووقت تقديم الطلب من المالك.
  final String? requestSubmittedAt;

  /// جولة التسويق الحالية (عند إعادة طرح الطلب).
  final int? marketingRound;

  /// فتح تتبّع الطلب من تاريخ التقديم حتى النشر.
  final VoidCallback? onOpenTracking;

  String _draft() => MarketerOwnerChatIntroAr.build(
        isAr: isAr,
        ownerDisplayName: ownerDisplayName,
        listingNoTenDigit: listingNoTenDigit,
        locationLine: locationLine,
      );

  String _waDigits(String raw) {
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('0')) d = d.substring(1);
    if (d.startsWith('966')) return d;
    if (d.length == 9 && d.startsWith('5')) return '966$d';
    if (d.length == 10 && d.startsWith('05')) return '966${d.substring(1)}';
    return d;
  }

  Future<void> _openWhatsApp(BuildContext context) async {
    final digits = _waDigits(ownerPhoneRaw);
    if (digits.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAr ? 'لا يتوفر رقم جوال للمالك.' : 'Owner phone not available.',
          ),
        ),
      );
      return;
    }
    final uri = Uri.parse(
      'https://wa.me/$digits?text=${Uri.encodeComponent(_draft())}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isAr ? 'تعذّر فتح واتساب.' : 'Could not open WhatsApp.'),
        ),
      );
    }
  }

  Future<void> _callOwner(BuildContext context) async {
    final raw = ownerPhoneRaw.trim();
    if (raw.isEmpty) return;
    final uri = Uri.parse('tel:${raw.replaceAll(RegExp(r'[^\d+]'), '')}');
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mq = MediaQuery.sizeOf(context);
    final hidePhoneCall = kIsWeb && mq.width >= 900;

    final areaFmt = AppMoney.formatNumber(
      areaM2,
      isAr: isAr,
      maxFractionDigits: 0,
    );
    final code = listingNoTenDigit.trim().isEmpty
        ? '—'
        : DisplayIds.tenDigit(listingNoTenDigit);
    final ownerName = ownerDisplayName.trim();
    final stageLabel = (workflowStageLabel ?? '').trim();
    final submittedAt = (requestSubmittedAt ?? '').trim();
    final round = marketingRound ?? 0;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(isAr ? 'إتمام الصفقة' : 'Complete deal'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: ListingMediaGallery(
                      imageUrls: heroImageUrls,
                      isAr: isAr,
                      aspectRatio: 16 / 10,
                      maxHeight: 210,
                      borderRadius: 16,
                      initialIndex: 0,
                    ),
                  ),
                  if (stageLabel.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Text(
                        stageLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _metricChip(
                          context,
                          Icons.payments_outlined,
                          isAr ? 'السعر' : 'Price',
                          null,
                          child: priceSar > 0
                              ? AppMoneyLine(
                                  amount: priceSar,
                                  currencyCode: 'SAR',
                                  isAr: isAr,
                                  maxFractionDigits: 0,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                    color: cs.onSurface,
                                  ),
                                )
                              : Text(
                                  '—',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                    color: cs.onSurface,
                                  ),
                                ),
                        ),
                        _metricChip(
                          context,
                          Icons.square_foot_outlined,
                          isAr ? 'المساحة' : 'Area',
                          isAr ? '$areaFmt م²' : '$areaFmt m²',
                        ),
                        _metricChip(
                          context,
                          Icons.location_on_outlined,
                          isAr ? 'الموقع' : 'Location',
                          locationLine.isEmpty ? '—' : locationLine,
                        ),
                        _metricChip(
                          context,
                          Icons.confirmation_number_outlined,
                          isAr ? 'رقم الإعلان' : 'Listing no.',
                          code,
                        ),
                        if (ownerName.isNotEmpty)
                          _metricChip(
                            context,
                            Icons.person_outline,
                            isAr ? 'صاحب الإعلان' : 'Advertiser',
                            ownerName,
                          ),
                        if (submittedAt.isNotEmpty)
                          _metricChip(
                            context,
                            Icons.event_outlined,
                            isAr ? 'تاريخ الطلب' : 'Request date',
                            submittedAt,
                          ),
                        if (round > 1)
                          _metricChip(
                            context,
                            Icons.replay_rounded,
                            isAr ? 'جولة التسويق' : 'Marketing round',
                            ListingWorkflowCopy.marketingRoundLabel(isAr, round),
                          ),
                      ],
                    ),
                  ),
                  if (onOpenTracking != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: OutlinedButton.icon(
                        onPressed: onOpenTracking,
                        icon: const Icon(Icons.timeline_outlined),
                        label: Text(
                          isAr
                              ? 'تتبّع الطلب من التقديم حتى النشر'
                              : 'Track request through publication',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!hideOwnerContactActions && onMessageOwner != null)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              AppHaptics.light();
                              await onMessageOwner!();
                            },
                            icon: const Icon(Icons.forum_outlined),
                            label: Text(
                              isAr ? 'مراسلة المالك' : 'Message owner',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: 'WhatsApp',
                          onPressed: () async {
                            AppHaptics.light();
                            await _openWhatsApp(context);
                          },
                          icon: const Icon(Icons.chat),
                        ),
                        if (!hidePhoneCall) ...[
                          const SizedBox(width: 4),
                          IconButton.filledTonal(
                            tooltip: isAr ? 'اتصال' : 'Call',
                            onPressed: () async {
                              AppHaptics.light();
                              await _callOwner(context);
                            },
                            icon: const Icon(Icons.call_outlined),
                          ),
                        ],
                      ],
                    ),
                  if (!hideOwnerContactActions && onMessageOwner != null)
                    const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () async {
                      AppHaptics.medium();
                      await onSubmitOffer();
                    },
                    icon: const Icon(Icons.edit_note_outlined),
                    label: Text(
                      isAr ? 'إتمام الصفقة' : 'Complete deal',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricChip(
    BuildContext context,
    IconData icon,
    String label,
    String? value, {
    Widget? child,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 160,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 2),
          if (child != null)
            child
          else
            Text(
              value ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                color: cs.onSurface,
              ),
            ),
        ],
      ),
    );
  }
}
