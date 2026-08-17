import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'core/platform/viewport_scroll_policy.dart';
import 'widgets/aqar_desktop_scrollbar.dart';

/// سلوك تمرير موحّد وذكي:
/// - الشاشات الصغيرة/اللمسية والجوال (تطبيق أو ويب جوال): لا شريط ظاهر.
///   التمرير باللمس مدعوم دائماً (touch + stylus) ولا يلتفّ بـ `Scrollbar` كي لا
///   يلتقط أحداث اللمس على بعض إصدارات Chrome/Safari للجوال.
/// - الشاشات الكبيرة وسطح المكتب: شريط تمرير ظاهر وتفاعلي.
class AqarScrollBehavior extends MaterialScrollBehavior {
  const AqarScrollBehavior();

  static const double compactScrollbarBreakpoint =
      ViewportScrollPolicy.compactBreakpoint;

  static bool isCompactTouchLike(BuildContext context) =>
      ViewportScrollPolicy.isCompactTouchLike(context);

  static bool isLargeScreenScrollbarVisible(BuildContext context) {
    if (isCompactTouchLike(context)) return false;
    return true;
  }

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // جوال (تطبيق أو ويب) — تمرير باللمس فقط بدون شريط يلتقط اللمس.
    if (isCompactTouchLike(context)) {
      return child;
    }
    final controller = details.controller;
    if (controller == null) {
      return child;
    }
    // يمين المستخدم (حافة يمين الشاشة) على سطح المكتب وويندوز.
    return AqarDesktopScrollbar(
      controller: controller,
      scrollbarOnRight: true,
      child: child,
    );
  }

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.unknown,
      };

  /// فيزياء قابلة للسحب على الجوال: نضمن أن أيّ Scrollable بدون [physics]
  /// محدّدة يحصل على فيزياء "Always" حتى لا تُمنع البطاقات من التحرّك حين
  /// لا يتجاوز محتواها حدّ المنفذ في الويب الجوال.
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    final base = super.getScrollPhysics(context);
    if (isCompactTouchLike(context)) {
      return AlwaysScrollableScrollPhysics(parent: base);
    }
    return base;
  }
}

/// شاشات المصادقة: نفس شريط سطح المكتب الذكي؛ جوال بدون شريط.
class AqarAuthScrollBehavior extends MaterialScrollBehavior {
  const AqarAuthScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (AqarScrollBehavior.isCompactTouchLike(context)) {
      return child;
    }
    final controller = details.controller;
    if (controller == null) {
      return child;
    }
    return AqarDesktopScrollbar(
      controller: controller,
      scrollbarOnRight: true,
      child: child,
    );
  }

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.unknown,
      };
}

class AppTheme {
  /// خط الواجهة الأساسي — Cairo محلي من pubspec (بدون تحميل شبكة) لتسريع كل الصفحات.
  static const String _webFontFamily = 'Cairo';
  static const List<String> _fontFallbacks = ['NotoNaskhArabic', 'sans-serif'];

  static TextStyle _tajawal({
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? height,
  }) {
    if (kIsWeb) {
      return TextStyle(
        fontFamily: _webFontFamily,
        fontFamilyFallback: _fontFallbacks,
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: height,
      );
    }
    // تطبيق أصلي: Cairo المحلي فقط — لا GoogleFonts وقت التشغيل.
    return TextStyle(
      fontFamily: 'Cairo',
      fontFamilyFallback: const ['NotoNaskhArabic'],
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
    );
  }

  /// انتقالات أقرب لسلوك iOS (سحب للرجوع حيث يدعمه المسار).
  static const PageTransitionsTheme _pageTransitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
    },
  );

  static const double _inputRadius = 12;

  /// حدود واضحة للحقول: فاتح = داكن، ليلي = فاتح — مع زوايا دائرية موحّدة.
  static InputDecorationTheme _inputDecorationTheme(
    ColorScheme cs, {
    required Color accent,
  }) {
    final isDark = cs.brightness == Brightness.dark;
    final borderColor =
        isDark ? cs.onSurface.withValues(alpha: 0.88) : const Color(0xFF1E1E1E);
    final disabledColor = isDark
        ? cs.onSurface.withValues(alpha: 0.35)
        : cs.onSurface.withValues(alpha: 0.38);
    final fill = isDark
        ? cs.surfaceContainerHighest.withValues(alpha: 0.45)
        : cs.surfaceContainerHighest.withValues(alpha: 0.65);

    OutlineInputBorder ob(BorderSide side) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(_inputRadius),
          borderSide: side,
        );

    return InputDecorationTheme(
      filled: true,
      fillColor: fill,
      isDense: true,
      alignLabelWithHint: true,
      // عمودي متوازن حتى لا تبدو النقاط/النص أعلى أو أسفل على ويب الجوال.
      contentPadding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      border: ob(BorderSide(color: borderColor, width: 1.25)),
      enabledBorder: ob(BorderSide(color: borderColor, width: 1.25)),
      focusedBorder: ob(BorderSide(color: accent, width: 2)),
      errorBorder: ob(BorderSide(color: cs.error, width: 1.25)),
      focusedErrorBorder: ob(BorderSide(color: cs.error, width: 2)),
      disabledBorder: ob(BorderSide(color: disabledColor, width: 1)),
    );
  }

  /// [accent] لون اختيار المستخدم — يُدمَج مع لوحة أساس ثابتة؛ يُبرَز في الإطارات والأزرار الرئيسية لا في كل السطوح.
  static ThemeData _themeFromScheme(ColorScheme cs, {required Color accent}) {
    final isLight = cs.brightness == Brightness.light;
    final readableText = isLight ? const Color(0xFF050505) : cs.onSurface;
    final readableMuted =
        isLight ? const Color(0xFF111111) : cs.onSurfaceVariant;
    final frameBlend = Color.alphaBlend(
      accent.withValues(alpha: cs.brightness == Brightness.dark ? 0.32 : 0.24),
      cs.outlineVariant.withValues(alpha: 0.55),
    );
    final base = ThemeData(
      colorScheme: cs,
      useMaterial3: true,
      brightness: cs.brightness,
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: _pageTransitions,
      scaffoldBackgroundColor: cs.surface,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        backgroundColor: cs.surface,
        foregroundColor: readableText,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: _tajawal(
          color: readableText,
          fontSize: 20,
          fontWeight: FontWeight.w900,
          height: 1.2,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: frameBlend, width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: accent.withValues(alpha: 0.28),
            width: 1,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: accent.withValues(alpha: 0.30),
            width: 1.2,
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        textColor: readableText,
        iconColor: isLight ? const Color(0xFF111111) : null,
        titleTextStyle: _tajawal(
          color: readableText,
          fontWeight: isLight ? FontWeight.w800 : FontWeight.w700,
          fontSize: 16,
        ),
        subtitleTextStyle: _tajawal(
          color: readableMuted,
          fontWeight: isLight ? FontWeight.w700 : FontWeight.w600,
          fontSize: 13,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: readableText,
        unselectedLabelColor: readableMuted,
        labelStyle: _tajawal(fontWeight: FontWeight.w900),
        unselectedLabelStyle: _tajawal(
          fontWeight: isLight ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return _tajawal(
            color: readableText,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w900
                : (isLight ? FontWeight.w800 : FontWeight.w600),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? accent
                : (isLight ? const Color(0xFF111111) : cs.onSurfaceVariant),
          );
        }),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        selectedItemColor: accent,
        unselectedItemColor:
            isLight ? const Color(0xFF111111) : cs.onSurfaceVariant,
        selectedLabelStyle: _tajawal(fontWeight: FontWeight.w900),
        unselectedLabelStyle: _tajawal(
          fontWeight: isLight ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: BorderSide(color: accent.withValues(alpha: 0.55)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      inputDecorationTheme: _inputDecorationTheme(cs, accent: accent),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: accent.withValues(alpha: isLight ? 0.28 : 0.35),
        selectionHandleColor: accent,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(9),
        radius: const Radius.circular(12),
        crossAxisMargin: 2,
        mainAxisMargin: 4,
        thumbVisibility: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) return true;
          return null;
        }),
        trackVisibility: WidgetStateProperty.resolveWith((states) => null),
      ),
    );
    // Cairo هوية الواجهة + Noto احتياطي للرسم العربي على الويب.
    const fallbacks = <String>[
      'Cairo',
      'NotoNaskhArabic',
      'Segoe UI',
      'Roboto',
      'Helvetica Neue',
      'Arial',
      'sans-serif',
    ];
    TextStyle strengthen(TextStyle? style, {bool display = false}) {
      final fallback = display
          ? const TextStyle(fontSize: 20)
          : const TextStyle(fontSize: 14);
      final s = style ?? fallback;
      final current = s.fontWeight ?? FontWeight.w400;
      final target = current.index < FontWeight.w700.index
          ? (isLight ? FontWeight.w700 : FontWeight.w600)
          : current;
      return s.copyWith(
        fontFamily: _webFontFamily,
        fontFamilyFallback: fallbacks,
        fontWeight: target,
        color: s.color ?? readableText,
        height: s.height ?? 1.35,
      );
    }

    TextTheme strengthenTheme(TextTheme textTheme) {
      final t = textTheme.apply(
        bodyColor: readableText,
        displayColor: readableText,
        fontFamily: _webFontFamily,
        fontFamilyFallback: fallbacks,
      );
      return t.copyWith(
        displayLarge: strengthen(t.displayLarge, display: true),
        displayMedium: strengthen(t.displayMedium, display: true),
        displaySmall: strengthen(t.displaySmall, display: true),
        headlineLarge: strengthen(t.headlineLarge, display: true),
        headlineMedium: strengthen(t.headlineMedium, display: true),
        headlineSmall: strengthen(t.headlineSmall, display: true),
        titleLarge: strengthen(t.titleLarge, display: true),
        titleMedium: strengthen(t.titleMedium, display: true),
        titleSmall: strengthen(t.titleSmall),
        bodyLarge: strengthen(t.bodyLarge),
        bodyMedium: strengthen(t.bodyMedium),
        bodySmall: strengthen(t.bodySmall),
        labelLarge: strengthen(t.labelLarge),
        labelMedium: strengthen(t.labelMedium),
        labelSmall: strengthen(t.labelSmall),
      );
    }

    return base.copyWith(
      textTheme: strengthenTheme(base.textTheme),
      primaryTextTheme: strengthenTheme(base.primaryTextTheme),
    );
  }

  /// بذرة ثابتة للأسطح والتدرجات؛ [accent] يُطبَّق على primary والإطارات فقط.
  static const Color _paletteBaseSeed = Color(0xFF0F766E);

  static ThemeData lightThemeFor(Color accent) {
    final base = ColorScheme.fromSeed(
      seedColor: _paletteBaseSeed,
      brightness: Brightness.light,
    );
    final fromAccent = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
    );
    final cs = base.copyWith(
      primary: accent,
      onPrimary: fromAccent.onPrimary,
      primaryContainer: fromAccent.primaryContainer,
      onPrimaryContainer: fromAccent.onPrimaryContainer,
      onSurface: const Color(0xFF050505),
      onSurfaceVariant: const Color(0xFF111111),
      outline: const Color(0xFF242424),
      outlineVariant: const Color(0xFF3A3A3A),
    );
    return _themeFromScheme(cs, accent: accent);
  }

  static ThemeData darkThemeFor(Color accent) {
    final base = ColorScheme.fromSeed(
      seedColor: _paletteBaseSeed,
      brightness: Brightness.dark,
    );
    final fromAccent = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    );
    final cs = base.copyWith(
      primary: accent,
      onPrimary: fromAccent.onPrimary,
      primaryContainer: fromAccent.primaryContainer,
      onPrimaryContainer: fromAccent.onPrimaryContainer,
      onSurface: const Color(0xFFF3F6F5),
      onSurfaceVariant: const Color(0xFFD5DEDB),
      outline: const Color(0xFF9BB0AA),
      outlineVariant: const Color(0xFF5A6F69),
    );
    return _themeFromScheme(cs, accent: accent);
  }
}
