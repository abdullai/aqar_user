import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/locale_content.dart';
import '../core/utils/date_helper.dart';
import '../core/utils/listing_date_display.dart';
import 'aqar_marquee_text.dart';

/// ألوان نصوص مقروءة — تغميق خفيف يوافق بطاقة الرئيسية.
abstract final class CatalogReadableInk {
  static Color title(ColorScheme cs) => cs.onSurface;

  static Color body(ColorScheme cs) => cs.onSurface;

  static Color muted(ColorScheme cs) => cs.onSurface
      .withValues(alpha: cs.brightness == Brightness.dark ? 0.78 : 0.72);
}

/// جسم بيانات بطاقة الإعلان/الطلب — ترتيب منصّات عقارية (صفوف مضغوطة بلا صناديق مبلغ).
class CatalogEstateCardBody extends StatelessWidget {
  const CatalogEstateCardBody({
    super.key,
    required this.isAr,
    required this.title,
    this.locationParts = const [],
    this.regionText = '',
    this.governorateText = '',
    this.cityText = '',
    this.districtText = '',
    this.areaText = '',
    this.roomsText = '',
    this.publisherCaption = '',
    this.publisherName = '',
    this.publisherLeading,
    this.publisherVerified = false,
    this.publicId,
    this.publicIdLabel,
    this.onCopyPublicId,
    this.amount,
    this.publishedAt,
    this.timeAgo,
    this.dateCaption,
    this.onCopyLocation,
    this.presence,
    this.leadingExtras = const [],
    this.trailingExtras = const [],
  });

  final bool isAr;
  final String title;
  final List<String> locationParts;
  final String regionText;
  final String governorateText;
  final String cityText;
  final String districtText;
  final String areaText;
  final String roomsText;
  final String publisherCaption;
  final String publisherName;
  final Widget? publisherLeading;
  final bool publisherVerified;
  final String? publicId;
  final String? publicIdLabel;
  final VoidCallback? onCopyPublicId;
  final Widget? amount;
  final DateTime? publishedAt;
  final String Function(DateTime, bool)? timeAgo;
  final String? dateCaption;
  final VoidCallback? onCopyLocation;
  final Widget? presence;
  final List<Widget> leadingExtras;
  final List<Widget> trailingExtras;

  static const double _gap = 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final titleColor = CatalogReadableInk.title(cs);
    final muted = CatalogReadableInk.muted(cs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (presence != null) ...[
          presence!,
          const SizedBox(height: _gap),
        ],
        if (title.trim().isNotEmpty)
          AqarMarqueeText(
            text: LocaleContent.forUi(title.trim(), isAr: isAr),
            height: 22,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              fontSize: 15.5,
              height: 1.22,
              letterSpacing: -0.12,
              color: titleColor,
              fontFamily: 'Cairo',
            ),
          ),
        ...leadingExtras,
        if (title.trim().isNotEmpty || leadingExtras.isNotEmpty)
          const SizedBox(height: _gap),
        SizedBox(
          width: double.infinity,
          child: _specChipsLine(context, cs: cs, muted: muted),
        ),
        if (publisherCaption.trim().isNotEmpty ||
            publisherName.trim().isNotEmpty) ...[
          const SizedBox(height: _gap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (publisherLeading != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6, top: 1),
                  child: publisherLeading!,
                )
              else
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6, top: 1),
                  child: Icon(
                    Icons.apartment_outlined,
                    size: 16,
                    color: cs.primary,
                  ),
                ),
              Expanded(
                child: Text(
                  () {
                    final cap = publisherCaption.trim();
                    final name = publisherName.trim();
                    if (cap.isNotEmpty && name.isNotEmpty) {
                      final head = cap.endsWith(':') ? cap : '$cap:';
                      return LocaleContent.forUi('$head $name', isAr: isAr);
                    }
                    if (name.isNotEmpty) {
                      return LocaleContent.forUi(name, isAr: isAr);
                    }
                    return cap;
                  }(),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: titleColor,
                    fontFamily: 'Cairo',
                    fontSize: 12.5,
                    height: 1.22,
                  ),
                ),
              ),
              if (publisherVerified)
                const Padding(
                  padding: EdgeInsetsDirectional.only(start: 4),
                  child: Icon(
                    Icons.verified_rounded,
                    size: 16,
                    color: Color(0xFF10B981),
                  ),
                ),
            ],
          ),
        ],
        if ((publicId ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 3),
          LayoutBuilder(
            builder: (context, constraints) {
              final idText = Text(
                '${publicIdLabel ?? (isAr ? 'رقم الإعلان' : 'Listing no.')}: ${publicId!.trim()}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.primary,
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  height: 1.15,
                ),
              );
              final copyButton = IconButton(
                tooltip: isAr ? 'نسخ' : 'Copy',
                visualDensity: VisualDensity.compact,
                constraints:
                    const BoxConstraints.tightFor(width: 30, height: 30),
                padding: EdgeInsets.zero,
                iconSize: 16,
                icon: Icon(Icons.copy_rounded, color: cs.primary),
                onPressed: onCopyPublicId ??
                    () async {
                      final value = publicId!.trim();
                      await Clipboard.setData(ClipboardData(text: value));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          content: Text(isAr ? 'تم النسخ' : 'Copied'),
                        ),
                      );
                    },
              );
              if (amount == null) {
                return Row(children: [Expanded(child: idText), copyButton]);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [Expanded(child: idText), copyButton]),
                  amount!,
                ],
              );
            },
          ),
        ] else if (amount != null) ...[
          const SizedBox(height: 3),
          SizedBox(width: double.infinity, child: amount!),
        ],
        if (publishedAt != null) ...[
          const SizedBox(height: _gap),
          _iconLine(
            context,
            icon: Icons.event_note_outlined,
            child: Directionality(
              textDirection: DateHelper.calendarTextDirection(isAr: isAr),
              child: AqarMarqueeText(
                text: _dateBlock(context),
                height: 16,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                  fontFamily: 'Cairo',
                  fontSize: 11.5,
                  height: 1.25,
                ),
              ),
            ),
          ),
        ],
        ...trailingExtras,
      ],
    );
  }

  String _dateBlock(BuildContext context) {
    final dt = publishedAt!;
    final abs = ListingDateDisplay.formatCardDateTime(dt, isAr: isAr);
    final caption = (dateCaption ?? '').trim();
    final head = caption.isNotEmpty
        ? caption
        : (isAr ? 'تاريخ ووقت نشر الإعلان' : 'Published date & time');
    if (abs.isEmpty) return head;
    return '$head: $abs';
  }

  Widget _specChipsLine(
    BuildContext context, {
    required ColorScheme cs,
    required Color muted,
  }) {
    final chips = <({IconData icon, String text})>[];
    void add(IconData icon, String raw) {
      final t = LocaleContent.forUi(raw.trim(), isAr: isAr);
      if (t.isEmpty) return;
      chips.add((icon: icon, text: t));
    }

    add(Icons.square_foot_outlined, areaText);
    final locations = <String>[
      regionText,
      governorateText,
      cityText,
      districtText,
      ...locationParts,
    ]
        .map((part) => LocaleContent.forUi(part.trim(), isAr: isAr))
        .where((part) => part.isNotEmpty)
        .toList();
    final seenLocations = <String>{};
    final locationLine = locations
        .where((part) => seenLocations.add(part.toLowerCase()))
        .join(isAr ? '، ' : ', ');
    add(Icons.place_outlined, locationLine);
    add(Icons.bed_outlined, roomsText);
    return Row(
      children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < chips.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Text(
                        '·',
                        style: TextStyle(
                          color: muted.withValues(alpha: 0.55),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  Icon(chips[i].icon, size: 15, color: cs.primary),
                  const SizedBox(width: 3),
                  Text(
                    chips[i].text,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: muted,
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      height: 1.15,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (onCopyLocation != null)
          IconButton(
            tooltip: isAr ? 'نسخ الموقع' : 'Copy location',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(
              width: 28,
              height: 28,
            ),
            padding: EdgeInsets.zero,
            iconSize: 15,
            onPressed: onCopyLocation,
            icon: Icon(Icons.copy_rounded, color: cs.primary),
          ),
      ],
    );
  }

  Widget _iconLine(
    BuildContext context, {
    required IconData icon,
    required Widget child,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: cs.onSurfaceVariant),
        ),
        const SizedBox(width: 5),
        Expanded(child: child),
      ],
    );
  }
}

/// شارة ذهبية «مميز» على صورة البطاقة.
class CatalogFeaturedBadge extends StatelessWidget {
  const CatalogFeaturedBadge({super.key, required this.isAr});

  final bool isAr;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFC9A227),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 13, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            isAr ? 'مميز' : 'Featured',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 11,
              fontFamily: 'Cairo',
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
