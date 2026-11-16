// Packs build/site into build/simplek-site.zip for upload to a static host.
// Uses forward-slash paths; Windows PowerShell's Compress-Archive writes
// backslashes, which hosts read as flat file names and the web app breaks.
// Run: dart run tool/zip_site.dart
import 'dart:io';

import 'package:archive/archive_io.dart';

void main() {
  final root = Directory('build/site');
  if (!root.existsSync()) {
    stderr.writeln('build/site not found. Run tool/build_site.sh first.');
    exit(1);
  }
  final archive = Archive();
  final prefix = root.absolute.path.length + 1;
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File) continue;
    final name = entity.absolute.path.substring(prefix).replaceAll('\\', '/');
    if (name.split('/').last == '.last_build_id') continue;
    final bytes = entity.readAsBytesSync();
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }
  final output = File('build/simplek-site.zip');
  output.writeAsBytesSync(ZipEncoder().encode(archive));
  stdout.writeln('${archive.length} files -> ${output.path}');
}
