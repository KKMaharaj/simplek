part of 'main.dart';

// Pieces shared by onboarding and Business Settings (CR-25 changes 1 to 4
// and 11): labelled text fields, the GSTIN lookup, and the business address
// with PIN code, State and District.

/// A text field with its label above the box (UI-25: no floating labels).
Widget _labeledText(
  TextEditingController controller,
  String label, {
  Key? key,
  bool required = false,
  bool optional = false,
  String? hint,
  String? helper,
  int lines = 1,
  int? maxLength,
  TextInputType? keyboardType,
  List<TextInputFormatter>? inputFormatters,
  Iterable<String>? autofillHints,
  TextCapitalization textCapitalization = TextCapitalization.none,
  ValueChanged<String>? onChanged,
  String? Function(String value)? validator,
  Widget? suffix,
  bool enabled = true,
  bool readOnly = false,
}) => LabeledField(
  key: key,
  label: label,
  required: required,
  optional: optional,
  child: TextFormField(
    controller: controller,
    enabled: enabled,
    readOnly: readOnly,
    minLines: lines,
    maxLines: lines,
    keyboardType: keyboardType,
    textCapitalization: textCapitalization,
    autofillHints: autofillHints,
    style: const TextStyle(fontSize: 16),
    inputFormatters: [
      ...?inputFormatters,
      if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
    ],
    autovalidateMode: AutovalidateMode.onUnfocus,
    onChanged: onChanged,
    validator: validator == null ? null : (value) => validator(value ?? ''),
    decoration: InputDecoration(
      hintText: hint,
      helperText: helper,
      suffixIcon: suffix,
      filled: true,
      fillColor: readOnly ? SimplekColors.navyTint : null,
    ),
  ),
);

/// Looks a GSTIN up through the `gstin-lookup` edge function. Returns the
/// provider's data, or throws a [StateError] with words for the user.
Future<Map<String, dynamic>> _lookupGstin(String gstin) async {
  try {
    final response = await Supabase.instance.client.functions
        .invoke('gstin-lookup', body: {'gstin': gstin})
        .timeout(const Duration(seconds: 15));
    final body = response.data;
    if (body is! Map || body['success'] != true || body['data'] is! Map) {
      throw StateError(
        body is Map
            ? body['error']?.toString() ?? 'GSTIN lookup failed.'
            : 'GSTIN lookup failed.',
      );
    }
    return Map<String, dynamic>.from(body['data'] as Map);
  } on FunctionException catch (error) {
    throw StateError(
      error.details is Map
          ? error.details['error']?.toString() ?? 'GSTIN lookup failed.'
          : 'GSTIN lookup failed.',
    );
  } on TimeoutException {
    throw StateError('The GSTIN service did not answer. Please try again.');
  }
}

/// One post office returned by the PIN code lookup.
class _PostOffice {
  const _PostOffice(this.name, this.block, this.district, this.state);
  final String name, block, district, state;

  /// The town to suggest for City: the block (taluk) when India Post gives
  /// one, else the district.
  String get city {
    final clean = block.trim();
    return clean.isEmpty || clean.toUpperCase() == 'NA'
        ? _titleCase(district.toLowerCase())
        : _titleCase(clean.toLowerCase());
  }
}

Future<List<_PostOffice>> _lookupPincode(String pincode) async {
  try {
    final response = await Supabase.instance.client.functions
        .invoke('pincode-lookup', body: {'pincode': pincode})
        .timeout(const Duration(seconds: 10));
    final body = response.data;
    if (body is! Map || body['success'] != true) {
      throw StateError(
        body is Map
            ? body['error']?.toString() ?? _pincodeNotFound
            : _pincodeNotFound,
      );
    }
    return [
      for (final office in (body['offices'] as List).cast<Map>())
        _PostOffice(
          office['name']?.toString() ?? '',
          office['block']?.toString() ?? '',
          office['district']?.toString() ?? '',
          office['state']?.toString() ?? '',
        ),
    ];
  } on FunctionException catch (error) {
    throw StateError(
      error.details is Map
          ? error.details['error']?.toString() ?? _pincodeNotFound
          : _pincodeNotFound,
    );
  } on TimeoutException {
    throw StateError(
      'The PIN code service did not answer. Tap Retry, or fill the address by hand.',
    );
  }
}

const _pincodeNotFound = "We couldn't find this PIN code; please check it.";

String? _pincodeError(String value, {bool required = true}) {
  final pin = value.trim();
  if (pin.isEmpty) return required ? 'Enter the PIN code' : null;
  return RegExp(r'^[1-9][0-9]{5}$').hasMatch(pin)
      ? null
      : 'Enter a 6-digit PIN code that does not start with 0';
}

/// The business address being edited, split into the fields of
/// BUILD-STANDARDS section 2. Country is always India.
class _AddressDraft {
  _AddressDraft.fromProfile(Map<String, String> profile)
    : line1 = TextEditingController(
        text: (profile['addressLine1'] ?? '').trim().isNotEmpty
            ? profile['addressLine1']
            // Businesses set up before 25 Nov 2026 had one free-text box.
            : profile['address'],
      ),
      line2 = TextEditingController(text: profile['addressLine2']),
      landmark = TextEditingController(text: profile['landmark']),
      city = TextEditingController(text: profile['city']),
      pincode = TextEditingController(text: profile['pincode']),
      state = stateNamed(profile['businessState'] ?? '')?.name,
      district = (profile['district'] ?? '').trim().isEmpty
          ? null
          : profile['district']!.trim();

  final TextEditingController line1, line2, landmark, city, pincode;
  String? state;
  String? district;

  /// True for a business that set up before the address was split: the
  /// district or PIN code still has to be chosen.
  bool get incomplete =>
      (district ?? '').isEmpty || pincode.text.trim().isEmpty;

  Map<String, String> toProfile() => {
    'addressLine1': line1.text.trim(),
    'addressLine2': line2.text.trim(),
    'landmark': landmark.text.trim(),
    'city': city.text.trim(),
    'district': district ?? '',
    'pincode': pincode.text.trim(),
    'businessState': state ?? '',
    'address': composeBusinessAddress(
      line1: line1.text,
      line2: line2.text,
      landmark: landmark.text,
      city: city.text,
      district: district ?? '',
      state: state ?? '',
      pincode: pincode.text,
    ),
  };

  void dispose() {
    for (final controller in [line1, line2, landmark, city, pincode]) {
      controller.dispose();
    }
  }
}

/// PIN code first, then address lines, City, State and District
/// (CR-25 change 11). [lockedState] is the state from a registered
/// business's GSTIN: shown read-only.
class _BusinessAddressFields extends StatefulWidget {
  const _BusinessAddressFields({required this.draft, this.lockedState});

  final _AddressDraft draft;
  final String? lockedState;

  @override
  State<_BusinessAddressFields> createState() => _BusinessAddressFieldsState();
}

class _BusinessAddressFieldsState extends State<_BusinessAddressFields> {
  bool _lookingUp = false;
  String? _lookupMessage;
  bool _lookupFailed = false;
  String _lastLookedUp = '';

  /// Used when the state has no district list loaded: the district is typed.
  late final _districtText = TextEditingController(text: widget.draft.district);

  _AddressDraft get _draft => widget.draft;

  @override
  void dispose() {
    _districtText.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    IndiaDistricts.load(
      () => rootBundle.loadString(IndiaDistricts.assetPath),
    ).then((_) {
      if (mounted) setState(() {});
    });
    _applyLockedState();
  }

  @override
  void didUpdateWidget(covariant _BusinessAddressFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lockedState != widget.lockedState) _applyLockedState();
  }

  void _applyLockedState() {
    final locked = widget.lockedState;
    if (locked == null || locked == _draft.state) return;
    _draft.state = locked;
    if (_draft.district != null &&
        IndiaDistricts.match(locked, _draft.district!) == null) {
      _draft.district = null;
    }
  }

  void _setState(String? state) {
    setState(() {
      if (state != _draft.state) {
        _draft.district = null;
        _districtText.clear();
      }
      _draft.state = state;
    });
  }

  Future<void> _lookup({bool force = false}) async {
    final pin = _draft.pincode.text.trim();
    if (_pincodeError(pin) != null) return;
    if (!force && pin == _lastLookedUp) return;
    _lastLookedUp = pin;
    setState(() {
      _lookingUp = true;
      _lookupMessage = null;
      _lookupFailed = false;
    });
    try {
      final offices = await _lookupPincode(pin);
      if (!mounted) return;
      var office = offices.first;
      if (offices.length > 1) {
        final chosen = await showDialog<_PostOffice>(
          context: context,
          builder: (dialogContext) => SimpleDialog(
            title: Text('Choose the post office for $pin'),
            children: [
              for (final option in offices)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(dialogContext).pop(option),
                  child: Text(
                    '${option.name} · ${option.city}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        );
        if (chosen == null || !mounted) {
          setState(() => _lookingUp = false);
          return;
        }
        office = chosen;
      }
      final foundState = stateNamed(office.state)?.name;
      setState(() {
        _draft.city.text = office.city;
        if (widget.lockedState == null && foundState != null) {
          _draft.state = foundState;
        }
        final state = _draft.state;
        final typed = state != null && IndiaDistricts.of(state).isEmpty;
        final district = state == null
            ? null
            : typed
            ? _titleCase(office.district.toLowerCase())
            : IndiaDistricts.match(state, office.district);
        _draft.district = district;
        _districtText.text = district ?? '';
        _lookupMessage = district == null
            ? 'City and state filled from the PIN code. Choose your district.'
            : 'City, district and state filled from the PIN code. You can change them.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _lookupFailed = true;
        _lookupMessage = error is StateError
            ? error.message
            : 'The PIN code service is not answering. Tap Retry, or fill the address by hand.';
      });
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = _draft.state;
    final districts = state == null
        ? const <String>[]
        : IndiaDistricts.of(state);
    const gap = SizedBox(height: 14);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _labeledText(
          _draft.pincode,
          'PIN code',
          required: true,
          hint: '6 digits, e.g. 577201',
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.postalCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          validator: _pincodeError,
          onChanged: (value) {
            if (value.trim().length == 6) _lookup();
          },
          suffix: _lookingUp
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,
        ),
        if (_lookupMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _lookupMessage!,
                    style: TextStyle(
                      fontSize: 13,
                      color: _lookupFailed
                          ? theme.colorScheme.error
                          : SimplekColors.skyText,
                    ),
                  ),
                ),
                if (_lookupFailed)
                  TextButton(
                    onPressed: _lookingUp ? null : () => _lookup(force: true),
                    child: const Text('Retry'),
                  ),
              ],
            ),
          ),
        gap,
        _labeledText(
          _draft.line1,
          'Address line 1',
          required: true,
          hint: 'House or flat, building',
          autofillHints: const [AutofillHints.streetAddressLine1],
          textCapitalization: TextCapitalization.words,
          maxLength: 150,
          validator: (value) => value.trim().length < 3
              ? 'Enter the house or flat and building'
              : null,
        ),
        gap,
        _labeledText(
          _draft.line2,
          'Address line 2',
          optional: true,
          hint: 'Street, area',
          autofillHints: const [AutofillHints.streetAddressLine2],
          textCapitalization: TextCapitalization.words,
          maxLength: 150,
        ),
        gap,
        _labeledText(
          _draft.landmark,
          'Landmark',
          optional: true,
          hint: 'e.g. Opposite the bus stand',
          textCapitalization: TextCapitalization.words,
          maxLength: 150,
        ),
        gap,
        _labeledText(
          _draft.city,
          'City / Town',
          required: true,
          autofillHints: const [AutofillHints.addressCity],
          textCapitalization: TextCapitalization.words,
          maxLength: 100,
          validator: (value) =>
              value.trim().length < 2 ? 'Enter the city or town' : null,
        ),
        gap,
        SearchableStateField(
          label: 'State',
          required: true,
          value: state,
          readOnly: widget.lockedState != null,
          helperText: widget.lockedState != null ? 'From your GSTIN' : null,
          onChanged: widget.lockedState != null ? null : _setState,
          validator: (value) => value == null ? 'Select the state' : null,
        ),
        gap,
        if (state != null && districts.isEmpty)
          _labeledText(
            _districtText,
            'District',
            required: true,
            textCapitalization: TextCapitalization.words,
            maxLength: 100,
            onChanged: (value) =>
                _draft.district = value.trim().isEmpty ? null : value.trim(),
            validator: (value) =>
                value.trim().length < 2 ? 'Enter the district' : null,
          )
        else
          SearchablePickerField(
            label: 'District',
            required: true,
            options: districts,
            value: _draft.district,
            hint: state == null ? 'Choose the state first' : 'Select district',
            searchHint: 'Search districts',
            emptyText: 'No matching districts',
            onChanged: state == null || districts.isEmpty
                ? null
                : (value) {
                    setState(() => _draft.district = value);
                  },
            validator: (value) => value == null || value.isEmpty
                ? (state == null
                      ? 'Choose the state, then the district'
                      : 'Select the district')
                : null,
          ),
      ],
    );
  }
}

/// The state name from a GSTIN once it is complete and valid, else null.
String? _gstinState(String gstin) =>
    isValidGstin(gstin) ? stateFromGstin(gstin)?.name : null;

String? _mobileError(String value) {
  final phone = _normaliseIndianMobile(value);
  return phone.isEmpty || RegExp(r'^[6-9][0-9]{9}$').hasMatch(phone)
      ? null
      : 'Enter a 10-digit mobile number';
}

/// Puts the registered address from a GSTIN lookup into an empty address:
/// the text before the PIN into line 1 (up to 150 characters) and the PIN.
void _fillAddressFromGst(_AddressDraft draft, String address) {
  final text = address.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty || draft.line1.text.trim().isNotEmpty) return;
  final pin = RegExp(r'\b([1-9][0-9]{5})\b').allMatches(text).lastOrNull;
  var street = pin == null ? text : text.substring(0, pin.start);
  street = street.replaceAll(RegExp(r'[\s,-]+$'), '');
  if (street.length > 150) {
    final cut = street.lastIndexOf(',', 150);
    street = street.substring(0, cut > 40 ? cut : 150);
  }
  draft.line1.text = _titleCase(street.toLowerCase());
  if (pin != null && draft.pincode.text.trim().isEmpty) {
    draft.pincode.text = pin.group(1)!;
  }
}
