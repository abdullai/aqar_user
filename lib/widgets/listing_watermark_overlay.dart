import 'package:flutter/material.dart';

/// ختم عرض فقط — أيقونة ركن صغيرة بلا رقم إعلان أو بيانات عقار على الوسائط.
class ListingWatermarkOverlay extends StatelessWidget {
  const ListingWatermarkOverlay({
    super.key,
    this.traceId = '',
    this.isAr = true,
    this.headline,
  });

  /// لم يعد يُعرض على الصورة (يُستخدم أسفل البطاقة عند الحاجة).
  final String traceId;
  final bool isAr;
  final String? headline;

  @override
  Widget build(BuildContext context) {
    final label = (headline ?? '').trim();
    if (label.isNotEmpty) {
      return IgnorePointer(
        child: Align(
          alignment: AlignmentDirectional.bottomEnd,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return const IgnorePointer(
      child: Align(
        alignment: AlignmentDirectional.bottomEnd,
        child: Padding(
          padding: EdgeInsets.all(7),
          child: Icon(
            Icons.verified_outlined,
            size: 15,
            color: Color(0x4DFFFFFF),
          ),
        ),
      ),
    );
  }
}
