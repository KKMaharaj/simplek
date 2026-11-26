import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

bool get isAndroidDevice => Platform.isAndroid;

bool isNetworkError(Object error) => error is SocketException;

bool localFileExists(String? path) =>
    path != null && path.isNotEmpty && File(path).existsSync();

Future<Uint8List?> readLocalFile(String? path) async =>
    localFileExists(path) ? File(path!).readAsBytes() : null;

/// Writes a short-lived file (picked images, exports) and returns its path.
Future<String> writeTempFile(String name, List<int> bytes) async {
  final path = '${Directory.systemTemp.path}${Platform.pathSeparator}$name';
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}

/// Writes a file that survives app restarts and returns its path.
Future<String> writeAppFile(String name, List<int> bytes) async {
  final directory = await getApplicationDocumentsDirectory();
  final path = '${directory.path}${Platform.pathSeparator}$name';
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}

Widget localImage(String path, {BoxFit fit = BoxFit.contain}) =>
    Image.file(File(path), fit: fit);

/// Removes a file written by [writeAppFile] or [writeTempFile], if it exists.
Future<void> deleteLocalFile(String? path) async {
  if (!localFileExists(path)) return;
  try {
    await File(path!).delete();
  } catch (_) {
    // Already gone or in use; the next account overwrites it anyway.
  }
}
