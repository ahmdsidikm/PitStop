import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class LocalCache {
  static LocalCache? _instance;
  static LocalCache get instance => _instance ??= LocalCache._();
  LocalCache._();

  Future<File> _getFile(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/pitstop_$name.json');
  }

  Future<List<Map<String, dynamic>>> readTable(String tableName) async {
    try {
      final file = await _getFile(tableName);
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final List<dynamic> decoded = jsonDecode(content);
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> writeTable(String tableName, List<Map<String, dynamic>> rows) async {
    final file = await _getFile(tableName);
    await file.writeAsString(jsonEncode(rows));
  }

  Future<List<Map<String, dynamic>>> readPendingChanges() async {
    try {
      final file = await _getFile('pending_changes');
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final List<dynamic> decoded = jsonDecode(content);
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> writePendingChanges(List<Map<String, dynamic>> changes) async {
    final file = await _getFile('pending_changes');
    await file.writeAsString(jsonEncode(changes));
  }

  Future<void> addPendingChange({
    required String table,
    required String operation,
    required Map<String, dynamic> data,
    String? recordId,
  }) async {
    final changes = await readPendingChanges();
    changes.removeWhere((c) =>
        c['table'] == table &&
        c['record_id'] == recordId &&
        recordId != null);
    changes.add({
      'table': table,
      'operation': operation,
      'data': data,
      'record_id': recordId,
      'timestamp': DateTime.now().toIso8601String(),
    });
    await writePendingChanges(changes);
  }

  Future<void> removePendingChange(String table, String? recordId) async {
    final changes = await readPendingChanges();
    changes.removeWhere((c) =>
        c['table'] == table && c['record_id'] == recordId);
    await writePendingChanges(changes);
  }

  Future<void> clearAllPendingChanges() async {
    await writePendingChanges([]);
  }
}
