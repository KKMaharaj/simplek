// Serves build/site on http://localhost:8080 for local preview.
// Run: dart run tool/serve.dart [port]
import 'dart:io';

const _types = {
  'html': 'text/html; charset=utf-8',
  'js': 'text/javascript',
  'mjs': 'text/javascript',
  'css': 'text/css',
  'json': 'application/json',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'svg': 'image/svg+xml',
  'ico': 'image/x-icon',
  'wasm': 'application/wasm',
  'otf': 'font/otf',
  'ttf': 'font/ttf',
  'woff2': 'font/woff2',
};

Future<void> main(List<String> args) async {
  final port = args.isEmpty ? 8080 : int.parse(args.first);
  final root = Directory('build/site').absolute;
  if (!root.existsSync()) {
    stderr.writeln('build/site not found. Run tool/build_site.sh first.');
    exit(1);
  }
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('Serving ${root.path} on http://localhost:$port');
  await for (final request in server) {
    var path = Uri.decodeComponent(request.uri.path);
    if (path.contains('..')) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      continue;
    }
    if (path.endsWith('/')) path += 'index.html';
    var file = File('${root.path}$path');
    // Like Cloudflare Pages: /privacy serves privacy.html.
    if (!file.existsSync() && File('${root.path}$path.html').existsSync()) {
      path += '.html';
      file = File('${root.path}$path');
    }
    if (!file.existsSync() && Directory('${root.path}$path').existsSync()) {
      request.response.redirect(Uri.parse('${request.uri.path}/'));
      continue;
    }
    if (!file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      continue;
    }
    final extension = path.split('.').last.toLowerCase();
    request.response.headers.set(
      HttpHeaders.contentTypeHeader,
      _types[extension] ?? 'application/octet-stream',
    );
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    await request.response.addStream(file.openRead());
    await request.response.close();
  }
}
