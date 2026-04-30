import '../../models/property.dart';
import 'listing_workflow_stage.dart';
import 'listing_workflow_ui_context.dart';

enum ListingUiEntityKind {
  prePublishRequest,
  publishedProperty,
}

class ListingPostPublishUiDecision {
  final ListingUiEntityKind kind;
  final ListingWorkflowStage stage;

  final String tabNameAr;
  final String statusLabelAr;
  final bool showOnHomePublic;

  final bool showInOwnerPage;
  final bool showInMarketerAdmin;
  final bool showCartButton;

  final bool showProgressStrip;
  final bool showPublishedBadgeOnly;

  /// مهم لمنع التضارب/التكرار:
  /// - إذا كان الكيان "منشورًا"، لا نُخرجه كـ "request card" داخل تبويب الطلبات.
  final bool shouldRenderAsRequestCard;

  const ListingPostPublishUiDecision({
    required this.kind,
    required this.stage,
    required this.tabNameAr,
    required this.statusLabelAr,
    required this.showOnHomePublic,
    required this.showInOwnerPage,
    required this.showInMarketerAdmin,
    required this.showCartButton,
    required this.showProgressStrip,
    required this.showPublishedBadgeOnly,
    required this.shouldRenderAsRequestCard,
  });
}

class ListingPostPublishUiHelper {
  ListingPostPublishUiHelper._();

  static ListingPostPublishUiDecision decideFromRequestRow(
    Map<String, dynamic> requestRow,
  ) {
    final ctx = ListingWorkflowUiContext.fromListingRequest(requestRow);

    final isPublished = ctx.isPublishedPublic;
    final kind = isPublished
        ? ListingUiEntityKind.publishedProperty
        : ListingUiEntityKind.prePublishRequest;

    return ListingPostPublishUiDecision(
      kind: kind,
      stage: ctx.stage,
      tabNameAr: ctx.ownerHubTabNameAr,
      statusLabelAr: ctx.statusLabelAr,
      showOnHomePublic: ctx.isPublishedPublic,
      showInOwnerPage: true,
      // طلبات ما قبل النشر تظهر في إدارة المسوق (عروض/تعاقد),
      // أما المنشورة فلها bucket منفصل في loaders.
      showInMarketerAdmin: true,
      showCartButton: isPublished,
      showProgressStrip: !isPublished,
      showPublishedBadgeOnly: isPublished,
      shouldRenderAsRequestCard: !isPublished,
    );
  }

  static ListingPostPublishUiDecision decideFromProperty(
    Property property, {
    String? currentMarketerId,
  }) {
    final ctx = ListingWorkflowUiContext.fromProperty(property);

    final isPublished = property.effectiveWorkflowStage ==
            ListingWorkflowStage.published ||
        property.effectiveWorkflowStage == ListingWorkflowStage.reserved;

    final showInMarketerAdmin =
        currentMarketerId != null &&
            property.publishedByMarketerId != null &&
            property.publishedByMarketerId == currentMarketerId &&
            isPublished;

    final kind = isPublished
        ? ListingUiEntityKind.publishedProperty
        : ListingUiEntityKind.prePublishRequest;

    /// عقار معاينة / قبل النشر العلني: يظهر في الرئيسية للمالك، ولا يُكرَّر في «صفحتي» كصف عقار.
    final showPropertyInOwnerHub = const {
      ListingWorkflowStage.published,
      ListingWorkflowStage.reserved,
      ListingWorkflowStage.inactive72h,
      ListingWorkflowStage.cancelled,
      ListingWorkflowStage.terminated,
      ListingWorkflowStage.contractCancelled,
      ListingWorkflowStage.archived,
    }.contains(property.effectiveWorkflowStage);

    return ListingPostPublishUiDecision(
      kind: kind,
      stage: ctx.stage,
      tabNameAr: ctx.ownerHubTabNameAr,
      statusLabelAr: ctx.statusLabelAr,
      showOnHomePublic: isPublished || ctx.isPublishedPublic,
      showInOwnerPage: showPropertyInOwnerHub,
      showInMarketerAdmin: showInMarketerAdmin,
      showCartButton: isPublished,
      showProgressStrip: false,
      showPublishedBadgeOnly: isPublished,
      shouldRenderAsRequestCard: false,
    );
  }
}

