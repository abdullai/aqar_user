import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/org/org_join_qr_payload.dart';

/// مسح رمز انضمام الفريق بالكاميرا (هاتف/لوحي فقط).
Future<void> showOrgTeamJoinQrScanner(
  BuildContext context, {
  required void Function(String parsedCode) onCode,
  required bool isAr,
}) async {
  if (kIsWeb) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isAr
              ? 'مسح QR بالكاميرا متاح على تطبيق الجوال. انسخ الرمز أو أدخله يدوياً.'
              : 'Camera QR scan is available on the mobile app. Paste or type the code.',
        ),
      ),
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return _OrgTeamJoinScanBody(
        isAr: isAr,
        onCode: (raw) {
          final parsed = OrgJoinQrPayload.parseRecruitOrOrgInput(raw);
          if (parsed.isEmpty) return;
          Navigator.of(ctx).pop();
          onCode(parsed);
        },
      );
    },
  );
}

class _OrgTeamJoinScanBody extends StatefulWidget {
  const _OrgTeamJoinScanBody({
    required this.isAr,
    required this.onCode,
  });

  final bool isAr;
  final void Function(String raw) onCode;

  @override
  State<_OrgTeamJoinScanBody> createState() => _OrgTeamJoinScanBodyState();
}

class _OrgTeamJoinScanBodyState extends State<_OrgTeamJoinScanBody> {
  final MobileScannerController _ctrl = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height * 0.72;
    return SafeArea(
      child: SizedBox(
        height: h,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                widget.isAr
                    ? 'وجّه الكاميرا نحو رمز الانضمام'
                    : 'Point the camera at the team join QR',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: MobileScanner(
                  controller: _ctrl,
                  onDetect: (capture) {
                    for (final b in capture.barcodes) {
                      final v = b.rawValue?.trim();
                      if (v != null && v.isNotEmpty) {
                        widget.onCode(v);
                        return;
                      }
                    }
                  },
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(widget.isAr ? 'إلغاء' : 'Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
