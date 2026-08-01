import 'package:flutter/material.dart';

import '../core/workflow/listing_workflow_copy.dart';
import '../widgets/marketing_offer_submit_sheet.dart';

/// صفحة كاملة لإرسال عرض تسويق — نفس محتوى الورقة السفلية الموحّدة.
class SubmitOfferPage extends StatelessWidget {
  final String requestId;
  final String lang;
  final String? inviteId;

  const SubmitOfferPage({
    super.key,
    required this.requestId,
    this.lang = 'ar',
    this.inviteId,
  });

  bool get _isAr => lang.toLowerCase() != 'en';

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(ListingWorkflowCopy.t(_isAr, 'إتمام صفقة تسويق', 'Complete deal')),
        ),
        body: SafeArea(
          child: MarketingOfferSubmitPanel(
            requestId: requestId,
            inviteId: inviteId,
            isAr: _isAr,
            showDragHandle: false,
            onSuccess: () {
              Navigator.of(context).pop(true);
            },
          ),
        ),
      ),
    );
  }
}
