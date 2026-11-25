import 'package:flutter/material.dart';

/// Simplek's visual language: soft neutral canvas, white floating cards,
/// one confident blue, pill buttons and generous rounding.
abstract final class SimplekColors {
  static const brand = Color(0xFF3B5BFD);
  static const brandDeep = Color(0xFF2A3FD6);
  static const violet = Color(0xFF7A4DF6);
  static const success = Color(0xFF0FA968);
  static const warning = Color(0xFFE38A0B);
  static const danger = Color(0xFFE5484D);

  // 25 Nov 2026 palette, shared with the website (UI_REDESIGN_2026-11-25.md).
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

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3B5BFD), Color(0xFF6A4DF4)],
  );
}

ThemeData simplekTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final background = Color(dark ? 0xFF0B1020 : 0xFFF3F5FB);
  final surface = Color(dark ? 0xFF151B2E : 0xFFFFFFFF);
  final field = Color(dark ? 0xFF1C2440 : 0xFFF1F4FA);
  final primary = Color(dark ? 0xFF8EA2FF : 0xFF3B5BFD);
  final onPrimary = Color(dark ? 0xFF0B1020 : 0xFFFFFFFF);
  final primaryContainer = Color(dark ? 0xFF243063 : 0xFFE7ECFF);
  final onPrimaryContainer = Color(dark ? 0xFFDCE3FF : 0xFF1F2F9E);
  final text = Color(dark ? 0xFFEEF1FB : 0xFF0E1630);
  final muted = Color(dark ? 0xFF9AA3C0 : 0xFF667091);
  final border = Color(dark ? 0xFF262F4A : 0xFFE2E6F1);

  final scheme =
      ColorScheme.fromSeed(seedColor: primary, brightness: brightness).copyWith(
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primaryContainer,
        onPrimaryContainer: onPrimaryContainer,
        secondaryContainer: primaryContainer,
        onSecondaryContainer: onPrimaryContainer,
        surface: surface,
        onSurface: text,
        onSurfaceVariant: muted,
        surfaceContainerLowest: surface,
        surfaceContainerLow: surface,
        surfaceContainer: surface,
        surfaceContainerHigh: field,
        surfaceContainerHighest: field,
        outline: muted,
        outlineVariant: border,
        error: SimplekColors.danger,
      );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  const pill = StadiumBorder();
  final buttonText = base.textTheme.labelLarge!.copyWith(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );
  OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );

  final textTheme = base.textTheme
      .apply(bodyColor: text, displayColor: text)
      .copyWith(
        headlineMedium: base.textTheme.headlineMedium!.copyWith(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          color: text,
          letterSpacing: -0.8,
        ),
        headlineSmall: base.textTheme.headlineSmall!.copyWith(
          fontSize: 23,
          fontWeight: FontWeight.w800,
          color: text,
          letterSpacing: -0.5,
        ),
        titleLarge: base.textTheme.titleLarge!.copyWith(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: text,
          letterSpacing: -0.2,
        ),
        titleMedium: base.textTheme.titleMedium!.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: text,
        ),
        bodyMedium: base.textTheme.bodyMedium!.copyWith(
          fontSize: 14.5,
          height: 1.4,
          color: text,
        ),
        bodySmall: base.textTheme.bodySmall!.copyWith(
          fontSize: 12.5,
          color: muted,
        ),
        labelLarge: buttonText,
      );

  return base.copyWith(
    scaffoldBackgroundColor: background,
    textTheme: textTheme,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: text,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      elevation: 0,
      titleTextStyle: textTheme.titleLarge!.copyWith(fontSize: 20),
    ),
    cardTheme: CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: dark ? 0 : 1.5,
      shadowColor: const Color(0x141B2559),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: dark ? BorderSide(color: border) : BorderSide.none,
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: muted,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: textTheme.titleMedium!.copyWith(fontSize: 15.5),
      subtitleTextStyle: textTheme.bodySmall!.copyWith(fontSize: 13),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? field : surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: inputBorder(border),
      enabledBorder: inputBorder(border),
      focusedBorder: inputBorder(primary, 1.8),
      errorBorder: inputBorder(SimplekColors.danger),
      focusedErrorBorder: inputBorder(SimplekColors.danger, 1.8),
      labelStyle: TextStyle(color: muted),
      floatingLabelStyle: TextStyle(
        color: primary,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(color: muted),
      prefixIconColor: muted,
      suffixIconColor: muted,
      helperMaxLines: 3,
      errorMaxLines: 3,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: pill,
        textStyle: buttonText,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: pill,
        elevation: 0,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: pill,
        foregroundColor: text,
        side: BorderSide(color: border, width: 1.2),
        textStyle: buttonText,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: pill,
        textStyle: buttonText,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: dark ? field : background,
        selectedBackgroundColor: primary,
        selectedForegroundColor: onPrimary,
        foregroundColor: muted,
        side: BorderSide.none,
        shape: pill,
        minimumSize: const Size(48, 46),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: dark ? field : surface,
      selectedColor: primaryContainer,
      side: BorderSide(color: border),
      shape: pill,
      labelStyle: TextStyle(color: text, fontWeight: FontWeight.w500),
      checkmarkColor: onPrimaryContainer,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 70,
      indicatorColor: primaryContainer,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? onPrimaryContainer
              : muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? text : muted,
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: onPrimary,
      elevation: 4,
      highlightElevation: 6,
      shape: pill,
      extendedTextStyle: buttonText,
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      titleTextStyle: textTheme.titleLarge,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFFEEF1FB) : const Color(0xFF0E1630),
      contentTextStyle: TextStyle(
        color: dark ? const Color(0xFF0E1630) : Colors.white,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: primary,
      linearTrackColor: primaryContainer,
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
  );
}

/// Light / dark / automatic switch. One tap, all three choices visible.
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
