import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Semantic color tokens accessible via `Theme.of(context).extension<AppColors>()!`.
class AppColors extends ThemeExtension<AppColors> {
  /// Primary headline text color (white in dark, near-black in light)
  final Color textHeadline;
  /// Secondary body text color
  final Color textBody;
  /// Muted/tertiary text color (labels, hints, timestamps)
  final Color textMuted;
  /// Card/container background
  final Color cardBackground;
  /// Subtle borders (dividers, card outlines)
  final Color subtleBorder;
  /// Translucent overlay for surfaces (charts, empty states)
  final Color surfaceOverlay;
  /// Chip/filter pill background color
  final Color chipBackground;
  /// Default icon color (secondary importance)
  final Color iconDefault;
  /// Inverted text for on-primary surfaces (mic button icon, checkmarks on filled)
  final Color onPrimaryText;
  /// Dialog/Sheet background
  final Color sheetBackground;

  const AppColors({
    required this.textHeadline,
    required this.textBody,
    required this.textMuted,
    required this.cardBackground,
    required this.subtleBorder,
    required this.surfaceOverlay,
    required this.chipBackground,
    required this.iconDefault,
    required this.onPrimaryText,
    required this.sheetBackground,
  });

  static const dark = AppColors(
    textHeadline: Colors.white,
    textBody: Color(0xB3FFFFFF), // Colors.white70
    textMuted: Color(0xFF607D8B), // Colors.blueGrey
    cardBackground: Color(0xFF142022),
    subtleBorder: Color(0x1AFFFFFF), // Colors.white10ish
    surfaceOverlay: Color(0x08FFFFFF), // Colors.white ~3%
    chipBackground: Color(0xFF1E293B),
    iconDefault: Color(0xFF607D8B), // Colors.blueGrey
    onPrimaryText: Colors.white,
    sheetBackground: Color(0xFF0B1517),
  );

  static const light = AppColors(
    textHeadline: Color(0xFF0F172A),
    textBody: Color(0xFF475569),
    textMuted: Color(0xFF94A3B8),
    cardBackground: Colors.white,
    subtleBorder: Color(0x0D000000), // ~5% black
    surfaceOverlay: Color(0x0A000000), // ~4% black
    chipBackground: Color(0xFFE2E8F0),
    iconDefault: Color(0xFF64748B),
    onPrimaryText: Colors.white,
    sheetBackground: Color(0xFFF1F5F9),
  );

  @override
  AppColors copyWith({
    Color? textHeadline,
    Color? textBody,
    Color? textMuted,
    Color? cardBackground,
    Color? subtleBorder,
    Color? surfaceOverlay,
    Color? chipBackground,
    Color? iconDefault,
    Color? onPrimaryText,
    Color? sheetBackground,
  }) {
    return AppColors(
      textHeadline: textHeadline ?? this.textHeadline,
      textBody: textBody ?? this.textBody,
      textMuted: textMuted ?? this.textMuted,
      cardBackground: cardBackground ?? this.cardBackground,
      subtleBorder: subtleBorder ?? this.subtleBorder,
      surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
      chipBackground: chipBackground ?? this.chipBackground,
      iconDefault: iconDefault ?? this.iconDefault,
      onPrimaryText: onPrimaryText ?? this.onPrimaryText,
      sheetBackground: sheetBackground ?? this.sheetBackground,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      textHeadline: Color.lerp(textHeadline, other.textHeadline, t)!,
      textBody: Color.lerp(textBody, other.textBody, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
      subtleBorder: Color.lerp(subtleBorder, other.subtleBorder, t)!,
      surfaceOverlay: Color.lerp(surfaceOverlay, other.surfaceOverlay, t)!,
      chipBackground: Color.lerp(chipBackground, other.chipBackground, t)!,
      iconDefault: Color.lerp(iconDefault, other.iconDefault, t)!,
      onPrimaryText: Color.lerp(onPrimaryText, other.onPrimaryText, t)!,
      sheetBackground: Color.lerp(sheetBackground, other.sheetBackground, t)!,
    );
  }
}

class AppTheme {
  static const Color primaryColor = Color(0xFF25D4E4);
  static const Color backgroundColor = Color(0xFF0B1517);
  static const Color cardColor = Color(0xFF142022);
  static const Color textBodyColor = Color(0xFF94A3B8);
  static const Color textHeadlineColor = Colors.white;

  static ThemeData getDarkTheme(double fontScale) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundColor,
      cardColor: cardColor,
      dividerColor: Colors.white.withValues(alpha: 0.05),
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: primaryColor,
        surface: cardColor,
        onPrimary: backgroundColor,
        onSurface: textHeadlineColor,
      ),
      extensions: const <ThemeExtension<dynamic>>[
        AppColors.dark,
      ],
      textTheme: GoogleFonts.interTextTheme().copyWith(
        displayLarge: GoogleFonts.inter(
          fontSize: 32 * fontScale,
          fontWeight: FontWeight.bold,
          color: textHeadlineColor,
        ),
        headlineMedium: GoogleFonts.inter(
          fontSize: 24 * fontScale,
          fontWeight: FontWeight.bold,
          color: textHeadlineColor,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 16 * fontScale,
          color: textHeadlineColor,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14 * fontScale,
          color: textBodyColor,
        ),
        labelLarge: GoogleFonts.inter(
          fontSize: 14 * fontScale,
          fontWeight: FontWeight.bold,
          color: textHeadlineColor,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: backgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            fontSize: 16 * fontScale,
          ),
        ),
      ),
      iconTheme: const IconThemeData(
        color: textBodyColor,
      ),
    );
  }

  static ThemeData getLightTheme(double fontScale) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: const Color(0xFFF1F5F9),
      cardColor: Colors.white,
      dividerColor: Colors.black.withValues(alpha: 0.05),
      colorScheme: const ColorScheme.light(
        primary: primaryColor,
        secondary: Color(0xFF0F172A),
        surface: Colors.white,
        onPrimary: Colors.white,
        onSurface: Color(0xFF0F172A),
      ),
      extensions: const <ThemeExtension<dynamic>>[
        AppColors.light,
      ],
      textTheme: GoogleFonts.interTextTheme().copyWith(
        displayLarge: GoogleFonts.inter(
          fontSize: 32 * fontScale,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF0F172A),
        ),
        headlineMedium: GoogleFonts.inter(
          fontSize: 24 * fontScale,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF0F172A),
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 16 * fontScale,
          color: const Color(0xFF0F172A),
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14 * fontScale,
          color: const Color(0xFF475569),
        ),
        labelLarge: GoogleFonts.inter(
          fontSize: 14 * fontScale,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF0F172A),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            fontSize: 16 * fontScale,
          ),
        ),
      ),
      iconTheme: const IconThemeData(
        color: Color(0xFF475569),
      ),
    );
  }
}
