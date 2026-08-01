part of 'user_dashboard.dart';

// ignore_for_file: unused_element, unused_element_parameter

// === ملف: user_dashboard.widgets.dart ===
// الهدف: Widgets مساعدة خاصة بالـ Dashboard مع تمرير جميع الدوال المطلوبة
//
// ✅ تعديلات هذا الإصدار:
// 1) زر "إضافة للسلة" صار يعتمد على canShowCartButton
//    ويظهر فقط عندما ترسل له الشاشة الرئيسية true
//    (مثل: المشترين + المعلنين / ويختفي عن صاحب الإعلان + جميع المسوقين).
// 2) تحسين ارتفاع بطاقات العقارات داخل الـ Grid حتى لا ينقص أسفل البطاقة.
// 3) تحسينات بسيطة على الأداء والثبات في العرض.

// =========================
// Widgets
// =========================

/// زوايا بطاقات الرئيسية — أقرب لهوية «موثوق» (بطاقات ناعمة 2024+).
const double _kHomeCardRadius = 24;

/// أخضر العلامة من هوية المشروع.
const Color _kAqarBrandPrimary = Color(0xFF0B4D3E);
const Color _kAqarBrandAccentBg = Color(0xFFEBF6F3);

BoxDecoration _homeFeedCardFaceDecoration({
  required ColorScheme cs,
  required Color typeAccent,
  required Color purposeAccent,
  required Color borderHint,
  Color? borderStrong,
  double borderWidth = 1.25,
  List<BoxShadow>? boxShadow,
  bool emphasizePaid = false,
}) {
  final isLight = cs.brightness == Brightness.light;
  // سطح صافٍ (أبيض/سطح الثيم) — بدون مزج ألوان باهتة على البطاقة العادية.
  final base = isLight
      ? (emphasizePaid ? const Color(0xFFF7FBF9) : Colors.white)
      : (emphasizePaid ? cs.surfaceContainerHighest : cs.surface);
  final face = emphasizePaid
      ? Color.alphaBlend(
          _kAqarBrandPrimary.withValues(alpha: isLight ? 0.04 : 0.08),
          base,
        )
      : base;
  final borderColor = borderStrong ??
      (emphasizePaid
          ? Color.alphaBlend(
              _kAqarBrandPrimary.withValues(alpha: 0.28),
              borderHint,
            )
          : Color.alphaBlend(
              cs.outlineVariant.withValues(alpha: isLight ? 0.55 : 0.45),
              borderHint,
            ));
  return BoxDecoration(
    color: face,
    gradient: null,
    borderRadius: BorderRadius.circular(_kHomeCardRadius),
    border: Border.all(color: borderColor, width: borderWidth),
    boxShadow: boxShadow ??
        (isLight
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : null),
  );
}

String _paidPriorityBadgeLabel(MarketPropertyRequestRow r, bool isAr) {
  final left = InstantMarketRequestFeed.boostRemaining(r);
  if (r.isInstantPaid) {
    if (left != null) {
      final h = left.inHours.clamp(1, 999);
      return isAr ? 'مدفوع · متبقي ~$h س' : 'Paid · ~$h h left';
    }
    return isAr ? 'طلب مدفوع أولوية' : 'Paid priority';
  }
  if (r.requestPriority == MarketPropertyRequestPriority.urgent) {
    if (left != null) {
      final h = left.inHours.clamp(1, 999);
      return isAr ? 'مستعجل · متبقي ~$h س' : 'Urgent · ~$h h left';
    }
    return isAr ? 'مستعجل' : 'Urgent';
  }
  if (left != null) {
    final h = left.inHours.clamp(1, 999);
    return isAr ? 'أولوية · متبقي ~$h س' : 'Priority · ~$h h left';
  }
  return isAr ? 'ذو أولوية' : 'Priority';
}

Color _marketRequestBorderAccent(
  MarketPropertyRequestRow r,
  ColorScheme cs,
  Color purposeAccent,
) {
  switch (r.requestPriority) {
    case MarketPropertyRequestPriority.immediate:
      return const Color(0xFFDC2626);
    case MarketPropertyRequestPriority.urgent:
      return const Color(0xFFEA580C);
    case MarketPropertyRequestPriority.priority:
      return const Color(0xFFF59E0B);
    case MarketPropertyRequestPriority.standard:
      return Color.lerp(purposeAccent, cs.primary, 0.35) ?? purposeAccent;
    case MarketPropertyRequestPriority.flexible:
      return Color.lerp(cs.outline, purposeAccent, 0.45) ?? cs.outline;
  }
}

class _IconBadgeButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final int badge;
  final Color color;
  final VoidCallback onPressed;

  const _IconBadgeButton({
    required this.tooltip,
    required this.icon,
    required this.badge,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(999),
              child: Ink(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(icon, color: color),
              ),
            ),
          ),
          if (badge > 0)
            PositionedDirectional(
              end: 2,
              top: 2,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                decoration: BoxDecoration(
                  color: cs.error,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: cs.surface, width: 1.4),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 10,
                      offset: const Offset(0, 6),
                      color: Colors.black.withOpacity(0.12),
                    ),
                  ],
                ),
                child: Text(
                  badge > 99 ? '99+' : '$badge',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onError,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    height: 1.0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BadgeIcon extends StatelessWidget {
  final IconData icon;
  final int badge;
  final Color color;

  const _BadgeIcon({
    required this.icon,
    required this.badge,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          if (badge > 0)
            PositionedDirectional(
              end: -6,
              top: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                decoration: BoxDecoration(
                  color: cs.error,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: cs.surface, width: 1.4),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 10,
                      offset: const Offset(0, 6),
                      color: Colors.black.withOpacity(0.12),
                    ),
                  ],
                ),
                child: Text(
                  badge > 99 ? '99+' : '$badge',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cs.onError,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    height: 1.0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// أيقونة «إدارتي» في الشريط السفلي: نقطة تنبيه بدون رقم مربك.
class _DeskNavBottomIcon extends StatelessWidget {
  const _DeskNavBottomIcon({
    required this.icon,
    required this.showDot,
    this.filled = false,
  });

  final IconData icon;
  final bool showDot;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = filled ? cs.primary : cs.onSurface;
    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(icon, color: c, size: 24),
          if (showDot)
            PositionedDirectional(
              end: -2,
              top: -2,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: cs.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.surface, width: 1.2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final VoidCallback? onTap;

  const _MiniChip({
    required this.icon,
    required this.text,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final light = cs.brightness == Brightness.light;

    final box = Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: light ? 0.10 : 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: light ? const Color(0xFF050505) : cs.onSurface,
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: box,
      ),
    );
  }
}

// =========================
// Add Button - مخصص للمالك والمسوق
// =========================

class _AddButton extends StatelessWidget {
  final bool isAr;
  final Color bankColor;
  final bool isMarketer;
  final VoidCallback onAddProperty;
  final VoidCallback onAddRequest;

  const _AddButton({
    required this.isAr,
    required this.bankColor,
    required this.isMarketer,
    required this.onAddProperty,
    required this.onAddRequest,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: bankColor,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            blurRadius: 14,
            spreadRadius: 0,
            offset: const Offset(0, 5),
            color: Colors.black.withOpacity(0.18),
          ),
        ],
      ),
      child: IconButton(
        icon: const Icon(Icons.add, color: Colors.white),
        onPressed: isMarketer ? onAddRequest : onAddProperty,
        tooltip: isMarketer
            ? (isAr ? 'إرسال طلب تسويق' : 'Send marketing request')
            : (isAr ? 'إضافة إعلان' : 'Add property'),
      ),
    );
  }
}

// =========================
// Request Card - لعرض طلبات التسويق
// =========================

class _RequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final bool isAr;
  final Color bankColor;
  final VoidCallback onTap;
  final DateTime? Function(dynamic) tryParseDt;
  final String Function(DateTime, bool) timeAgo;
  final VoidCallback? onInviteMarketer;
  final VoidCallback? onMakeOffer;
  final VoidCallback? onSignContract;
  final VoidCallback? onViewPermit;

  const _RequestCard({
    required this.request,
    required this.isAr,
    required this.bankColor,
    required this.onTap,
    required this.tryParseDt,
    required this.timeAgo,
    this.onInviteMarketer,
    this.onMakeOffer,
    this.onSignContract,
    this.onViewPermit,
  });

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
      case 'new':
        return isAr ? 'بانتظار موافقة وسيط' : 'Pending mediator';
      case 'invited':
        return isAr ? 'تم إرسال الدعوات' : 'Invites sent';
      case 'offers_received':
        return isAr ? 'تم استلام عروض' : 'Offers received';
      case 'assigned':
        return isAr ? 'تم اختيار مسوق' : 'Marketer assigned';
      case 'contract':
      case 'pending_owner':
      case 'signed':
        return isAr ? 'بانتظار توقيع العقد' : 'Awaiting contract';
      case 'published':
      case 'active':
      case 'approved':
        return isAr ? 'منشور' : 'Published';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
      case 'new':
      case 'invited':
        return Colors.orange;
      case 'offers_received':
        return Colors.blue;
      case 'assigned':
      case 'contract':
      case 'pending_owner':
      case 'signed':
        return Colors.purple;
      case 'published':
      case 'active':
      case 'approved':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _safe(dynamic v) => (v ?? '').toString().trim();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final id = _safe(request['id']);
    final title = _safe(request['title']).isNotEmpty
        ? _safe(request['title'])
        : _safe(request['request_title']);
    final city = _safe(request['city']).isNotEmpty
        ? _safe(request['city'])
        : _safe(request['request_city']);
    final status = _safe(request['status']).toLowerCase();
    final createdAt =
        tryParseDt(request['created_at'] ?? request['updated_at']);
    final when = createdAt == null ? '' : timeAgo(createdAt, isAr);

    final hasActions = onInviteMarketer != null ||
        onMakeOffer != null ||
        onSignContract != null ||
        onViewPermit != null;

    return Card(
      elevation: 1.6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: bankColor.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.description_outlined, color: bankColor),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.isEmpty
                              ? (isAr ? 'طلب إعلان' : 'Listing request')
                              : title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [if (id.isNotEmpty) id, if (when.isNotEmpty) when]
                              .join('  •  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (city.isNotEmpty)
                    _MiniChip(
                      icon: Icons.location_on_outlined,
                      text: city,
                      color: bankColor,
                    ),
                  _MiniChip(
                    icon: Icons.info_outline,
                    text: _getStatusText(status),
                    color: _getStatusColor(status),
                  ),
                ],
              ),
              if (hasActions) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, c) {
                    final narrow = c.maxWidth < 620;
                    final buttons = <Widget>[
                      if (onInviteMarketer != null)
                        _buildActionButton(
                          icon: Icons.person_add_outlined,
                          label: isAr ? 'دعوة مسوق' : 'Invite marketer',
                          onPressed: onInviteMarketer!,
                          color: Colors.blue,
                        ),
                      if (onMakeOffer != null)
                        _buildActionButton(
                          icon: Icons.request_quote_outlined,
                          label: isAr ? 'إتمام الصفقة' : 'Complete deal',
                          onPressed: onMakeOffer!,
                          color: Colors.green,
                        ),
                      if (onSignContract != null)
                        _buildActionButton(
                          icon: Icons.description_outlined,
                          label: isAr ? 'توقيع عقد' : 'Sign contract',
                          onPressed: onSignContract!,
                          color: Colors.purple,
                        ),
                      if (onViewPermit != null)
                        _buildActionButton(
                          icon: Icons.assignment_turned_in_outlined,
                          label: isAr ? 'عرض التصريح' : 'View permit',
                          onPressed: onViewPermit!,
                          color: Colors.orange,
                        ),
                    ];

                    if (narrow) {
                      return Column(
                        children: [
                          for (int i = 0; i < buttons.length; i++) ...[
                            SizedBox(width: double.infinity, child: buttons[i]),
                            if (i != buttons.length - 1)
                              const SizedBox(height: 8),
                          ],
                        ],
                      );
                    }

                    return Row(
                      children: [
                        for (int i = 0; i < buttons.length; i++) ...[
                          Expanded(child: buttons[i]),
                          if (i != buttons.length - 1) const SizedBox(width: 8),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

// =========================
// Reservation cards/actions
// =========================

enum _ReservationActionKind { outlined, filledDanger }

class _ReservationAction {
  final _ReservationActionKind kind;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _ReservationAction({
    required this.kind,
    required this.icon,
    required this.label,
    required this.onPressed,
  });
}

class _ReservationCard extends StatelessWidget {
  final Color bankColor;
  final IconData icon;
  final String title;
  final Widget? subtitle;
  final List<Widget> chips;
  final Widget priceTable;
  final _ReservationAction? primaryAction;
  final _ReservationAction? secondaryAction;
  final _ReservationAction? thirdAction;
  final _ReservationAction? fourthAction;
  final DateTime? Function(dynamic) tryParseDt;
  final String Function(DateTime, bool) timeAgo;
  final String Function(DateTime) fmtDateTime;

  const _ReservationCard({
    required this.bankColor,
    required this.icon,
    required this.title,
    required this.chips,
    required this.priceTable,
    required this.primaryAction,
    required this.secondaryAction,
    required this.thirdAction,
    this.fourthAction,
    required this.tryParseDt,
    required this.timeAgo,
    required this.fmtDateTime,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget buildAction(_ReservationAction a) {
      final label = Text(
        a.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w900),
      );

      switch (a.kind) {
        case _ReservationActionKind.outlined:
          return OutlinedButton.icon(
            onPressed: a.onPressed,
            icon: Icon(a.icon, size: 18),
            label: label,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          );

        case _ReservationActionKind.filledDanger:
          return ElevatedButton.icon(
            onPressed: a.onPressed,
            icon: Icon(a.icon, size: 18),
            label: label,
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          );
      }
    }

    final seenActionKeys = <String>{};
    final actionWidgets = <Widget>[];
    void addAction(_ReservationAction? action) {
      if (action == null) return;
      final key = '${action.icon.codePoint}:${action.label}';
      if (!seenActionKeys.add(key)) return;
      actionWidgets.add(buildAction(action));
    }

    addAction(primaryAction);
    addAction(secondaryAction);
    addAction(thirdAction);
    addAction(fourthAction);

    final light = cs.brightness == Brightness.light;
    final strongText = light ? const Color(0xFF050505) : cs.onSurface;
    final cardBg = light ? const Color(0xFFFFFFFF) : cs.surface;
    final tintedBg = Color.alphaBlend(
      bankColor.withValues(alpha: light ? 0.055 : 0.12),
      cardBg,
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: kIsWeb ? tintedBg : null,
        gradient: kIsWeb
            ? null
            : LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: [tintedBg, cardBg],
              ),
        border: Border.all(
          color: Color.alphaBlend(
            bankColor.withValues(alpha: light ? 0.30 : 0.42),
            cs.outlineVariant.withValues(alpha: 0.55),
          ),
          width: 1.15,
        ),
        boxShadow: [
          BoxShadow(
            blurRadius: 22,
            offset: const Offset(0, 12),
            color: cs.shadow.withValues(alpha: light ? 0.10 : 0.22),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: bankColor.withValues(alpha: light ? 0.14 : 0.20),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: bankColor.withValues(alpha: 0.26),
                ),
              ),
              child: Icon(icon, color: bankColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: strongText,
                        ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    subtitle!,
                  ],
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: chips),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: light
                          ? const Color(0xFFF7F7F7)
                          : cs.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.55),
                      ),
                    ),
                    child: priceTable,
                  ),
                  if (actionWidgets.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, c) {
                        final narrow = c.maxWidth < 560;

                        if (narrow) {
                          // سطر أفقي متكيّف بدل تكديس عمودي يطيل البطاقة.
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (int i = 0;
                                    i < actionWidgets.length;
                                    i++) ...[
                                  if (i > 0) const SizedBox(width: 8),
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minWidth: 118,
                                      maxWidth: actionWidgets.length <= 2
                                          ? c.maxWidth
                                          : 168,
                                    ),
                                    child: actionWidgets[i],
                                  ),
                                ],
                              ],
                            ),
                          );
                        }

                        return Row(
                          children: [
                            for (int i = 0; i < actionWidgets.length; i++) ...[
                              Expanded(child: actionWidgets[i]),
                              if (i != actionWidgets.length - 1)
                                const SizedBox(width: 10),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// عدّاد تنازلي لمهلة الحجز (مثلاً 72 ساعة) — يُحدَّث كل ثانية.
class _ReservationExpiryCountdown extends StatefulWidget {
  final DateTime expiresAt;
  final bool isAr;

  const _ReservationExpiryCountdown({
    required this.expiresAt,
    required this.isAr,
  });

  @override
  State<_ReservationExpiryCountdown> createState() =>
      _ReservationExpiryCountdownState();
}

class _ReservationExpiryCountdownState
    extends State<_ReservationExpiryCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final left = widget.expiresAt.difference(now);
    final style = TextStyle(
      fontWeight: FontWeight.w900,
      fontSize: 13,
      color: left.isNegative ? cs.error : cs.primary,
    );
    if (left.isNegative) {
      return Text(
        widget.isAr ? 'انتهت مهلة الحجز' : 'Hold period ended',
        style: style,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }
    final h = left.inHours;
    final m = left.inMinutes.remainder(60);
    final s = left.inSeconds.remainder(60);
    final hh = h.toString().padLeft(2, '0');
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    final text = widget.isAr
        ? 'متبقٍ على انتهاء الحجز: $hh:$mm:$ss'
        : 'Time left on hold: $hh:$mm:$ss';
    return Text(
      text,
      style: style,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// عدد أعمدة شبكة بطاقات الإعلانات والخليط (صفحتي / الرئيسية) — منطق موحّد.
int _homeListingGridCrossAxisCount(double w) {
  // جوال / ويب ضيق / تابلت عمودي: عمود واحد بعرض الشاشة كاملاً.
  if (w < 600) return 1;
  // ويب ويندوز / شاشات عريضة: عمودان — صورة بجانب البيانات.
  return 2;
}

/// ارتفاع موحّد لخلية الشبكة (طلب + إعلان) عند أكثر من عمود.
/// ويب سطح المكتب يستخدم تخطيطاً جانبياً (صورة+بيانات) فيحتاج ارتفاعاً كافياً بلا قصّ.
double? _homeListingGridEqualCardHeight({
  required double maxWidth,
  required int crossAxisCount,
  double horizontalPadding = 24,
  double spacing = 12,
}) {
  if (crossAxisCount <= 1) return null;
  final gaps = spacing * (crossAxisCount - 1);
  final usable = (maxWidth - horizontalPadding - gaps).clamp(180.0, maxWidth);
  final cellW = usable / crossAxisCount;
  if (kIsWeb) {
    // ارتفاع أوضح للصورة الكبيرة بجانب البيانات (~45%).
    return (cellW / 1.55).clamp(248.0, 340.0);
  }
  return (cellW / 0.46).clamp(460.0, 760.0);
}

/// عرض ≥600: بطاقات شبكة بتخطيط جانبي (صورة بجانب البيانات) — ويب وتطبيق.
/// العربية: الصورة يمين المستخدم. الإنجليزية: يسار.
bool _homeListingCardsUseSideBySideLayout(BuildContext context) {
  return MediaQuery.sizeOf(context).width >= 600;
}

/// نسبة صورة البطاقة: أقصر على الشاشات الضيقة لتوفير مساحة للبيانات.
double _homeListingHeroAspectRatio(BuildContext context, {bool isRequest = false}) {
  final w = MediaQuery.sizeOf(context).width;
  if (w < 600) {
    // جوال / ويب ضيق: صورة أقصر (نمط بطاقات عقارية عالمي).
    return isRequest ? 2.35 : 2.2;
  }
  return isRequest ? 1.72 : 1.58;
}

/// صفقة مكتملة/مباع — تُستبعد من المفضلة ويُخفى قلب التفضيل.
bool _listingCompletedDealForFavorites(Property p) {
  final s = (p.status ?? '').trim().toLowerCase();
  final rs = (p.reservationStatus ?? '').trim().toLowerCase();
  return s == 'sold' ||
      s == 'closed' ||
      s == 'completed' ||
      rs == 'sold' ||
      rs == 'closed' ||
      rs == 'completed';
}

Widget _wrapEqualGridCardHeight({
  required double? height,
  required Widget child,
}) {
  // IntrinsicHeight + CrossAxisAlignment.stretch يوحّدان الارتفاع؛
  // البطاقة تملأ الفراغ عبر UnifiedRealEstateCard دون قصّ.
  return child;
}

// =========================
// Mixed home timeline (إعلانات + طلبات — الأحدث أولاً)
// =========================

class _HomeMixedTimeline extends StatelessWidget {
  const _HomeMixedTimeline({
    required this.entries,
    this.scrollController,
    this.primaryScroll = false,
    required this.currentUserId,
    required this.isAr,
    required this.bankColor,
    required this.isFav,
    required this.onToggleFav,
    required this.onOpenDetails,
    required this.activeHoldCount,
    required this.isReserved,
    required this.reservedUntil,
    required this.reservedByName,
    required this.onAddToCart,
    required this.onEditProperty,
    required this.onDeleteProperty,
    required this.timeAgo,
    required this.canShowCartButton,
    this.onPropertyViewsInteraction,
    this.onCopyListingWebLink,
    required this.onOpenMarketRequest,
    this.onSubmitMarketRequestOffer,
    required this.marketRequestPriorityLabel,
    this.suppressPublicOwnerIdentityOnCards = false,
    this.showRegulatoryIdentityOnCards = true,
    this.onShareListingFromCard,
    this.onHomeHideFromFeed,
    this.onHomeReportListing,
    this.onHomeHideMarketRequest,
    this.onHomeReportMarketRequest,
    this.onEditMarketRequest,
    this.onCopyMarketRequestWebLink,
    this.onShareMarketRequestFromCard,
    this.homeFeedShowsHiddenOnly = false,
    this.onRestorePropertyToHome,
    this.onWithdrawPropertyReport,
    this.onRestoreMarketRequest,
    this.markPublishedItemsAsMine = false,
    this.dealSubscriptionBlocked = false,
    this.onSubscribeForDeal,
  });

  final List<HomeMixedFeedEntry> entries;
  final ScrollController? scrollController;
  final bool primaryScroll;
  final String currentUserId;
  final bool isAr;
  final Color bankColor;
  final bool Function(String id) isFav;
  final Future<void> Function(String id) onToggleFav;
  final void Function(Property p) onOpenDetails;
  final int Function(String propertyId) activeHoldCount;
  final bool Function(String propertyId) isReserved;
  final DateTime? Function(String propertyId) reservedUntil;
  final String? Function(String propertyId) reservedByName;
  final Future<void> Function(Property p) onAddToCart;
  final Future<void> Function(Property p) onEditProperty;
  final Future<void> Function(Property p) onDeleteProperty;
  final String Function(DateTime, bool) timeAgo;
  final bool canShowCartButton;
  final void Function(BuildContext context, Property p, bool isOwner)?
      onPropertyViewsInteraction;
  final Future<void> Function(Property p)? onCopyListingWebLink;
  final void Function(MarketPropertyRequestRow r) onOpenMarketRequest;
  final void Function(MarketPropertyRequestRow r)? onSubmitMarketRequestOffer;
  final String Function(MarketPropertyRequestRow r) marketRequestPriorityLabel;

  final bool suppressPublicOwnerIdentityOnCards;
  final bool showRegulatoryIdentityOnCards;
  final Future<void> Function(Property p)? onShareListingFromCard;

  final Future<void> Function(Property p)? onHomeHideFromFeed;
  final Future<void> Function(Property p)? onHomeReportListing;
  final Future<void> Function(MarketPropertyRequestRow r)?
      onHomeHideMarketRequest;
  final Future<void> Function(MarketPropertyRequestRow r)?
      onHomeReportMarketRequest;
  final Future<void> Function(MarketPropertyRequestRow r)? onEditMarketRequest;
  final Future<void> Function(MarketPropertyRequestRow r)?
      onCopyMarketRequestWebLink;
  final Future<void> Function(MarketPropertyRequestRow r)?
      onShareMarketRequestFromCard;

  final bool homeFeedShowsHiddenOnly;
  final Future<void> Function(Property p)? onRestorePropertyToHome;
  final Future<void> Function(Property p)? onWithdrawPropertyReport;
  final Future<void> Function(MarketPropertyRequestRow r)?
      onRestoreMarketRequest;

  final bool dealSubscriptionBlocked;
  final VoidCallback? onSubscribeForDeal;

  /// عند `true` (تبويب «إعلاناتي/طلباتي»): تُغلَّف كل بطاقة إعلان وصلت لمرحلة
  /// النشر العام (`published` أو `reserved`) بشارة «منشور» صغيرة في الزاوية
  /// العلوية لتمييز أنّ هذا الإعلان منشور للجميع في الرئيسية، ويخصّ المستخدم
  /// (إمّا كمعلن فرد أو كمسوّق نشره نيابة عن المالك).
  final bool markPublishedItemsAsMine;

  Widget _gridCellAt(int index) {
    if (index >= entries.length) return const SizedBox.shrink();
    return _cardForEntry(entries[index]) ?? const SizedBox.shrink();
  }

  /// شارة «منشور» صغيرة في الزاوية العلوية للبطاقة — تُستخدم في تبويب
  /// «إعلاناتي/طلباتي» لتمييز أنّ الإعلان وصل للنشر العام في الرئيسية
  /// رغم أنه يخصّ المستخدم (كمعلن فرد أو كمسوّق نشر نيابة عن المالك).
  Widget _wrapWithPublishedChip(
    Widget card,
    Property property, {
    required bool showChip,
  }) {
    if (!showChip) return card;
    final stage = property.effectiveWorkflowStage;
    final isPublishedLike = stage == ListingWorkflowStage.published ||
        stage == ListingWorkflowStage.reserved;
    if (!isPublishedLike) return card;
    final pubBy = (property.publishedByMarketerId ?? '').trim();
    final isMine = property.ownerId == currentUserId ||
        (pubBy.isNotEmpty && pubBy == currentUserId);
    if (!isMine) return card;
    final ownerLabel = isAr
        ? (property.ownerId == currentUserId ? 'منشور' : 'منشور بواسطتي')
        : (property.ownerId == currentUserId ? 'Published' : 'Published by me');
    return Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        PositionedDirectional(
          top: 8,
          start: 12,
          child: _PublishedSelfChip(label: ownerLabel),
        ),
      ],
    );
  }

  Widget? _cardForEntry(HomeMixedFeedEntry e) {
    final p = e.listing;
    if (p != null) {
      final isOwner = p.ownerId == currentUserId;
      final isGuest = currentUserId == 'guest';
      final allowCart = ListingPermissionsHelper.canAddToCart(
        property: p,
        currentUserId: isGuest ? null : currentUserId,
        isGuest: isGuest,
        showCartNavSlot: canShowCartButton,
      );
      final card = _RealEstateCard(
        property: p,
        isOwner: isOwner,
        isAr: isAr,
        bankColor: bankColor,
        favorite: !isGuest && isFav(p.id),
        onToggleFav: () => onToggleFav(p.id),
        onOpenDetails: () => onOpenDetails(p),
        activeCartHoldsCount: activeHoldCount(p.id),
        isReserved: isReserved(p.id),
        reservedUntil: reservedUntil(p.id),
        reservedByName: reservedByName(p.id),
        onAddToCart: allowCart ? () => onAddToCart(p) : null,
        currentUserId: currentUserId,
        showEditDelete: isOwner,
        onEditProperty: isOwner ? () => onEditProperty(p) : null,
        onDeleteProperty: isOwner ? () => onDeleteProperty(p) : null,
        timeAgo: timeAgo,
        canShowCartButton: canShowCartButton,
        onViewsPillTap: onPropertyViewsInteraction == null
            ? null
            : (ctx) => onPropertyViewsInteraction!(ctx, p, isOwner),
        showListingQuickActions: true,
        onCopyListingWebLink: onCopyListingWebLink,
        suppressPublicOwnerIdentity: suppressPublicOwnerIdentityOnCards,
        showRegulatoryIdentityOnCard:
            showRegulatoryIdentityOnCards && currentUserId != 'guest',
        omitMarketingLicenseEntriesOnCard: true,
        onShareListingFromCard: onShareListingFromCard == null
            ? null
            : () => onShareListingFromCard!(p),
        onHomeHideFromFeed: onHomeHideFromFeed,
        onHomeReportListing: onHomeReportListing,
        homeFeedShowsHiddenOnly: homeFeedShowsHiddenOnly,
        onRestorePropertyToHome: onRestorePropertyToHome,
        onWithdrawPropertyReport: onWithdrawPropertyReport,
        preferStaticPrimaryImage: true,
      );
      return _wrapWithPublishedChip(
        card,
        p,
        showChip: markPublishedItemsAsMine,
      );
    }
    final r = e.request;
    if (r == null) return null;
    return _MarketRequestListingStyleCard(
      request: r,
      isAr: isAr,
      bankColor: bankColor,
      currentUserId: currentUserId,
      timeAgo: timeAgo,
      priorityLabel: marketRequestPriorityLabel(r),
      onOpen: () => onOpenMarketRequest(r),
      onSubmitOffer: onSubmitMarketRequestOffer == null
          ? null
          : () => onSubmitMarketRequestOffer!(r),
      dealSubscriptionBlocked: dealSubscriptionBlocked,
      onSubscribeForDeal: onSubscribeForDeal,
      homeFeedShowsHiddenOnly: homeFeedShowsHiddenOnly,
      onRestoreMarketRequest: onRestoreMarketRequest,
      onHomeHideMarketRequest: onHomeHideMarketRequest,
      onHomeReportMarketRequest: onHomeReportMarketRequest,
      onEditMarketRequest: onEditMarketRequest,
      onCopyMarketRequestWebLink: onCopyMarketRequestWebLink,
      onShareMarketRequestFromCard: onShareMarketRequestFromCard,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();

    Widget buildEntryList({
      required int cross,
      required double maxWidth,
      required ScrollController? controller,
      required bool primary,
    }) {
      const spacing = 8.0;
      final pad = const EdgeInsets.symmetric(horizontal: 12, vertical: 8);

      final cacheExtent = primary && kIsWeb ? 360.0 : (primary ? 250.0 : 0.0);

      if (cross <= 1) {
        return ListView.separated(
          // ويب/Expanded: primary:false دائماً — الاعتماد على PrimaryScrollController
          // كان يُظهر عدد النتائج دون رسم البطاقات (ارتفاع/ربط تمرير معطوب).
          controller: controller,
          primary: false,
          shrinkWrap: !primary,
          cacheExtent: cacheExtent,
          physics: primary
              ? const AlwaysScrollableScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: pad,
          itemCount: entries.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final card = _cardForEntry(entries[i]);
            return card ?? const SizedBox.shrink();
          },
        );
      }

      final rowCount = (entries.length + cross - 1) ~/ cross;
      final equalH = _homeListingGridEqualCardHeight(
        maxWidth: maxWidth,
        crossAxisCount: cross,
        horizontalPadding: 24,
        spacing: spacing,
      );
      return ListView.separated(
        controller: controller,
        primary: false,
        shrinkWrap: !primary,
        cacheExtent: cacheExtent,
        physics: primary
            ? const AlwaysScrollableScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: pad,
        itemCount: rowCount,
        separatorBuilder: (_, __) => const SizedBox(height: spacing),
        itemBuilder: (context, row) {
          final start = row * cross;
          // ارتفاع موحّد بين بطاقة الإعلان والطلب في نفس الصف.
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var j = 0; j < cross; j++) ...[
                  if (j > 0) const SizedBox(width: spacing),
                  Expanded(
                    child: _wrapEqualGridCardHeight(
                      height: equalH,
                      child: _gridCellAt(start + j),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      );
    }

    // primaryScroll: قائمة جذر داخل Expanded → shrinkWrap=false + AlwaysScrollable.
    // ListView.primary يبقى false دائماً أعلاه (لا PrimaryScrollController على الويب).
    if (primaryScroll) {
      return LayoutBuilder(
        builder: (context, c) {
          final cross = _homeListingGridCrossAxisCount(c.maxWidth);
          return buildEntryList(
            cross: cross,
            maxWidth: c.maxWidth,
            controller: scrollController,
            primary: true,
          );
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: LayoutBuilder(
        builder: (context, c) {
          final cross = _homeListingGridCrossAxisCount(c.maxWidth);
          return buildEntryList(
            cross: cross,
            maxWidth: c.maxWidth,
            controller: null,
            primary: false,
          );
        },
      ),
    );
  }
}

// =========================
// Market request card — نفس هيكل بطاقة الإعلان (قائمة: صورة + محتوى)
// =========================

class _MarketRequestListingStyleCard extends StatelessWidget {
  const _MarketRequestListingStyleCard({
    required this.request,
    required this.isAr,
    required this.bankColor,
    required this.currentUserId,
    required this.timeAgo,
    required this.priorityLabel,
    required this.onOpen,
    this.onSubmitOffer,
    this.homeFeedShowsHiddenOnly = false,
    this.onRestoreMarketRequest,
    this.onHomeHideMarketRequest,
    this.onHomeReportMarketRequest,
    this.onEditMarketRequest,
    this.onCopyMarketRequestWebLink,
    this.onShareMarketRequestFromCard,
    this.dealSubscriptionBlocked = false,
    this.onSubscribeForDeal,
  });

  final MarketPropertyRequestRow request;
  final bool isAr;
  final Color bankColor;
  final String currentUserId;
  final String Function(DateTime, bool) timeAgo;
  final String priorityLabel;
  final VoidCallback onOpen;
  final VoidCallback? onSubmitOffer;
  final bool homeFeedShowsHiddenOnly;
  final Future<void> Function(MarketPropertyRequestRow r)?
      onRestoreMarketRequest;
  final Future<void> Function(MarketPropertyRequestRow r)?
      onHomeHideMarketRequest;
  final Future<void> Function(MarketPropertyRequestRow r)?
      onHomeReportMarketRequest;
  final Future<void> Function(MarketPropertyRequestRow r)? onEditMarketRequest;
  final Future<void> Function(MarketPropertyRequestRow r)?
      onCopyMarketRequestWebLink;
  final Future<void> Function(MarketPropertyRequestRow r)?
      onShareMarketRequestFromCard;
  final bool dealSubscriptionBlocked;
  final VoidCallback? onSubscribeForDeal;

  /// رقم الطلب العقاري من الخادم فقط ([MarketPropertyRequestRow.requestPublicCode])؛ لا يُشتق من UUID.
  static String? _requestPublicTenDigit(MarketPropertyRequestRow r) {
    final c = r.requestPublicCode?.trim() ?? '';
    if (c.isEmpty) return null;
    return DisplayIds.tenDigit(c);
  }

  static Future<void> _copyValue(
    BuildContext context,
    String value,
    bool isAr,
  ) async {
    final v = value.trim();
    if (v.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: v));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(isAr ? 'تم النسخ' : 'Copied'),
      ),
    );
  }

  static Widget _copyIcon(BuildContext context, String value, bool isAr) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(_copyValue(context, value, isAr)),
      child: IconButton(
        tooltip: isAr ? 'نسخ' : 'Copy',
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        padding: EdgeInsets.zero,
        iconSize: 16,
        icon: const Icon(Icons.copy_rounded),
        onPressed: () => unawaited(_copyValue(context, value, isAr)),
      ),
    );
  }

  static String _areaSpec(MarketPropertyRequestRow r, bool isAr) {
    final area = r.areaMinM2;
    if (area == null) return '';
    final v = AppMoney.formatNumber(
      area,
      isAr: isAr,
      maxFractionDigits: 0,
    );
    return isAr ? '≥ $v م²' : '≥ $v m²';
  }

  static String _roomsSpec(MarketPropertyRequestRow r, bool isAr) {
    final bd = r.details['bedrooms'];
    if (bd is! num) return '';
    final n = bd.toInt();
    return isAr ? '$n غرف' : '$n br';
  }

  static String _districtSpec(MarketPropertyRequestRow r) {
    final d =
        r.districts.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (d.isNotEmpty) return d.first;
    return r.city.trim();
  }

  static Widget _budgetLine(
    BuildContext context,
    MarketPropertyRequestRow r,
    bool isAr,
    Color color,
  ) {
    final min = r.budgetMin;
    final max = r.budgetMax;
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          height: 1.0,
          fontSize: 10,
        );
    final amountStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w900,
          color: color,
          height: 1.1,
          fontSize: 14,
        );
    if (min == null && max == null) {
      return Text(
        isAr ? 'المبلغ غير محدد' : 'Amount not set',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: amountStyle,
      );
    }

    Widget amountWidget;
    if (min != null && max != null && max != min) {
      amountWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppMoneyLine(
            amount: min,
            currencyCode: 'SAR',
            isAr: isAr,
            maxFractionDigits: 0,
            symbolColor: color,
            style: amountStyle,
          ),
          Text(
            isAr ? ' إلى ' : ' to ',
            style: amountStyle?.copyWith(fontWeight: FontWeight.w800),
          ),
          AppMoneyLine(
            amount: max,
            currencyCode: 'SAR',
            isAr: isAr,
            maxFractionDigits: 0,
            symbolColor: color,
            style: amountStyle,
          ),
        ],
      );
    } else {
      final amount = min ?? max;
      if (amount == null) {
        return Text(
          isAr ? 'المبلغ غير محدد' : 'Amount not set',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: amountStyle,
        );
      }
      amountWidget = AppMoneyLine(
        amount: amount,
        currencyCode: 'SAR',
        isAr: isAr,
        maxFractionDigits: 0,
        symbolColor: color,
        style: amountStyle,
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEBF6F3).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF0B4D3E).withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isAr ? 'المبلغ المحدد' : 'Specified amount',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: labelStyle,
          ),
          const SizedBox(height: 3),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: amountWidget,
            ),
          ),
        ],
      ),
    );
  }

  /// إخفاء القائمة عند عدم توفر إجراءات (حسب حالة الطلب في الخادم).
  static bool _showOverflowMenuForStatus(
    MarketPropertyRequestRow r, {
    required bool allowMenu,
    required bool baseShowMenu,
  }) {
    if (!allowMenu || !baseShowMenu) return false;
    final st = r.status.trim().toLowerCase();
    if (st == 'closed' || st == 'cancelled' || st == 'canceled') {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    try {
      return _buildSafe(context);
    } catch (e, st) {
      assert(() {
        // ignore: avoid_print
        print('[DBG][HOME][REQUEST_CARD] build failed: $e\n$st');
        return true;
      }());
      final cs = Theme.of(context).colorScheme;
      return Material(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_kHomeCardRadius),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(_kHomeCardRadius),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              isAr
                  ? (request.title.trim().isEmpty
                      ? 'طلب عقاري'
                      : request.title.trim())
                  : (request.title.trim().isEmpty
                      ? 'Market request'
                      : request.title.trim()),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
              ),
            ),
          ),
        ),
      );
    }
  }

  Widget _buildSafe(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final r = request;
    final typeKey =
        r.propertyType.trim().isEmpty ? 'apartment' : r.propertyType;
    final typeAccent = PropertyTypeCatalog.accentFor(typeKey);
    final purposeAccent = r.purpose == 'rent'
        ? cs.tertiary
        : (Color.lerp(bankColor, cs.primary, 0.5) ?? bankColor);
    final borderColor = theme.brightness == Brightness.light
        ? Colors.black.withOpacity(0.15)
        : Colors.white.withOpacity(0.15);
    final loggedIn = currentUserId != 'guest';
    final requestStatus = r.status.trim().toLowerCase();
    final requestCompleted = requestStatus == 'completed' ||
        requestStatus == 'closed' ||
        requestStatus == 'sold';
    final deletionRequested =
        requestStatus == 'delete_requested' || r.deletionRequestedAt != null;
    final baseShowMenu = (homeFeedShowsHiddenOnly &&
            loggedIn &&
            onRestoreMarketRequest != null) ||
        (!homeFeedShowsHiddenOnly &&
            (onHomeHideMarketRequest != null ||
                onHomeReportMarketRequest != null)) ||
        (onCopyMarketRequestWebLink != null) ||
        (onShareMarketRequestFromCard != null);
    // ضيف: نسخ/مشاركة فقط. مسجّل: إخفاء/بلاغ/استعادة حسب الوضع.
    final showMenu = _showOverflowMenuForStatus(
      r,
      allowMenu: loggedIn || !homeFeedShowsHiddenOnly,
      baseShowMenu: baseShowMenu,
    );
    final canSubmitOffer = !homeFeedShowsHiddenOnly &&
        !requestCompleted &&
        !deletionRequested &&
        (currentUserId == 'guest' || currentUserId != r.requesterId);
    final isRequester =
        currentUserId != 'guest' && currentUserId == r.requesterId;

    final purposeShort = r.purpose == 'rent'
        ? (isAr ? 'للإيجار' : 'for rent')
        : (isAr ? 'للشراء' : 'to buy');
    final headline = PropertyListingDisplay.displayRequestTitle(r, isAr);
    final requestTen = _requestPublicTenDigit(r);
    final showPriorityChip =
        !InstantMarketRequestBadge.showsFor(r.requestPriority) &&
            priorityLabel.trim().isNotEmpty;
    final locationParts = PropertyListingDisplay.locationPartsWithoutTitleEcho(
      PropertyListingDisplay.locationHierarchyPartsForRequest(r),
      headline,
    );

    final dataColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          headline,
          maxLines: 2,
          softWrap: true,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w900,
            fontSize: 15.5,
            height: 1.28,
            letterSpacing: -0.15,
            color: theme.brightness == Brightness.dark
                ? null
                : const Color(0xFF041D18),
            fontFamily: 'Cairo',
          ),
        ),
        if (showPriorityChip) ...[
          const SizedBox(height: 3),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: purposeAccent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: purposeAccent.withValues(alpha: 0.28),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                child: Text(
                  priorityLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: purposeAccent,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ],
        if (InstantMarketRequestBadge.showsFor(r.requestPriority)) ...[
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: InstantMarketRequestBadge(
              isAr: isAr,
              row: r,
              viewerRegion: null,
              showRemaining: true,
            ),
          ),
          const SizedBox(height: 4),
          InstantMarketRequestFeatureStrip(isAr: isAr),
        ],
        if (deletionRequested || requestCompleted) ...[
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: requestCompleted
                    ? Colors.green.withValues(alpha: 0.12)
                    : cs.errorContainer.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Text(
                  requestCompleted
                      ? (isAr ? 'تمت الصفقة' : 'Deal completed')
                      : (isAr ? 'مرفوع طلب حذف' : 'Deletion requested'),
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: requestCompleted
                        ? Colors.green.shade800
                        : cs.onErrorContainer,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 6),
        UnifiedCardSpecRow(
          bankColor: bankColor,
          areaText: _areaSpec(r, isAr),
          roomsText: _roomsSpec(r, isAr),
          locationParts: locationParts,
        ),
        if (!isRequester && r.requesterId.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          UserPresenceStrip(
            userId: r.requesterId.trim(),
            isAr: isAr,
            compact: true,
            surface: PresenceDisplaySurface.requestCards,
            fallbackTimestamp: r.updatedAt ?? r.createdAt,
          ),
        ],
        if ((r.showRequesterName ||
                (r.requesterPublicName?.trim().isNotEmpty == true)) &&
            (r.requesterPublicName?.trim().isNotEmpty == true ||
                (r.requesterAvatarUrl ?? '').trim().isNotEmpty)) ...[
          const SizedBox(height: 5),
          Row(
            children: [
              if ((r.requesterAvatarUrl ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: (r.requesterAvatarUrl ?? '').trim(),
                      width: 24,
                      height: 24,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Icon(
                        Icons.person_outline,
                        size: 16,
                        color: bankColor,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isAr ? 'منشئ الطلب' : 'Request creator',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                        fontSize: 10.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (r.requesterPublicName ?? '').trim().isEmpty
                          ? (isAr ? 'طالب' : 'Requester')
                          : (r.requesterPublicName ?? '').trim(),
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.primary,
                        height: 1.25,
                        fontSize: 13.5,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
        if (requestTen != null) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Text(
                  isAr ? 'رقم الطلب: $requestTen' : 'Request no.: $requestTen',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                  ),
                ),
              ),
              _copyIcon(context, requestTen, isAr),
            ],
          ),
        ],
        const SizedBox(height: 4),
        _budgetLine(context, r, isAr, purposeAccent),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.schedule_rounded,
              size: 14,
              color: cs.primary,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                isAr
                    ? 'تاريخ الطلب: ${ListingDateDisplay.formatCardDateTime(r.sortTime, isAr: isAr)} · ${timeAgo(r.sortTime, isAr)}'
                    : 'Requested: ${ListingDateDisplay.formatCardDateTime(r.sortTime, isAr: isAr)} · ${timeAgo(r.sortTime, isAr)}',
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Cairo',
                  height: 1.25,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ],
    );

    final requestFooter = LayoutBuilder(
      builder: (context, c) {
        if (canSubmitOffer &&
            dealSubscriptionBlocked &&
            !request.isInstantPaid &&
            onSubscribeForDeal != null) {
          return SubscriptionGateAlertChip(
            isAr: isAr,
            action: SubscriptionGateAction.completeMarketDeal,
            onSubscribe: onSubscribeForDeal!,
            compact: true,
          );
        }
        final mainAction = canSubmitOffer
            ? ElevatedButton.icon(
                onPressed: onSubmitOffer ?? onOpen,
                icon: const Icon(Icons.handshake_outlined, size: 18),
                label: Text(
                  isAr ? 'إتمام الصفقة' : 'Complete deal',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0B4D3E),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 50),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  elevation: 2,
                  shadowColor: const Color(0xFF0B4D3E).withValues(alpha: 0.35),
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              )
            : OutlinedButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(
                  isAr ? 'تفاصيل الطلب' : 'Request details',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              );
        final editAction = isRequester && onEditMarketRequest != null
            ? OutlinedButton.icon(
                onPressed: () => unawaited(onEditMarketRequest!(r)),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(
                  isAr ? 'تعديل الطلب' : 'Edit request',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              )
            : null;
        if (editAction == null)
          return SizedBox(width: double.infinity, child: mainAction);
        if (c.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [mainAction, const SizedBox(height: 8), editAction],
          );
        }
        return Row(
          children: [
            Expanded(child: mainAction),
            const SizedBox(width: 8),
            Expanded(child: editAction),
          ],
        );
      },
    );

    final imageStack = Stack(
      fit: StackFit.expand,
      children: [
        // رأس مميّز للطلب (بدون صورة مشروع) ليفرق عن بطاقة الإعلان العقاري.
        ColoredBox(
          color: theme.brightness == Brightness.dark
              ? const Color(0xFF3B2114)
              : const Color(0xFFFFF4EC),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: theme.brightness == Brightness.dark
                    ? const [
                        Color(0xFF4A2818),
                        Color(0xFF2A1810),
                      ]
                    : const [
                        Color(0xFFFFF7ED),
                        Color(0xFFFFEDD5),
                      ],
              ),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEA580C).withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              const Color(0xFFEA580C).withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Icon(
                        Icons.assignment_turned_in_outlined,
                        size: 28,
                        color: Color(0xFFEA580C),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isAr ? 'طلب عقاري' : 'Property request',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        fontFamily: 'Cairo',
                        color: theme.brightness == Brightness.dark
                            ? const Color(0xFFFFEDD5)
                            : const Color(0xFF9A3412),
                      ),
                    ),
                    if (purposeShort.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        purposeShort.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          fontFamily: 'Cairo',
                          color: theme.brightness == Brightness.dark
                              ? const Color(0xFFFDBA74)
                              : const Color(0xFFC2410C),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (InstantMarketRequestFeed.showsPaidPriorityChrome(r)) ...[
          // بداية الاتجاه — بعيداً عن قائمة ⋮ في النهاية حتى لا يغطي النبض الثلاث نقاط.
          PositionedDirectional(
            top: 8,
            start: 10,
            child: CardImagePulseBadge(
              label: _paidPriorityBadgeLabel(r, isAr),
              color: r.isInstantPaid
                  ? const Color(0xFF0B4D3E)
                  : const Color(0xFFDA3E27),
              icon: r.isInstantPaid
                  ? Icons.workspace_premium_rounded
                  : Icons.bolt_rounded,
              prominent: true,
            ),
          ),
        ],
        if (showMenu)
          PositionedDirectional(
            top: 8,
            end: 8,
            child: MarketRequestPublicActionsMenuButton(
              colorScheme: cs,
              homeFeedShowsHiddenOnly: homeFeedShowsHiddenOnly,
              onCopyLink: onCopyMarketRequestWebLink == null
                  ? null
                  : () => onCopyMarketRequestWebLink!(r),
              onShare: onShareMarketRequestFromCard == null
                  ? null
                  : () => onShareMarketRequestFromCard!(r),
              onHideFromHome:
                  homeFeedShowsHiddenOnly || onHomeHideMarketRequest == null
                      ? null
                      : () => onHomeHideMarketRequest!(r),
              onReport:
                  homeFeedShowsHiddenOnly || onHomeReportMarketRequest == null
                      ? null
                      : () => onHomeReportMarketRequest!(r),
              onRestoreToHome:
                  !homeFeedShowsHiddenOnly || onRestoreMarketRequest == null
                      ? null
                      : () => onRestoreMarketRequest!(r),
            ),
          ),
      ],
    );

    return UnifiedRealEstateCard(
      decoration: _homeFeedCardFaceDecoration(
        cs: cs,
        typeAccent: typeAccent,
        purposeAccent: purposeAccent,
        borderHint: borderColor,
        borderStrong: InstantMarketRequestFeed.showsPaidPriorityChrome(r)
            ? const Color(0xFFDFB230)
            : Color.alphaBlend(
                cs.outlineVariant.withValues(alpha: 0.7),
                borderColor,
              ),
        borderWidth:
            InstantMarketRequestFeed.showsPaidPriorityChrome(r) ? 2.2 : 1.15,
        emphasizePaid: InstantMarketRequestFeed.showsPaidPriorityChrome(r),
      ),
      isAr: isAr,
      kind: UnifiedCardKind.request,
      onCardTap: onOpen,
      cardRadius: _kHomeCardRadius,
      fullWidthHeroImage: !_homeListingCardsUseSideBySideLayout(context),
      // جوال/ضيق: صورة أعلى بعرض البطاقة وارتفاع مريح ثم البيانات تحتها.
      heroAspectRatio: _homeListingHeroAspectRatio(context, isRequest: true),
      dataColumn: dataColumn,
      imageColumn: imageStack,
      belowMainRow: null,
      footer: requestFooter,
    );
  }
}

// =========================
// Property Grid / Cards
// =========================

class _PropertyGrid extends StatelessWidget {
  final List<Property> items;
  final ScrollController? scrollController;
  final bool primaryScroll;
  final String currentUserId;
  final bool isAr;
  final Color bankColor;
  final bool Function(String id) isFav;
  final Future<void> Function(String id) onToggleFav;
  final void Function(Property p) onOpenDetails;
  final int Function(String propertyId) activeHoldCount;
  final bool Function(String propertyId) isReserved;
  final DateTime? Function(String propertyId) reservedUntil;
  final String? Function(String propertyId) reservedByName;
  final Future<void> Function(Property p) onAddToCart;
  final bool showEditDelete;
  final Future<void> Function(Property p) onEditProperty;
  final Future<void> Function(Property p) onDeleteProperty;
  final String Function(DateTime, bool) timeAgo;

  // ✅ NEW:
  // مرر true فقط للمستخدمين الذين يسمح لهم زر السلة
  // مثل المشترين + المعلنين
  // ومرر false لصاحب الإعلان + جميع المسوقين
  final bool canShowCartButton;

  /// عند الضغط على عداد المشاهدات على الصورة.
  final void Function(BuildContext context, Property p, bool isOwner)?
      onPropertyViewsInteraction;

  /// أزرار صريحة (تفاصيل / رابط الإعلان) — تُستخدم في الرئيسية والمفضلة.
  final bool showListingQuickActions;
  final Future<void> Function(Property p)? onCopyListingWebLink;

  final bool suppressPublicOwnerIdentityOnCards;
  final bool showRegulatoryIdentityOnCards;
  final Future<void> Function(Property p)? onShareListingFromCard;

  final Future<void> Function(Property p)? onHomeHideFromFeed;
  final Future<void> Function(Property p)? onHomeReportListing;

  final bool homeFeedShowsHiddenOnly;
  final Future<void> Function(Property p)? onRestorePropertyToHome;
  final Future<void> Function(Property p)? onWithdrawPropertyReport;

  const _PropertyGrid({
    required this.items,
    this.scrollController,
    this.primaryScroll = false,
    required this.currentUserId,
    required this.isAr,
    required this.bankColor,
    required this.isFav,
    required this.onToggleFav,
    required this.onOpenDetails,
    required this.activeHoldCount,
    required this.isReserved,
    required this.reservedUntil,
    required this.reservedByName,
    required this.onAddToCart,
    required this.showEditDelete,
    required this.onEditProperty,
    required this.onDeleteProperty,
    required this.timeAgo,
    this.canShowCartButton = true,
    this.onPropertyViewsInteraction,
    this.showListingQuickActions = false,
    this.onCopyListingWebLink,
    this.suppressPublicOwnerIdentityOnCards = false,
    this.showRegulatoryIdentityOnCards = true,
    this.onShareListingFromCard,
    this.onHomeHideFromFeed,
    this.onHomeReportListing,
    this.homeFeedShowsHiddenOnly = false,
    this.onRestorePropertyToHome,
    this.onWithdrawPropertyReport,
  });

  int _crossAxisCount(double w) => _homeListingGridCrossAxisCount(w);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final paddingH = w >= 900 ? 18.0 : 12.0;
        // ضيق العرض (ويب أو تطبيق): عمود واحد؛ عرض أوسع: شبكة تتكيّف بعدد الأعمدة.
        final isPhone = w < 600;

        Widget listingCard(Property p) {
          final isOwner = p.ownerId == currentUserId;
          final isGuest = currentUserId == 'guest';
          final allowCart = ListingPermissionsHelper.canAddToCart(
            property: p,
            currentUserId: isGuest ? null : currentUserId,
            isGuest: isGuest,
            showCartNavSlot: canShowCartButton,
          );

          return _RealEstateCard(
            property: p,
            isOwner: isOwner,
            isAr: isAr,
            bankColor: bankColor,
            favorite: !isGuest && isFav(p.id),
            onToggleFav: () => onToggleFav(p.id),
            onOpenDetails: () => onOpenDetails(p),
            activeCartHoldsCount: activeHoldCount(p.id),
            isReserved: isReserved(p.id),
            reservedUntil: reservedUntil(p.id),
            reservedByName: reservedByName(p.id),
            onAddToCart: allowCart ? () => onAddToCart(p) : null,
            currentUserId: currentUserId,
            showEditDelete: showEditDelete && isOwner,
            onEditProperty: () => onEditProperty(p),
            onDeleteProperty: () => onDeleteProperty(p),
            timeAgo: timeAgo,
            canShowCartButton: canShowCartButton,
            onViewsPillTap: onPropertyViewsInteraction == null
                ? null
                : (ctx) => onPropertyViewsInteraction!(ctx, p, isOwner),
            showListingQuickActions: showListingQuickActions,
            onCopyListingWebLink: onCopyListingWebLink,
            suppressPublicOwnerIdentity: suppressPublicOwnerIdentityOnCards,
            showRegulatoryIdentityOnCard:
                showRegulatoryIdentityOnCards && currentUserId != 'guest',
            omitMarketingLicenseEntriesOnCard: true,
            onShareListingFromCard: onShareListingFromCard == null
                ? null
                : () => onShareListingFromCard!(p),
            onHomeHideFromFeed: onHomeHideFromFeed,
            onHomeReportListing: onHomeReportListing,
            homeFeedShowsHiddenOnly: homeFeedShowsHiddenOnly,
            onRestorePropertyToHome: onRestorePropertyToHome,
            onWithdrawPropertyReport: onWithdrawPropertyReport,
            preferStaticPrimaryImage: true,
          );
        }

        if (isPhone) {
          if (primaryScroll) {
            return ListView.separated(
              controller: scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: 12),
              cacheExtent: kIsWeb ? 360 : 250,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => listingCard(items[i]),
            );
          }

          final tiles = <Widget>[];
          for (var i = 0; i < items.length; i++) {
            if (i > 0) tiles.add(const SizedBox(height: 12));
            tiles.add(listingCard(items[i]));
          }
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: tiles,
            ),
          );
        }

        final cross = _crossAxisCount(w);
        const spacing = 12.0;
        final equalH = _homeListingGridEqualCardHeight(
          maxWidth: w,
          crossAxisCount: cross,
          horizontalPadding: paddingH * 2,
          spacing: spacing,
        );

        // بدون GridView بنسبة ارتفاع ثابتة (كانت تُفرغ أسفل البطاقة على الويب)
        final rowCount = (items.length + cross - 1) ~/ cross;
        if (primaryScroll) {
          return ListView.separated(
            controller: scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: 12),
            cacheExtent: kIsWeb ? 360 : 250,
            itemCount: rowCount,
            separatorBuilder: (_, __) => const SizedBox(height: spacing),
            itemBuilder: (context, row) {
              final start = row * cross;
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < cross; j++) ...[
                      if (j > 0) SizedBox(width: spacing),
                      Expanded(
                        child: start + j < items.length
                            ? _wrapEqualGridCardHeight(
                                height: equalH,
                                child: listingCard(items[start + j]),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        }

        final rowChildren = <Widget>[];
        for (var start = 0; start < items.length; start += cross) {
          if (rowChildren.isNotEmpty) {
            rowChildren.add(SizedBox(height: spacing));
          }
          final end =
              start + cross > items.length ? items.length : start + cross;
          final chunk = items.sublist(start, end);
          rowChildren.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = 0; j < cross; j++) ...[
                    if (j > 0) SizedBox(width: spacing),
                    Expanded(
                      child: j < chunk.length
                          ? _wrapEqualGridCardHeight(
                              height: equalH,
                              child: listingCard(chunk[j]),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rowChildren,
          ),
        );
      },
    );
  }
}

// =========================
// Real Estate Card
// =========================

class _RealEstateCard extends StatelessWidget {
  final Property property;
  final bool isOwner;
  final bool isAr;
  final Color bankColor;
  final bool favorite;
  final VoidCallback onToggleFav;
  final VoidCallback onOpenDetails;

  /// حجوزات سلة نشطة من مستخدمين مختلفين (يُجلب من الخادم).
  final int activeCartHoldsCount;
  final bool isReserved;
  final DateTime? reservedUntil;
  final String? reservedByName;
  final Future<void> Function()? onAddToCart;
  final String currentUserId;
  final bool showEditDelete;
  final VoidCallback? onEditProperty;
  final VoidCallback? onDeleteProperty;
  final String Function(DateTime, bool) timeAgo;

  // ✅ NEW
  final bool canShowCartButton;

  final void Function(BuildContext context)? onViewsPillTap;

  final bool showListingQuickActions;
  final Future<void> Function(Property p)? onCopyListingWebLink;

  /// الرئيسية/المفضلة: إخفاء اسم المعلن الرباعي عن غير المالك.
  final bool suppressPublicOwnerIdentity;

  /// سياق مسوّق (معاينة): إظهار الاسم كاملاً على البطاقة.
  final bool showFullOwnerLegalNameOnCard;

  /// مشاركة من أيقونة على الصورة (لا تُستخدم على الويب إن وُجدت قيود).
  final Future<void> Function()? onShareListingFromCard;

  /// للزوار: إخفاء محلي + بلاغ (لا يُعرض لصاحب الإعلان).
  final Future<void> Function(Property p)? onHomeHideFromFeed;
  final Future<void> Function(Property p)? onHomeReportListing;

  /// وضع شريط «المخفية» في الرئيسية: إظهار + سحب بلاغ معلّق.
  final bool homeFeedShowsHiddenOnly;
  final Future<void> Function(Property p)? onRestorePropertyToHome;
  final Future<void> Function(Property p)? onWithdrawPropertyReport;

  /// «صفحتي» — عرض النصوص كاملة دون ellipsis حيث يلزم.
  final bool relaxTextTruncation;

  /// الرئيسية/المنشور: سطر الوسيط + فال/REGA من لقطة الترخيص. قبل النشر في «صفحتي»: إخفاؤها وإبقاء المعلن (ومع [isOwner] يُعرض جوال المعلن تحت الاسم عند توفره).
  final bool showRegulatoryIdentityOnCard;

  /// الرئيسية: عرض الصورة الأولى فقط بدون تمرير/نقاط؛ يقلل العمل وتسرّع التحميل.
  final bool preferStaticPrimaryImage;

  /// تبويب «صفحتي» — إعلانات المالك: هوية المالك قبل النشر ثم الوسيط والترخيص بعد النشر.
  final bool ownerHubListingCard;

  /// «صفحتي»: إخفاء أسطر رقم فال / رقم إعلان الهيئة مع الإبقاء على سطر الوسيط.
  final bool omitMarketingLicenseEntriesOnCard;

  /// محتوى داخل البطاقة تحت صف البيانات+الصورة (مراحل التسويق، أزرار واضحة).
  final Widget? cardBelowMainRow;

  const _RealEstateCard({
    required this.property,
    required this.isOwner,
    required this.isAr,
    required this.bankColor,
    required this.favorite,
    required this.onToggleFav,
    required this.onOpenDetails,
    this.activeCartHoldsCount = 0,
    required this.isReserved,
    required this.reservedUntil,
    required this.reservedByName,
    required this.onAddToCart,
    required this.currentUserId,
    required this.timeAgo,
    this.showEditDelete = false,
    this.onEditProperty,
    this.onDeleteProperty,
    this.canShowCartButton = true,
    this.onViewsPillTap,
    this.showListingQuickActions = false,
    this.onCopyListingWebLink,
    this.suppressPublicOwnerIdentity = false,
    this.showFullOwnerLegalNameOnCard = false,
    this.onShareListingFromCard,
    this.onHomeHideFromFeed,
    this.onHomeReportListing,
    this.homeFeedShowsHiddenOnly = false,
    this.onRestorePropertyToHome,
    this.onWithdrawPropertyReport,
    this.relaxTextTruncation = false,
    this.showRegulatoryIdentityOnCard = true,
    this.preferStaticPrimaryImage = false,
    this.ownerHubListingCard = false,
    this.omitMarketingLicenseEntriesOnCard = false,
    this.cardBelowMainRow,
  });

  Future<void> _copyValue(BuildContext context, String value) async {
    final v = value.trim();
    if (v.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: v));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(isAr ? 'تم النسخ' : 'Copied'),
      ),
    );
  }

  Widget _copyInlineIcon(BuildContext context, String value) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: 'Copy',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      padding: EdgeInsets.zero,
      iconSize: 15,
      onPressed: () => unawaited(_copyValue(context, value)),
      icon: Icon(Icons.copy_rounded, size: 15, color: cs.primary),
    );
  }

  /// فال + رقم الإعلان + إعلان الهيئة — رقم ونسخ واضحان على الجوال والويب.
  Widget _elegantLicenseCopyGrid(
    BuildContext context, {
    required ThemeData theme,
    required ColorScheme cs,
    required List<Map<String, String>> entries,
  }) {
    final shown = entries.take(3).toList(growable: false);
    if (shown.isEmpty) return const SizedBox.shrink();
    final isDark = cs.brightness == Brightness.dark;
    final labelColor = isDark ? cs.onSurfaceVariant : const Color(0xFF1A3A32);
    final valueColor = isDark ? cs.onSurface : const Color(0xFF041D18);

    Widget tile(Map<String, String> e) {
      final label = (e['label'] ?? '').trim();
      final value = (e['value'] ?? '').trim();
      return Container(
        width: double.infinity,
        padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 4, 8),
        decoration: BoxDecoration(
          color: isDark
              ? cs.surfaceContainerHighest.withValues(alpha: 0.7)
              : const Color(0xFFE8F3F0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                AqarBrandColors.primary.withValues(alpha: isDark ? 0.45 : 0.28),
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: labelColor,
                fontWeight: FontWeight.w900,
                fontFamily: 'Cairo',
                fontSize: 11,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    value,
                    maxLines: 2,
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: valueColor,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      height: 1.15,
                      letterSpacing: 0.15,
                    ),
                  ),
                ),
                _copyInlineIcon(context, value),
              ],
            ),
          ],
        ),
      );
    }

    // عمود واحد دائماً حتى يظهر الرقم كاملاً على الجوال والويب الضيق.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          tile(shown[i]),
        ],
      ],
    );
  }

  static String _fmtReserveHint(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}-${two(d.month)}-${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  static String locationTextFor(Property p) =>
      PropertyListingDisplay.cityLine(p);

  static String ownerNameForCard(
    Property p,
    bool isAr,
    double cardWidth, {
    bool viewingAsPropertyOwner = false,
    bool suppressPublicOwnerIdentity = false,
    bool showFullOwnerLegalNameOnCard = false,
  }) =>
      PropertyListingDisplay.ownerNameForListingCard(
        p,
        isAr,
        cardWidth,
        viewingAsPropertyOwner: viewingAsPropertyOwner,
        suppressPublicOwnerIdentity: suppressPublicOwnerIdentity,
        showFullLegalNameOnCard: showFullOwnerLegalNameOnCard,
      );

  static String? marketerLineFor(Property p, bool isAr) {
    final line = p.marketerEntityPublicLine(isAr);
    final s = (line ?? '').trim();
    if (s.isNotEmpty) return s;
    final publishedBy = (p.publishedByMarketerId ?? '').trim();
    if (publishedBy.isEmpty) return null;
    return null;
  }

  /// تسمية دور الجهة الظاهرة على البطاقة (مسوّق / مكتب / مؤسسة / شركة).
  static String marketerRoleCaption(Property p, bool isAr) {
    final snap = p.marketingLicenseSnapshot ?? const <String, dynamic>{};
    final raw = (snap['marketer_entity_type'] ??
            snap['entity_type'] ??
            snap['organization_type'] ??
            snap['broker_entity_type'] ??
            '')
        .toString()
        .toLowerCase()
        .trim();
    if (raw.contains('office') ||
        raw.contains('مكتب') ||
        raw == 'broker_office') {
      return isAr ? 'مكتب عقاري' : 'Real estate office';
    }
    if (raw.contains('company') ||
        raw.contains('شركة') ||
        raw == 'broker_company') {
      return isAr ? 'شركة عقارية' : 'Real estate company';
    }
    if (raw.contains('institution') ||
        raw.contains('establishment') ||
        raw.contains('مؤسسة') ||
        raw == 'broker_institution') {
      return isAr ? 'مؤسسة عقارية' : 'Real estate establishment';
    }
    if ((p.publishedByMarketerId ?? '').trim().isNotEmpty) {
      return isAr ? 'منشور بواسطة المسوق' : 'Published by marketer';
    }
    return isAr ? 'المعلن' : 'Advertiser';
  }

  static List<Map<String, String>> listingLicenseEntries(
    Property p,
    bool isAr,
  ) {
    final snap = p.marketingLicenseSnapshot ?? const <String, dynamic>{};

    String pick(List<String> keys) {
      for (final key in keys) {
        final value = (snap[key] ?? '').toString().trim();
        if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
      }
      return '';
    }

    final falLicense = pick(const [
      'fal_broker_license_number',
      'fal_license_number',
      'broker_license_number',
      'brokerage_license_number',
    ]);
    final adLicense = pick(const [
      'rega_ad_license_number',
      'ad_license_number',
      'advertisement_license_number',
      'advertising_license_number',
      'license_number',
    ]);
    final listingCode = (p.listingPublicCode ?? '').trim();
    final listingDisplay =
        listingCode.isEmpty ? '' : DisplayIds.tenDigit(listingCode);
    final deedNo = (p.deedNumber ?? '').trim();
    String deedDateStr = '';
    if (p.deedDate != null) {
      final d = p.deedDate!;
      deedDateStr =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }

    return [
      if (falLicense.isNotEmpty)
        {
          'label': isAr ? 'رخصة فال' : 'FAL',
          'value': falLicense,
        },
      if (listingDisplay.isNotEmpty)
        {
          'label': isAr ? 'رقم الإعلان' : 'Listing no.',
          'value': listingDisplay,
        },
      if (adLicense.isNotEmpty)
        {
          'label': isAr ? 'إعلان الهيئة' : 'REGA ad',
          'value': adLicense,
        },
      if (deedNo.isNotEmpty)
        {
          'label': isAr ? 'رقم الصك' : 'Deed no.',
          'value': deedNo,
        },
      if (deedDateStr.isNotEmpty)
        {
          'label': isAr ? 'تاريخ الصك' : 'Deed date',
          'value': deedDateStr,
        },
    ];
  }

  static List<String> listingLicenseLines(Property p, bool isAr) {
    return listingLicenseEntries(p, isAr)
        .map((e) => '${e['label']}: ${e['value']}')
        .toList(growable: false);
  }

  /// وقت إنشاء الإعلان من المالك، ووقت النشر عند توفره (من جهة التسويق).
  /// يُعرض داخل عمود البيانات بجانب الصورة — ليس تحتها.
  static Widget listingCardCreatedPublishedTimes({
    required BuildContext context,
    required Property property,
    required bool isAr,
    required TextStyle style,
    bool relaxClamp = false,
    String Function(DateTime, bool)? relativeTime,
    bool compactInline = true,
  }) {
    final cs = Theme.of(context).colorScheme;
    final createdAt = property.publishedAt ?? property.createdAt;
    final abs = ListingDateDisplay.formatCardDateTime(
      createdAt,
      isAr: isAr,
    );
    final rel = relativeTime?.call(createdAt, isAr).trim() ?? '';
    final clock = abs.isEmpty ? '' : (rel.isEmpty ? abs : '$abs  ·  $rel');
    if (compactInline) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 14,
            color: cs.primary,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              clock.isNotEmpty
                  ? (isAr ? 'تاريخ الإعلان: $clock' : 'Listed: $clock')
                  : (isAr ? 'تاريخ الإعلان: —' : 'Listed: —'),
              maxLines: 2,
              softWrap: true,
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(
                fontWeight: FontWeight.w800,
                fontFamily: 'Cairo',
                color: clock.isNotEmpty ? cs.onSurface : cs.onSurfaceVariant,
                height: 1.25,
                fontSize: (style.fontSize ?? 12) * 0.95,
              ),
            ),
          ),
        ],
      );
    }
    final isDark = cs.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerHighest : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? cs.outlineVariant : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 13,
                color: isDark ? cs.primary : AqarBrandColors.primary,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  isAr ? 'تاريخ ووقت الإعلان' : 'Listing date and time',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style.copyWith(
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Cairo',
                    color: cs.onSurface,
                    fontSize: (style.fontSize ?? 11) * 0.95,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            clock.isNotEmpty ? clock : (isAr ? '—' : '—'),
            maxLines: 2,
            softWrap: true,
            overflow: TextOverflow.ellipsis,
            style: style.copyWith(
              fontWeight: FontWeight.w900,
              fontFamily: 'Cairo',
              color: clock.isNotEmpty ? cs.primary : cs.onSurfaceVariant,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  static String typeLabel(Property property, bool isAr) {
    final key = property.listingTypeKey.trim().isNotEmpty
        ? property.listingTypeKey
        : property.type.name;
    return PropertyTypeCatalog.label(key, isAr);
  }

  /// تخطيط صورة البطاقة الموحّد (V3): قلب أعلى اليمين، قائمة ⋮ أعلى اليسار، شارة كاميرا أسفل اليمين.
  Widget _imageBlockUnifiedList(
    BuildContext context, {
    required bool canAddToCart,
    required bool canBidFromCard,
  }) {
    final cs = Theme.of(context).colorScheme;
    final allowReport =
        ListingPermissionsHelper.shouldOfferPublicListingReport(property);
    final loggedIn = currentUserId != 'guest';
    final isGuest = currentUserId == 'guest';

    final hasCopy = onCopyListingWebLink != null;
    final hasShare = onShareListingFromCard != null;
    final hasHide =
        !isOwner && !homeFeedShowsHiddenOnly && onHomeHideFromFeed != null;
    final hasReport = !isOwner &&
        !homeFeedShowsHiddenOnly &&
        allowReport &&
        onHomeReportListing != null;
    final hasHiddenFeedActions = homeFeedShowsHiddenOnly &&
        loggedIn &&
        !isOwner &&
        (onRestorePropertyToHome != null || onWithdrawPropertyReport != null);

    final showListingOverflowMenu = hasCopy ||
        hasShare ||
        hasHide ||
        hasReport ||
        hasHiddenFeedActions ||
        onViewsPillTap != null ||
        (isOwner && loggedIn && (hasShare || hasCopy)) ||
        (isGuest && (hasCopy || hasShare));

    final showOwnerOverflow =
        showEditDelete && (onEditProperty != null || onDeleteProperty != null);

    return Stack(
      fit: StackFit.expand,
      children: [
        _PropertyImage(
          urls: PropertyListingDisplay.propertyCardImagePaths(property),
          fit: BoxFit.cover,
          videoPathOrUrl: property.videoUrl,
          isAr: isAr,
          allowInlineVideo: !kIsWeb,
          listingIdForWatermark: property.id,
          preferStaticPrimaryImage: preferStaticPrimaryImage,
        ),
        if (property.isAuction)
          Positioned(
            bottom: 8,
            left: isAr ? null : 8,
            right: isAr ? 8 : null,
            child: CardImagePulseBadge(
              label: isAr ? 'مزايدة' : 'Auction',
              color: const Color(0xFFEA580C),
              icon: Icons.gavel_rounded,
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: kIsWeb ? Colors.black.withOpacity(0.08) : null,
            gradient: kIsWeb
                ? null
                : LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.14),
                      Colors.transparent,
                    ],
                  ),
          ),
        ),
        // قلب المفضلة — ظاهر وفعّال لكل الإعلانات غير المكتملة (بما فيها الضيف → حوار الدخول).
        if (!_listingCompletedDealForFavorites(property))
          PositionedDirectional(
            top: 8,
            start: 8,
            child: Material(
              elevation: 3,
              color: Colors.black.withValues(alpha: 0.48),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: IconButton(
                tooltip: favorite
                    ? (isAr ? 'إزالة من المفضلة' : 'Remove favorite')
                    : (isAr ? 'إضافة للمفضلة' : 'Add to favorites'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                iconSize: 20,
                onPressed: onToggleFav,
                icon: Icon(
                  favorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: favorite ? const Color(0xFFEF4444) : Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        // عدد الصور أسفل منتصف الصورة.
        if (PropertyListingDisplay.propertyCardImagePaths(property).length > 1)
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.photo_camera_outlined,
                        size: 12, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      '${PropertyListingDisplay.propertyCardImagePaths(property).length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (showOwnerOverflow)
          PositionedDirectional(
            top: 8,
            end: 8,
            child: Material(
              color: Colors.black.withOpacity(0.45),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                iconSize: 20,
                icon:
                    const Icon(Icons.more_vert, color: Colors.white, size: 20),
                color: cs.surface,
                elevation: 2,
                onSelected: (v) {
                  if (v == 'edit') onEditProperty?.call();
                  if (v == 'delete') onDeleteProperty?.call();
                  if (v == 'copy') unawaited(onCopyListingWebLink!(property));
                  if (v == 'share') unawaited(onShareListingFromCard!());
                  if (v == 'views' && onViewsPillTap != null) {
                    onViewsPillTap!(context);
                  }
                },
                itemBuilder: (ctx) => [
                  if (onEditProperty != null)
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 20, color: cs.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isAr ? 'تعديل' : 'Edit',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (onDeleteProperty != null)
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 20, color: cs.error),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isAr ? 'حذف' : 'Delete',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: cs.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (hasCopy)
                    PopupMenuItem(
                      value: 'copy',
                      child: Row(
                        children: [
                          Icon(Icons.link, size: 20, color: cs.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isAr ? 'نسخ الرابط' : 'Copy link',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (hasShare)
                    PopupMenuItem(
                      value: 'share',
                      child: Row(
                        children: [
                          Icon(Icons.share_outlined,
                              size: 20, color: cs.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isAr ? 'مشاركة' : 'Share',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (onViewsPillTap != null)
                    PopupMenuItem(
                      value: 'views',
                      child: Row(
                        children: [
                          Icon(Icons.remove_red_eye_outlined,
                              size: 20, color: cs.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isAr ? 'المشاهدات' : 'Views',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          )
        else if (showListingOverflowMenu)
          PositionedDirectional(
            top: 8,
            end: 8,
            child: Material(
              color: Colors.black.withOpacity(0.45),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: ListingPublicActionsMenuButton(
                property: property,
                colorScheme: cs,
                homeFeedShowsHiddenOnly: homeFeedShowsHiddenOnly,
                onCopyLink:
                    hasCopy ? () => onCopyListingWebLink!(property) : null,
                onShare: hasShare ? () => onShareListingFromCard!() : null,
                onShowViews: onViewsPillTap == null
                    ? null
                    : () async => onViewsPillTap!(context),
                onToggleFavorite: () async {
                  onToggleFav();
                },
                onHideFromHome:
                    hasHide ? () => onHomeHideFromFeed!(property) : null,
                onReport:
                    hasReport ? () => onHomeReportListing!(property) : null,
                onRestoreToHome:
                    homeFeedShowsHiddenOnly && onRestorePropertyToHome != null
                        ? () => onRestorePropertyToHome!(property)
                        : null,
                onWithdrawReport:
                    homeFeedShowsHiddenOnly && onWithdrawPropertyReport != null
                        ? () => onWithdrawPropertyReport!(property)
                        : null,
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _ownerHubPrePublishIdentitySlice(
    BuildContext context,
    ThemeData theme,
    ColorScheme cs,
    double layoutWidth,
  ) {
    final ownerDisp = ownerNameForCard(
      property,
      isAr,
      layoutWidth,
      viewingAsPropertyOwner: true,
      suppressPublicOwnerIdentity: false,
      showFullOwnerLegalNameOnCard: true,
    );
    final ph = (property.ownerPhone ?? '').trim();
    return [
      const SizedBox(height: 4),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: Icon(Icons.person_outline, size: 20, color: bankColor),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isAr ? 'منشئ الطلب' : 'Request creator',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  ownerDisp,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      if (ph.isNotEmpty) ...[
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isAr ? 'جوال منشئ الطلب' : "Creator's mobile",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ph,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              _copyInlineIcon(context, ph),
            ],
          ),
        ),
      ],
    ];
  }

  /// شارة «منشور بواسطة المسوّق» + «متصل الآن» في الرئيسية فقط.
  bool _showHomePublishedByMarketerBadge(bool ownerHubListingCard) {
    if (ownerHubListingCard) return false;
    final pubBy = (property.publishedByMarketerId ?? '').trim();
    if (pubBy.isEmpty) return false;
    if (pubBy == currentUserId.trim()) return false;
    final st = property.effectiveWorkflowStage;
    return st == ListingWorkflowStage.published ||
        st == ListingWorkflowStage.reserved;
  }

  Widget _unifiedListCard(
    BuildContext context, {
    required ThemeData theme,
    required ColorScheme cs,
    required String
        locationText, // ignored — hierarchy via PropertyListingDisplay

    required String? marketerLine,
    required String advertiserName,
    required double baseAmount,
    required Color purposeAccent,
    required Color typeAccent,
    required bool canAddToCart,
    required bool canBidFromCard,
    bool relaxText = false,
    String? ownerPhoneWhenBrokerHidden,
    String peerPresenceId = '',
    required double layoutWidth,
    bool ownerHubListingCard = false,
    Widget? belowMainRow,
    bool omitMarketingLicenseEntries = false,
  }) {
    final borderHint = theme.brightness == Brightness.light
        ? Colors.black.withOpacity(0.15)
        : Colors.white.withOpacity(0.15);
    final listingBorder = Color.lerp(
          PropertyListingDisplay.accentColor(property),
          typeAccent,
          0.28,
        ) ??
        typeAccent;

    final br = property.bedrooms;
    final roomsText = br != null && br > 0 ? (isAr ? '$br غرف' : '$br br') : '';
    final areaVal = property.area;
    final areaText = areaVal > 0
        ? (isAr
            ? '${AppMoney.formatNumber(areaVal, isAr: isAr, maxFractionDigits: 0)} م²'
            : '${AppMoney.formatNumber(areaVal, isAr: isAr, maxFractionDigits: 0)} m²')
        : '';
    final licenseEntries = listingLicenseEntries(property, isAr);
    final ownerPrePublish =
        ownerHubListingCard && isOwner && marketerLine == null;
    // عند وجود جهة تسويق لا نكرّر نفس الاسم تحت «منشئ الإعلان».
    final hideAdvertiserRow = ownerPrePublish ||
        marketerLine != null ||
        (ownerHubListingCard && isOwner && marketerLine != null);

    final compactHome =
        !ownerHubListingCard && layoutWidth > 0 && layoutWidth < 420;
    final gapSm = compactHome ? 2.0 : 4.0;
    // لا نخفي الرخص/الصك على الشاشات الضيقة — نفس بيانات الويب.
    final hideLicenses = omitMarketingLicenseEntries;
    final listingTitle =
        PropertyListingDisplay.displayListingTitle(property, isAr);
    // موقع مختصر (مدينة/حي) — بدون تكرار ما في العنوان.
    final locationParts = PropertyListingDisplay.locationPartsWithoutTitleEcho(
      PropertyListingDisplay.locationHierarchyParts(property),
      listingTitle,
    );
    final locationPin = locationParts.isEmpty
        ? ''
        : locationParts.length <= 2
            ? locationParts.join('، ')
            : locationParts.sublist(locationParts.length - 2).join('، ');
    final extraChips = PropertyListingDisplay.diversifySpecChips(
      property,
      isAr,
      max: 2,
    );

    final dataColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (listingTitle.trim().isNotEmpty)
          Text(
            listingTitle,
            maxLines: 2,
            softWrap: true,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              height: 1.28,
              letterSpacing: -0.15,
              color: theme.brightness == Brightness.dark
                  ? null
                  : const Color(0xFF041D18),
              fontFamily: 'Cairo',
            ),
          ),
        SizedBox(height: gapSm + 1),
        // السعر بارز مباشرة تحت العنوان (أسلوب بطاقة عالمي).
        if (baseAmount > 0)
          AppMoneyLine(
            amount: baseAmount,
            currencyCode: 'SAR',
            isAr: isAr,
            maxFractionDigits: 0,
            symbolColor:
                property.isAuction ? Colors.orange.shade800 : cs.primary,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: property.isAuction ? Colors.orange.shade800 : cs.onSurface,
              fontFamily: 'Cairo',
              fontSize: 18.5,
              height: 1.15,
            ),
          )
        else
          Text(
            isAr ? 'السعر عند الطلب' : 'Price on request',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: cs.onSurfaceVariant,
              fontFamily: 'Cairo',
              fontSize: 13.5,
            ),
          ),
        if (property.isAuction) ...[
          SizedBox(height: gapSm),
          Text(
            isAr ? 'مزايدة علنية' : 'Open auction',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12,
              color: Colors.orange.shade800,
            ),
          ),
        ],
        SizedBox(height: gapSm + 2),
        UnifiedCardSpecRow(
          bankColor: bankColor,
          areaText: areaText,
          roomsText: roomsText,
          locationParts: const [],
          extraChips: extraChips,
        ),
        if (locationPin.isNotEmpty) ...[
          SizedBox(height: gapSm),
          Row(
            children: [
              Icon(Icons.place_outlined, size: 15, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  locationPin,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurfaceVariant,
                    fontFamily: 'Cairo',
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (marketerLine != null) ...[
          SizedBox(height: gapSm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (property.marketerBrandImagePublicUrl != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CachedNetworkImage(
                          imageUrl: property.marketerBrandImagePublicUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Icon(
                            Icons.business_outlined,
                            size: 14,
                            color: bankColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isAr ? 'منشئ الإعلان' : 'Listing publisher',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Cairo',
                          height: 1.05,
                          fontSize: 10.5,
                        ),
                      ),
                      if (marketerRoleCaption(property, isAr)
                          .trim()
                          .isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          marketerRoleCaption(property, isAr),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Cairo',
                            height: 1.05,
                            fontSize: 10,
                          ),
                        ),
                      ],
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              (marketerLine ?? '').trim(),
                              maxLines: 2,
                              softWrap: true,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.start,
                              style: TextStyle(
                                color: theme.brightness == Brightness.dark
                                    ? cs.onSurface
                                    : const Color(0xFF041D18),
                                fontWeight: FontWeight.w900,
                                fontFamily: 'Cairo',
                                fontSize: 13.5,
                                height: 1.25,
                                letterSpacing: -0.1,
                              ),
                            ),
                          ),
                          if (PropertyListingDisplay.showMarketerVerifiedBadge(
                            property,
                          ))
                            const Padding(
                              padding: EdgeInsetsDirectional.only(
                                start: 4,
                                top: 1,
                              ),
                              child: Icon(
                                Icons.verified_rounded,
                                size: 17,
                                color: Color(0xFF10B981),
                              ),
                            ),
                        ],
                      ),
                      if (peerPresenceId.trim().isNotEmpty ||
                          _showHomePublishedByMarketerBadge(
                            ownerHubListingCard,
                          )) ...[
                        const SizedBox(height: 4),
                        UserPresenceStrip(
                          userId: peerPresenceId.trim().isNotEmpty
                              ? peerPresenceId.trim()
                              : (property.publishedByMarketerId ?? '').trim(),
                          isAr: isAr,
                          compact: true,
                          surface: PresenceDisplaySurface.listingCards,
                          fallbackTimestamp:
                              property.publishedAt ?? property.createdAt,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!hideLicenses && licenseEntries.isNotEmpty) ...[
            const SizedBox(height: 4),
            _elegantLicenseCopyGrid(
              context,
              theme: theme,
              cs: cs,
              entries: licenseEntries,
            ),
          ],
        ] else if (!hideLicenses && licenseEntries.isNotEmpty) ...[
          const SizedBox(height: 4),
          _elegantLicenseCopyGrid(
            context,
            theme: theme,
            cs: cs,
            entries: licenseEntries,
          ),
        ] else if (ownerPrePublish) ...[
          ..._ownerHubPrePublishIdentitySlice(context, theme, cs, layoutWidth),
        ],
        if (property.orgListingSnapshot != null &&
            property.orgListingSnapshot!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Builder(
            builder: (ctx) {
              final o = property.orgListingSnapshot!;
              final id = (o['id'] ?? o['org_unit_id'] ?? '').toString().trim();
              final nameAr = (o['display_name_ar'] ?? '').toString().trim();
              final nameEn = (o['display_name_en'] ?? '').toString().trim();
              final name = isAr
                  ? (nameAr.isNotEmpty ? nameAr : nameEn)
                  : (nameEn.isNotEmpty ? nameEn : nameAr);
              final fal = (o['fal_public_code'] ?? '').toString().trim();
              final mc = int.tryParse('${o['member_count']}') ?? 0;
              if (name.isEmpty && fal.isEmpty) {
                return const SizedBox.shrink();
              }
              final t = AppLocalizations.of(ctx);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(Icons.apartment_outlined,
                          size: 16, color: cs.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: InkWell(
                          onTap: id.isEmpty
                              ? null
                              : () {
                                  Navigator.push(
                                    ctx,
                                    MaterialPageRoute<void>(
                                      builder: (_) => OrganizationProfileScreen(
                                        orgId: id,
                                        lang: isAr ? 'ar' : 'en',
                                      ),
                                    ),
                                  );
                                },
                          child: Text(
                            '${t?.orgListingOrgTap ?? 'Org'}: ${name.isEmpty ? '—' : name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: cs.primary,
                            ),
                          ),
                        ),
                      ),
                      if (mc > 0) ...[
                        Icon(Icons.people_outline, size: 14, color: cs.outline),
                        const SizedBox(width: 2),
                        Text(
                          '$mc',
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ],
                  ),
                  if (!omitMarketingLicenseEntries && fal.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    OrgLicenseBadge(code: fal, compact: true),
                  ],
                ],
              );
            },
          ),
        ],
        if (!hideAdvertiserRow && advertiserName.isNotEmpty) ...[
          const SizedBox(height: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isAr ? 'منشئ الإعلان' : 'Listing creator',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  fontSize: 10.5,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      advertiserName,
                      maxLines: 5,
                      softWrap: true,
                      overflow: TextOverflow.visible,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                        fontSize: 13.5,
                        height: 1.3,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
                  if (PropertyListingDisplay.showMarketerVerifiedBadge(
                    property,
                  ))
                    const Padding(
                      padding: EdgeInsetsDirectional.only(start: 4, top: 1),
                      child: Icon(
                        Icons.verified_rounded,
                        size: 16,
                        color: Color(0xFF10B981),
                      ),
                    ),
                ],
              ),
              if (peerPresenceId.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                UserPresenceStrip(
                  userId: peerPresenceId.trim(),
                  isAr: isAr,
                  compact: true,
                  surface: PresenceDisplaySurface.listingCards,
                  fallbackTimestamp: property.publishedAt ?? property.createdAt,
                ),
              ],
            ],
          ),
        ],
        SizedBox(height: gapSm + 2),
        listingCardCreatedPublishedTimes(
          context: context,
          property: property,
          isAr: isAr,
          relaxClamp: relaxText,
          relativeTime: timeAgo,
          compactInline: true,
          style: (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
            color: cs.onSurfaceVariant,
            height: 1.15,
          ),
        ),
      ],
    );

    final Widget? dateBelow = belowMainRow;

    Widget? slotA;
    Widget? slotB;

    if (canAddToCart || canBidFromCard) {
      slotA = ElevatedButton.icon(
        onPressed:
            canAddToCart ? () async => onAddToCart?.call() : onOpenDetails,
        icon: Icon(
            canAddToCart ? Icons.handshake_outlined : Icons.gavel_outlined),
        label: Text(
          canAddToCart
              ? (isAr ? 'إتمام الصفقة' : 'Complete deal')
              : (isAr ? 'المزايدة' : 'Place bid'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor:
              canAddToCart ? const Color(0xFF0B4D3E) : Colors.orange.shade800,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 50),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          elevation: 2,
          shadowColor: const Color(0xFF0B4D3E).withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        ),
      );
    } else if (showListingQuickActions) {
      slotA = OutlinedButton.icon(
        onPressed: onOpenDetails,
        icon: const Icon(Icons.open_in_new, size: 18),
        label: Text(
          isAr ? 'تفاصيل العقار' : 'Property details',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        ),
      );
    }

    Widget? footer;
    final slotAF = slotA;
    final slotBF = slotB;
    if (slotAF != null || slotBF != null) {
      footer = Row(
        children: [
          if (slotAF != null) Expanded(child: slotAF),
          if (slotAF != null && slotBF != null) const SizedBox(width: 8),
          if (slotBF != null) Expanded(child: slotBF),
        ],
      );
    }

    return UnifiedRealEstateCard(
      decoration: _homeFeedCardFaceDecoration(
        cs: cs,
        typeAccent: typeAccent,
        purposeAccent: purposeAccent,
        borderHint: borderHint,
        borderStrong: property.isAuction
            ? listingBorder
            : Color.alphaBlend(
                cs.outlineVariant.withValues(alpha: 0.75),
                borderHint,
              ),
        borderWidth: property.isAuction ? 1.55 : 1.15,
        emphasizePaid: property.isAuction,
      ),
      isAr: isAr,
      kind: UnifiedCardKind.ad,
      onCardTap: onOpenDetails,
      onCardDoubleTap: onToggleFav,
      cardRadius: _kHomeCardRadius,
      fullWidthHeroImage: !_homeListingCardsUseSideBySideLayout(context),
      // جوال/ضيق: صورة علوية بعرض الشاشة ثم البيانات تحتها.
      heroAspectRatio: _homeListingHeroAspectRatio(context),
      dataColumn: dataColumn,
      imageColumn: _imageBlockUnifiedList(
        context,
        canAddToCart: canAddToCart,
        canBidFromCard: canBidFromCard,
      ),
      belowMainRow: dateBelow,
      footer: footer,
    );
  }

  @override
  Widget build(BuildContext context) {
    try {
      return _buildSafe(context);
    } catch (e, st) {
      assert(() {
        // ignore: avoid_print
        print('[DBG][HOME][LISTING_CARD] build failed: $e\n$st');
        return true;
      }());
      final cs = Theme.of(context).colorScheme;
      return Material(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_kHomeCardRadius),
        child: InkWell(
          onTap: onOpenDetails,
          borderRadius: BorderRadius.circular(_kHomeCardRadius),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              property.title.trim().isEmpty
                  ? (isAr ? 'إعلان عقاري' : 'Listing')
                  : property.title.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
              ),
            ),
          ),
        ),
      );
    }
  }

  Widget _buildSafe(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final locationText = locationTextFor(property);
    final marketerLineResolved =
        showRegulatoryIdentityOnCard ? marketerLineFor(property, isAr) : null;
    final ownerPhoneWhenBrokerHidden =
        (!showRegulatoryIdentityOnCard && isOwner)
            ? (property.ownerPhone ?? '').trim()
            : '';
    final purposeAccent = PropertyListingDisplay.accentColor(property);
    final typeKey = property.listingTypeKey.trim().isNotEmpty
        ? property.listingTypeKey
        : property.type.name;
    final typeAccent = PropertyTypeCatalog.accentFor(typeKey);

    final isGuest = currentUserId == 'guest';
    final canAddToCart = ListingPermissionsHelper.canAddToCart(
          property: property,
          currentUserId: isGuest ? null : currentUserId,
          isGuest: isGuest,
          showCartNavSlot: canShowCartButton,
        ) &&
        onAddToCart != null;
    final canBidFromCard = ListingPermissionsHelper.canOpenBidFromHomeCard(
      property: property,
      currentUserId: isGuest ? null : currentUserId,
      isGuest: isGuest,
    );

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final advertiserName = ownerNameForCard(
          property,
          isAr,
          w,
          viewingAsPropertyOwner: isOwner,
          suppressPublicOwnerIdentity: suppressPublicOwnerIdentity,
          showFullOwnerLegalNameOnCard: showFullOwnerLegalNameOnCard,
        );
        final publishedBy = (property.publishedByMarketerId ?? '').trim();
        final ownerUid = property.ownerId.trim();
        final selfUid = isGuest ? '' : currentUserId.trim();
        String peerPresenceId = '';
        if (publishedBy.isNotEmpty && publishedBy != selfUid) {
          peerPresenceId = publishedBy;
        } else if (!isOwner &&
            ownerUid.isNotEmpty &&
            ownerUid != selfUid &&
            publishedBy.isEmpty) {
          peerPresenceId = ownerUid;
        }
        // — الرئيسية (بعد النشر): الأساس + ضريبة 5٪ + أتعاب التسويق على البطاقة.
        // — صفحتي/التبويبات الداخلية: السعر الأساسي فقط؛ التفصيل داخل تفاصيل العرض.
        final rawBase = property.isAuction
            ? (property.currentBid ?? property.price).toDouble()
            : property.price.toDouble();
        final baseAmount = property.isAuction || ownerHubListingCard
            ? rawBase
            : MarketingOfferFee.listingDisplayTotalIncVatAndFee(rawBase);
        return _unifiedListCard(
          context,
          theme: theme,
          cs: cs,
          locationText: locationText,
          marketerLine: marketerLineResolved,
          advertiserName: advertiserName,
          baseAmount: baseAmount,
          purposeAccent: purposeAccent,
          typeAccent: typeAccent,
          canAddToCart: canAddToCart,
          canBidFromCard: canBidFromCard,
          relaxText: relaxTextTruncation,
          ownerPhoneWhenBrokerHidden: ownerPhoneWhenBrokerHidden.isEmpty
              ? null
              : ownerPhoneWhenBrokerHidden,
          peerPresenceId: peerPresenceId,
          layoutWidth: w,
          ownerHubListingCard: ownerHubListingCard,
          belowMainRow: cardBelowMainRow,
          omitMarketingLicenseEntries: omitMarketingLicenseEntriesOnCard,
        );
      },
    );
  }
}

/// شارة على بطاقة الرئيسية: إعلان نُشر عبر مسوّق عقاري (للزوار والمالك).
class _PublishedByMarketerChip extends StatelessWidget {
  const _PublishedByMarketerChip({required this.isAr});
  final bool isAr;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 390;
    final label = narrow
        ? (isAr ? 'مسوّق معتمد' : 'Licensed marketer')
        : (isAr ? 'منشور بواسطة المسوّق' : 'Published by marketer');
    return Material(
      color: Colors.transparent,
      elevation: 4,
      borderRadius: BorderRadius.circular(999),
      shadowColor: Colors.black.withValues(alpha: 0.18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF0F766E),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.88),
            width: 1.1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.campaign_outlined, size: 13, color: Colors.white),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// شارة «منشور» مدمَجة على بطاقات «إعلاناتي/طلباتي» — تأكيد بصري سريع بأنّ
/// هذا الإعلان قد نُشر للجمهور في الرئيسية ويخصّ المستخدم (مالك فرد أو مسوّق نشر).
class _PublishedSelfChip extends StatelessWidget {
  const _PublishedSelfChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 6,
      borderRadius: BorderRadius.circular(999),
      shadowColor: Colors.black.withValues(alpha: 0.2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1B7A3E),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.85), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.public_rounded,
              size: 13,
              color: Colors.white,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.check_circle_rounded,
              size: 13,
              color: Color(0xFFB7F5C7),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeartTapScale extends StatefulWidget {
  const _HeartTapScale({required this.child});

  final Widget child;

  @override
  State<_HeartTapScale> createState() => _HeartTapScaleState();
}

class _HeartTapScaleState extends State<_HeartTapScale> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => setState(() => _scale = 0.9),
      onPointerUp: (_) => setState(() => _scale = 1.0),
      onPointerCancel: (_) => setState(() => _scale = 1.0),
      child: Transform.scale(
        scale: _scale,
        alignment: Alignment.center,
        child: widget.child,
      ),
    );
  }
}

class _PropertyImage extends StatelessWidget {
  final List<String> urls;
  final BoxFit fit;
  final String? videoPathOrUrl;
  final bool isAr;

  /// على الويب، مشغّل الفيديو المضمّن يستهلك أحداث المؤشر فيغطّي الضغط على البطاقة/الأزرار.
  /// في بطاقات القوائم مرّر false لعرض غلاف ثابت بدل المشغّل.
  final bool allowInlineVideo;

  final String? listingIdForWatermark;
  final bool showListingWatermark;

  /// عند true مع عدة صور: نعرض الأولى فقط (بدون PageView/نقاط).
  final bool preferStaticPrimaryImage;

  const _PropertyImage({
    required this.urls,
    this.fit = BoxFit.cover,
    this.videoPathOrUrl,
    this.isAr = true,
    this.allowInlineVideo = true,
    this.listingIdForWatermark,
    this.showListingWatermark = true,
    this.preferStaticPrimaryImage = false,
  });

  static const String _imagesBucket = 'property-images';
  static const String _videosBucket = 'property-videos';

  bool _isUrl(String s) => s.startsWith('http://') || s.startsWith('https://');

  String _normalizeImagePublicUrl(String value) {
    final v = value.trim();
    if (v.isEmpty) return v;

    if (_isUrl(v)) return v;

    return Supabase.instance.client.storage.from(_imagesBucket).getPublicUrl(v);
  }

  String _normalizeVideoPlayableUrl(String value) {
    final v = value.trim();
    if (v.isEmpty) return v;
    if (_isUrl(v)) return v;
    return Supabase.instance.client.storage.from(_videosBucket).getPublicUrl(v);
  }

  String _wmTrace(String? id) {
    final s = (id ?? '').trim();
    if (s.length <= 8) return s;
    return s.substring(s.length - 8);
  }

  Widget _withWatermark(Widget child) {
    if (!showListingWatermark) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        ListingWatermarkOverlay(
          traceId: _wmTrace(listingIdForWatermark),
          isAr: isAr,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget placeholder() => ColoredBox(
          color: cs.surfaceContainerHighest.withOpacity(0.35),
          child: const BrandingLogoImage(
            fillFrame: true,
            filterQuality: FilterQuality.high,
            errorIcon: Icons.image_not_supported_outlined,
          ),
        );

    final vid = (videoPathOrUrl ?? '').trim();
    final wantVideoCover = vid.isNotEmpty;

    if (wantVideoCover && !allowInlineVideo) {
      final playable = _normalizeVideoPlayableUrl(vid);
      if (playable.isEmpty) return placeholder();
      return _withWatermark(
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            unawaited(
              PropertyVideoSheet.open(
                context,
                isAr: isAr,
                title: isAr ? 'فيديو العقار' : 'Property video',
                videoUrl: playable,
              ),
            );
          },
          child: ColoredBox(
            color: cs.surfaceContainerHighest.withOpacity(0.4),
            child: Center(
              child: Icon(
                Icons.play_circle_fill_rounded,
                size: 56,
                color: cs.primary.withOpacity(0.88),
              ),
            ),
          ),
        ),
      );
    }

    if (wantVideoCover && allowInlineVideo) {
      final playable = _normalizeVideoPlayableUrl(vid);
      if (playable.isEmpty) return placeholder();
      return _withWatermark(
        FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: 800,
            height: 450,
            child: InlinePropertyVideoPlayer(
              videoUrl: playable,
              isAr: isAr,
            ),
          ),
        ),
      );
    }

    if (urls.isEmpty) return placeholder();

    final cleanUrls =
        urls.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    if (cleanUrls.isEmpty) return placeholder();

    final normalized = cleanUrls
        .map(_normalizeImagePublicUrl)
        .where((s) => s.isNotEmpty)
        .toList();
    if (normalized.isEmpty) return placeholder();

    final instantFade = preferStaticPrimaryImage;
    Widget oneImage(String imageUrl) => CachedNetworkImage(
          imageUrl: imageUrl,
          fit: fit,
          memCacheWidth: kIsWeb ? 900 : 1400,
          memCacheHeight: kIsWeb ? 650 : 1000,
          fadeInDuration:
              instantFade ? Duration.zero : const Duration(milliseconds: 180),
          placeholder: (context, url) => Container(
            color: cs.surfaceContainerHighest.withOpacity(0.35),
            child: Center(
              child: AppLogoLoading(size: 40, compact: true),
            ),
          ),
          errorWidget: (context, url, error) {
            debugPrint('Property image load error: $error | url=$url');
            return placeholder();
          },
        );

    if (normalized.length == 1 || preferStaticPrimaryImage) {
      return _withWatermark(oneImage(normalized.first));
    }

    return _withWatermark(
      _ListingImagePager(
        urls: normalized,
        buildOne: oneImage,
      ),
    );
  }
}

/// Swipeable gallery + dot indicators for listing cards (home / favorites).
class _ListingImagePager extends StatefulWidget {
  const _ListingImagePager({
    required this.urls,
    required this.buildOne,
  });

  final List<String> urls;
  final Widget Function(String url) buildOne;

  @override
  State<_ListingImagePager> createState() => _ListingImagePagerState();
}

class _ListingImagePagerState extends State<_ListingImagePager> {
  late final PageController _pc;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pc = PageController();
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.urls.length;
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _pc,
          itemCount: n,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (context, i) => widget.buildOne(widget.urls[i]),
        ),
        if (n > 1)
          PositionedDirectional(
            bottom: 8,
            start: 0,
            end: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(n, (i) {
                final on = i == _page;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: on ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: on
                          ? Colors.white.withOpacity(0.95)
                          : Colors.white.withOpacity(0.45),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.35),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color? background;
  final Color? foreground;

  const _Pill({
    required this.text,
    required this.icon,
    this.background,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final bg = background ?? cs.surface.withOpacity(0.92);
    final fg = foreground ?? cs.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      constraints: const BoxConstraints(minHeight: 28),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: cs.outlineVariant.withOpacity(0.45),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w900,
                fontSize: 12,
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// وسام صغير في زاوية الصورة — أخف من الشريط العريض.
class _CornerBadge extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color background;
  final Color foreground;

  const _CornerBadge({
    required this.text,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foreground),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w900,
                fontSize: 11,
                height: 1.05,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =========================
// Search Field (Text + city filter)
// =========================

class _SearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final bool isAr;
  final String nearbyValue;
  final ValueChanged<String> onNearbyChanged;
  final List<String> cityOptions;
  final String Function(String) cityLabel;
  final String Function() nearbyChipText;

  const _SearchField({
    required this.hint,
    required this.onChanged,
    required this.isAr,
    required this.nearbyValue,
    required this.onNearbyChanged,
    required this.cityOptions,
    required this.cityLabel,
    required this.nearbyChipText,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final w = MediaQuery.of(context).size.width;
    final isSmall = w < 600;

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F766E).withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF0F766E).withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.near_me_outlined,
            size: 16,
            color: Color(0xFF0F766E),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              nearbyChipText(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
                fontSize: isSmall ? 12 : 13,
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );

    final dd = DropdownButtonHideUnderline(
      child: Container(
        height: isSmall ? 48 : 52,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: DropdownButton<String>(
          value: cityOptions.contains(nearbyValue) ? nearbyValue : '',
          isExpanded: true,
          isDense: true,
          icon: Icon(Icons.keyboard_arrow_down, color: cs.onSurfaceVariant),
          style: TextStyle(
            fontSize: isSmall ? 14 : 15,
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
          ),
          items: cityOptions
              .map(
                (v) => DropdownMenuItem<String>(
                  value: v,
                  child: Text(
                    cityLabel(v),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            onNearbyChanged(v);
          },
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                blurRadius: 14,
                offset: const Offset(0, 8),
                color: cs.shadow.withOpacity(0.05),
              ),
            ],
          ),
          child: AqarTextField(
            onChanged: onChanged,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: isSmall ? 14 : 16,
            ),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                fontSize: isSmall ? 13 : 15,
              ),
              prefixIcon: Icon(
                Icons.search,
                color: cs.onSurfaceVariant,
                size: isSmall ? 20 : 24,
              ),
              suffixIcon: Icon(
                Icons.travel_explore_outlined,
                color: const Color(0xFF0F766E).withOpacity(0.80),
                size: isSmall ? 20 : 22,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xFF0F766E),
                  width: 1.6,
                ),
              ),
              isDense: true,
              filled: true,
              fillColor: cs.surfaceContainerHighest.withOpacity(0.35),
              contentPadding: isSmall
                  ? const EdgeInsets.symmetric(vertical: 12, horizontal: 12)
                  : const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            ),
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, c) {
            final ww = c.maxWidth;
            final tight = ww < 520;

            if (tight) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment:
                        isAr ? Alignment.centerRight : Alignment.centerLeft,
                    child: chip,
                  ),
                  const SizedBox(height: 10),
                  dd,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: dd),
                const SizedBox(width: 10),
                Flexible(child: chip),
              ],
            );
          },
        ),
      ],
    );
  }
}

// =========================
// Sort Menu
// =========================

/// قسم البحث الجغرافي الهرمي + اختصار «خريطة» داخل ورقة «البحث المتقدّم».
/// يظهر القيم المختارة كشرائح (Chips) قابلة للنقر لإعادة تشغيل المختار، مع زر
/// مسح كامل وزر فتح الخريطة لاستكشاف الإعلانات/الطلبات بإحداثياتها.
class _AdvSearchLocationSection extends StatelessWidget {
  const _AdvSearchLocationSection({
    required this.isAr,
    required this.brandPrimary,
    required this.region,
    required this.governorate,
    required this.city,
    required this.district,
    required this.onPickLocation,
    required this.onClearLocation,
    required this.onOpenMap,
  });

  final bool isAr;
  final Color brandPrimary;
  final String region;
  final String governorate;
  final String city;
  final String district;
  final VoidCallback onPickLocation;
  final VoidCallback onClearLocation;
  final VoidCallback onOpenMap;

  bool get _anySelected =>
      region.isNotEmpty ||
      governorate.isNotEmpty ||
      city.isNotEmpty ||
      district.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chips = <_AdvLocChipData>[
      if (region.isNotEmpty)
        _AdvLocChipData(
          label: isAr ? 'المنطقة' : 'Region',
          value: region,
          icon: Icons.public_outlined,
        ),
      if (governorate.isNotEmpty)
        _AdvLocChipData(
          label: isAr ? 'المحافظة' : 'Governorate',
          value: governorate,
          icon: Icons.account_balance_outlined,
        ),
      if (city.isNotEmpty)
        _AdvLocChipData(
          label: isAr ? 'المدينة' : 'City',
          value: city,
          icon: Icons.location_city_outlined,
        ),
      if (district.isNotEmpty)
        _AdvLocChipData(
          label: isAr ? 'الحيّ' : 'District',
          value: district,
          icon: Icons.holiday_village_outlined,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.travel_explore_outlined, color: brandPrimary, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                isAr ? 'الموقع الجغرافي' : 'Geographic location',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
            if (_anySelected)
              TextButton.icon(
                onPressed: onClearLocation,
                icon: const Icon(Icons.close, size: 16),
                label: Text(isAr ? 'مسح' : 'Clear'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Material(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.32),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: onPickLocation,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: brandPrimary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.map_outlined,
                      color: brandPrimary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _anySelected
                              ? (isAr
                                  ? 'حدّد البحث بالمنطقة/المحافظة/المدينة/الحي'
                                  : 'Region / Governorate / City / District')
                              : (isAr
                                  ? 'ابحث بالمنطقة ثم المحافظة ثم المدينة ثم الحيّ'
                                  : 'Drill down: Region → Governorate → City → District'),
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (chips.isEmpty)
                          Text(
                            isAr
                                ? 'لم يتم تحديد موقع — اضغط للاختيار التدرّجي.'
                                : 'No location chosen — tap to browse hierarchically.',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        else
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: chips
                                .map(
                                  (c) => _AdvLocChip(
                                    data: c,
                                    color: brandPrimary,
                                  ),
                                )
                                .toList(),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isAr
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                    color: cs.outline,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(
                    color: brandPrimary.withValues(alpha: 0.55),
                  ),
                  foregroundColor: brandPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: onOpenMap,
                icon: const Icon(Icons.map_rounded),
                label: Text(
                  isAr ? 'البحث في الخريطة' : 'Search on map',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AdvLocChipData {
  const _AdvLocChipData({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;
}

class _AdvLocChip extends StatelessWidget {
  const _AdvLocChip({required this.data, required this.color});

  final _AdvLocChipData data;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(data.icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            '${data.label}: ',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          Text(
            data.value,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _SortMenu extends StatelessWidget {
  final bool isAr;
  final String value;
  final ValueChanged<String> onChanged;

  /// صف أدوات ضيّق (مثل صف «صفحتي» بجانب البحث على الويب).
  final bool compactToolbar;

  const _SortMenu({
    required this.isAr,
    required this.value,
    required this.onChanged,
    this.compactToolbar = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSmall = MediaQuery.of(context).size.width < 600;

    final double barHeight = compactToolbar ? 44 : (isSmall ? 48 : 52);
    final double fontSz = compactToolbar ? 13 : (isSmall ? 14 : 16);

    return DropdownButtonHideUnderline(
      child: Container(
        height: barHeight,
        padding: EdgeInsets.symmetric(horizontal: compactToolbar ? 8 : 10),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          isDense: true,
          style: TextStyle(
            fontSize: fontSz,
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
          ),
          items: [
            DropdownMenuItem(
              value: 'latest',
              child: Text(
                isAr ? 'الأحدث' : 'Latest',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DropdownMenuItem(
              value: 'nearest',
              child: Text(
                isAr ? 'الأقرب' : 'Nearest',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DropdownMenuItem(
              value: 'price_low',
              child: Text(
                isAr ? 'السعر: الأقل' : 'Price: Low',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DropdownMenuItem(
              value: 'price_high',
              child: Text(
                isAr ? 'السعر: الأعلى' : 'Price: High',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DropdownMenuItem(
              value: 'area_high',
              child: Text(
                isAr ? 'المساحة: الأكبر' : 'Area: High',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DropdownMenuItem(
              value: 'most_viewed',
              child: Text(
                isAr ? 'الأكثر مشاهدة' : 'Most viewed',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
