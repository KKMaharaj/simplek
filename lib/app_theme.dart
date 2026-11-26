import 'package:flutter/material.dart';

/// Simplek's look (UI_REDESIGN_2026-11-25.md): light and colourful, three
/// brand colours shared with the website: navy, orange and sky.
abstract final class SimplekColors {
  // Brand colours.
  static const navy = Color(0xFF0B1A33);
  static const navy2 = Color(0xFF12306B);
  static const navyDeep = Color(0xFF050C1A);
  static const orange = Color(0xFFF26B1D);
  static const orangeText = Color(0xFFC2410C);
  static const orangeTint = Color(0xFFFFF1E8);
  static const sky = Color(0xFF7CCBFF);
  static const skyTint = Color(0xFFE8F5FF);
  static const skyLine = Color(0xFFBFE6FF);
  static const skyText = Color(0xFF1D6FA3);
  static const navyTint = Color(0xFFE7ECF5);
  static const page = Color(0xFFF7F9FC);
  static const line = Color(0xFFE2E8F0);
  static const slate = Color(0xFF475569);
  static const grey = Color(0xFFF1F5F9);

  /// Errors only.
  static const danger = Color(0xFFE5484D);

  // Older names, kept so every screen maps onto the three colours.
  static const brand = orange;
  static const brandDeep = navy;
  static const success = skyText;
  static const warning = orangeText;
  static const violet = navy2;

  // Dark theme: navy page, navy2 cards.
  static const darkPage = navy;
  static const darkCard = navy2;
  static const darkField = Color(0xFF0F2652);
  static const darkLine = Color(0xFF2A4A86);
  static const darkMuted = Color(0xFFB9C6DD);
}

/// Inter for everything, Fraunces 600 for screen titles. Both are variable
/// fonts, so the weight is also set on the 'wght' axis.
TextStyle inter(double size, FontWeight weight, Color color) => TextStyle(
  fontFamily: 'Inter',
  fontSize: size,
  fontWeight: weight,
  fontVariations: [FontVariation('wght', weight.value.toDouble())],
  color: color,
);

TextStyle fraunces(double size, Color color) => TextStyle(
  fontFamily: 'Fraunces',
  fontSize: size,
  fontWeight: FontWeight.w600,
  fontVariations: const [FontVariation('wght', 600), FontVariation('opsz', 48)],
  color: color,
  letterSpacing: -0.3,
  height: 1.15,
);

/// Shrinks a button to 98% while it is pressed (BUILD-STANDARDS 4).
Widget _pressScale(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) => AnimatedScale(
  scale: states.contains(WidgetState.pressed) ? 0.98 : 1,
  duration: const Duration(milliseconds: 80),
  child: child,
);

ThemeData simplekTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final background = dark ? SimplekColors.darkPage : SimplekColors.page;
  final surface = dark ? SimplekColors.darkCard : Colors.white;
  final field = dark ? SimplekColors.darkField : Colors.white;
  final text = dark ? Colors.white : SimplekColors.navy;
  final muted = dark ? SimplekColors.darkMuted : SimplekColors.slate;
  final border = dark ? SimplekColors.darkLine : SimplekColors.line;
  const primary = SimplekColors.orange;
  const onPrimary = SimplekColors.navy;
  final tint = dark ? SimplekColors.navyDeep : SimplekColors.orangeTint;
  final onTint = dark ? SimplekColors.orange : SimplekColors.orangeText;

  final scheme =
      ColorScheme.fromSeed(seedColor: primary, brightness: brightness).copyWith(
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: tint,
        onPrimaryContainer: onTint,
        secondary: dark ? SimplekColors.sky : SimplekColors.navy,
        onSecondary: dark ? SimplekColors.navy : Colors.white,
        secondaryContainer: dark
            ? SimplekColors.navyDeep
            : SimplekColors.skyTint,
        onSecondaryContainer: dark ? SimplekColors.sky : SimplekColors.skyText,
        tertiary: SimplekColors.sky,
        surface: surface,
        onSurface: text,
        onSurfaceVariant: muted,
        surfaceContainerLowest: surface,
        surfaceContainerLow: surface,
        surfaceContainer: surface,
        surfaceContainerHigh: dark
            ? SimplekColors.darkField
            : SimplekColors.grey,
        surfaceContainerHighest: dark
            ? SimplekColors.darkField
            : SimplekColors.grey,
        outline: muted,
        outlineVariant: border,
        error: SimplekColors.danger,
        shadow: const Color(0x140B1A33),
      );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Inter',
  );
  final radius = BorderRadius.circular(12);
  final shape = RoundedRectangleBorder(borderRadius: radius);
  final buttonText = inter(15, FontWeight.w600, text);
  OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: color, width: width),
      );
  WidgetStateProperty<BorderSide?> focusSide([BorderSide? normal]) =>
      WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? const BorderSide(color: SimplekColors.orange, width: 2)
            : normal,
      );

  final textTheme = base.textTheme
      .apply(fontFamily: 'Inter', bodyColor: text, displayColor: text)
      .copyWith(
        headlineMedium: fraunces(30, text),
        headlineSmall: fraunces(26, text),
        titleLarge: inter(18, FontWeight.w700, text),
        titleMedium: inter(16, FontWeight.w600, text),
        titleSmall: inter(14, FontWeight.w600, text),
        bodyLarge: inter(16, FontWeight.w400, text),
        bodyMedium: inter(15, FontWeight.w400, text).copyWith(height: 1.4),
        bodySmall: inter(13, FontWeight.w400, muted),
        labelLarge: buttonText,
        labelMedium: inter(13, FontWeight.w600, text),
        labelSmall: inter(12, FontWeight.w500, muted),
      );

  return base.copyWith(
    scaffoldBackgroundColor: background,
    textTheme: textTheme,
    splashFactory: InkRipple.splashFactory,
    highlightColor: dark ? const Color(0x33BFE6FF) : SimplekColors.skyTint,
    focusColor: SimplekColors.orangeTint,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: text,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      elevation: 0,
      toolbarHeight: 64,
      titleTextStyle: fraunces(26, text),
      actionsIconTheme: IconThemeData(color: text),
    ),
    cardTheme: CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: muted,
      shape: RoundedRectangleBorder(borderRadius: radius),
      titleTextStyle: inter(15.5, FontWeight.w600, text),
      subtitleTextStyle: inter(13, FontWeight.w400, muted),
      selectedColor: onTint,
      selectedTileColor: tint,
    ),
    // Labels sit above fields (FieldLabel); nothing floats inside the box.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: field,
      isDense: false,
      floatingLabelBehavior: FloatingLabelBehavior.never,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: inputBorder(border),
      enabledBorder: inputBorder(border),
      disabledBorder: inputBorder(border.withValues(alpha: 0.5)),
      focusedBorder: inputBorder(SimplekColors.orange, 2),
      errorBorder: inputBorder(SimplekColors.danger),
      focusedErrorBorder: inputBorder(SimplekColors.danger, 2),
      hintStyle: inter(16, FontWeight.w400, muted),
      labelStyle: inter(16, FontWeight.w400, muted),
      helperStyle: inter(12.5, FontWeight.w400, muted),
      errorStyle: inter(12.5, FontWeight.w500, SimplekColors.danger),
      prefixIconColor: muted,
      suffixIconColor: muted,
      helperMaxLines: 3,
      errorMaxLines: 3,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: SimplekColors.orange,
      selectionHandleColor: SimplekColors.orange,
      selectionColor: Color(0x55F26B1D),
    ),
    // Primary: orange with navy text; pressed deepens to #C2410C with white.
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
        shape: WidgetStatePropertyAll(shape),
        textStyle: WidgetStatePropertyAll(buttonText),
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? SimplekColors.orange.withValues(alpha: 0.5)
              : states.contains(WidgetState.pressed)
              ? SimplekColors.orangeText
              : states.contains(WidgetState.hovered)
              ? const Color(0xFFE5600F)
              : SimplekColors.orange,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? SimplekColors.navy.withValues(alpha: 0.5)
              : states.contains(WidgetState.pressed)
              ? Colors.white
              : SimplekColors.navy,
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        side: focusSide(),
        backgroundBuilder: _pressScale,
      ),
    ),
    // Secondary: navy with white text.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
        shape: WidgetStatePropertyAll(shape),
        textStyle: WidgetStatePropertyAll(buttonText),
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? SimplekColors.navy.withValues(alpha: 0.3)
              : states.contains(WidgetState.pressed)
              ? SimplekColors.navyDeep
              : states.contains(WidgetState.hovered)
              ? SimplekColors.navy2
              : (dark ? SimplekColors.navyDeep : SimplekColors.navy),
        ),
        foregroundColor: const WidgetStatePropertyAll(Colors.white),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        side: focusSide(),
        backgroundBuilder: _pressScale,
      ),
    ),
    // Outline: white, sky border, navy text; pressed fills with sky line.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
        shape: WidgetStatePropertyAll(shape),
        textStyle: WidgetStatePropertyAll(buttonText),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.pressed)
              ? (dark ? SimplekColors.navyDeep : SimplekColors.skyLine)
              : states.contains(WidgetState.hovered)
              ? (dark ? SimplekColors.darkField : SimplekColors.skyTint)
              : surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? text.withValues(alpha: 0.4)
              : text,
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        side: focusSide(
          BorderSide(
            color: dark ? SimplekColors.darkLine : SimplekColors.skyLine,
          ),
        ),
        backgroundBuilder: _pressScale,
      ),
    ),
    // Text: orange text.
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        shape: WidgetStatePropertyAll(shape),
        textStyle: WidgetStatePropertyAll(buttonText),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? muted.withValues(alpha: 0.6)
              : (dark ? SimplekColors.orange : SimplekColors.orangeText),
        ),
        overlayColor: WidgetStatePropertyAll(tint),
        side: focusSide(),
        backgroundBuilder: _pressScale,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
        foregroundColor: WidgetStatePropertyAll(text),
        side: focusSide(),
        backgroundBuilder: _pressScale,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? surface
              : (dark ? SimplekColors.darkField : SimplekColors.grey),
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? text : muted,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: border)),
        shape: WidgetStatePropertyAll(shape),
        minimumSize: const WidgetStatePropertyAll(Size(48, 44)),
        textStyle: WidgetStatePropertyAll(inter(14, FontWeight.w600, text)),
      ),
    ),
    chipTheme: ChipThemeData(
      color: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? (dark ? SimplekColors.orange : SimplekColors.navy)
            : surface,
      ),
      side: BorderSide(color: border),
      shape: const StadiumBorder(),
      labelStyle: inter(14, FontWeight.w600, text),
      secondaryLabelStyle: inter(
        14,
        FontWeight.w600,
        dark ? SimplekColors.navy : Colors.white,
      ),
      checkmarkColor: dark ? SimplekColors.navy : SimplekColors.sky,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 72,
      indicatorColor: tint,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? SimplekColors.orange
              : muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? inter(12.5, FontWeight.w700, text)
            : inter(12.5, FontWeight.w500, muted),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: SimplekColors.orange,
      foregroundColor: SimplekColors.navy,
      elevation: 3,
      highlightElevation: 1,
      focusElevation: 3,
      hoverElevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      extendedTextStyle: inter(16, FontWeight.w700, SimplekColors.navy),
      extendedPadding: const EdgeInsets.symmetric(horizontal: 22),
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: fraunces(22, text),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: border),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? Colors.white : SimplekColors.navy,
      contentTextStyle: inter(
        14.5,
        FontWeight.w500,
        dark ? SimplekColors.navy : Colors.white,
      ),
      actionTextColor: dark ? SimplekColors.orangeText : SimplekColors.sky,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: SimplekColors.orange,
      linearTrackColor: tint,
      circularTrackColor: Colors.transparent,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? SimplekColors.orange
            : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(SimplekColors.navy),
      side: BorderSide(color: muted, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? SimplekColors.orange
            : (dark ? SimplekColors.darkField : SimplekColors.line),
      ),
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    radioTheme: const RadioThemeData(
      fillColor: WidgetStatePropertyAll(SimplekColors.orange),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: text,
      unselectedLabelColor: muted,
      indicatorColor: SimplekColors.orange,
      labelStyle: inter(14, FontWeight.w700, text),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: SimplekColors.navy,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: inter(13, FontWeight.w500, Colors.white),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      iconColor: text,
      collapsedIconColor: muted,
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(),
    ),
  );
}

class ThemeModeToggle extends StatelessWidget {
  const ThemeModeToggle({
    super.key,
    required this.mode,
    required this.onChanged,
    this.compact = false,
  });

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  /// Icons only, for tight spaces such as the navigation sidebar.
  final bool compact;

  @override
  Widget build(BuildContext context) => SegmentedButton<ThemeMode>(
    showSelectedIcon: false,
    expandedInsets: compact ? null : EdgeInsets.zero,
    segments: [
      for (final option in const [
        (ThemeMode.light, Icons.light_mode_outlined, 'Light'),
        (ThemeMode.dark, Icons.dark_mode_outlined, 'Dark'),
        (ThemeMode.system, Icons.brightness_auto_outlined, 'Auto'),
      ])
        ButtonSegment(
          value: option.$1,
          icon: Icon(option.$2, size: 20),
          label: compact ? null : Text(option.$3),
          tooltip: option.$3,
        ),
    ],
    selected: {mode},
    onSelectionChanged: (selection) => onChanged(selection.first),
  );
}

/// A soft tinted square holding an icon; used for actions and list leads.
class TintedIcon extends StatelessWidget {
  const TintedIcon(this.icon, {super.key, this.color, this.size = 44});
  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: tint, size: size * 0.5),
    );
  }
}
