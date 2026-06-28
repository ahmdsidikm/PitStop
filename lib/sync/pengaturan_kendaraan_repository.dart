import 'package:flutter/foundation.dart'; // ✅ untuk debugPrint
import '../database/supabase.dart';
import 'local_cache.dart';
import 'connectivity_service.dart';

class PengaturanKendaraanRepository {
  static PengaturanKendaraanRepository? _instance;
  static PengaturanKendaraanRepository get instance =>
      _instance ??= PengaturanKendaraanRepository._();
  PengaturanKendaraanRepository._();

  static const _table = 'pengaturan_kendaraan';

  // ✅ BARU: Baca cache lokal saja — sangat cepat (~5ms), tanpa network
  Future<Map<String, dynamic>?> getFromCacheOnly(String kendaraanId) async {
    final cached = await LocalCache.instance.readTable(_table);
    return cached.cast<Map<String, dynamic>?>().firstWhere(
          (p) => p?['kendaraan_id'] == kendaraanId,
          orElse: () => null,
        );
  }

  // Baca dari DB kalau online, fallback ke cache kalau offline/error
  Future<Map<String, dynamic>?> getByKendaraanId(String kendaraanId) async {
    if (ConnectivityService.instance.isOnline) {
      try {
        final data = await supabase
            .from(_table)
            .select()
            .eq('kendaraan_id', kendaraanId)
            .maybeSingle();
        if (data != null) {
          // Update cache dengan data terbaru dari DB
          final cached = await LocalCache.instance.readTable(_table);
          final idx =
              cached.indexWhere((p) => p['kendaraan_id'] == kendaraanId);
          if (idx != -1) {
            cached[idx] = data;
          } else {
            cached.add(data);
          }
          await LocalCache.instance.writeTable(_table, cached);
        }
        return data;
      } catch (e) {
        debugPrint('[PengaturanRepo] getByKendaraanId error: $e');
        // Fallback ke cache
      }
    }

    // Offline atau error — pakai cache lokal
    final cached = await LocalCache.instance.readTable(_table);
    return cached.cast<Map<String, dynamic>?>().firstWhere(
          (p) => p?['kendaraan_id'] == kendaraanId,
          orElse: () => null,
        );
  }

  Future<void> upsert(Map<String, dynamic> data) async {
    final kendaraanId = data['kendaraan_id'] as String;

    // ✅ Selalu update cache lokal DULU (optimistic), baru sync ke server
    final cached = await LocalCache.instance.readTable(_table);
    final idx = cached.indexWhere((p) => p['kendaraan_id'] == kendaraanId);
    if (idx != -1) {
      cached[idx] = {...cached[idx], ...data};
    } else {
      cached.add(data);
    }
    await LocalCache.instance.writeTable(_table, cached);

    if (ConnectivityService.instance.isOnline) {
      try {
        await supabase
            .from(_table)
            .upsert(data, onConflict: 'kendaraan_id');
      } catch (e) {
        debugPrint('[PengaturanRepo] upsert error: $e');
        // Queue untuk sync nanti
        await LocalCache.instance.addPendingChange(
          table: _table,
          operation: 'upsert',
          data: data,
          recordId: kendaraanId,
        );
      }
    } else {
      // Offline — queue untuk sync nanti
      await LocalCache.instance.addPendingChange(
        table: _table,
        operation: 'upsert',
        data: data,
        recordId: kendaraanId,
      );
    }
  }
}