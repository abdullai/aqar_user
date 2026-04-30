import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// سلوك تمرير موحّد وذكي:
/// - الشاشات الصغيرة/اللمسية: التمرير يعمل باللمس بدون شريط كلاسيكي ظاهر.
/// - الشاشات الكبيرة وسطح المكتب: شريط تمرير ظاهر وتفاعلي.
class AqarScrollBehavior extends MaterialScrollBehavior {
  const AqarScrollBehavior();

  static const double compactScrollbarBreakpoint = 700;

  static bool isCompactTouchLike(BuildContext context) {
    final width = MediaQuery.sizeOf(context).shortestSide;
    final platform = defaultTargetPlatform;
    final mobilePlatform =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    if (mobilePlatform) return true;
    if (kIsWeb) return width < compactScrollbarBreakpoint;
    return width < compactScrollbarBreakpoint;
  }

  static bool isLargeScreenScrollbarVisible(BuildContext context) {
    if (isCompactTouchLike(context)) return false;
    return kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.fuchsia;
  }

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (isCompactTouchLike(context)) {
      return child;
    }
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final alwaysVisible = isLargeScreenScrollbarVisible(context);
    return Scrollbar(
      controller: details.controller,
      thickness: alwaysVisible ? 8 : 5,
      radius: const Radius.circular(12),
      scrollbarOrientation:
          rtl ? ScrollbarOrientation.right : ScrollbarOrientation.left,
      thumbVisibility: alwaysVisible,
      trackVisibility: alwaysVisible,
      interactive: true,
      child: child,
    );
  }

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      };
}

class AppTheme {
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
        titleTextStyle: GoogleFonts.tajawal(
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
        titleTextStyle: GoogleFonts.tajawal(
          color: readableText,
          fontWeight: isLight ? FontWeight.w800 : FontWeight.w700,
          fontSize: 16,
        ),
        subtitleTextStyle: GoogleFonts.tajawal(
          color: readableMuted,
          fontWeight: isLight ? FontWeight.w700 : FontWeight.w600,
          fontSize: 13,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: readableText,
        unselectedLabelColor: readableMuted,
        labelStyle: GoogleFonts.tajawal(fontWeight: FontWeight.w900),
        unselectedLabelStyle: GoogleFonts.tajawal(
          fontWeight: isLight ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return GoogleFonts.tajawal(
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
        selectedLabelStyle: GoogleFonts.tajawal(fontWeight: FontWeight.w900),
        unselectedLabelStyle: GoogleFonts.tajawal(
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
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(kIsWeb ? 8 : 6),
        radius: const Radius.circular(12),
        thumbVisibility: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) return true;
          if (kIsWeb) return true;
          return null;
        }),
        trackVisibility: WidgetStateProperty.all(kIsWeb ? true : false),
      ),
    );
    // Tajawal + fallback للخطوط النظامية بدون خط محلي قديم يسبب assets/assets على الويب.
    const fallbacks = <String>[
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
      if (!isLight) return s.copyWith(fontFamilyFallback: fallbacks);
      final current = s.fontWeight ?? FontWeight.w400;
      final target =
          current.index < FontWeight.w700.index ? FontWeight.w700 : current;
      return s.copyWith(
        color: readableText,
        fontWeight: target,
        fontFamilyFallback: fallbacks,
      );
    }

    TextTheme strengthenTheme(TextTheme textTheme) {
      final t = GoogleFonts.tajawalTextTheme(textTheme).apply(
        bodyColor: readableText,
        displayColor: readableText,
        fontFamilyFallback: fallbacks,
      );
      if (!isLight) return t;
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
    );
    return _themeFromScheme(cs, accent: accent);
  }
}
