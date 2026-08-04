import 'package:flutter/material.dart';

abstract final class LedgerlyColors {
  static const brand = Color(0xFF0D4F5C);
  static const brandMint = Color(0xFF72D7B5);
  static const canvas = Color(0xFFF7F8F7);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF222625);
  static const muted = Color(0xFF7C8481);
  static const disabled = Color(0xFFB7BDBA);
  static const divider = Color(0xFFE8ECE9);
  static const action = Color(0xFFF6B27B);
  static const actionStrong = Color(0xFFE49A62);
  static const actionSurface = Color(0xFFFFF5EA);
  static const income = Color(0xFFD95D45);
  static const expense = Color(0xFF31858E);
  static const chartTeal = Color(0xFF63C4C3);
  static const chartBlue = Color(0xFF6D95E8);
  static const warning = Color(0xFFE7B54C);
}

ThemeData ledgerlyTheme() {
  final colors = ColorScheme.fromSeed(
    seedColor: LedgerlyColors.brand,
    brightness: Brightness.light,
  ).copyWith(
    primary: LedgerlyColors.brand,
    onPrimary: Colors.white,
    secondary: LedgerlyColors.brandMint,
    tertiary: LedgerlyColors.action,
    onTertiary: const Color(0xFF593119),
    surface: LedgerlyColors.surface,
    onSurface: LedgerlyColors.ink,
    outline: LedgerlyColors.divider,
    outlineVariant: LedgerlyColors.divider,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    scaffoldBackgroundColor: LedgerlyColors.canvas,
    fontFamilyFallback: const [
      'PingFang SC',
      'Noto Sans CJK SC',
      'Microsoft YaHei',
    ],
    textTheme: const TextTheme(
      headlineSmall: TextStyle(
        fontSize: 24,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: LedgerlyColors.ink,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w700,
        color: LedgerlyColors.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 17,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: LedgerlyColors.ink,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.45,
        color: LedgerlyColors.ink,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.4,
        color: LedgerlyColors.muted,
      ),
      labelLarge: TextStyle(
        fontSize: 15,
        height: 1.2,
        fontWeight: FontWeight.w600,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: LedgerlyColors.canvas,
      foregroundColor: LedgerlyColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: LedgerlyColors.ink,
        fontSize: 24,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: const CardThemeData(
      color: LedgerlyColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        side: BorderSide(color: LedgerlyColors.divider),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: LedgerlyColors.divider,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: LedgerlyColors.surface,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: LedgerlyColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: LedgerlyColors.divider),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: LedgerlyColors.brand,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: LedgerlyColors.action,
      foregroundColor: Color(0xFF593119),
      elevation: 4,
      shape: CircleBorder(),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: LedgerlyColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: LedgerlyColors.surface,
      modalBackgroundColor: LedgerlyColors.surface,
      showDragHandle: false,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
  );
}
