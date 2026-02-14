part of 'user_dashboard.dart';

// === ملف: user_dashboard.widgets.dart ===
// الهدف: Widgets مساعدة خاصة بالـ Dashboard (بطاقات/شبكات/حقول بحث/شرائح/أزرار).
// يحتوي: عناصر UI قابلة لإعادة الاستخدام ولا تعتمد على State الداخلي مباشرة.

// =========================
// Widgets
// =========================

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
          IconButton(
            onPressed: onPressed,
            icon: Icon(icon, color: cs.onSurface),
          ),
          if (badge > 0)
            PositionedDirectional(
              end: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: cs.surface, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 10,
                      offset: const Offset(0, 6),
                      color: Colors.black.withOpacity(0.12),
                    )
                  ],
                ),
                child: Text(
                  badge > 99 ? '99+' : '$badge',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
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
        Icon(icon, color: cs.onSurface),
        if (badge > 0)
          PositionedDirectional(
            end: -6,
            top: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: cs.surface, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 10,
                    offset: const Offset(0, 6),
                    color: Colors.black.withOpacity(0.12),
                  )
                ],
              ),
              child: Text(
                badge > 99 ? '99+' : '$badge',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
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

class _MiniChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color bankColor;

  const _MiniChip({
    required this.icon,
    required this.text,
    required this.bankColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bankColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: bankColor.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: bankColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
                height: 1.0,
              ),
            ),
          ),
        ],
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

  const _ReservationCard({
    required this.bankColor,
    required this.icon,
    required this.title,
    required this.chips,
    required this.priceTable,
    required this.primaryAction,
    required this.secondaryAction,
    required this.thirdAction,
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
          return Expanded(
            child: OutlinedButton.icon(
              onPressed: a.onPressed,
              icon: Icon(a.icon, size: 18),
              label: label,
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          );

        case _ReservationActionKind.filledDanger:
          return Expanded(
            child: ElevatedButton.icon(
              onPressed: a.onPressed,
              icon: Icon(a.icon, size: 18),
              label: label,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          );
      }
    }

    final actions = <Widget>[];
    if (primaryAction != null) actions.add(buildAction(primaryAction!));
    if (secondaryAction != null) {
      if (actions.isNotEmpty) actions.add(const SizedBox(width: 10));
      actions.add(buildAction(secondaryAction!));
    }
    if (thirdAction != null) {
      if (actions.isNotEmpty) actions.add(const SizedBox(width: 10));
      actions.add(buildAction(thirdAction!));
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: cs.surface,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 10),
            color: cs.shadow.withOpacity(0.08),
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
                color: bankColor.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
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
                      color: cs.surfaceContainerHighest.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: cs.outlineVariant.withOpacity(0.45)),
                    ),
                    child: priceTable,
                  ),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, c) {
                        final w = c.maxWidth;

                        if (w < 520 && actions.length >= 2) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              actions[0],
                              const SizedBox(height: 10),
                              if (actions.length > 2) ...[
                                actions[1],
                                const SizedBox(height: 10),
                                actions[2],
                              ] else
                                actions[1],
                            ],
                          );
                        }

                        return Row(children: actions);
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

  final bool Function(String propertyId) isReserved;
  final DateTime? Function(String propertyId) reservedUntil;
  final String? Function(String propertyId) reservedByName;

  final Future<void> Function(Property p) onAddToCart;

  final bool showEditDelete;
  final Future<void> Function(Property p) onEditProperty;
  final Future<void> Function(String propertyId) onDeleteProperty;

  const _PropertyGrid({
    required this.items,
    required this.currentUserId,
    required this.isAr,
    required this.bankColor,
    required this.isFav,
    required this.onToggleFav,
    required this.onOpenDetails,
    required this.isReserved,
    required this.reservedUntil,
    required this.reservedByName,
    required this.onAddToCart,
    required this.showEditDelete,
    required this.onEditProperty,
    required this.onDeleteProperty,
  });

  int _crossAxisCount(double w) {
    if (w < 720) return 1;
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
		  final cross = _crossAxisCount(w);
		  final paddingH = w >= 900 ? 18.0 : 12.0;
		  const spacing = 12.0;

		  final cardW = (w - (paddingH * 2) - (spacing * (cross - 1))) / cross;

		  final horizontalCard = cardW >= 320;
		  final aspect = horizontalCard
			  ? (cross == 1 ? 1.9 : 1.35)
			  : (cross == 1 ? 0.82 : 0.72);

		  return GridView.builder(
			shrinkWrap: true,
			physics: const NeverScrollableScrollPhysics(),
			padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: 12),
			gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
			  crossAxisCount: cross,
			  mainAxisSpacing: spacing,
			  crossAxisSpacing: spacing,
			  childAspectRatio: aspect,
			),
			itemCount: items.length,
			itemBuilder: (context, i) {
			  final p = items[i];
			  final isOwner = p.ownerId == currentUserId;
			  final isGuest = currentUserId == 'guest';

			  return _RealEstateCard(
				property: p,
				isOwner: isOwner,
				isAr: isAr,
				bankColor: bankColor,
				favorite: !isGuest && isFav(p.id),
				onToggleFav: isGuest ? () {} : () => onToggleFav(p.id),
				onOpenDetails: () => onOpenDetails(p),
				isReserved: isReserved(p.id),
				reservedUntil: reservedUntil(p.id),
				reservedByName: reservedByName(p.id),
				onAddToCart: (isGuest || isOwner) ? null : () => onAddToCart(p),
				currentUserId: currentUserId,
				showEditDelete: showEditDelete && isOwner,
				onEditProperty: () => onEditProperty(p),
				onDeleteProperty: () => onDeleteProperty(p.id),
			  );
			},
		  );
		},
	  );
	}
  }


// =========================
// Featured Property Card
// =========================

class _FeaturedPropertyCard extends StatelessWidget {
  final Property property;
  final bool isOwner;
  final bool isAr;
  final Color bankColor;

  final bool favorite;
  final VoidCallback onToggleFav;
  final VoidCallback onOpenDetails;

  final bool isReserved;
  final DateTime? reservedUntil;
  final String? reservedByName;

  final Future<void> Function()? onAddToCart;
  final String currentUserId;

  const _FeaturedPropertyCard({
    required this.property,
    required this.isOwner,
    required this.isAr,
    required this.bankColor,
    required this.favorite,
    required this.onToggleFav,
    required this.onOpenDetails,
    required this.isReserved,
    required this.reservedUntil,
    required this.reservedByName,
    required this.onAddToCart,
    required this.currentUserId,
  });

  String _fmt(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.amber.withOpacity(0.3), width: 2),
        boxShadow: [
          BoxShadow(
            blurRadius: 20,
            offset: const Offset(0, 8),
            color: Colors.amber.withOpacity(0.15),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: cs.surface,
          child: InkWell(
            onTap: onOpenDetails,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    SizedBox(
                      height: 160,
                      width: double.infinity,
                      child: _PropertyImage(urls: property.images),
                    ),
                    PositionedDirectional(
                      top: 10,
                      start: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star,
                                size: 14, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              isAr ? 'مميز' : 'Featured',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                height: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      top: 10,
                      end: 10,
                      child: GestureDetector(
                        onTap: onToggleFav,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            favorite ? Icons.favorite : Icons.favorite_border,
                            color: favorite ? Colors.red : Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        property.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined,
                              size: 14, color: cs.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              property.location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              isAr
                                  ? '${property.area.toStringAsFixed(0)} م²'
                                  : '${property.area.toStringAsFixed(0)} m²',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${_RealEstateCard._money(property.price)} ${isAr ? 'ر.س' : 'SAR'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: bankColor,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (!isOwner && onAddToCart != null && !isReserved)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => onAddToCart!(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: bankColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: Text(
                              isAr ? 'إضافة للسلة' : 'Add to Cart',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      if (isReserved && reservedUntil != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            isAr
                                ? 'محجوز حتى: ${_fmt(reservedUntil!)}'
                                : 'Reserved until: ${_fmt(reservedUntil!)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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

  final bool isReserved;
  final DateTime? reservedUntil;
  final String? reservedByName;

  final Future<void> Function()? onAddToCart;
  final String currentUserId;

  final bool showEditDelete;
  final VoidCallback? onEditProperty;
  final VoidCallback? onDeleteProperty;

  const _RealEstateCard({
    required this.property,
    required this.isOwner,
    required this.isAr,
    required this.bankColor,
    required this.favorite,
    required this.onToggleFav,
    required this.onOpenDetails,
    required this.isReserved,
    required this.reservedUntil,
    required this.reservedByName,
    required this.onAddToCart,
    required this.currentUserId,
    this.showEditDelete = false,
    this.onEditProperty,
    this.onDeleteProperty,
  });

  String _fmt(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _imageBlock(BuildContext context, {required bool horizontal}) {
    final cs = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: horizontal
          ? const BorderRadiusDirectional.horizontal(
              start: Radius.circular(18),
              end: Radius.circular(0),
            )
          : const BorderRadius.vertical(top: Radius.circular(18)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _PropertyImage(urls: property.images),
          if (property.isAuction)
            PositionedDirectional(
              top: 10,
              end: 10,
              child: _Pill(
                text: isAr ? 'مزاد' : 'Auction',
                icon: Icons.gavel_outlined,
                background: Colors.orange.withOpacity(0.95),
                foreground: Colors.white,
              ),
            ),
          PositionedDirectional(
            bottom: 10,
            end: 10,
            child: _Pill(
              text: '${property.views}',
              icon: Icons.remove_red_eye_outlined,
              background: Colors.black.withOpacity(0.45),
              foreground: Colors.white,
            ),
          ),
          if (isReserved)
            PositionedDirectional(
              bottom: 10,
              start: 10,
              child: _Pill(
                text: isAr ? 'محجوز' : 'Reserved',
                icon: Icons.lock_clock_outlined,
                background: Colors.red.withOpacity(0.86),
                foreground: Colors.white,
              ),
            ),
          PositionedDirectional(
            top: 10,
            start: 10,
            child: Opacity(
              opacity: currentUserId == 'guest' ? 0.5 : 1,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: currentUserId == 'guest' ? null : onToggleFav,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withOpacity(0.25)),
                    ),
                    child: Icon(
                      favorite ? Icons.favorite : Icons.favorite_border,
                      color: favorite ? Colors.redAccent : Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (showEditDelete &&
              (onEditProperty != null || onDeleteProperty != null))
            PositionedDirectional(
              top: 10,
              end: 50,
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
                                color: Colors.white.withOpacity(0.25)),
                          ),
                          child: const Icon(Icons.edit,
                              color: Colors.white, size: 18),
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
                            color: Colors.red.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.25)),
                          ),
                          child: const Icon(Icons.delete,
                              color: Colors.white, size: 18),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final timeText = _timeAgo(property.createdAt, isAr);

    final reservedChipText = () {
      final ex = reservedUntil;
      final until = ex == null ? '' : _fmt(ex);
      if (isOwner) {
        final who = (reservedByName ?? '').trim();
        if (who.isNotEmpty) {
          return isAr
              ? 'محجوز بواسطة: $who • حتى $until'
              : 'Reserved by: $who • until $until';
        }
        return isAr ? 'محجوز • حتى $until' : 'Reserved • until $until';
      }
      return isAr ? 'محجوز • حتى $until' : 'Reserved • until $until';
    }();

    final borderColor = theme.brightness == Brightness.light
        ? Colors.black.withOpacity(0.15)
        : Colors.white.withOpacity(0.15);

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final horizontal = w >= 320;
        final imageW = horizontal ? (w < 380 ? 130.0 : 160.0) : null;

        Widget content() {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  property.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  property.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                if (isReserved)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.red.withOpacity(0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_clock_outlined,
                            size: 16, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            reservedChipText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined,
                        size: 16, color: bankColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        property.location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.straighten_outlined, size: 16, color: bankColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        isAr
                            ? '${property.area.toStringAsFixed(0)} م²'
                            : '${property.area.toStringAsFixed(0)} m²',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        property.isAuction
                            ? (isAr
                                ? '${_money(property.currentBid ?? 0)} ر.س'
                                : '${_money(property.currentBid ?? 0)} SAR')
                            : (isAr
                                ? '${_money(property.price)} ر.س'
                                : '${_money(property.price)} SAR'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color:
                              property.isAuction ? Colors.orange : Colors.green,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 18),
                Row(
                  children: [
                    Text(
                      timeText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const Spacer(),
                  ],
                ),
                if (!isOwner && onAddToCart != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed:
                            isReserved ? null : () async => onAddToCart?.call(),
                        icon: const Icon(Icons.add_shopping_cart),
                        label: Text(
                          isAr
                              ? 'إضافة للسلة 72 ساعة'
                              : 'Reserve in cart (72h)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: bankColor,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              cs.surfaceContainerHighest.withOpacity(0.55),
                          disabledForegroundColor: cs.onSurfaceVariant,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onOpenDetails,
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                    color: cs.shadow.withOpacity(0.10),
                  )
                ],
              ),
              child: horizontal
                  ? Row(
                      children: [
                        SizedBox(
                          width: imageW!,
                          child: _imageBlock(context, horizontal: true),
                        ),
                        Expanded(child: content()),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                            child: _imageBlock(context, horizontal: false)),
                        content(),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  static String _money(double v) {
    final s = v.toStringAsFixed(0);
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final fromEnd = s.length - i;
      b.write(s[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) b.write(',');
    }
    return b.toString();
  }

  static String _timeAgo(DateTime dt, bool isAr) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes <= 1 ? 1 : diff.inMinutes;
      return isAr ? 'قبل $m دقيقة' : '$m min ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours <= 1 ? 1 : diff.inHours;
      return isAr ? 'قبل $h ساعة' : '$h hours ago';
    }
    final d = diff.inDays <= 1 ? 1 : diff.inDays;
    return isAr ? 'قبل $d يوم' : '$d days ago';
  }
}

class _PropertyImage extends StatelessWidget {
  final List<String> urls;
  const _PropertyImage({required this.urls});

  bool _isUrl(String s) => s.startsWith('http://') || s.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (urls.isEmpty) {
      return Container(
        color: cs.surfaceContainerHighest.withOpacity(0.55),
        child: const Center(child: Icon(Icons.image_not_supported_outlined)),
      );
    }

    final first = urls.first.trim();
    if (first.isEmpty) {
      return Container(
        color: cs.surfaceContainerHighest.withOpacity(0.55),
        child: const Center(child: Icon(Icons.image_not_supported_outlined)),
      );
    }

    if (_isUrl(first)) {
      return Image.network(
        first,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: cs.surfaceContainerHighest.withOpacity(0.55),
          child: const Center(child: Icon(Icons.image_not_supported_outlined)),
        ),
      );
    }

    return Image.asset(
      first,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: cs.surfaceContainerHighest.withOpacity(0.55),
        child: const Center(child: Icon(Icons.image_not_supported_outlined)),
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
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
        ],
      ),
    );
  }
}

// =========================
// Search Field (Text + "Nearby" city filter)
// =========================

class _SearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;

  final bool isAr;
  final String nearbyValue;
  final ValueChanged<String> onNearbyChanged;

  const _SearchField({
    required this.hint,
    required this.onChanged,
    required this.isAr,
    required this.nearbyValue,
    required this.onNearbyChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final w = MediaQuery.of(context).size.width;
    final isSmall = w < 600;

    final nearbyOptions = <String>[
      '',
      'riyadh',
      'jeddah',
      'makkah',
      'madinah',
      'dammam',
      'khobar',
      'taif',
      'tabuk',
      'abha',
      'hail',
      'qassim',
      'jazan',
      'najran',
      'al jubail',
      'yanbu',
    ];

    String labelFor(String v) {
      if (v.isEmpty) return isAr ? 'الكل' : 'All';
      final t = v.trim();
      if (t.isEmpty) return isAr ? 'الكل' : 'All';
      return t[0].toUpperCase() + t.substring(1);
    }

    final chipText = nearbyValue.isEmpty
        ? (isAr ? 'الإعلانات القريبة' : 'Nearby listings')
        : (isAr
            ? 'قريب: ${labelFor(nearbyValue)}'
            : 'Nearby: ${labelFor(nearbyValue)}');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          onChanged: onChanged,
          style: TextStyle(
              fontWeight: FontWeight.w900, fontSize: isSmall ? 14 : 16),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              fontSize: isSmall ? 13 : 15,
            ),
            prefixIcon: Icon(Icons.search,
                color: cs.onSurfaceVariant, size: isSmall ? 20 : 24),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: Color(0xFF0F766E), width: 1.6),
            ),
            isDense: true,
            filled: true,
            fillColor: cs.surfaceContainerHighest.withOpacity(0.35),
            contentPadding: isSmall
                ? const EdgeInsets.symmetric(vertical: 12, horizontal: 12)
                : const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, c) {
            final ww = c.maxWidth;
            final tight = ww < 520;

            final chip = Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F766E).withOpacity(0.08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: const Color(0xFF0F766E).withOpacity(0.18)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.near_me_outlined,
                      size: 16, color: Color(0xFF0F766E)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      chipText,
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
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: DropdownButton<String>(
                  value: nearbyOptions.contains(nearbyValue) ? nearbyValue : '',
                  isDense: true,
                  icon: Icon(Icons.keyboard_arrow_down,
                      color: cs.onSurfaceVariant),
                  style: TextStyle(
                    fontSize: isSmall ? 14 : 15,
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                  items: nearbyOptions
                      .map(
                        (v) => DropdownMenuItem<String>(
                          value: v,
                          child: Text(
                            labelFor(v),
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
                chip,
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

  const _SortMenu({
    required this.isAr,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSmall = MediaQuery.of(context).size.width < 600;

    return DropdownButtonHideUnderline(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          style: TextStyle(
            fontSize: isSmall ? 14 : 16,
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
          ),
          items: [
            DropdownMenuItem(
              value: 'latest',
              child: Text(isAr ? 'الأحدث' : 'Latest',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            DropdownMenuItem(
              value: 'price_low',
              child: Text(isAr ? 'السعر: الأقل' : 'Price: Low',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            DropdownMenuItem(
              value: 'price_high',
              child: Text(isAr ? 'السعر: الأعلى' : 'Price: High',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            DropdownMenuItem(
              value: 'area_high',
              child: Text(isAr ? 'المساحة: الأكبر' : 'Area: High',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
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
