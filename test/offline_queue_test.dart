import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simplek/offline_queue.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const key = 'queue';
  const rejectedKey = 'rejected';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<List<Object?>> queuedIds() async =>
      (await OfflineQueue.read(key)).map((row) => row['id']).toList();

  test('an item added during a sync is not lost', () async {
    await OfflineQueue.add(key, {'id': 'a'});
    final sending = Completer<void>();
    final release = Completer<void>();
    final drain = OfflineQueue.drain(
      key: key,
      rejectedKey: rejectedKey,
      send: (_) async {
        sending.complete();
        await release.future;
      },
    );
    await sending.future;
    await OfflineQueue.add(key, {'id': 'b'});
    release.complete();

    expect(await drain, 1);
    expect(await queuedIds(), ['b']);
  });

  test('a network failure keeps the item and everything after it', () async {
    for (final id in ['a', 'b', 'c']) {
      await OfflineQueue.add(key, {'id': id});
    }
    final sent = <Object?>[];
    final synced = await OfflineQueue.drain(
      key: key,
      rejectedKey: rejectedKey,
      send: (item) async {
        if (item['id'] == 'b') throw Exception('Connection reset');
        sent.add(item['id']);
      },
    );

    expect(synced, 1);
    expect(sent, ['a']);
    expect(await queuedIds(), ['b', 'c']);
    expect(await OfflineQueue.takeRejected(rejectedKey), isEmpty);
  });

  test('a rejected item is set aside and later items still sync', () async {
    for (final id in ['a', 'b']) {
      await OfflineQueue.add(key, {'id': id});
    }
    final sent = <Object?>[];
    final synced = await OfflineQueue.drain(
      key: key,
      rejectedKey: rejectedKey,
      send: (item) async {
        if (item['id'] == 'a') {
          throw const PostgrestException(
            message: 'Payment cannot exceed outstanding balance',
            code: 'P0001',
          );
        }
        sent.add(item['id']);
      },
    );

    expect(synced, 1);
    expect(sent, ['b']);
    expect(await queuedIds(), isEmpty);

    final rejected = await OfflineQueue.takeRejected(rejectedKey);
    expect(rejected.single['item']['id'], 'a');
    expect(
      rejected.single['reason'],
      'Payment cannot exceed outstanding balance',
    );
    expect(await OfflineQueue.takeRejected(rejectedKey), isEmpty);
  });

  test('overlapping syncs send each item once', () async {
    await OfflineQueue.add(key, {'id': 'a'});
    final release = Completer<void>();
    var sends = 0;
    Future<void> send(Map<String, dynamic> _) async {
      sends++;
      await release.future;
    }

    final first = OfflineQueue.drain(
      key: key,
      rejectedKey: rejectedKey,
      send: send,
    );
    final second = OfflineQueue.drain(
      key: key,
      rejectedKey: rejectedKey,
      send: send,
    );
    expect(await second, 0);
    release.complete();
    expect(await first, 1);
    expect(sends, 1);
  });

  test('re-adding an item with the same identity replaces it', () async {
    await OfflineQueue.add(key, {'_queue_id': 'x', 'amount': 1});
    await OfflineQueue.add(key, {'_queue_id': 'x', 'amount': 2});
    final rows = await OfflineQueue.read(key);
    expect(rows.single['amount'], 2);
  });

  test('items without an identity are given one', () async {
    await OfflineQueue.add(key, {'amount': 1});
    await OfflineQueue.add(key, {'amount': 2});
    final rows = await OfflineQueue.read(key);
    expect(rows, hasLength(2));
    expect(rows.first['_queue_id'], isNot(rows.last['_queue_id']));
  });

  test('only definite server refusals count as permanent', () {
    PostgrestException refusal(String? code) =>
        PostgrestException(message: 'x', code: code);

    expect(isPermanentSyncRejection(refusal('P0001')), isTrue);
    expect(isPermanentSyncRejection(refusal('22P02')), isTrue);
    expect(isPermanentSyncRejection(refusal('23514')), isTrue);
    // Unsynced references, expired session, RLS, undeployed API and network
    // problems must retry.
    expect(isPermanentSyncRejection(refusal('23503')), isFalse);
    expect(isPermanentSyncRejection(refusal('PGRST301')), isFalse);
    expect(isPermanentSyncRejection(refusal('42501')), isFalse);
    expect(isPermanentSyncRejection(refusal('PGRST202')), isFalse);
    expect(isPermanentSyncRejection(refusal(null)), isFalse);
    expect(isPermanentSyncRejection(Exception('Connection reset')), isFalse);
  });
}
