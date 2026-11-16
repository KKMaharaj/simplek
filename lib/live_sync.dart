import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps open screens current when the same account changes data on another
/// device, for example an invoice saved in the web app while the phone app is
/// open. Row-level security limits the events to the signed-in business.
abstract final class LiveSync {
  static const _tables = ['invoices', 'quotations', 'customers', 'products'];

  /// Increments shortly after a change arrives from the server.
  static final changes = ValueNotifier(0);

  static RealtimeChannel? _channel;
  static String? _userId;
  static Timer? _debounce;

  /// Starts listening for the signed-in user, or stops when signed out.
  static void sync() {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == _userId) return;
    stop();
    if (userId == null) return;
    _userId = userId;
    var channel = client.channel('simplek-live-$userId');
    for (final table in _tables) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => _notify(),
      );
    }
    _channel = channel..subscribe();
  }

  static void _notify() {
    // One save touches several rows; refresh once for the burst.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () => changes.value++);
  }

  static void stop() {
    _debounce?.cancel();
    final channel = _channel;
    _channel = null;
    _userId = null;
    if (channel != null) Supabase.instance.client.removeChannel(channel);
  }
}
