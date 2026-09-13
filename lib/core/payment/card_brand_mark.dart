import 'package:flutter/material.dart';

/// شعار الشبكة من حزمة Moyasar (Visa / Mastercard / mada).
class CardBrandMark extends StatelessWidget {
  const CardBrandMark({
    super.key,
    required this.scheme,
    this.height = 20,
  });

  final String scheme;
  final double height;

  static const _assets = <String, String>{
    'visa': 'assets/images/visa.png',
    'mastercard': 'assets/images/mastercard.png',
    'mada': 'assets/images/mada.png',
    'amex': 'assets/images/amex.png',
  };

  @override
  Widget build(BuildContext context) {
    final asset = _assets[scheme];
    if (asset == null) return const SizedBox.shrink();
    return Image.asset(
      asset,
      package: 'moyasar',
      height: height,
      width: height * 1.55,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}
