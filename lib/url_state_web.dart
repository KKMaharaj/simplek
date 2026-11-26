import 'package:web/web.dart' as web;

import 'url_keys.dart';

/// The web app: reads and rewrites the list keys in the query part of the
/// address. Other query values (a sign-in link's `code`, `signup`) and the
/// part after `#`, which belongs to Flutter's own navigation, are kept, and
/// so is the history entry's state, so Back and Forward work as before.
abstract final class UrlState {
  static Map<String, String> read() =>
      Uri.parse(web.window.location.href).queryParameters;

  /// Sets the list keys to [params] (empty values are removed) without
  /// adding a history entry.
  static void replace(Map<String, String> params) {
    final href = web.window.location.href;
    final next = withListQuery(href, params);
    if (next == href) return;
    web.window.history.replaceState(web.window.history.state, '', next);
  }
}
