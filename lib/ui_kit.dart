/// Shared pieces of the 25 Nov 2026 look (UI_REDESIGN_2026-11-25.md,
/// docs/design/Main.png): press feedback, status chips, list rows, coloured
/// icon tiles and the square top-bar buttons. Screens use these instead of
/// styling each widget by hand.
library;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';

bool get _isPhone =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Every tappable card, row or tile: shrinks to 98% for about 80 ms, flashes
/// sky tint, shows a 2 px orange outline under keyboard focus, and gives a
/// light haptic tick on a phone.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.color,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;

  /// Background; transparent when null.
  final Color? color;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;
  bool _focused = false;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: enabled,
      label: widget.semanticLabel,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: const Duration(milliseconds: 80),
        child: Material(
          color: widget.color ?? Colors.transparent,
          borderRadius: widget.borderRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: widget.borderRadius,
            onTap: enabled
                ? () {
                    if (_isPhone) HapticFeedback.lightImpact();
                    widget.onTap!();
                  }
                : null,
            onTapDown: enabled ? (_) => _setPressed(true) : null,
            onTapUp: enabled ? (_) => _setPressed(false) : null,
            onTapCancel: () => _setPressed(false),
            onFocusChange: (value) => setState(() => _focused = value),
            highlightColor: dark
                ? const Color(0x33BFE6FF)
                : SimplekColors.skyTint,
            splashColor: Colors.transparent,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: widget.borderRadius,
                border: _focused
                    ? Border.all(color: SimplekColors.orange, width: 2)
                    : null,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// A white card with a thin border and 16 px corners (no heavy shadow).
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: color ?? scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      padding: padding,
      child: child,
    );
  }
}

/// The colours of one status chip.
({Color background, Color text}) statusColors(String status, bool dark) {
  switch (status.toLowerCase()) {
    case 'paid':
    case 'accepted':
      return dark
          ? (background: const Color(0x337CCBFF), text: SimplekColors.sky)
          : (background: SimplekColors.skyTint, text: SimplekColors.skyText);
    case 'partial':
    case 'overdue':
      return dark
          ? (background: const Color(0x33F26B1D), text: SimplekColors.orange)
          : (
              background: SimplekColors.orangeTint,
              text: SimplekColors.orangeText,
            );
    case 'sent':
      return dark
          ? (background: const Color(0x33E7ECF5), text: Colors.white)
          : (background: SimplekColors.navyTint, text: SimplekColors.navy2);
    default:
      return dark
          ? (background: const Color(0x22FFFFFF), text: SimplekColors.darkMuted)
          : (background: SimplekColors.grey, text: SimplekColors.slate);
  }
}

/// "● Paid": a small dot and the word, so colour is never the only signal.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = statusColors(
      status,
      Theme.of(context).brightness == Brightness.dark,
    );
    final word = status.isEmpty
        ? ''
        : status[0].toUpperCase() + status.substring(1).toLowerCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: colors.text,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            word,
            maxLines: 1,
            style: inter(12, FontWeight.w600, colors.text),
          ),
        ],
      ),
    );
  }
}

/// The three tints that icon tiles and initials cycle through.
enum TileTone { orange, sky, navy }

({Color background, Color foreground}) toneColors(
  TileTone tone,
  bool dark,
) => switch (tone) {
  TileTone.orange =>
    dark
        ? (
            background: const Color(0x33F26B1D),
            foreground: SimplekColors.orange,
          )
        : (
            background: SimplekColors.orangeTint,
            foreground: SimplekColors.orangeText,
          ),
  TileTone.sky =>
    dark
        ? (background: const Color(0x337CCBFF), foreground: SimplekColors.sky)
        : (
            background: SimplekColors.skyTint,
            foreground: SimplekColors.skyText,
          ),
  TileTone.navy =>
    dark
        ? (background: const Color(0x33E7ECF5), foreground: Colors.white)
        : (background: SimplekColors.navyTint, foreground: SimplekColors.navy2),
};

/// A stable tone for a name, so a customer keeps its colour.
TileTone toneFor(String text) =>
    TileTone.values[text.trim().isEmpty ? 0 : text.trim().codeUnitAt(0) % 3];

/// A rounded square with an icon on a tint.
class IconTile extends StatelessWidget {
  const IconTile(
    this.icon, {
    super.key,
    this.tone = TileTone.orange,
    this.size = 44,
  });
  final IconData icon;
  final TileTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = toneColors(
      tone,
      Theme.of(context).brightness == Brightness.dark,
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(size * 0.27),
      ),
      child: Icon(icon, color: colors.foreground, size: size * 0.5),
    );
  }
}

/// A rounded square with the first letter of a name.
class InitialTile extends StatelessWidget {
  const InitialTile(this.name, {super.key, this.size = 42});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = toneColors(
      toneFor(name),
      Theme.of(context).brightness == Brightness.dark,
    );
    final initial = name.trim().isEmpty ? '#' : name.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(size * 0.27),
      ),
      child: Text(
        initial,
        style: inter(size * 0.4, FontWeight.w700, colors.foreground),
      ),
    );
  }
}

/// One list row: a leading tile, a name and a detail line, and a trailing
/// amount or chip. Text never wraps into its neighbours.
class ListRowTile extends StatelessWidget {
  const ListRowTile({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle = '',
    this.trailingTop,
    this.trailingBottom,
    this.trailing,
    this.onTap,
    this.showChevron = false,
  });

  final Widget leading;
  final String title;
  final String subtitle;

  /// Usually the amount.
  final Widget? trailingTop;

  /// Usually a [StatusChip].
  final Widget? trailingBottom;

  /// Replaces the two trailing slots, e.g. a menu button.
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ] else if (trailingTop != null || trailingBottom != null) ...[
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ?trailingTop,
                    if (trailingTop != null && trailingBottom != null)
                      const SizedBox(height: 5),
                    ?trailingBottom,
                  ],
                ),
              ],
              if (showChevron) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Rows inside one bordered card, with thin dividers between them.
class RowGroup extends StatelessWidget {
  const RowGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SectionCard(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (final (index, child) in children.indexed) ...[
          if (index > 0) const Divider(height: 1),
          child,
        ],
      ],
    ),
  );
}

/// The 44 px square outline icon button used in top bars.
class SquareIconButton extends StatelessWidget {
  const SquareIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Pressable(
        onTap: onPressed,
        semanticLabel: tooltip,
        borderRadius: BorderRadius.circular(12),
        color: scheme.surface,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Icon(icon, size: 22, color: scheme.onSurface),
        ),
      ),
    );
  }
}

/// Section heading in small orange capitals ("BRANDING", "NOVEMBER 2026").
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.muted = false});
  final String text;

  /// Slate instead of orange, for month groups in lists.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: inter(
          12.5,
          FontWeight.w700,
          muted
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : (dark ? SimplekColors.orange : SimplekColors.orangeText),
        ).copyWith(letterSpacing: 0.8),
      ),
    );
  }
}

/// A small tile with a label and a figure ("To collect ₹19,800.00").
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.tone,
    this.filled = false,
  });
  final String label;
  final String value;

  /// Tint and label colour; null for a plain white tile.
  final TileTone? tone;

  /// Navy tile with white text (Reports "Sales").
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final colors = tone == null ? null : toneColors(tone!, dark);
    final background = filled
        ? (dark ? SimplekColors.navyDeep : SimplekColors.navy)
        : colors?.background ?? theme.colorScheme.surface;
    final labelColor = filled
        ? SimplekColors.sky
        : colors?.foreground ?? theme.colorScheme.onSurfaceVariant;
    final valueColor = filled ? Colors.white : theme.colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: tone == null && !filled
            ? Border.all(color: theme.colorScheme.outlineVariant)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: inter(13, FontWeight.w600, labelColor),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: inter(19, FontWeight.w700, valueColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// The orange floating "Create" style button with its label always visible.
class CreateButton extends StatelessWidget {
  const CreateButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.add,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) => FloatingActionButton.extended(
    heroTag: null,
    onPressed: onPressed,
    icon: Icon(icon),
    label: Text(label, maxLines: 1),
  );
}

/// Empty list: a short message and the next action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => SectionCard(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        IconTile(icon, size: 56),
        const SizedBox(height: 14),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 14),
          FilledButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ],
    ),
  );
}

/// Grey placeholder rows while a list loads (never a blank page).
class SkeletonRows extends StatelessWidget {
  const SkeletonRows({super.key, this.count = 5});
  final int count;

  @override
  Widget build(BuildContext context) {
    final shade = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: shade,
        borderRadius: BorderRadius.circular(6),
      ),
    );
    return RowGroup(
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: shade,
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(150, 12),
                      const SizedBox(height: 8),
                      bar(100, 10),
                    ],
                  ),
                ),
                bar(70, 12),
              ],
            ),
          ),
      ],
    );
  }
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Dates on screens: "19 Nov 2026" (BUILD-STANDARDS 1). PDFs keep
/// DD/MM/YYYY.
String screenDate(DateTime? date) => date == null
    ? '-'
    : '${date.day.toString().padLeft(2, '0')} ${_months[date.month - 1]} ${date.year}';

/// "NOVEMBER 2026", for month groups.
String monthHeading(DateTime date) {
  const names = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${names[date.month - 1]} ${date.year}';
}
