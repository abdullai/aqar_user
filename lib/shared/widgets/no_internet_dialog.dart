import 'package:flutter/material.dart';

class NoInternetDialog extends StatelessWidget {
  final bool isAr;

  const NoInternetDialog({
    super.key,
    this.isAr = true,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(isAr ? 'لا يوجد اتصال بالإنترنت' : 'No Internet Connection'),
      content: Text(
        isAr
            ? 'يرجى التأكد من اتصالك بالإنترنت ثم إعادة المحاولة.'
            : 'Please check your internet connection and try again.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(isAr ? 'حسناً' : 'OK'),
        ),
      ],
    );
  }
}

/// Optional helper (إذا تحب الاستدعاء كدالة)
Future<void> showNoInternetDialog(
  BuildContext context, {
  required bool isAr,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => NoInternetDialog(isAr: isAr),
  );
}
