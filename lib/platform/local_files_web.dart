import 'dart:typed_data';

import 'package:flutter/widgets.dart';

final _files = <String, Uint8List>{};

bool get isAndroidDevice => false;

bool isNetworkError(Object error) => false;

bool localFileExists(String? path) => path != null && _files.containsKey(path);

Future<Uint8List?> readLocalFile(String? path) async => _files[path];

Future<String> writeTempFile(String name, List<int> bytes) async {
  final path = 'memory://temp/$name';
  _files[path] = Uint8List.fromList(bytes);
  return path;
}

Future<String> writeAppFile(String name, List<int> bytes) async {
  final path = 'memory://app/$name';
  _files[path] = Uint8List.fromList(bytes);
  return path;
}

Widget localImage(String path, {BoxFit fit = BoxFit.contain}) {
  final bytes = _files[path];
  return bytes == null
      ? const SizedBox.shrink()
      : Image.memory(bytes, fit: fit);
}

/// Removes a file kept in memory for this session.
Future<void> deleteLocalFile(String? path) async => _files.remove(path);
