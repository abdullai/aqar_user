import 'in_app_otp_handoff.dart';

/// Equal OTP boxes that always fit the available width on phones and small web.
class OtpPinMetrics {
  const OtpPinMetrics({
    required this.fieldWidth,
    required this.fieldHeight,
    required this.gap,
    required this.fontSize,
  });

  final double fieldWidth;
  final double fieldHeight;
  final double gap;
  final double fontSize;

  double get rowWidth =>
      fieldWidth * InAppOtpHandoff.otpLen +
      gap * (InAppOtpHandoff.otpLen - 1);

  bool fits(double maxWidth) => rowWidth <= maxWidth + 0.5;
}

abstract final class OtpPinLayout {
  static const int length = InAppOtpHandoff.otpLen;

  static OtpPinMetrics of(double maxWidth) {
    final maxW = maxWidth.isFinite && maxWidth > 0 ? maxWidth : 280.0;
    final gap = maxW < 300 ? 4.0 : (maxW < 380 ? 6.0 : 8.0);
    final fieldW = ((maxW - gap * (length - 1)) / length).clamp(28.0, 52.0);
    final fieldH = (fieldW + 6).clamp(40.0, 56.0);
    final fontSize = fieldW < 34 ? 16.0 : (fieldW < 42 ? 18.0 : 22.0);
    return OtpPinMetrics(
      fieldWidth: fieldW,
      fieldHeight: fieldH,
      gap: gap,
      fontSize: fontSize,
    );
  }
}
