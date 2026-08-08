import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared palette for the "Aurora" design language.
///
/// Brand DNA: warm sunrise. Coral/peach core with amber glow, mint status
/// accents, and creamy surfaces that keep both light and dark modes
/// high-contrast and readable.
class AppColors {
  AppColors._();

  // Brand core
  static const Color indigo = Color(0xFFFF6B4A);
  static const Color violet = Color(0xFFFF8A5C);
  static const Color purple = Color(0xFFF65E8B);
  static const Color cyan = Color(0xFFFFB86B);
  static const Color teal = Color(0xFF2FBF8F);

  // Status
  static const Color success = Color(0xFF2FBF8F);
  static const Color warning = Color(0xFFFFB020);
  static const Color danger = Color(0xFFFF4D5E);
  static const Color info = Color(0xFF38A6F5);
  static const Color orange = Color(0xFFFF8A3D);

  // Light surfaces (warm cream)
  static const Color lightBg = Color(0xFFFBF4EC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightText = Color(0xFF2E1F1A);
  static const Color lightMuted = Color(0xFF8C7A6E);
  static const Color lightBorder = Color(0xFFF0E3D3);

  // Dark surfaces (warm espresso)
  static const Color darkBg = Color(0xFF171015);
  static const Color darkSurface = Color(0xFF241B21);
  static const Color darkSurfaceHigh = Color(0xFF2E2228);
  static const Color darkText = Color(0xFFF9F1EA);
  static const Color darkMuted = Color(0xFFA8938C);
  static const Color darkBorder = Color(0xFF3B2C33);
}

/// Reusable gradient recipes used across screens.
class AppGradients {
  AppGradients._();

  static const LinearGradient brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF6B4A), Color(0xFFFF8A5C), Color(0xFFF65E8B)],
  );

  static const LinearGradient aurora = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFB86B), Color(0xFFFF6B4A), Color(0xFFF65E8B)],
  );

  static const LinearGradient fire = LinearGradient(
    colors: [Color(0xFFF65E8B), Color(0xFFFF8A3D)],
  );

  static LinearGradient screen(bool isDark) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? const [Color(0xFF171015), Color(0xFF241A20)]
            : const [Color(0xFFFFF7EE), Color(0xFFFBE7DA)],
      );
}

/// Central place for all ThemeData so the whole app (main + overlay) shares one
/// design language instead of hand-maintained per-screen colors.
class AppTheme {
  AppTheme._();

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData overlay() => _base(Brightness.dark).copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        cardColor: Colors.transparent,
      );

  static ThemeData _base(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = isDark
        ? const ColorScheme.dark(
            primary: Color(0xFFFF8A5C),
            onPrimary: Color(0xFF241B21),
            secondary: Color(0xFFFFB86B),
            onSecondary: Color(0xFF241B21),
            tertiary: Color(0xFFF65E8B),
            surface: AppColors.darkSurface,
            onSurface: AppColors.darkText,
            surfaceContainerHighest: AppColors.darkSurfaceHigh,
            error: AppColors.danger,
          )
        : const ColorScheme.light(
            primary: AppColors.indigo,
            onPrimary: Colors.white,
            secondary: AppColors.cyan,
            onSecondary: Color(0xFF241B21),
            tertiary: AppColors.purple,
            surface: AppColors.lightSurface,
            onSurface: AppColors.lightText,
            surfaceContainerHighest: AppColors.lightBorder,
            error: Color(0xFFE8455A),
          );

    final cardBorder = BorderSide(
      color: isDark
          ? AppColors.darkBorder.withValues(alpha: 0.8)
          : AppColors.lightBorder,
      width: 1.1,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? AppColors.darkBg : AppColors.lightBg,
      splashFactory: InkRipple.splashFactory,

      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        iconTheme: IconThemeData(color: scheme.onSurface),
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
        systemOverlayStyle: isDark
            ? const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
                statusBarBrightness: Brightness.dark,
              )
            : const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.dark,
                statusBarBrightness: Brightness.light,
              ),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: cardBorder,
        ),
        clipBehavior: Clip.antiAlias,
      ),

      dividerTheme: DividerThemeData(
        color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        thickness: 1,
        space: 1,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? AppColors.darkSurfaceHigh.withValues(alpha: 0.6)
            : const Color(0xFFF1F4FB),
        hintStyle: TextStyle(
          color: isDark ? AppColors.darkMuted : AppColors.lightMuted,
          fontSize: 14,
        ),
        labelStyle: TextStyle(
          color: isDark ? AppColors.darkMuted : AppColors.lightMuted,
          fontSize: 14,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.transparent),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.indigo, width: 1.6),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.indigo,
            width: 1.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: isDark
            ? AppColors.darkSurfaceHigh
            : const Color(0xFFEFF2FC),
        selectedColor: scheme.primary.withValues(alpha: 0.15),
        labelStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
        side: BorderSide(color: Colors.transparent),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.onPrimary;
          return isDark ? AppColors.darkMuted : Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return isDark ? AppColors.darkBorder : AppColors.lightBorder;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.darkSurfaceHigh : const Color(0xFF2E1F1A),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.primary.withValues(alpha: 0.15),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: scheme.primary,
        textColor: scheme.onSurface,
        contentPadding: EdgeInsets.zero,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
      ),
    );
  }
}
