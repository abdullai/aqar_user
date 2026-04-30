part of 'user_dashboard.dart';

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

/// زوايا بطاقات الرئيسية — مظهر حديث (تطبيقات 2024+).
const double _kHomeCardRadius = 20;

BoxDecoration _homeFeedCardFaceDecoration({
  required ColorScheme cs,
  required Color typeAccent,
  required Color purposeAccent,
  required Color borderHint,
  Color? borderStrong,
  double borderWidth = 1.25,
  List<BoxShadow>? boxShadow,
}) {
  final borderColor = borderStrong ??
      Color.alphaBlend(
        Color.alphaBlend(
          typeAccent.withOpacity(0.32),
          purposeAccent.withOpacity(0.2),
        ),
        borderHint,
      );
  return BoxDecoration(
    color: Color.alphaBlend(
      typeAccent.withOpacity(0.06),
      Color.alphaBlend(purposeAccent.withOpacity(0.05), cs.surface),
    ),
    borderRadius: BorderRadius.circular(_kHomeCardRadius),
    border: Border.all(
      color: borderColor,
      width: borderWidth,
    ),
    boxShadow: boxShadow ??
        [
          BoxShadow(
            color: cs.shadow.withOpacity(0.08),
            blurRadius: 32,
            offset: const Offset(0, 14),
            spreadRadius: -8,
          ),
        ],
  );
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
                  color: color.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(icon, color: cs.onSurface),
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

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          child: Icon(icon, color: cs.onSurface),
        ),
        if (badge > 0)
          PositionedDirectional(
            end: -8,
            top: -7,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
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
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: Icon(icon, color: c),
        ),
        if (showDot)
          PositionedDirectional(
            end: -4,
            top: -4,
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
                          label: isAr ? 'تقديم عرض' : 'Make offer',
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
        gradient: LinearGradient(
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
                          if (actionWidgets.length <= 2) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (int i = 0;
                                    i < actionWidgets.length;
                                    i++) ...[
                                  actionWidgets[i],
                                  if (i != actionWidgets.length - 1)
                                    const SizedBox(height: 10),
                                ],
                              ],
                            );
                          }
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final w in actionWidgets)
                                SizedBox(
                                  width: (c.maxWidth - 8) / 2,
                                  child: w,
                                ),
                            ],
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

// =========================
// Mixed home timeline (إعلانات + طلبات — الأحدث أولاً)
// =========================

class _HomeMixedTimeline extends StatelessWidget {
  const _HomeMixedTimeline({
    required this.entries,
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
    this.onShareListingFromCard,
    this.onHomeHideFromFeed,
    this.onHomeReportListing,
    this.onHomeHideMarketRequest,
    this.onHomeReportMarketRequest,
    this.onEditMarketRequest,
    this.homeFeedShowsHiddenOnly = false,
    this.onRestorePropertyToHome,
    this.onWithdrawPropertyReport,
    this.onRestoreMarketRequest,
  });

  final List<HomeMixedFeedEntry> entries;
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
  final Future<void> Function(Property p)? onShareListingFromCard;

  final Future<void> Function(Property p)? onHomeHideFromFeed;
  final Future<void> Function(Property p)? onHomeReportListing;
  final Future<void> Function(MarketPropertyRequestRow r)?
      onHomeHideMarketRequest;
  final Future<void> Function(MarketPropertyRequestRow r)?
      onHomeReportMarketRequest;
  final Future<void> Function(MarketPropertyRequestRow r)? onEditMarketRequest;

  final bool homeFeedShowsHiddenOnly;
  final Future<void> Function(Property p)? onRestorePropertyToHome;
  final Future<void> Function(Property p)? onWithdrawPropertyReport;
  final Future<void> Function(MarketPropertyRequestRow r)?
      onRestoreMarketRequest;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
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
        cards.add(
          _RealEstateCard(
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
            forceListLayout: true,
            canShowCartButton: canShowCartButton,
            onViewsPillTap: onPropertyViewsInteraction == null
                ? null
                : (ctx) => onPropertyViewsInteraction!(ctx, p, isOwner),
            showListingQuickActions: true,
            onCopyListingWebLink: onCopyListingWebLink,
            suppressPublicOwnerIdentity: suppressPublicOwnerIdentityOnCards,
            onShareListingFromCard: onShareListingFromCard == null
                ? null
                : () => onShareListingFromCard!(p),
            onHomeHideFromFeed: onHomeHideFromFeed,
            onHomeReportListing: onHomeReportListing,
            homeFeedShowsHiddenOnly: homeFeedShowsHiddenOnly,
            onRestorePropertyToHome: onRestorePropertyToHome,
            onWithdrawPropertyReport: onWithdrawPropertyReport,
          ),
        );
        continue;
      }
      final r = e.request;
      if (r == null) continue;
      cards.add(
        _MarketRequestListingStyleCard(
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
          homeFeedShowsHiddenOnly: homeFeedShowsHiddenOnly,
          onRestoreMarketRequest: onRestoreMarketRequest,
          onHomeHideMarketRequest: onHomeHideMarketRequest,
          onHomeReportMarketRequest: onHomeReportMarketRequest,
          onEditMarketRequest: onEditMarketRequest,
        ),
      );
    }

    Widget narrowColumn() {
      final tiles = <Widget>[];
      for (var i = 0; i < cards.length; i++) {
        if (i > 0) tiles.add(const SizedBox(height: 12));
        tiles.add(cards[i]);
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: tiles,
      );
    }

    Widget wideGrid() {
      final rows = <Widget>[];
      for (var i = 0; i < cards.length; i += 2) {
        if (i > 0) rows.add(const SizedBox(height: 12));
        final a = cards[i];
        final b = i + 1 < cards.length ? cards[i + 1] : null;
        // بدون IntrinsicHeight — على الويب يفسد ارتفاع الصف ويسبب تداخل البطاقات ويعطل التمرير.
        rows.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: a),
              const SizedBox(width: 12),
              Expanded(child: b ?? const SizedBox.shrink()),
            ],
          ),
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 720;
          if (!wide || cards.length <= 1) {
            return narrowColumn();
          }
          return wideGrid();
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

  static String _requestListingLabel(MarketPropertyRequestRow r) {
    final c = DisplayIds.tenDigit(r.requestPublicCode ?? r.id);
    if (c.isNotEmpty) return c;
    final t = r.id.trim();
    if (t.length <= 10) return t;
    return '…${t.substring(t.length - 8)}';
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
    return IconButton(
      tooltip: isAr ? 'نسخ' : 'Copy',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      padding: EdgeInsets.zero,
      iconSize: 16,
      icon: const Icon(Icons.copy_rounded),
      onPressed: () => unawaited(_copyValue(context, value, isAr)),
    );
  }

  static String _areaSpec(MarketPropertyRequestRow r, bool isAr) {
    if (r.areaMinM2 == null) return '';
    final v = AppMoney.formatNumber(
      r.areaMinM2!,
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
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w900,
          color: color,
          height: 1.1,
        );
    if (min == null && max == null) {
      return Text(
        isAr ? 'الميزانية غير محددة' : 'Budget not set',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    Widget amount(double v) => AppMoneyLine(
          amount: v,
          currencyCode: 'SAR',
          isAr: isAr,
          maxFractionDigits: 0,
          symbolColor: color,
          style: style,
        );

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isAr ? 'الميزانية: ' : 'Budget: ',
            style: style,
            maxLines: 1,
          ),
          if (min != null) amount(min),
          if (min != null && max != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('-', style: style, maxLines: 1),
            ),
          if (max != null && max != min) amount(max),
        ],
      ),
    );
  }

  /// إخفاء القائمة عند عدم توفر إجراءات (حسب حالة الطلب في الخادم).
  static bool _showOverflowMenuForStatus(
    MarketPropertyRequestRow r, {
    required bool loggedIn,
    required bool baseShowMenu,
  }) {
    if (!loggedIn || !baseShowMenu) return false;
    final st = r.status.trim().toLowerCase();
    if (st == 'closed' || st == 'cancelled' || st == 'canceled') {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
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
                onHomeReportMarketRequest != null));
    final showMenu = _showOverflowMenuForStatus(
      r,
      loggedIn: loggedIn || !homeFeedShowsHiddenOnly,
      baseShowMenu: baseShowMenu,
    );
    final canSubmitOffer = !homeFeedShowsHiddenOnly &&
        !requestCompleted &&
        !deletionRequested &&
        (currentUserId == 'guest' || currentUserId != r.requesterId);
    final isRequester = currentUserId != 'guest' && currentUserId == r.requesterId;
    String wmTail(String id) {
      final s = id.trim();
      if (s.length <= 8) return s;
      return s.substring(s.length - 8);
    }

    final purposeShort = r.purpose == 'rent'
        ? (isAr ? 'إيجار' : 'Rent')
        : (isAr ? 'شراء' : 'Buy');
    final purposeChip = r.purpose == 'rent'
        ? (isAr ? 'إيجار' : 'Rent')
        : (isAr ? 'شراء' : 'Purchase');
    final metaLine =
        '${PropertyTypeCatalog.label(r.propertyType, isAr)} · $purposeShort · $priorityLabel';

    final dataColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          r.title.trim().isEmpty
              ? (isAr ? 'طلب عقاري' : 'Property request')
              : r.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w900,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          metaLine,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: purposeAccent,
          ),
        ),
        const SizedBox(height: 3),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: purposeAccent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: purposeAccent.withValues(alpha: 0.28)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              child: Text(
                purposeChip,
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
          districtText: _districtSpec(r),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.payments_outlined, size: 17, color: bankColor),
            const SizedBox(width: 6),
            Expanded(child: _budgetLine(context, r, isAr, purposeAccent)),
          ],
        ),
        if (r.showRequesterName &&
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
                      imageUrl: r.requesterAvatarUrl!.trim(),
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
                child: Text(
                  isAr
                      ? 'منشئ الطلب: ${(r.requesterPublicName ?? '').trim()}'
                      : 'Request creator: ${(r.requesterPublicName ?? '').trim()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Text(
                isAr
                    ? 'رقم الطلب: ${_requestListingLabel(r)}'
                    : 'Request no.: ${_requestListingLabel(r)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.primary,
                ),
              ),
            ),
            _copyIcon(context, _requestListingLabel(r), isAr),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          isAr ? 'تاريخ ووقت الإنشاء' : 'Created date and time',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 1),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            '${ListingDateDisplay.formatCardDateTime(r.sortTime, isAr: isAr)} • ${timeAgo(r.sortTime, isAr)}',
            maxLines: 1,
            softWrap: false,
            style: theme.textTheme.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );

    final requestFooter = LayoutBuilder(
      builder: (context, c) {
        final mainAction = canSubmitOffer
            ? ElevatedButton.icon(
              onPressed: onSubmitOffer ?? onOpen,
              icon: const Icon(Icons.local_offer_outlined, size: 18),
              label: Text(
                isAr ? 'تقديم عرض' : 'Submit offer',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: bankColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
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
                  borderRadius: BorderRadius.circular(14),
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
        if (editAction == null) return SizedBox(width: double.infinity, child: mainAction);
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

    PopupMenuItem<String> requestMenuItem({
      required String value,
      required IconData icon,
      required String label,
      required Color color,
    }) {
      return PopupMenuItem<String>(
        value: value,
        height: 48,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 190),
          child: Row(
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final imageStack = Stack(
      fit: StackFit.expand,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final side = c.maxHeight.isFinite ? c.maxHeight : c.maxWidth;
            return MarketRequestLeadThumb(
              storagePath: r.coverImageStoragePath,
              width: side,
              height: side,
              borderRadius: 0,
            );
          },
        ),
        ListingWatermarkOverlay(
          traceId: wmTail(r.id),
          isAr: isAr,
          headline: isAr ? 'طلب عقاري' : 'Property request',
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withOpacity(0.5),
                Colors.transparent,
              ],
            ),
          ),
        ),
        if (showMenu)
          PositionedDirectional(
            top: 8,
            end: 8,
            child: Material(
              color: Colors.black.withOpacity(0.45),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                iconSize: 20,
                icon:
                    const Icon(Icons.more_vert, color: Colors.white, size: 20),
                color: cs.surface,
                elevation: 2,
                onSelected: (v) {
                  if (v == 'restore') {
                    unawaited(onRestoreMarketRequest!(r));
                  } else if (v == 'hide') {
                    unawaited(onHomeHideMarketRequest!(r));
                  } else if (v == 'report') {
                    unawaited(onHomeReportMarketRequest!(r));
                  }
                },
                itemBuilder: (ctx) => [
                  if (homeFeedShowsHiddenOnly && onRestoreMarketRequest != null)
                    requestMenuItem(
                      value: 'restore',
                      icon: Icons.visibility_rounded,
                      label: isAr ? 'إظهار في الرئيسية' : 'Show on home',
                      color: cs.primary,
                    )
                  else ...[
                    if (onHomeHideMarketRequest != null)
                      requestMenuItem(
                        value: 'hide',
                        icon: Icons.visibility_off_outlined,
                        label: isAr ? 'إخفاء من الرئيسية' : 'Hide from home',
                        color: cs.onSurface,
                      ),
                    if (onHomeReportMarketRequest != null)
                      requestMenuItem(
                        value: 'report',
                        icon: Icons.flag_outlined,
                        label: isAr ? 'إبلاغ' : 'Report',
                        color: cs.error,
                      ),
                  ],
                ],
              ),
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
        borderStrong: _marketRequestBorderAccent(r, cs, purposeAccent),
        borderWidth: 1.38,
      ),
      isAr: isAr,
      kind: UnifiedCardKind.request,
      onCardTap: onOpen,
      cardRadius: _kHomeCardRadius,
      dataColumn: dataColumn,
      imageColumn: imageStack,
      footer: requestFooter,
    );
  }
}

// =========================
// Property Grid / Cards
// =========================

class _PropertyGrid extends StatelessWidget {
  final List<Property> items;
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
  final Future<void> Function(Property p)? onShareListingFromCard;

  final Future<void> Function(Property p)? onHomeHideFromFeed;
  final Future<void> Function(Property p)? onHomeReportListing;

  final bool homeFeedShowsHiddenOnly;
  final Future<void> Function(Property p)? onRestorePropertyToHome;
  final Future<void> Function(Property p)? onWithdrawPropertyReport;

  const _PropertyGrid({
    required this.items,
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
    this.onShareListingFromCard,
    this.onHomeHideFromFeed,
    this.onHomeReportListing,
    this.homeFeedShowsHiddenOnly = false,
    this.onRestorePropertyToHome,
    this.onWithdrawPropertyReport,
  });

  int _crossAxisCount(double w) {
    if (w < 600) return 1;
    if (w < 980) return 2;
    if (w < 1250) return 3;
    if (w < 1550) return 4;
    return 5;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final paddingH = w >= 900 ? 18.0 : 12.0;
        // ضيق العرض (ويب أو تطبيق): عمود واحد؛ عرض أوسع: شبكة تتكيّف بعدد الأعمدة.
        final isPhone = w < 600;

        if (isPhone) {
          final tiles = <Widget>[];
          for (var i = 0; i < items.length; i++) {
            if (i > 0) tiles.add(const SizedBox(height: 12));
            final p = items[i];
            final isOwner = p.ownerId == currentUserId;
            final isGuest = currentUserId == 'guest';
            final allowCart = ListingPermissionsHelper.canAddToCart(
              property: p,
              currentUserId: isGuest ? null : currentUserId,
              isGuest: isGuest,
              showCartNavSlot: canShowCartButton,
            );

            tiles.add(
              _RealEstateCard(
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
                forceListLayout: true,
                canShowCartButton: canShowCartButton,
                onViewsPillTap: onPropertyViewsInteraction == null
                    ? null
                    : (ctx) => onPropertyViewsInteraction!(ctx, p, isOwner),
                showListingQuickActions: showListingQuickActions,
                onCopyListingWebLink: onCopyListingWebLink,
                suppressPublicOwnerIdentity: suppressPublicOwnerIdentityOnCards,
                onShareListingFromCard: onShareListingFromCard == null
                    ? null
                    : () => onShareListingFromCard!(p),
                onHomeHideFromFeed: onHomeHideFromFeed,
                onHomeReportListing: onHomeReportListing,
                homeFeedShowsHiddenOnly: homeFeedShowsHiddenOnly,
                onRestorePropertyToHome: onRestorePropertyToHome,
                onWithdrawPropertyReport: onWithdrawPropertyReport,
              ),
            );
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

        Widget cardFor(Property p) {
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
            forceListLayout: false,
            canShowCartButton: canShowCartButton,
            onViewsPillTap: onPropertyViewsInteraction == null
                ? null
                : (ctx) => onPropertyViewsInteraction!(ctx, p, isOwner),
            showListingQuickActions: showListingQuickActions,
            onCopyListingWebLink: onCopyListingWebLink,
            suppressPublicOwnerIdentity: suppressPublicOwnerIdentityOnCards,
            onShareListingFromCard: onShareListingFromCard == null
                ? null
                : () => onShareListingFromCard!(p),
            onHomeHideFromFeed: onHomeHideFromFeed,
            onHomeReportListing: onHomeReportListing,
            homeFeedShowsHiddenOnly: homeFeedShowsHiddenOnly,
            onRestorePropertyToHome: onRestorePropertyToHome,
            onWithdrawPropertyReport: onWithdrawPropertyReport,
          );
        }

        // بدون GridView بنسبة ارتفاع ثابتة (كانت تُفرغ أسفل البطاقة على الويب)
        final rowChildren = <Widget>[];
        for (var start = 0; start < items.length; start += cross) {
          if (rowChildren.isNotEmpty) {
            rowChildren.add(SizedBox(height: spacing));
          }
          final end =
              start + cross > items.length ? items.length : start + cross;
          final chunk = items.sublist(start, end);
          rowChildren.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = 0; j < cross; j++) ...[
                  if (j > 0) SizedBox(width: spacing),
                  Expanded(
                    child: j < chunk.length
                        ? cardFor(chunk[j])
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
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
  final bool forceListLayout;
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
    this.forceListLayout = false,
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
    return IconButton(
      tooltip: isAr ? 'نسخ' : 'Copy',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      padding: EdgeInsets.zero,
      iconSize: 16,
      icon: const Icon(Icons.copy_rounded),
      onPressed: () => unawaited(_copyValue(context, value)),
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
    return isAr ? 'مسوق عقاري معتمد' : 'Licensed real estate marketer';
  }

  static List<Map<String, String>> listingLicenseEntries(
    Property p,
    bool isAr,
  ) {
    final snap = p.marketingLicenseSnapshot;
    if (snap == null || snap.isEmpty) return const [];

    String pick(List<String> keys) {
      for (final key in keys) {
        final value = (snap[key] ?? '').toString().trim();
        if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
      }
      return '';
    }

    final adLicense = pick(const [
      'rega_ad_license_number',
      'ad_license_number',
      'advertisement_license_number',
      'advertising_license_number',
      'license_number',
    ]);
    final falLicense = pick(const [
      'fal_broker_license_number',
      'fal_license_number',
      'broker_license_number',
      'brokerage_license_number',
    ]);

    return [
      if (falLicense.isNotEmpty)
        {
          'label': isAr ? 'رقم رخصة فال' : 'FAL license no.',
          'value': falLicense,
        },
      if (adLicense.isNotEmpty)
        {
          'label': isAr ? 'رقم إعلان الهيئة' : 'REGA ad no.',
          'value': adLicense,
        },
    ];
  }

  static List<String> listingLicenseLines(Property p, bool isAr) {
    return listingLicenseEntries(p, isAr)
        .map((e) => '${e['label']}: ${e['value']}')
        .toList(growable: false);
  }

  /// وقت إنشاء الإعلان من المالك، ووقت النشر عند توفره (من جهة التسويق).
  static Widget listingCardCreatedPublishedTimes({
    required Property property,
    required bool isAr,
    required TextStyle style,
    bool relaxClamp = false,
    String Function(DateTime, bool)? relativeTime,
  }) {
    final createdAt = property.createdAt;
    final abs = ListingDateDisplay.formatCardDateTime(
      createdAt,
      isAr: isAr,
    );
    final rel = relativeTime?.call(createdAt, isAr).trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          isAr ? 'تاريخ ووقت الإنشاء' : 'Created date and time',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            rel.isEmpty ? abs : '$abs • $rel',
            maxLines: 1,
            softWrap: false,
            style: style.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ],
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
          urls: property.images,
          fit: BoxFit.cover,
          videoPathOrUrl: property.videoUrl,
          isAr: isAr,
          allowInlineVideo: !kIsWeb,
          listingIdForWatermark: property.id,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withOpacity(0.14),
                Colors.transparent,
              ],
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
                onToggleFavorite: loggedIn && !isOwner
                    ? () async {
                        onToggleFav();
                      }
                    : null,
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

  Widget _imageBlock(
    BuildContext context, {
    required bool horizontal,
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

    return ClipRRect(
      borderRadius: horizontal
          ? const BorderRadiusDirectional.horizontal(
              start: Radius.circular(_kHomeCardRadius),
              end: Radius.circular(0),
            )
          : const BorderRadius.vertical(top: Radius.circular(_kHomeCardRadius)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _PropertyImage(
            urls: property.images,
            fit: BoxFit.cover,
            videoPathOrUrl: property.videoUrl,
            isAr: isAr,
            allowInlineVideo: !kIsWeb,
            listingIdForWatermark: property.id,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withOpacity(0.14),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          PositionedDirectional(
            top: 8,
            end: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showListingOverflowMenu)
                  ListingPublicActionsMenuButton(
                    property: property,
                    colorScheme: cs,
                    homeFeedShowsHiddenOnly: homeFeedShowsHiddenOnly,
                    onCopyLink:
                        hasCopy ? () => onCopyListingWebLink!(property) : null,
                    onShare: hasShare ? () => onShareListingFromCard!() : null,
                    onShowViews: onViewsPillTap == null
                        ? null
                        : () async => onViewsPillTap!(context),
                    onToggleFavorite: loggedIn && !isOwner
                        ? () async {
                            onToggleFav();
                          }
                        : null,
                    onHideFromHome:
                        hasHide ? () => onHomeHideFromFeed!(property) : null,
                    onReport:
                        hasReport ? () => onHomeReportListing!(property) : null,
                    onRestoreToHome: homeFeedShowsHiddenOnly &&
                            onRestorePropertyToHome != null
                        ? () => onRestorePropertyToHome!(property)
                        : null,
                    onWithdrawReport: homeFeedShowsHiddenOnly &&
                            onWithdrawPropertyReport != null
                        ? () => onWithdrawPropertyReport!(property)
                        : null,
                  ),
              ],
            ),
          ),
          if (showEditDelete &&
              (onEditProperty != null || onDeleteProperty != null))
            PositionedDirectional(
              top: 8,
              start: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onEditProperty != null)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: onEditProperty,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.25),
                            ),
                          ),
                          child: const Icon(
                            Icons.edit,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  if (onDeleteProperty != null)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: onDeleteProperty,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: cs.error.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.25),
                            ),
                          ),
                          child: Icon(
                            Icons.delete,
                            color: cs.onError,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.0)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaChip({
    required IconData icon,
    required String text,
    Color? color,
  }) {
    return _MiniChip(
      icon: icon,
      text: text,
      color: color ?? bankColor,
    );
  }

  Widget _unifiedListCard(
    BuildContext context, {
    required ThemeData theme,
    required ColorScheme cs,
    required String locationText,
    required String? marketerLine,
    required String advertiserName,
    required double baseAmount,
    required Color purposeAccent,
    required Color typeAccent,
    required bool canAddToCart,
    required bool canBidFromCard,
    bool relaxText = false,
  }) {
    final borderColor = theme.brightness == Brightness.light
        ? Colors.black.withOpacity(0.15)
        : Colors.white.withOpacity(0.15);
    final listingBorder = Color.lerp(
      PropertyListingDisplay.accentColor(property),
      typeAccent,
      0.28,
    )!;

    final br = property.bedrooms;
    final roomsText = br != null ? (isAr ? '$br غرف' : '$br br') : '';
    final areaValue = AppMoney.formatNumber(
      property.area,
      isAr: isAr,
      maxFractionDigits: 0,
    );
    final areaText = isAr ? '$areaValue م²' : '$areaValue m²';
    final licenseEntries = listingLicenseEntries(property, isAr);

    final int? textCap = relaxText ? null : 1;
    final overflow = relaxText ? TextOverflow.visible : TextOverflow.ellipsis;

    final dataColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (property.title.trim().isNotEmpty)
          Text(
            property.title,
            maxLines: textCap,
            overflow: overflow,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1.15,
            ),
          ),
        if (property.title.trim().isNotEmpty) const SizedBox(height: 3),
        if (property.isAuction) ...[
          const SizedBox(height: 4),
          Text(
            isAr ? 'مزايدة علنية' : 'Open auction',
            maxLines: textCap,
            overflow: overflow,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12,
              color: Colors.orange.shade800,
            ),
          ),
        ],
        const SizedBox(height: 6),
        UnifiedCardSpecRow(
          bankColor: bankColor,
          areaText: areaText,
          roomsText: roomsText,
          districtText: locationText,
        ),
        if (marketerLine != null) ...[
          const SizedBox(height: 6),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              mainAxisSize: MainAxisSize.max,
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
                Flexible(
                  child: Text(
                    isAr
                        ? 'الوسيط العقاري: $marketerLine'
                        : 'Real estate broker: $marketerLine',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (licenseEntries.isNotEmpty) ...[
            const SizedBox(height: 4),
            for (final entry in licenseEntries.take(2))
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${entry['label']}: ${entry['value']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                    ),
                    _copyInlineIcon(context, entry['value'] ?? ''),
                  ],
                ),
              ),
          ],
        ],
        if (advertiserName.isNotEmpty) ...[
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              isAr ? 'المعلن: $advertiserName' : 'Advertiser: $advertiserName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.start,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.payments_outlined,
              size: 17,
              color:
                  property.isAuction ? Colors.orange.shade800 : purposeAccent,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: AppMoneyLine(
                amount: baseAmount,
                currencyCode: 'SAR',
                isAr: isAr,
                maxFractionDigits: 0,
                symbolColor:
                    property.isAuction ? Colors.orange.shade800 : purposeAccent,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: property.isAuction
                      ? Colors.orange.shade800
                      : purposeAccent,
                  fontSize: 15,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
        if ((property.listingPublicCode ?? property.id).trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  isAr
                      ? 'رقم الإعلان: ${DisplayIds.tenDigit(property.listingPublicCode ?? property.id)}'
                      : 'Listing no.: ${DisplayIds.tenDigit(property.listingPublicCode ?? property.id)}',
                  maxLines: textCap,
                  overflow: overflow,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                  ),
                ),
              ),
              _copyInlineIcon(
                context,
                DisplayIds.tenDigit(property.listingPublicCode ?? property.id),
              ),
            ],
          ),
        ],
        const SizedBox(height: 3),
        listingCardCreatedPublishedTimes(
          property: property,
          isAr: isAr,
          relaxClamp: relaxText,
          relativeTime: timeAgo,
          style: (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
            color: cs.onSurfaceVariant,
            height: 1.15,
          ),
        ),
      ],
    );

    Widget? slotA;
    Widget? slotB;

    if (canAddToCart || canBidFromCard) {
      slotA = ElevatedButton.icon(
        onPressed:
            canAddToCart ? () async => onAddToCart?.call() : onOpenDetails,
        icon: Icon(
            canAddToCart ? Icons.local_offer_outlined : Icons.gavel_outlined),
        label: Text(
          canAddToCart
              ? (isAr ? 'تقديم عرض' : 'Submit offer')
              : (isAr ? 'المزايدة' : 'Place bid'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: canAddToCart ? bankColor : Colors.orange.shade800,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(vertical: 10),
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
          padding: const EdgeInsets.symmetric(vertical: 10),
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
        borderHint: borderColor,
        borderStrong: listingBorder,
        borderWidth: property.isAuction ? 1.55 : 1.35,
      ),
      isAr: isAr,
      kind: UnifiedCardKind.ad,
      onCardTap: onOpenDetails,
      cardRadius: _kHomeCardRadius,
      dataColumn: dataColumn,
      imageColumn: _imageBlockUnifiedList(
        context,
        canAddToCart: canAddToCart,
        canBidFromCard: canBidFromCard,
      ),
      footer: footer,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final locationText = locationTextFor(property);
    final marketerLine = marketerLineFor(property, isAr);
    final licenseEntries = listingLicenseEntries(property, isAr);
    final borderColor = theme.brightness == Brightness.light
        ? Colors.black.withOpacity(0.15)
        : Colors.white.withOpacity(0.15);
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
        final listLike = forceListLayout;

        if (listLike) {
          final advertiserName = ownerNameForCard(
            property,
            isAr,
            w,
            viewingAsPropertyOwner: isOwner,
            suppressPublicOwnerIdentity: suppressPublicOwnerIdentity,
            showFullOwnerLegalNameOnCard: showFullOwnerLegalNameOnCard,
          );
          final baseAmount = property.isAuction
              ? (property.currentBid ?? property.price).toDouble()
              : property.price.toDouble();
          return _unifiedListCard(
            context,
            theme: theme,
            cs: cs,
            locationText: locationText,
            marketerLine: marketerLine,
            advertiserName: advertiserName,
            baseAmount: baseAmount,
            purposeAccent: purposeAccent,
            typeAccent: typeAccent,
            canAddToCart: canAddToCart,
            canBidFromCard: canBidFromCard,
            relaxText: relaxTextTruncation,
          );
        }

        // ✅ في وضع الـ Grid نجعل البطاقة عمودية دائمًا
        // حتى لا ينضغط أسفل البطاقة ويختفي زر السلة
        final horizontal = listLike;
        final imageW =
            horizontal ? (listLike ? 146.0 : (w < 380 ? 132.0 : 180.0)) : null;
        final imageH = listLike ? 178.0 : null;
        final advertiserName = ownerNameForCard(
          property,
          isAr,
          w,
          viewingAsPropertyOwner: isOwner,
          suppressPublicOwnerIdentity: suppressPublicOwnerIdentity,
          showFullOwnerLegalNameOnCard: showFullOwnerLegalNameOnCard,
        );
        final peerPresenceId = !isOwner && !isGuest
            ? ((property.publishedByMarketerId ?? '').trim().isNotEmpty
                ? (property.publishedByMarketerId!).trim()
                : property.ownerId.trim())
            : '';
        final baseAmount = property.isAuction
            ? (property.currentBid ?? property.price).toDouble()
            : property.price.toDouble();

        Widget content() {
          final relax = relaxTextTruncation;
          final int? cap = relax ? null : 2;
          final int? capId = relax ? null : 1;
          final overflow = relax ? TextOverflow.visible : TextOverflow.ellipsis;

          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (marketerLine != null) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (property.marketerBrandImagePublicUrl != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 36,
                            height: 36,
                            child: CachedNetworkImage(
                              imageUrl: property.marketerBrandImagePublicUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Icon(
                                Icons.business_outlined,
                                size: 18,
                                color: bankColor,
                              ),
                            ),
                          ),
                        ),
                      ] else
                        Icon(
                          Icons.business_outlined,
                          size: 18,
                          color: bankColor,
                        ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                isAr
                                    ? 'الوسيط العقاري: $marketerLine'
                                    : 'Real estate broker: $marketerLine',
                                maxLines: cap,
                                overflow: overflow,
                                style: TextStyle(
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.w800,
                                  height: 1.25,
                                ),
                              ),
                            ),
                            if (PropertyListingDisplay
                                .showMarketerVerifiedBadge(
                              property,
                            ))
                              Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  start: 4,
                                  top: 1,
                                ),
                                child: Icon(
                                  Icons.verified_rounded,
                                  size: 17,
                                  color: purposeAccent,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (licenseEntries.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    for (final entry in licenseEntries.take(2))
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${entry['label']}: ${entry['value']}',
                              maxLines: capId,
                              overflow: overflow,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: cs.onSurfaceVariant,
                                height: 1.15,
                              ),
                            ),
                          ),
                          _copyInlineIcon(context, entry['value'] ?? ''),
                        ],
                      ),
                  ],
                  const SizedBox(height: 10),
                ],
                if (!relax &&
                    peerPresenceId.isNotEmpty &&
                    peerPresenceId != currentUserId) ...[
                  UserPresenceStrip(userId: peerPresenceId, isAr: isAr),
                  const SizedBox(height: 10),
                ],
                if (property.title.trim().isNotEmpty) ...[
                  Text(
                    property.title,
                    maxLines: cap,
                    overflow: overflow,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (property.isAuction) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(
                        Colors.orange.withValues(
                          alpha:
                              theme.brightness == Brightness.dark ? 0.22 : 0.12,
                        ),
                        cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.orange.shade800.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.gavel_rounded,
                          size: 22,
                          color: Colors.orange.shade800,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isAr ? 'مزايدة علنية' : 'Open auction',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if ((property.listingPublicCode ?? property.id)
                    .trim()
                    .isNotEmpty) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          isAr
                              ? 'رقم الإعلان: ${DisplayIds.tenDigit(property.listingPublicCode ?? property.id)}'
                              : 'Listing no.: ${DisplayIds.tenDigit(property.listingPublicCode ?? property.id)}',
                          maxLines: capId,
                          overflow: overflow,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: cs.primary,
                          ),
                        ),
                      ),
                      _copyInlineIcon(
                        context,
                        DisplayIds.tenDigit(
                          property.listingPublicCode ?? property.id,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 10),
                _InfoLine(
                  icon: Icons.location_on_outlined,
                  text: locationText,
                  isAr: isAr,
                  valueColor: cs.onSurface,
                  iconColor: bankColor,
                  maxLines: cap,
                ),
                if (advertiserName.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _InfoLine(
                    icon: Icons.person_outline,
                    text: isAr
                        ? 'المعلن: $advertiserName'
                        : 'Advertiser: $advertiserName',
                    isAr: isAr,
                    valueColor: cs.onSurface,
                    iconColor: bankColor,
                    maxLines: cap,
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _metaChip(
                      icon: PropertyListingDisplay.areaIcon(property),
                      text: isAr
                          ? '${AppMoney.formatNumber(property.area, isAr: isAr, maxFractionDigits: 0)} م²'
                          : '${AppMoney.formatNumber(property.area, isAr: isAr, maxFractionDigits: 0)} m²',
                    ),
                    for (final u in PropertyListingDisplay.usageBadgeTuples(
                      property,
                      isAr,
                    ))
                      _metaChip(
                        icon: u.$1,
                        text: '${u.$2} ✓',
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: listingCardCreatedPublishedTimes(
                        property: property,
                        isAr: isAr,
                        relaxClamp: relax,
                        relativeTime: timeAgo,
                        style: (theme.textTheme.bodySmall ?? const TextStyle())
                            .copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      flex: 2,
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerEnd,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: (w * 0.52).clamp(120.0, 280.0),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.payments_outlined,
                                      size: 17,
                                      color: property.isAuction
                                          ? Colors.orange.shade800
                                          : purposeAccent,
                                    ),
                                    const SizedBox(width: 4),
                                    AppMoneyLine(
                                      amount: baseAmount,
                                      currencyCode: 'SAR',
                                      isAr: isAr,
                                      maxFractionDigits: 0,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                                fontWeight: FontWeight.w900,
                                                color: property.isAuction
                                                    ? Colors.orange.shade800
                                                    : purposeAccent,
                                                fontSize: 14,
                                                height: 1.1,
                                              ) ??
                                              TextStyle(
                                                fontWeight: FontWeight.w900,
                                                color: property.isAuction
                                                    ? Colors.orange.shade800
                                                    : purposeAccent,
                                                fontSize: 14,
                                                height: 1.1,
                                              ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (canAddToCart || canBidFromCard)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: canAddToCart
                            ? () async => onAddToCart?.call()
                            : onOpenDetails,
                        icon: Icon(
                          canAddToCart
                              ? Icons.local_offer_outlined
                              : Icons.gavel_outlined,
                        ),
                        label: Text(
                          canAddToCart
                              ? (isAr ? 'تقديم عرض' : 'Submit offer')
                              : (isAr ? 'المزايدة' : 'Place bid'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              canAddToCart ? bankColor : Colors.orange.shade800,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                if (showListingQuickActions) ...[
                  Padding(
                    padding: EdgeInsets.only(
                      top: (canAddToCart || canBidFromCard) ? 10 : 12,
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: onOpenDetails,
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: Text(
                            isAr ? 'تفاصيل العقار' : 'Property details',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        final listingBorder = Color.lerp(
          PropertyListingDisplay.accentColor(property),
          typeAccent,
          0.28,
        )!;
        return RepaintBoundary(
          child: _WebHoverListingShell(
            child: Container(
              decoration: _homeFeedCardFaceDecoration(
                cs: cs,
                typeAccent: typeAccent,
                purposeAccent: purposeAccent,
                borderHint: borderColor,
                borderStrong: listingBorder,
                borderWidth: property.isAuction ? 1.55 : 1.35,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(_kHomeCardRadius),
                  mouseCursor: SystemMouseCursors.click,
                  onTap: onOpenDetails,
                  child: horizontal
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: imageW!,
                              height: imageH,
                              child: _imageBlock(context, horizontal: true),
                            ),
                            Expanded(child: content()),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AspectRatio(
                              aspectRatio: kIsWeb ? 1.22 : 1.38,
                              child: _imageBlock(context, horizontal: false),
                            ),
                            content(),
                          ],
                        ),
                ),
              ),
            ),
          ),
        );
      },
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

/// Web: subtle hover scale on listing cards (keeps mobile path unchanged).
class _WebHoverListingShell extends StatefulWidget {
  const _WebHoverListingShell({required this.child});

  final Widget child;

  @override
  State<_WebHoverListingShell> createState() => _WebHoverListingShellState();
}

class _WebHoverListingShellState extends State<_WebHoverListingShell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return widget.child;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.004 : 1.0,
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool isAr;
  final Color? valueColor;
  final Color? iconColor;

  /// عند null تُعرض السطور كاملة دون قص (مثل تبويب «صفحتي»).
  final int? maxLines;

  const _InfoLine({
    required this.icon,
    required this.text,
    required this.isAr,
    this.valueColor,
    this.iconColor,
    this.maxLines = 2,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 16,
          color: iconColor ?? cs.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: maxLines,
            overflow:
                maxLines == null ? TextOverflow.visible : TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor ?? cs.onSurface,
              fontSize: 12.8,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
            textAlign: isAr ? TextAlign.right : TextAlign.left,
          ),
        ),
      ],
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

  const _PropertyImage({
    required this.urls,
    this.fit = BoxFit.cover,
    this.videoPathOrUrl,
    this.isAr = true,
    this.allowInlineVideo = true,
    this.listingIdForWatermark,
    this.showListingWatermark = true,
  });

  static const String _imagesBucket = 'property-images';
  static const String _videosBucket = 'property-videos';
  static const String _fallbackAsset = 'assets/logo.png';

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

    Widget placeholder() => Container(
          color: cs.surfaceContainerHighest.withOpacity(0.55),
          padding: const EdgeInsets.all(18),
          child: Center(
            child: Image.asset(
              _fallbackAsset,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) => Icon(
                Icons.image_not_supported_outlined,
                color: cs.primary,
              ),
            ),
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

    Widget oneImage(String imageUrl) => CachedNetworkImage(
          imageUrl: imageUrl,
          fit: fit,
          memCacheWidth: kIsWeb ? 900 : 1400,
          memCacheHeight: kIsWeb ? 650 : 1000,
          fadeInDuration: const Duration(milliseconds: 180),
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

    if (normalized.length == 1) {
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
          child: TextField(
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
