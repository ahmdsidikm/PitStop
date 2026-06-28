import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/supabase.dart';
import 'local_cache.dart';
import 'connectivity_service.dart';

class SyncManager {
  static SyncManager? _instance;
  static SyncManager get instance => _instance ??= SyncManager._();
  SyncManager._();

  static const _tableKendaraan = 'kendaraan';
  static const _tablePengaturan = 'pengaturan_kendaraan';

  RealtimeChannel? _realtimeChannel;
  StreamSubscription? _connectivitySub;
  bool _isSyncing = false;

  final _notifier = StreamController<void>.broadcast();
  Stream<void> get onDataChanged => _notifier.stream;

  Future<void> init() async {
    await ConnectivityService.instance.init();
    _connectivitySub =
        ConnectivityService.instance.onStatusChange.listen((isOnline) async {
      if (isOnline) {
        await _onCameOnline();
      } else {
        _teardownRealtime();
      }
    });

    if (ConnectivityService.instance.isOnline) {
      await _onCameOnline();
    }
  }

  Future<void> _onCameOnline() async {
    await _uploadPendingChanges();
    await _fetchAndCacheAll();
    _setupRealtime();
  }

  Future<void> _fetchAndCacheAll() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final kendaraanData = await supabase
          .from(_tableKendaraan)
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final kendaraanList = List<Map<String, dynamic>>.from(kendaraanData);
      await LocalCache.instance.writeTable(_tableKendaraan, kendaraanList);

      final ids = kendaraanList.map((k) => k['id'] as String).toList();
      if (ids.isNotEmpty) {
        final pengaturanData = await supabase
            .from(_tablePengaturan)
            .select()
            .inFilter('kendaraan_id', ids);
        await LocalCache.instance.writeTable(
            _tablePengaturan, List<Map<String, dynamic>>.from(pengaturanData));
      } else {
        await LocalCache.instance.writeTable(_tablePengaturan, []);
      }

      _notifier.add(null);
    } catch (e) {
      debugPrint('[SyncManager] fetch gagal: $e');
    }
  }

  void _setupRealtime() {
    _teardownRealtime();
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    _realtimeChannel = supabase
        .channel('sync_kendaraan_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: _tableKendaraan,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) async {
            await _fetchAndCacheAll();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: _tablePengaturan,
          callback: (_) async {
            await _fetchAndCacheAll();
          },
        )
        .subscribe();
  }

  void _teardownRealtime() {
    if (_realtimeChannel != null) {
      supabase.removeChannel(_realtimeChannel!);
      _realtimeChannel = null;
    }
  }

  Future<void> _uploadPendingChanges() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final pending = await LocalCache.instance.readPendingChanges();
      if (pending.isEmpty) return;

      final sorted = List<Map<String, dynamic>>.from(pending)
        ..sort((a, b) =>
            (a['timestamp'] as String).compareTo(b['timestamp'] as String));

      for (final change in sorted) {
        await _applyChange(change);
      }

      await LocalCache.instance.clearAllPendingChanges();
    } catch (e) {
      debugPrint('[SyncManager] upload pending gagal: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _applyChange(Map<String, dynamic> change) async {
    final table = change['table'] as String;
    final operation = change['operation'] as String;
    final data = Map<String, dynamic>.from(change['data'] as Map);
    final recordId = change['record_id'] as String?;

    try {
      if (operation == 'insert') {
        await supabase.from(table).insert(data);
      } else if (operation == 'update' && recordId != null) {
        await supabase.from(table).update(data).eq('id', recordId);
      } else if (operation == 'delete' && recordId != null) {
        await supabase.from(table).delete().eq('id', recordId);
      } else if (operation == 'upsert') {
        await supabase.from(table).upsert(data);
      }
    } catch (e) {
      debugPrint('[SyncManager] gagal apply perubahan ($operation $table): $e');
    }
  }

  Future<void> refreshCache() async {
    if (ConnectivityService.instance.isOnline) {
      await _fetchAndCacheAll();
    }
  }

  Future<void> dispose() async {
    _teardownRealtime();
    await _connectivitySub?.cancel();
    await _notifier.close();
    ConnectivityService.instance.dispose();
  }
}
