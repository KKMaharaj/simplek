/// Shared form pieces: labels above fields, Yes / No choices, code-style
/// formatters and GSTIN checks. Every form uses these, so fields behave the
/// same everywhere (CR-25 changes 1 to 3, UI-25 section 3).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';

/// Upper-case letters and digits only, at most [maxLength] characters. For
/// PAN (10), IFSC (11) and GSTIN (15). Works on web and with physical
/// keyboards, where `textCapitalization` does nothing.
List<TextInputFormatter> upperCaseCodeFormatters(int maxLength) => [
  FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
  LengthLimitingTextInputFormatter(maxLength),
  const _UpperCaseFormatter(),
];

class _UpperCaseFormatter extends TextInputFormatter {
  const _UpperCaseFormatter();
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}

final _gstinPattern = RegExp(
  r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$',
);
const _gstinAlphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

/// The 15th character of a GSTIN, computed from the first 14 (the GSTN
/// checksum: base 36, alternate weights 1 and 2).
String gstinCheckCharacter(String first14) {
  var sum = 0;
  for (var i = 0; i < 14; i++) {
    final value = _gstinAlphabet.indexOf(first14[i]);
    final product = value * (i.isEven ? 1 : 2);
    sum += product ~/ 36 + product % 36;
  }
  return _gstinAlphabet[(36 - sum % 36) % 36];
}

/// Pattern plus checksum (BUILD-STANDARDS section 1).
bool isValidGstin(String value) {
  final gstin = value.trim().toUpperCase();
  if (!_gstinPattern.hasMatch(gstin)) return false;
  return gstinCheckCharacter(gstin.substring(0, 14)) == gstin[14];
}

/// Error text for a GSTIN field, or null when it's fine.
String? gstinError(String? value, {bool required = false}) {
  final gstin = (value ?? '').trim().toUpperCase();
  if (gstin.isEmpty) return required ? 'Enter the GSTIN' : null;
  if (gstin.length != 15) return 'A GSTIN has 15 characters';
  if (!_gstinPattern.hasMatch(gstin)) return 'Enter a valid GSTIN';
  if (!isValidGstin(gstin)) {
    return 'This GSTIN fails its check digit. Check for a typing mistake.';
  }
  return null;
}

/// The words shown after a GSTIN lookup. Uses the provider's real status;
/// never assumes "Active".
String gstinStatusMessage(Object? status) {
  final text = status?.toString().trim() ?? '';
  return text.isEmpty
      ? 'GSTIN found. The provider did not return a status.'
      : 'GSTIN found. Status: $text';
}

/// The label above a field: 13 px, semi-bold, with an orange * when required
/// or a grey "(optional)".
class FieldLabel extends StatelessWidget {
  const FieldLabel(
    this.text, {
    super.key,
    this.required = false,
    this.optional = false,
  });

  final String text;
  final bool required;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          text: text,
          children: [
            if (required)
              const TextSpan(
                text: ' *',
                style: TextStyle(color: SimplekColors.orangeText),
              ),
            if (optional)
              TextSpan(
                text: ' (optional)',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w400,
                ),
              ),
          ],
        ),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// A field with its label above it.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.required = false,
    this.optional = false,
  });

  final String label;
  final Widget child;
  final bool required;
  final bool optional;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      FieldLabel(label, required: required, optional: optional),
      child,
    ],
  );
}

/// Two buttons side by side: "Yes, …" and "No, …". Nothing is selected until
/// the user picks, so a business can't slip through as "not registered".
class YesNoChoice extends StatelessWidget {
  const YesNoChoice({
    super.key,
    required this.value,
    required this.onChanged,
    this.yesLabel = 'Yes',
    this.noLabel = 'No',
    this.errorText,
  });

  final bool? value;
  final ValueChanged<bool>? onChanged;
  final String yesLabel;
  final String noLabel;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget option(bool choice, String label) {
      final selected = value == choice;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          child: OutlinedButton.icon(
            key: ValueKey('yes-no-$choice'),
            onPressed: onChanged == null ? null : () => onChanged!(choice),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              backgroundColor: selected ? SimplekColors.navy : null,
              foregroundColor: selected
                  ? Colors.white
                  : theme.colorScheme.onSurface,
              side: BorderSide(
                color: selected
                    ? SimplekColors.navy
                    : (errorText != null
                          ? theme.colorScheme.error
                          : SimplekColors.skyLine),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: selected
                ? const Icon(Icons.check, color: SimplekColors.sky, size: 18)
                : const SizedBox.shrink(),
            label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              option(true, yesLabel),
              const SizedBox(width: 10),
              option(false, noLabel),
            ],
          ),
          if (errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                errorText!,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontSize: 12.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// [YesNoChoice] inside a form: fails validation with "Select Yes or No"
/// until one is chosen.
class YesNoFormField extends FormField<bool> {
  YesNoFormField({
    super.key,
    super.initialValue,
    required ValueChanged<bool> onChanged,
    String yesLabel = 'Yes',
    String noLabel = 'No',
    bool enabled = true,
  }) : super(
         validator: (value) => value == null ? 'Select Yes or No' : null,
         builder: (field) => YesNoChoice(
           value: field.value,
           yesLabel: yesLabel,
           noLabel: noLabel,
           errorText: field.errorText,
           onChanged: enabled
               ? (value) {
                   field.didChange(value);
                   onChanged(value);
                 }
               : null,
         ),
       );
}

/// Centres a form and keeps it at most [maxWidth] wide, so fields and
/// choices don't stretch across a wide browser window.
class FormWidth extends StatelessWidget {
  const FormWidth({super.key, required this.child, this.maxWidth = 640});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
