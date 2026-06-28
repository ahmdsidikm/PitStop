import 'package:uuid/uuid.dart';
import '../database/supabase.dart';
import 'local_cache.dart';
import 'connectivity_service.dart';
import 'sync_manager.dart';

class KendaraanRepository {
  static KendaraanRepository? _instance;
  static KendaraanRepository get instance =>
      _instance ??= KendaraanRepository._();
  KendaraanRepository._();

  static const _table = 'kendaraan';
  final _uuid = const Uuid();

  Future<List<Map<String, dynamic>>> getAll() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    if (ConnectivityService.instance.isOnline) {
      try {
        final data = await supabase
            .from(_table)
            .select()
            .eq('user_id', userId)
            .order('created_at', ascending: false);
        final list = List<Map<String, dynamic>>.from(data);
        await LocalCache.instance.writeTable(_table, list);
        return list;
      } catch (_) {}
    }

    final cached = await LocalCache.instance.readTable(_table);
    return cached.where((k) => k['user_id'] == userId).toList();
  }

  Future<void> insert(Map<String, dynamic> data) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final payload = Map<String, dynamic>.from(data);
    payload['user_id'] = userId;

    if (ConnectivityService.instance.isOnline) {
      await supabase.from(_table).insert(payload);
      await SyncManager.instance.refreshCache();
    } else {
      final tempId = _uuid.v4();
      payload['id'] = tempId;
      payload['created_at'] = DateTime.now().toIso8601String();

      final cached = await LocalCache.instance.readTable(_table);
      cached.insert(0, payload);
      await LocalCache.instance.writeTable(_table, cached);

      await LocalCache.instance.addPendingChange(
        table: _table,
        operation: 'insert',
        data: payload,
        recordId: tempId,
      );
    }
  }

  Future<void> update(String id, Map<String, dynamic> data) async {
    if (ConnectivityService.instance.isOnline) {
      await supabase.from(_table).update(data).eq('id', id);
      await SyncManager.instance.refreshCache();
    } else {
      final cached = await LocalCache.instance.readTable(_table);
      final idx = cached.indexWhere((k) => k['id'] == id);
      if (idx != -1) {
        cached[idx] = {...cached[idx], ...data};
        await LocalCache.instance.writeTable(_table, cached);
      }

      await LocalCache.instance.addPendingChange(
        table: _table,
        operation: 'update',
        data: data,
        recordId: id,
      );
    }
  }

  Future<void> delete(String id) async {
    if (ConnectivityService.instance.isOnline) {
      await supabase.from(_table).delete().eq('id', id);
      await SyncManager.instance.refreshCache();
    } else {
      final cached = await LocalCache.instance.readTable(_table);
      cached.removeWhere((k) => k['id'] == id);
      await LocalCache.instance.writeTable(_table, cached);

      final pending = await LocalCache.instance.readPendingChanges();
      final filteredPending =
          pending.where((c) => c['record_id'] != id).toList();
      await LocalCache.instance.writePendingChanges(filteredPending);

      await LocalCache.instance.addPendingChange(
        table: _table,
        operation: 'delete',
        data: {'id': id},
        recordId: id,
      );
    }
  }

  Future<void> updateKm(String id, int kmBaru) async {
    final cached = await LocalCache.instance.readTable(_table);
    final idx = cached.indexWhere((k) => k['id'] == id);
    if (idx != -1) {
      cached[idx] = {...cached[idx], 'km_sekarang': kmBaru};
      await LocalCache.instance.writeTable(_table, cached);
    }

    if (ConnectivityService.instance.isOnline) {
      try {
        await supabase
            .from(_table)
            .update({'km_sekarang': kmBaru})
            .eq('id', id);
      } catch (e) {
        await LocalCache.instance.addPendingChange(
          table: _table,
          operation: 'update',
          data: {'km_sekarang': kmBaru},
          recordId: id,
        );
      }
    } else {
      await LocalCache.instance.addPendingChange(
        table: _table,
        operation: 'update',
        data: {'km_sekarang': kmBaru},
        recordId: id,
      );
    }
  }
}