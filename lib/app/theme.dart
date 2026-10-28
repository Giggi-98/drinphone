import 'package:flutter/material.dart';

/// Palette della proposta D (canvas: docs/DECISIONS.md 2026-10-28), chiaro e scuro.
@immutable
class DrinColors extends ThemeExtension<DrinColors> {
  const DrinColors({
    required this.ground,
    required this.side,
    required this.surface,
    required this.card,
    required this.field,
    required this.border,
    required this.text,
    required this.muted,
    required this.accent,
    required this.keyBtn,
    required this.avatar,
    required this.ok,
    required this.okText,
    required this.busy,
    required this.busyText,
    required this.ringing,
  });

  final Color ground,
      side,
      surface,
      card,
      field,
      border,
      text,
      muted,
      accent,
      keyBtn,
      avatar;
  final Color ok, okText, busy, busyText, ringing;

  static const callGreen = Color(0xFF1E7F4F);
  static const hangupRed = Color(0xFFC4312B);

  static const dark = DrinColors(
    ground: Color(0xFF111316),
    side: Color(0xFF16191D),
    surface: Color(0xFF1A1E23),
    card: Color(0xFF20252B),
    field: Color(0xFF111316),
    border: Color(0xFF2B323A),
    text: Color(0xFFE9EDF2),
    muted: Color(0xFFA1AAB6),
    accent: Color(0xFF4FC1B0),
    keyBtn: Color(0xFF262C33),
    avatar: Color(0xFF2E353E),
    ok: Color(0xFF2EA866),
    okText: Color(0xFF7FD8A4),
    busy: Color(0xFFE0554B),
    busyText: Color(0xFFF2A9A3),
    ringing: Color(0xFFD9A21B),
  );

  static const light = DrinColors(
    ground: Color(0xFFEEF1F4),
    side: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFF8F9FB),
    field: Color(0xFFF8F9FB),
    border: Color(0xFFDDE2E8),
    text: Color(0xFF14171C),
    muted: Color(0xFF56606D),
    accent: Color(0xFF0F766E),
    keyBtn: Color(0xFFEBEFF3),
    avatar: Color(0xFFE1E6EC),
    ok: Color(0xFF2EA866),
    okText: Color(0xFF1B6B3F),
    busy: Color(0xFFE0554B),
    busyText: Color(0xFFB42318),
    ringing: Color(0xFFD9A21B),
  );

  @override
  DrinColors copyWith() => this;

  @override
  DrinColors lerp(DrinColors? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

extension DrinColorsX on BuildContext {
  DrinColors get drin => Theme.of(this).extension<DrinColors>()!;
}

ThemeData buildTheme(Brightness b) {
  final c = b == Brightness.dark ? DrinColors.dark : DrinColors.light;
  return ThemeData(
    brightness: b,
    // Font di sistema di Windows 11; Segoe UI su Windows 10.
    fontFamily: 'Segoe UI Variable Text',
    fontFamilyFallback: const ['Segoe UI'],
    visualDensity: VisualDensity.standard,
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      textStyle: TextStyle(color: c.text, fontSize: 12),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(6),
      ),
    ),
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.accent,
      brightness: b,
      primary: c.accent,
      surface: c.surface,
      onSurface: c.text,
    ),
    scaffoldBackgroundColor: c.ground,
    dividerColor: c.border,
    extensions: [c],
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.field,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.border),
      ),
    ),
  );
}

/// Numeri e interni: Cascadia Mono (Windows 11), poi Consolas.
const monoFont = 'Cascadia Mono';
const monoFallback = ['Consolas'];

TextStyle mono(Color color, {double size = 13, FontWeight? weight}) =>
    TextStyle(
      fontFamily: monoFont,
      fontFamilyFallback: monoFallback,
      fontSize: size,
      color: color,
      fontWeight: weight,
    );
