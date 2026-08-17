import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/property.dart';
import '../services/user_listing_preferences_service.dart';

/// زر ⋮ للإعلانات العامة: مشاركة، إخفاء/إظهار، بلاغ/سحب بلاغ — أحجام تتبع عرض الشاشة.
class ListingPublicActionsMenuButton extends StatefulWidget {
  const ListingPublicActionsMenuButton({
    super.key,
    required this.property,
    required this.colorScheme,
    this.homeFeedShowsHiddenOnly = false,
    this.useAppBarStyle = false,
    this.onCopyLink,
    this.onShare,
    this.onShowViews,
    this.onToggleFavorite,
    this.onHideFromHome,
    this.onReport,
    this.onRestoreToHome,
    this.onWithdrawReport,
  });

  final Property property;
  final ColorScheme colorScheme;
  final bool homeFeedShowsHiddenOnly;

  /// شريط التطبيق: أيقونة عادية بدون خلفية داكنة على الصورة.
  final bool useAppBarStyle;

  /// نسخ رابط الإعلان إلى الحافظة (مثلاً من بطاقة الرئيسية).
  final Future<void> Function()? onCopyLink;

  final Future<void> Function()? onShare;
  final Future<void> Function()? onShowViews;

  /// إضافة/إزالة من المفضلة (يُعرض كـ «الأفضل» في العربية عند الحاجة).
  final Future<void> Function()? onToggleFavorite;

  final Future<void> Function()? onHideFromHome;
  final Future<void> Function()? onReport;
  final Future<void> Function()? onRestoreToHome;
  final Future<void> Function()? onWithdrawReport;

  @override
  State<ListingPublicActionsMenuButton> createState() =>
      _ListingPublicActionsMenuButtonState();
}

class _ListingPublicActionsMenuButtonState
    extends State<ListingPublicActionsMenuButton> {
  bool _pendingReport = false;
  final GlobalKey _anchorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    unawaited(_refreshPending());
  }

  @override
  void didUpdateWidget(covariant ListingPublicActionsMenuButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.property.id != widget.property.id ||
        oldWidget.homeFeedShowsHiddenOnly != widget.homeFeedShowsHiddenOnly) {
      unawaited(_refreshPending());
    }
  }

  Future<void> _refreshPending() async {
    final v = await UserListingPreferencesService.hasPendingPropertyReport(
      widget.property.id,
    );
    if (mounted) setState(() => _pendingReport = v);
  }

  double _iconSize(BuildContext context) {
    return 20;
  }

  double _pad(BuildContext context) {
    return 8;
  }

  Future<void> _openMenu() async {
    await _refreshPending();
    if (!mounted) return;

    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;
    final isAr = Directionality.of(context) == TextDirection.rtl;

    final iconSz = _iconSize(context);
    final anchorCtx = _anchorKey.currentContext;
    final rect = RelativeRect.fromRect(
      _MenuAnchorRect.getRect(anchorCtx ?? context),
      Offset.zero & MediaQuery.sizeOf(context),
    );

    final items = <PopupMenuEntry<String>>[];
    if (widget.onCopyLink != null) {
      items.add(
        PopupMenuItem<String>(
          value: 'copy',
          child: _MenuRow(
            icon: Icons.link_rounded,
            label: l10n.listingPublicCopyLink,
            iconSize: iconSz,
            colorScheme: widget.colorScheme,
          ),
        ),
      );
    }
    if (widget.onShare != null) {
      items.add(
        PopupMenuItem<String>(
          value: 'share',
          child: _MenuRow(
            icon: Icons.share_rounded,
            label: l10n.listingPublicShareLink,
            iconSize: iconSz,
            colorScheme: widget.colorScheme,
          ),
        ),
      );
    }
    if (widget.onShowViews != null) {
      items.add(
        PopupMenuItem<String>(
          value: 'views',
          child: _MenuRow(
            icon: Icons.remove_red_eye_outlined,
            label: isAr ? 'المشاهدات' : 'Views',
            iconSize: iconSz,
            colorScheme: widget.colorScheme,
          ),
        ),
      );
    }
    if (widget.onToggleFavorite != null) {
      items.add(
        PopupMenuItem<String>(
          value: 'favorite',
          child: _MenuRow(
            icon: Icons.favorite_rounded,
            label: l10n.listingPublicToggleBest,
            iconSize: iconSz,
            colorScheme: widget.colorScheme,
          ),
        ),
      );
    }
    if (widget.homeFeedShowsHiddenOnly) {
      if (widget.onRestoreToHome != null) {
        items.add(
          PopupMenuItem<String>(
            value: 'restore',
            child: _MenuRow(
              icon: Icons.visibility_rounded,
              label: l10n.listingPublicShowOnHome,
              iconSize: iconSz,
              colorScheme: widget.colorScheme,
            ),
          ),
        );
      }
      if (_pendingReport && widget.onWithdrawReport != null) {
        items.add(
          PopupMenuItem<String>(
            value: 'withdraw',
            child: _MenuRow(
              icon: Icons.undo_rounded,
              label: l10n.listingPublicWithdrawPendingReport,
              iconSize: iconSz,
              colorScheme: widget.colorScheme,
            ),
          ),
        );
      }
    } else {
      if (widget.onHideFromHome != null) {
        items.add(
          PopupMenuItem<String>(
            value: 'hide',
            child: _MenuRow(
              icon: Icons.visibility_off_outlined,
              label: l10n.listingPublicHideFromHome,
              iconSize: iconSz,
              colorScheme: widget.colorScheme,
            ),
          ),
        );
      }
      if (widget.onReport != null) {
        items.add(
          PopupMenuItem<String>(
            value: 'report',
            child: _MenuRow(
              icon: Icons.flag_outlined,
              label: l10n.listingPublicReport,
              iconSize: iconSz,
              colorScheme: widget.colorScheme,
              foreground: widget.colorScheme.error,
            ),
          ),
        );
      }
    }

    if (items.isEmpty) return;

    final choice = await showMenu<String>(
      context: context,
      position: rect,
      items: items,
    );

    if (!mounted) return;
    switch (choice) {
      case 'copy':
        if (widget.onCopyLink != null) await widget.onCopyLink!();
        break;
      case 'share':
        if (widget.onShare != null) await widget.onShare!();
        break;
      case 'views':
        if (widget.onShowViews != null) await widget.onShowViews!();
        break;
      case 'favorite':
        if (widget.onToggleFavorite != null) await widget.onToggleFavorite!();
        break;
      case 'hide':
        if (widget.onHideFromHome != null) await widget.onHideFromHome!();
        break;
      case 'report':
        if (widget.onReport != null) await widget.onReport!();
        break;
      case 'restore':
        if (widget.onRestoreToHome != null) await widget.onRestoreToHome!();
        break;
      case 'withdraw':
        if (widget.onWithdrawReport != null) await widget.onWithdrawReport!();
        break;
    }
    if (mounted) await _refreshPending();
  }

  @override
  Widget build(BuildContext context) {
    final iconSz = _iconSize(context);
    final pad = _pad(context);
    final l10n = AppLocalizations.of(context);

    if (widget.useAppBarStyle) {
      return IconButton(
        key: _anchorKey,
        tooltip: l10n?.listingPublicActionsTooltip ?? 'Options',
        iconSize: iconSz + 4,
        color: widget.colorScheme.onSurface,
        onPressed: _openMenu,
        icon: const Icon(Icons.more_vert_rounded),
      );
    }

    return Material(
      key: _anchorKey,
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: _openMenu,
        child: Container(
          padding: EdgeInsets.all(pad),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: Icon(Icons.more_vert, color: Colors.white, size: iconSz),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.iconSize,
    required this.colorScheme,
    this.foreground,
  });

  final IconData icon;
  final String label;
  final double iconSize;
  final ColorScheme colorScheme;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? colorScheme.onSurface;
    return Row(
      children: [
        Icon(icon, size: iconSize + 1, color: fg),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: iconSize >= 19 ? 14.5 : 13.5,
              color: fg,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}

/// مستطيل تقريبي لموضع القائمة بجانب الزر.
class _MenuAnchorRect {
  static Rect getRect(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    final overlayState = Navigator.of(context).overlay;
    if (box == null || !box.hasSize || overlayState == null) {
      return Rect.zero;
    }
    final overlay = overlayState.context.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    return Rect.fromLTWH(
        topLeft.dx, topLeft.dy, box.size.width, box.size.height);
  }
}
