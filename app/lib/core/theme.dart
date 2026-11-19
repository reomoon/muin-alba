import 'package:material_ui/material_ui.dart';

/// 시안과 같은 색 (흰 바탕 + 파란색 한 가지)
class AppColors {
  static const brand = Color(0xFF2563EB);
  static const brandSoft = Color(0xFFEEF3FD);
  static const ink = Color(0xFF16181D);
  static const ink2 = Color(0xFF374151);
  static const sub = Color(0xFF5B6170);
  static const meta = Color(0xFF6B7280);
  static const line = Color(0xFFE3E6EB);
  static const surface = Color(0xFFF5F7FA);
  static const danger = Color(0xFFD92D20);
  static const kakao = Color(0xFFFEE500);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    primary: AppColors.brand,
    surface: Colors.white,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  const buttonText = TextStyle(fontSize: 16, fontWeight: FontWeight.w700);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(color: AppColors.ink, fontSize: 17, fontWeight: FontWeight.w700),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: shape,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: shape,
        side: const BorderSide(color: AppColors.line, width: 1.5),
        foregroundColor: AppColors.ink,
        textStyle: buttonText,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.brandSoft,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? AppColors.brand : AppColors.meta,
        ),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
