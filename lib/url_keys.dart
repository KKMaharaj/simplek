/// The query keys the lists own in the web address ([withListQuery]).
const listUrlKeys = {
  'tab',
  'page',
  'q',
  'status',
  'period',
  'from',
  'to',
  'sort',
};

/// [href] with the list keys set to [params]: keys missing from [params] or
/// empty are removed, every other query value and the `#…` part are kept.
String withListQuery(String href, Map<String, String> params) {
  final hash = href.indexOf('#');
  final fragment = hash < 0 ? '' : href.substring(hash);
  final beforeHash = hash < 0 ? href : href.substring(0, hash);
  final question = beforeHash.indexOf('?');
  final path = question < 0 ? beforeHash : beforeHash.substring(0, question);
  final old = question < 0
      ? const <String, String>{}
      : Uri.splitQueryString(beforeHash.substring(question + 1));
  final kept = <String, String>{
    for (final entry in old.entries)
      if (!listUrlKeys.contains(entry.key)) entry.key: entry.value,
    for (final entry in params.entries)
      if (listUrlKeys.contains(entry.key) && entry.value.isNotEmpty)
        entry.key: entry.value,
  };
  final query = kept.isEmpty ? '' : '?${Uri(queryParameters: kept).query}';
  return '$path$query$fragment';
}
