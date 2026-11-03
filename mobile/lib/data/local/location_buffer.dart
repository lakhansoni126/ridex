import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import '../api/rides_repository.dart';

/// Offline location point buffer with batch sync.
///
/// Persists to a JSON file under the app documents directory. The Isar
/// [PendingLocationPoint] collection (see `database/models.dart`) is registered
/// for schema continuity; this buffer is the runtime path used by
/// [BackgroundLocationService].
class LocationBuffer {
  File? _fileHandle;

  /// Hard cap so a long offline period can't grow the file without bound.
  static const maxPoints = 20000;

  /// Serialises every read-modify-write of the JSON file. Without this,
  /// a GPS enqueue racing a sync could silently drop or resend points.
  Future<void> _lock = Future.value();

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _lock = _lock.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<File> _file() async {
    if (_fileHandle != null) return _fileHandle!;
    final dir = await getApplicationDocumentsDirectory();
    _fileHandle = File('${dir.path}/pending_location_points.json');
    if (!await _fileHandle!.exists()) {
      await _fileHandle!.writeAsString('[]');
    }
    return _fileHandle!;
  }

  Future<List<Map<String, dynamic>>> _readAll() async {
    final file = await _file();
    try {
      return (jsonDecode(await file.readAsString()) as List<dynamic>)
          .cast<Map<String, dynamic>>();
    } catch (e) {
      // Corrupt file (e.g. app killed mid-write): start fresh.
      debugPrint('LocationBuffer: resetting unreadable buffer: $e');
      return [];
    }
  }

  Future<void> _writeAll(List<Map<String, dynamic>> list) async {
    final file = await _file();
    // Write to a temp file then rename, so a crash never leaves half a file.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(list), flush: true);
    await tmp.rename(file.path);
  }

  Future<void> enqueue({
    required String targetType,
    required String targetId,
    required double lat,
    required double lon,
    double? speedMps,
    double? heading,
    double? accuracyM,
    String? status,
    DateTime? recordedAt,
  }) async {
    final at = recordedAt ?? DateTime.now().toUtc();
    await _synchronized(() async {
      final list = await _readAll();
      if (list.length >= maxPoints) {
        list.removeRange(0, list.length - maxPoints + 1);
      }
      list.add({
        'id': DateTime.now().microsecondsSinceEpoch,
        'targetType': targetType,
        'targetId': targetId,
        'lat': lat,
        'lon': lon,
        'speedMps': speedMps,
        'heading': heading,
        'accuracyM': accuracyM,
        'status': status,
        'recordedAt': at.toIso8601String(),
        'synced': false,
      });
      await _writeAll(list);
    });
  }

  Future<int> pendingCount() =>
      _synchronized(() async => (await _readAll()).length);

  Future<List<BufferedPoint>> peekUnsynced({int limit = 100}) =>
      _synchronized(() => _peek(limit));

  Future<List<BufferedPoint>> _peek(int limit) async {
    final list = await _readAll();
    return list
        .where((m) => m['synced'] != true)
        .take(limit)
        .map(
          (m) => BufferedPoint(
            localId: m['id'] as int,
            targetType: m['targetType'] as String,
            targetId: m['targetId'] as String,
            point: LocationPointDto(
              lat: (m['lat'] as num).toDouble(),
              lon: (m['lon'] as num).toDouble(),
              recordedAt: DateTime.parse(m['recordedAt'] as String),
              speedMps: (m['speedMps'] as num?)?.toDouble(),
              heading: (m['heading'] as num?)?.toDouble(),
              accuracyM: (m['accuracyM'] as num?)?.toDouble(),
              status: m['status'] as String?,
            ),
          ),
        )
        .toList();
  }

  Future<void> markSynced(List<int> localIds) async {
    if (localIds.isEmpty) return;
    final idSet = localIds.toSet();
    await _synchronized(() async {
      final list = await _readAll();
      await _writeAll(list.where((m) => !idSet.contains(m['id'])).toList());
    });
  }

  Future<void> clearTarget(String targetType, String targetId) =>
      _synchronized(() async {
        final list = await _readAll();
        await _writeAll(
          list
              .where((m) =>
                  !(m['targetType'] == targetType && m['targetId'] == targetId))
              .toList(),
        );
      });

  /// Group unsynced points by target and invoke [flushBatch] per group.
  bool _syncing = false;

  Future<void> syncAll({
    required Future<void> Function(
      String targetType,
      String targetId,
      List<LocationPointDto> points,
    ) flushBatch,
  }) async {
    if (_syncing) return;
    _syncing = true;
    try {
      await _syncLoop(flushBatch);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncLoop(
    Future<void> Function(
      String targetType,
      String targetId,
      List<LocationPointDto> points,
    ) flushBatch,
  ) async {
    while (true) {
      final batch = await peekUnsynced(limit: 200);
      if (batch.isEmpty) return;

      final grouped = <String, List<BufferedPoint>>{};
      for (final p in batch) {
        final key = '${p.targetType}|${p.targetId}';
        grouped.putIfAbsent(key, () => []).add(p);
      }

      for (final entry in grouped.entries) {
        final parts = entry.key.split('|');
        final type = parts[0];
        final id = parts.sublist(1).join('|');
        final points = entry.value.map((e) => e.point).toList();
        try {
          await flushBatch(type, id, points);
          await markSynced(entry.value.map((e) => e.localId).toList());
        } on ApiException catch (e) {
          // 4xx (ride ended, share stopped, not a participant…) will never
          // succeed: drop those points so they don't block the queue forever.
          final permanent = e.statusCode >= 400 &&
              e.statusCode < 500 &&
              e.statusCode != 401 &&
              e.statusCode != 408 &&
              e.statusCode != 429;
          if (permanent) {
            debugPrint('LocationBuffer: dropping $type/$id (${e.statusCode})');
            await clearTarget(type, id);
            continue;
          }
          debugPrint('LocationBuffer sync failed for $type/$id: $e');
          return;
        } catch (e) {
          debugPrint('LocationBuffer sync failed for $type/$id: $e');
          return;
        }
      }
    }
  }
}

class BufferedPoint {
  BufferedPoint({
    required this.localId,
    required this.targetType,
    required this.targetId,
    required this.point,
  });

  final int localId;
  final String targetType;
  final String targetId;
  final LocationPointDto point;
}
