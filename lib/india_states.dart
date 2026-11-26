/// States, union territories and districts of India.
///
/// The 36 states and UTs come from the Local Government Directory (LGD),
/// https://lgdirectory.gov.in/globalviewstateforcitizen.do (read 25 Nov 2026).
/// Names keep the spelling the app has always saved ("Jammu and Kashmir"),
/// so customers and invoices saved earlier still match. Each state also has
/// its GST state code, which is what tax decisions compare (BUILD-STANDARDS
/// 8.1): never typed names.
///
/// Districts are loaded from `assets/data/states_districts.json`, generated
/// from the LGD district download by `tool/import_lgd.dart`. The same data is
/// in the `states` and `districts` tables on the server.
library;

import 'dart:convert';

class IndiaState {
  const IndiaState({
    required this.name,
    required this.gstCode,
    required this.lgdCode,
    this.isUnionTerritory = false,
  });

  final String name;

  /// Two digits, e.g. "29" for Karnataka. The first two digits of a GSTIN.
  final String gstCode;
  final int lgdCode;
  final bool isUnionTerritory;

  /// "Karnataka (29)".
  String get withCode => '$name ($gstCode)';
}

const indiaStates = <IndiaState>[
  IndiaState(
    name: 'Andaman and Nicobar Islands',
    gstCode: '35',
    lgdCode: 35,
    isUnionTerritory: true,
  ),
  IndiaState(name: 'Andhra Pradesh', gstCode: '37', lgdCode: 28),
  IndiaState(name: 'Arunachal Pradesh', gstCode: '12', lgdCode: 12),
  IndiaState(name: 'Assam', gstCode: '18', lgdCode: 18),
  IndiaState(name: 'Bihar', gstCode: '10', lgdCode: 10),
  IndiaState(
    name: 'Chandigarh',
    gstCode: '04',
    lgdCode: 4,
    isUnionTerritory: true,
  ),
  IndiaState(name: 'Chhattisgarh', gstCode: '22', lgdCode: 22),
  IndiaState(
    name: 'Dadra and Nagar Haveli and Daman and Diu',
    gstCode: '26',
    lgdCode: 38,
    isUnionTerritory: true,
  ),
  IndiaState(name: 'Delhi', gstCode: '07', lgdCode: 7, isUnionTerritory: true),
  IndiaState(name: 'Goa', gstCode: '30', lgdCode: 30),
  IndiaState(name: 'Gujarat', gstCode: '24', lgdCode: 24),
  IndiaState(name: 'Haryana', gstCode: '06', lgdCode: 6),
  IndiaState(name: 'Himachal Pradesh', gstCode: '02', lgdCode: 2),
  IndiaState(
    name: 'Jammu and Kashmir',
    gstCode: '01',
    lgdCode: 1,
    isUnionTerritory: true,
  ),
  IndiaState(name: 'Jharkhand', gstCode: '20', lgdCode: 20),
  IndiaState(name: 'Karnataka', gstCode: '29', lgdCode: 29),
  IndiaState(name: 'Kerala', gstCode: '32', lgdCode: 32),
  IndiaState(
    name: 'Ladakh',
    gstCode: '38',
    lgdCode: 37,
    isUnionTerritory: true,
  ),
  IndiaState(
    name: 'Lakshadweep',
    gstCode: '31',
    lgdCode: 31,
    isUnionTerritory: true,
  ),
  IndiaState(name: 'Madhya Pradesh', gstCode: '23', lgdCode: 23),
  IndiaState(name: 'Maharashtra', gstCode: '27', lgdCode: 27),
  IndiaState(name: 'Manipur', gstCode: '14', lgdCode: 14),
  IndiaState(name: 'Meghalaya', gstCode: '17', lgdCode: 17),
  IndiaState(name: 'Mizoram', gstCode: '15', lgdCode: 15),
  IndiaState(name: 'Nagaland', gstCode: '13', lgdCode: 13),
  IndiaState(name: 'Odisha', gstCode: '21', lgdCode: 21),
  IndiaState(
    name: 'Puducherry',
    gstCode: '34',
    lgdCode: 34,
    isUnionTerritory: true,
  ),
  IndiaState(name: 'Punjab', gstCode: '03', lgdCode: 3),
  IndiaState(name: 'Rajasthan', gstCode: '08', lgdCode: 8),
  IndiaState(name: 'Sikkim', gstCode: '11', lgdCode: 11),
  IndiaState(name: 'Tamil Nadu', gstCode: '33', lgdCode: 33),
  IndiaState(name: 'Telangana', gstCode: '36', lgdCode: 36),
  IndiaState(name: 'Tripura', gstCode: '16', lgdCode: 16),
  IndiaState(name: 'Uttar Pradesh', gstCode: '09', lgdCode: 9),
  IndiaState(name: 'Uttarakhand', gstCode: '05', lgdCode: 5),
  IndiaState(name: 'West Bengal', gstCode: '19', lgdCode: 19),
];

/// Every state and UT name, for pickers.
final indiaStateNames = [for (final state in indiaStates) state.name];

String _key(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]'), '')
    .replaceFirst(RegExp('^the'), '');

/// The state for a name in any case or spacing ("JAMMU AND KASHMIR",
/// "The Dadra And Nagar Haveli And Daman And Diu"), or null.
IndiaState? stateNamed(String name) {
  final key = _key(name);
  if (key.isEmpty) return null;
  for (final state in indiaStates) {
    if (_key(state.name) == key) return state;
  }
  return null;
}

/// The state for a GST state code. "25" (the old Daman and Diu code) maps to
/// the merged UT.
IndiaState? stateForGstCode(String code) {
  final clean = code == '25' ? '26' : code;
  for (final state in indiaStates) {
    if (state.gstCode == clean) return state;
  }
  return null;
}

/// The state from the first two digits of a GSTIN, or null.
IndiaState? stateFromGstin(String gstin) {
  final clean = gstin.trim();
  if (clean.length < 2) return null;
  return stateForGstCode(clean.substring(0, 2));
}

/// Two-digit GST code for a state name, or null.
String? gstStateCode(String state) => stateNamed(state)?.gstCode;

/// "Karnataka (29)", or the name alone when it isn't recognised.
String stateWithCode(String state) {
  final match = stateNamed(state);
  return match == null ? state.trim() : match.withCode;
}

/// True when both names are the same state, compared by GST code.
bool sameGstState(String a, String b) {
  final first = gstStateCode(a);
  final second = gstStateCode(b);
  if (first != null && second != null) return first == second;
  return _key(a) == _key(b);
}

/// Districts of each state, loaded once from the bundled asset.
abstract final class IndiaDistricts {
  static Map<String, List<String>> _byGstCode = const {};
  static bool _loaded = false;

  /// Where the district list came from, from the asset's own header.
  static String source = '';

  static bool get isLoaded => _loaded;

  /// Where the app bundles the list.
  static const assetPath = 'assets/data/states_districts.json';

  /// Loads the list once. [read] returns the asset's text, e.g.
  /// `() => rootBundle.loadString(IndiaDistricts.assetPath)`.
  static Future<void> load(Future<String> Function() read) async {
    if (_loaded) return;
    try {
      loadFromJson(await read());
    } catch (_) {
      // Pickers fall back to typing the district.
      _byGstCode = const {};
      _loaded = true;
    }
  }

  static void loadFromJson(String text) {
    final json = jsonDecode(text) as Map<String, dynamic>;
    source = json['source']?.toString() ?? '';
    final result = <String, List<String>>{};
    for (final row in (json['states'] as List).cast<Map>()) {
      final code = row['gst_state_code']?.toString() ?? '';
      final districts = [
        for (final district in (row['districts'] as List? ?? const []))
          (district is Map ? district['name'] : district).toString(),
      ]..sort();
      if (code.isNotEmpty) result[code] = districts;
    }
    _byGstCode = result;
    _loaded = true;
  }

  /// Districts of [state] (a name), sorted; empty when unknown.
  static List<String> of(String state) {
    final code = gstStateCode(state);
    return code == null ? const [] : (_byGstCode[code] ?? const []);
  }

  /// The district as spelt in the list, matching case and punctuation
  /// loosely, or null when it isn't in [state].
  static String? match(String state, String district) {
    final key = _key(district);
    if (key.isEmpty) return null;
    for (final name in of(state)) {
      if (_key(name) == key) return name;
    }
    return null;
  }
}

/// The business address as one comma-separated line for documents:
/// line 1, line 2, landmark, city, district (only when it differs from the
/// city), then "State PIN". Example: "12 Main Road, Durgigudi, Shivamogga,
/// Karnataka 577201".
String composeBusinessAddress({
  required String line1,
  String line2 = '',
  String landmark = '',
  String city = '',
  String district = '',
  String state = '',
  String pincode = '',
}) {
  String clean(String value) => value
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r',$'), '');
  final cityText = clean(city);
  final districtText = clean(district);
  final statePin = [
    clean(state),
    clean(pincode),
  ].where((part) => part.isNotEmpty).join(' ');
  return [
    clean(line1),
    clean(line2),
    clean(landmark),
    cityText,
    if (districtText.toLowerCase() != cityText.toLowerCase()) districtText,
    statePin,
  ].where((part) => part.isNotEmpty).join(', ');
}
