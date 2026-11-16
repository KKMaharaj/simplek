/// Local file access that works on phones (real files) and on the web
/// (kept in memory for the session and restored from cloud storage).
library;

export 'local_files_io.dart'
    if (dart.library.js_interop) 'local_files_web.dart';
