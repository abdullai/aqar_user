import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../security/web_user_agent.dart';
import 'viewport_scroll_policy.dart';

/// نوع سطح التشغيل الفعلي — جوال أصلي / ويب جوال / جهاز لوحي / ويندوز / ويب سطح مكتب.
enum AppSurfaceKind {
  phoneNative,
  phoneWeb,
  tablet,
  windowsNative,
  desktopNative,
  desktopWeb,
}

/// لقطة حجم الشاشة + المنصة. تُحقَن من [MaterialApp.builder] وتُقرأ في أي شاشة.
@immutable
class AppSurfaceSnapshot {
  const AppSurfaceSnapshot({
    required this.kind,
    required this.size,
    required this.shortestSide,
    required this.textScaler,
    required this.viewInsetsBottom,
  });

  final AppSurfaceKind kind;
  final Size size;
  final double shortestSide;
  final TextScaler textScaler;
  final double viewInsetsBottom;

  bool get isPhone =>
      kind == AppSurfaceKind.phoneNative || kind == AppSurfaceKind.phoneWeb;

  bool get isTablet => kind == AppSurfaceKind.tablet;

  bool get isDesktop =>
      kind == AppSurfaceKind.windowsNative ||
      kind == AppSurfaceKind.desktopNative ||
      kind == AppSurfaceKind.desktopWeb;

  bool get isWindows => kind == AppSurfaceKind.windowsNative;

  bool get isTouchPrimary => isPhone || isTablet || kind == AppSurfaceKind.phoneWeb;

  /// شريحة لصق رمز التحقق فوق الكيبورد: هواتف وتطبيقات/ويب الجوال فقط.
  /// ويندوز وسطح المكتب: الإشعار العلوي فقط.
  bool get showOtpKeyboardPasteChip => isPhone;

  bool get isCompact =>
      isPhone || size.width < ViewportScrollPolicy.compactBreakpoint;

  bool get showSmartScrollbar => !isCompact;

  bool get denseFields => isPhone;

  /// عرض بطاقة النموذج: الجوال ملء العرض، الجهاز اللوحي أوسع، سطح المكتب موحّد.
  double get formMaxWidth {
    if (isPhone) return size.width;
    if (isTablet) return 720;
    if (size.width >= 1400) return 880;
    return 640;
  }

  EdgeInsets get formGutter {
    if (isPhone) {
      return const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
    }
    if (isTablet) {
      return const EdgeInsets.symmetric(horizontal: 20, vertical: 12);
    }
    return const EdgeInsets.symmetric(horizontal: 24, vertical: 16);
  }

  double get fieldVerticalPadding => denseFields ? 12 : 14;

  static AppSurfaceKind detectKind(Size size) {
    final shortest = size.shortestSide;
    if (!kIsWeb) {
      final p = defaultTargetPlatform;
      if (p == TargetPlatform.android || p == TargetPlatform.iOS) {
        return shortest >= 600
            ? AppSurfaceKind.tablet
            : AppSurfaceKind.phoneNative;
      }
      if (p == TargetPlatform.windows) return AppSurfaceKind.windowsNative;
      return AppSurfaceKind.desktopNative;
    }

    final ua = readWebUserAgentImpl().toLowerCase();
    final mobileUa = ua.contains('android') ||
        ua.contains('iphone') ||
        ua.contains('ipod') ||
        ua.contains('mobile');
    final tabletUa = ua.contains('ipad') ||
        (ua.contains('android') && !ua.contains('mobile'));
    if (mobileUa && !tabletUa) return AppSurfaceKind.phoneWeb;
    if (tabletUa || shortest >= 600 && size.width < 1024) {
      return AppSurfaceKind.tablet;
    }
    if (size.width < ViewportScrollPolicy.compactBreakpoint) {
      return AppSurfaceKind.phoneWeb;
    }
    return AppSurfaceKind.desktopWeb;
  }

  factory AppSurfaceSnapshot.from(BuildContext context) {
    final mq = MediaQuery.of(context);
    return AppSurfaceSnapshot(
      kind: detectKind(mq.size),
      size: mq.size,
      shortestSide: mq.size.shortestSide,
      textScaler: mq.textScaler,
      viewInsetsBottom: mq.viewInsets.bottom,
    );
  }
}

/// يوفّر [AppSurfaceSnapshot] لكل الشاشات دون إعادة حساب المنصة في كل حقل.
class AppSurfaceScope extends InheritedWidget {
  const AppSurfaceScope({
    super.key,
    required this.snapshot,
    required super.child,
  });

  final AppSurfaceSnapshot snapshot;

  static AppSurfaceSnapshot of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppSurfaceScope>();
    return scope?.snapshot ?? AppSurfaceSnapshot.from(context);
  }

  static AppSurfaceSnapshot? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppSurfaceScope>()?.snapshot;
  }

  @override
  bool updateShouldNotify(AppSurfaceScope oldWidget) {
    return oldWidget.snapshot.kind != snapshot.kind ||
        oldWidget.snapshot.size != snapshot.size ||
        (oldWidget.snapshot.viewInsetsBottom - snapshot.viewInsetsBottom).abs() >
            8;
  }
}

/// يوسّط النموذج على ويندوز/الويب الواسع ويملأ الجوال.
class AppAdaptiveForm extends StatelessWidget {
  const AppAdaptiveForm({
    super.key,
    required this.child,
    this.maxWidth,
  });

  final Widget child;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final surface = AppSurfaceScope.of(context);
    final cap = maxWidth ?? surface.formMaxWidth;
    if (surface.isPhone) {
      return Padding(padding: surface.formGutter, child: child);
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: cap),
        child: Padding(padding: surface.formGutter, child: child),
      ),
    );
  }
}
