import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// True when the server definitely refused a queued item, so retrying the same
/// payload can never work: raised business rules, invalid data and constraint
/// violations. Everything else (network, expired session, an API that is not
/// deployed yet) may succeed later, so the item stays queued. That includes a
/// foreign key error (23503): the item may reference a product that is itself
/// still waiting to sync.
bool isPermanentSyncRejection(Object error) {
  if (error is! PostgrestException) return false;
  final code = error.code ?? '';
  if (code == '23503') return false;
  return code == 'P0001' || code.startsWith('22') || code.startsWith('23');
}

String syncRejectionReason(Object error) =>
    error is PostgrestException ? error.message : error.toString();

/// Persistent first-in, first-out queues of writes waiting for the network.
///
/// Items leave a queue one at a time as they are processed, so anything added
/// during a sync survives, and an app kill mid-sync resends only what had not
/// finished. Items are identified by `id`, or `_queue_id` if they have none.
abstract final class OfflineQueue {
  static final _tails = <String, Future<void>>{};
  static final _draining = <String>{};

  /// Runs read-modify-write steps on one stored list strictly one at a time.
  static Future<T> _locked<T>(String key, Future<T> Function() action) {
    final result = (_tails[key] ?? Future<void>.value()).then((_) => action());
    _tails[key] = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  static Future<List<Map<String, dynamic>>> read(String key) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(key);
    if (encoded == null || encoded.isEmpty) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(encoded) as List);
    } catch (_) {
      return [];
    }
  }

  static Future<void> _write(
    String key,
    List<Map<String, dynamic>> rows,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(key, jsonEncode(rows));
  }

  static Object? _identity(Map<String, dynamic> item) =>
      item['id'] ?? item['_queue_id'];

  static Future<void> add(String key, Map<String, dynamic> payload) =>
      _locked(key, () async {
        final queued = Map<String, dynamic>.from(payload);
        if (_identity(queued) == null) queued['_queue_id'] = const Uuid().v4();
        final queue = await read(key);
        queue.removeWhere((item) => _identity(item) == _identity(queued));
        queue.add(queued);
        await _write(key, queue);
      });

  /// Sends queued items in order and returns how many were sent.
  ///
  /// A permanent rejection moves that item to [rejectedKey] and carries on, so
  /// one bad item cannot block the rest. Any other failure stops the sync and
  /// keeps the item and everything after it, in order. A call made while the
  /// same queue is already syncing returns 0 rather than sending items twice.
  static Future<int> drain({
    required String key,
    required String rejectedKey,
    required Future<void> Function(Map<String, dynamic> item) send,
  }) async {
    if (!_draining.add(key)) return 0;
    var synced = 0;
    try {
      final snapshot = await _locked(key, () => read(key));
      for (final item in snapshot) {
        try {
          await send(item);
          synced++;
        } catch (error) {
          if (!isPermanentSyncRejection(error)) break;
          await _locked(rejectedKey, () async {
            final rejected = await read(rejectedKey);
            rejected.add({'item': item, 'reason': syncRejectionReason(error)});
            await _write(rejectedKey, rejected);
          });
        }
        await _locked(key, () async {
          final queue = await read(key);
          queue.removeWhere((row) => _identity(row) == _identity(item));
          await _write(key, queue);
        });
      }
    } finally {
      _draining.remove(key);
    }
    return synced;
  }

  /// Returns rejected items and clears them, for showing to the user once.
  static Future<List<Map<String, dynamic>>> takeRejected(String rejectedKey) =>
      _locked(rejectedKey, () async {
        final rejected = await read(rejectedKey);
        if (rejected.isNotEmpty) await _write(rejectedKey, []);
        return rejected;
      });
}
