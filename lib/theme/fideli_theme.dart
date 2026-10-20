import 'package:flutter/material.dart';

/// Sistema visual editorial de Fideli.
///
/// Mantiene la aplicación en una paleta sobria de blanco, grafito y grises.
/// Los colores configurables de las tarjetas Wallet no dependen de estos
/// valores y continúan siendo elegidos por cada comercio.
abstract final class FideliTheme {
  static const ink = Color(0xFF1D1D21);
  static const inkSoft = Color(0xFF343438);
  static const muted = Color(0xFF77777C);
  static const canvas = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSoft = Color(0xFFF7F7F6);
  static const skySoft = Color(0xFFE2EEF2);
  static const skyMuted = Color(0xFFD3E5EB);
  static const graySoft = Color(0xFFDEE1E3);
  static const yellowSoft = Color(0xFFF7E7A6);
  static const roseSoft = Color(0xFFEBDDD9);
  static const line = Color(0xFFE7E7E4);
  static const danger = Color(0xFFB3261E);

  static ThemeData light() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: ink,
          brightness: Brightness.light,
          surface: surface,
        ).copyWith(
          primary: ink,
          secondary: inkSoft,
          surface: surface,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: ink,
          outline: line,
          error: danger,
        );
    const rounded18 = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(18)),
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      cardColor: surface,
      fontFamily: 'Poppins',
      useMaterial3: true,
      dividerColor: line,
      disabledColor: const Color(0xFFB8B8B6),
      visualDensity: VisualDensity.standard,
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: ink,
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w700,
          letterSpacing: -2,
        ),
        headlineLarge: TextStyle(
          color: ink,
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w700,
          letterSpacing: -1.2,
        ),
        headlineMedium: TextStyle(
          color: ink,
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w700,
          letterSpacing: -.8,
        ),
        titleLarge: TextStyle(
          color: ink,
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w700,
          letterSpacing: -.35,
        ),
        titleMedium: TextStyle(color: ink, fontWeight: FontWeight.w700),
        bodyLarge: TextStyle(color: inkSoft, height: 1.45),
        bodyMedium: TextStyle(color: inkSoft, height: 1.4),
        bodySmall: TextStyle(color: muted, height: 1.35),
        labelLarge: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: const BorderSide(color: line),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: ink,
          fontFamily: 'Poppins',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -.5,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFE0E0DE),
          disabledForegroundColor: const Color(0xFF969694),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
          shape: rounded18,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: const BorderSide(color: line),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
          shape: rounded18,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ink,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: ink,
        foregroundColor: Colors.white,
        elevation: 8,
        focusElevation: 8,
        hoverElevation: 12,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        labelStyle: const TextStyle(color: muted),
        hintStyle: const TextStyle(color: Color(0xFFAAAAA7)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 17,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: ink, width: 1.35),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceSoft,
        selectedColor: ink,
        secondarySelectedColor: ink,
        disabledColor: const Color(0xFFE7E7E5),
        labelStyle: const TextStyle(color: ink, fontWeight: FontWeight.w600),
        secondaryLabelStyle: const TextStyle(color: Colors.white),
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? ink
              : const Color(0xFFE1E1DF),
        ),
        thumbColor: const WidgetStatePropertyAll(Colors.white),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: ink,
        selectionColor: Color(0x331D1D21),
        selectionHandleColor: ink,
      ),
    );
  }
}
