/// The list being viewed, kept in the web address (CR-25B B2): the tab, the
/// page, the search, the filters and the sort, as query parameters such as
/// `?tab=invoices&page=3&status=unpaid&period=this_month`. Refresh and Back
/// then return to the same view. On phones there is no address bar, so
/// [UrlState.read] is empty and [UrlState.replace] does nothing.
library;

export 'url_keys.dart';
export 'url_state_io.dart' if (dart.library.js_interop) 'url_state_web.dart';
