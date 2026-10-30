import 'package:flutter/material.dart';

/// Token dello stile "Squillo": valori e regole in DESIGN.md, riferimento
/// grafico in docs/design/drin-design-system.html. Mai colori, misure di
/// testo o durate scritti a mano nei widget.
@immutable
class DrinColors extends ThemeExtension<DrinColors> {
  const DrinColors({
    required this.brand,
    required this.primary,
    required this.onPrimary,
    required this.ink,
    required this.muted,
    required this.ground,
    required this.surface,
    required this.raised,
    required this.panel,
    required this.line,
    required this.squillo,
    required this.onSquillo,
    required this.squilloLine,
    required this.free,
    required this.onFree,
    required this.freeText,
    required this.busy,
    required this.onBusy,
    required this.busyText,
    required this.away,
  });

  /// Logo, accenti grandi, selezione, focus.
  final Color brand;

  /// Pulsanti e testo d'azione; [onPrimary] sopra.
  final Color primary, onPrimary;
  final Color ink, muted;
  final Color ground, surface, raised, panel, line;

  /// Solo ciò che squilla. [squilloLine] per bordi e onde.
  final Color squillo, onSquillo, squilloLine;

  /// Libero / rispondi; [freeText] per testo verde su fondo chiaro.
  final Color free, onFree, freeText;

  /// Occupato / termina / errore.
  final Color busy, onBusy, busyText;

  /// In attesa, non raggiungibile, in corso (neutro).
  final Color away;

  // Nomi della prima palette, ancora usati dalle schermate da migrare.
  Color get side => surface;
  Color get card => raised;
  Color get field => raised;
  Color get border => line;
  Color get text => ink;
  Color get accent => primary;
  Color get keyBtn => panel;
  Color get avatar => panel;
  Color get ok => free;
  Color get okText => freeText;
  Color get ringing => squilloLine;

  static const light = DrinColors(
    brand: Color(0xFF1380C6),
    primary: Color(0xFF0E6BA8),
    onPrimary: Color(0xFFFFFFFF),
    ink: Color(0xFF0B2A43),
    muted: Color(0xFF4F6478),
    ground: Color(0xFFEEF3F7),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFF6F9FC),
    panel: Color(0xFFE3EAF0),
    line: Color(0xFFD3DFE8),
    squillo: Color(0xFFFFB800),
    onSquillo: Color(0xFF3D2C00),
    squilloLine: Color(0xFFB88300),
    free: Color(0xFF1A9E68),
    onFree: Color(0xFFFFFFFF),
    freeText: Color(0xFF137A50),
    busy: Color(0xFFDC3E43),
    onBusy: Color(0xFFFFFFFF),
    busyText: Color(0xFFB42318),
    away: Color(0xFF7C8B99),
  );

  static const dark = DrinColors(
    brand: Color(0xFF4BA9EC),
    primary: Color(0xFF4BA9EC),
    onPrimary: Color(0xFF06182A),
    ink: Color(0xFFE8F2FA),
    muted: Color(0xFF93AABD),
    ground: Color(0xFF0A1825),
    surface: Color(0xFF0F2233),
    raised: Color(0xFF14293C),
    panel: Color(0xFF1A3045),
    line: Color(0xFF1E3A52),
    squillo: Color(0xFFFFC53D),
    onSquillo: Color(0xFF2B1F00),
    squilloLine: Color(0xFFFFC53D),
    free: Color(0xFF3CCB8C),
    onFree: Color(0xFF06182A),
    freeText: Color(0xFF7FDDB0),
    busy: Color(0xFFFF6B6F),
    onBusy: Color(0xFF06182A),
    busyText: Color(0xFFFFA9AB),
    away: Color(0xFF7F93A6),
  );

  @override
  DrinColors copyWith() => this;

  @override
  DrinColors lerp(DrinColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return DrinColors(
      brand: c(brand, other.brand),
      primary: c(primary, other.primary),
      onPrimary: c(onPrimary, other.onPrimary),
      ink: c(ink, other.ink),
      muted: c(muted, other.muted),
      ground: c(ground, other.ground),
      surface: c(surface, other.surface),
      raised: c(raised, other.raised),
      panel: c(panel, other.panel),
      line: c(line, other.line),
      squillo: c(squillo, other.squillo),
      onSquillo: c(onSquillo, other.onSquillo),
      squilloLine: c(squilloLine, other.squilloLine),
      free: c(free, other.free),
      onFree: c(onFree, other.onFree),
      freeText: c(freeText, other.freeText),
      busy: c(busy, other.busy),
      onBusy: c(onBusy, other.onBusy),
      busyText: c(busyText, other.busyText),
      away: c(away, other.away),
    );
  }
}

/// Gli otto stili di testo (DESIGN.md §2). Font variabili inclusi nell'app:
/// il peso passa anche come asse `wght`, uguale su ogni piattaforma.
abstract final class DrinText {
  static const display = 'Bricolage Grotesque';
  static const ui = 'Onest';
  static const numbers = 'Red Hat Mono';

  static TextStyle _s(String f, double size, double line, int w) => TextStyle(
    fontFamily: f,
    fontSize: size,
    height: line / size,
    fontWeight: FontWeight.values[(w ~/ 100) - 1],
    fontVariations: [
      FontVariation('wght', w.toDouble()),
      if (f == display) FontVariation('opsz', size),
    ],
  );

  static final displayStyle = _s(display, 28, 34, 800);
  static final title = _s(display, 20, 26, 700);
  static final heading = _s(ui, 15, 20, 600);
  static final body = _s(ui, 14, 20, 400);
  static final detail = _s(ui, 12.5, 16, 400);
  static final label = _s(ui, 12, 16, 600);
  static final number = _s(
    numbers,
    13,
    18,
    500,
  ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
  static final numberLarge = _s(
    numbers,
    22,
    28,
    600,
  ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}

/// Griglia da 4 (DESIGN.md §3).
abstract final class DrinSpace {
  static const s1 = 4.0, s2 = 8.0, s3 = 12.0, s4 = 16.0, s5 = 24.0, s6 = 32.0;
}

/// Raggi per ruolo (DESIGN.md §3).
abstract final class DrinRadius {
  static const control = 8.0, row = 10.0, panel = 14.0, sheet = 20.0;
  static const pill = 999.0;
}

/// Movimento (DESIGN.md §5). [of] azzera tutto con "riduci movimento".
abstract final class DrinMotion {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 200);
  static const wide = Duration(milliseconds: 320);
  static const ring = Duration(milliseconds: 900);
  static const wave = Duration(milliseconds: 1600);
  static const curve = Curves.easeOutCubic;
  static const emphasized = Curves.easeInOutCubicEmphasized;

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration of(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;
}

/// Tema dell'interfaccia (Sistema, Scuro, Chiaro), commutabile al volo.
final appThemeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

extension DrinColorsX on BuildContext {
  DrinColors get drin => Theme.of(this).extension<DrinColors>()!;
}

ThemeData buildTheme(Brightness b) {
  final c = b == Brightness.dark ? DrinColors.dark : DrinColors.light;
  TextStyle t(TextStyle s, Color color) => s.copyWith(color: color);
  return ThemeData(
    brightness: b,
    fontFamily: DrinText.ui,
    visualDensity: VisualDensity.standard,
    textTheme: TextTheme(
      displaySmall: t(DrinText.displayStyle, c.ink),
      headlineSmall: t(DrinText.displayStyle, c.ink),
      titleLarge: t(DrinText.title, c.ink),
      titleMedium: t(DrinText.heading, c.ink),
      titleSmall: t(DrinText.heading, c.ink),
      bodyLarge: t(DrinText.body, c.ink),
      bodyMedium: t(DrinText.body, c.ink),
      bodySmall: t(DrinText.detail, c.muted),
      labelLarge: t(DrinText.label, c.ink),
      labelMedium: t(DrinText.label, c.ink),
      labelSmall: t(DrinText.label, c.muted),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      textStyle: t(DrinText.detail, c.ink),
      decoration: BoxDecoration(
        color: c.raised,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(DrinRadius.control),
      ),
    ),
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.brand,
      brightness: b,
      primary: c.primary,
      onPrimary: c.onPrimary,
      surface: c.surface,
      onSurface: c.ink,
      error: c.busy,
      onError: c.onBusy,
    ),
    scaffoldBackgroundColor: c.ground,
    dividerColor: c.line,
    extensions: [c],
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DrinRadius.sheet),
      ),
      titleTextStyle: t(DrinText.title, c.ink),
      contentTextStyle: t(DrinText.body, c.ink),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        textStyle: DrinText.label.copyWith(fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DrinRadius.control),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        side: BorderSide(color: c.line),
        textStyle: DrinText.label.copyWith(fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DrinRadius.control),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.primary,
        textStyle: DrinText.label.copyWith(fontSize: 13),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.ink,
      contentTextStyle: t(DrinText.body, c.surface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DrinRadius.row),
      ),
    ),
    // Cambio pagina in dissolvenza ([DrinMotion.base]), non scorrimento.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      },
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.raised,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DrinRadius.control),
        borderSide: BorderSide(color: c.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DrinRadius.control),
        borderSide: BorderSide(color: c.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DrinRadius.control),
        borderSide: BorderSide(color: c.brand, width: 2),
      ),
    ),
  );
}

/// Numeri e interni (DESIGN.md §2, `number`): Red Hat Mono, cifre tabulari.
const monoFont = DrinText.numbers;

TextStyle mono(Color color, {double size = 13, FontWeight? weight}) =>
    DrinText.number.copyWith(
      fontSize: size,
      color: color,
      fontWeight: weight ?? FontWeight.w500,
      fontVariations: [
        FontVariation('wght', (weight ?? FontWeight.w500).value.toDouble()),
      ],
    );
