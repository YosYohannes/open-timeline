import 'package:flutter/material.dart';

const kRadius = 4.0;
final kBorderRadius = BorderRadius.circular(kRadius);
const _shape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(kRadius)),
);

const _black = Color(0xFF000000);

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: Color(0xFFD4D4D4),
    onPrimary: _black,
    primaryContainer: Color(0xFF2C2C2C),
    onPrimaryContainer: Color(0xFFEDEDED),
    secondary: Color(0xFFB4B4B4),
    onSecondary: _black,
    secondaryContainer: Color(0xFF262626),
    onSecondaryContainer: Color(0xFFE2E2E2),
    tertiary: Color(0xFFB4B4B4),
    onTertiary: _black,
    surface: _black,
    onSurface: Color(0xFFE6E6E6),
    onSurfaceVariant: Color(0xFFA8A8A8),
    surfaceContainerLowest: _black,
    surfaceContainerLow: Color(0xFF0B0B0B),
    surfaceContainer: Color(0xFF121212),
    surfaceContainerHigh: Color(0xFF1A1A1A),
    surfaceContainerHighest: Color(0xFF242424),
    outline: Color(0xFF5C5C5C),
    outlineVariant: Color(0xFF2E2E2E),
    surfaceTint: Colors.transparent,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: _black,
    canvasColor: _black,
    appBarTheme: const AppBarTheme(
      backgroundColor: _black,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: kBorderRadius,
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: _shape),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: _shape,
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: _shape),
    ),
    chipTheme: ChipThemeData(
      shape: _shape,
      side: BorderSide(color: scheme.outlineVariant),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      shape: _shape,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: _black,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.surfaceContainerHighest,
      indicatorShape: _shape,
    ),
    dialogTheme: const DialogThemeData(
      shape: _shape,
      backgroundColor: Color(0xFF121212),
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadius)),
      ),
      backgroundColor: Color(0xFF121212),
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: const PopupMenuThemeData(
      shape: _shape,
      color: Color(0xFF121212),
      surfaceTintColor: Colors.transparent,
    ),
    datePickerTheme: const DatePickerThemeData(
      shape: _shape,
      backgroundColor: Color(0xFF121212),
      surfaceTintColor: Colors.transparent,
    ),
    timePickerTheme: const TimePickerThemeData(
      shape: _shape,
      hourMinuteShape: _shape,
      dayPeriodShape: _shape,
      backgroundColor: Color(0xFF121212),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
  );
}
