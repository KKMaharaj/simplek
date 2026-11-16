import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Accountant access: sharing a business with another Simplek account for
/// view-only use. The server decides what is visible; this class only asks it
/// to switch and remembers which business is on screen.
abstract final class BusinessAccess {
  /// The shared business being viewed, or null when working in your own.
  static final viewing = ValueNotifier<({String ownerId, String name})?>(null);

  /// True while viewing someone else's business. The server refuses changes.
  static bool get readOnly => viewing.value != null;

  static const readOnlyMessage =
      'View-only access. You cannot make changes to this business.';

  static SupabaseClient get _client => Supabase.instance.client;

  /// Businesses other owners have shared with the signed-in account.
  static Future<List<Map<String, dynamic>>> sharedWithMe() async =>
      List<Map<String, dynamic>>.from(
        await _client.rpc('shared_businesses') as List,
      );

  /// Picks up a view started earlier or on another device. The choice is
  /// stored on the server, so it survives restarts.
  static Future<void> restore() async {
    if (_client.auth.currentUser == null) {
      viewing.value = null;
      return;
    }
    try {
      final current = (await sharedWithMe())
          .where((row) => row['viewing'] == true)
          .firstOrNull;
      viewing.value = current == null
          ? null
          : (
              ownerId: current['owner_id'].toString(),
              name: current['business_name']?.toString() ?? 'Business',
            );
    } catch (_) {
      // Offline or the feature is not deployed: stay as we were.
    }
  }

  /// Switches to a shared business, or back to your own with null.
  static Future<void> view(String? ownerId, {String name = 'Business'}) async {
    await _client.rpc('set_viewing_business', params: {'p_owner_id': ownerId});
    viewing.value = ownerId == null ? null : (ownerId: ownerId, name: name);
  }

  /// Emails the signed-in owner has given view access to.
  static Future<List<Map<String, dynamic>>> invites() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];
    return List<Map<String, dynamic>>.from(
      await _client
          .from('business_access')
          .select('id, accountant_email, created_at')
          .eq('owner_id', userId)
          .order('created_at'),
    );
  }

  static Future<void> invite(String email) => _client
      .from('business_access')
      .insert({'accountant_email': email.trim().toLowerCase()});

  static Future<void> remove(String id) =>
      _client.from('business_access').delete().eq('id', id);
}
