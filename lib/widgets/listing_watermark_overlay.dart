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
