import 'dart:convert';
import 'dart:io';

import 'package:stickers/src/data/sticker_pack.dart';

/// Keeps the legacy list manifest, serializing writes and retaining a valid backup.
class PackStore {
  PackStore(this.file);

  final File file;
  File get _backup => File('${file.path}.bak');
  Future<void> _pending = Future<void>.value();

  Future<void> save(List<StickerPack> packs) {
    // Snapshot now: pack metadata and emoji lists can change while an earlier save is pending.
    final snapshot = jsonEncode(packs.map((pack) => pack.toJson()).toList());
    final result = _pending.then((_) => _write(snapshot));
    // A failed write must be reported to its caller without blocking later retries.
    _pending = result.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return result;
  }

  Future<List<StickerPack>> load() async {
    await _pending;
    if (await file.exists()) {
      try {
        return await _read(file);
      } on FormatException {
        // Recover below, including a partially written legacy manifest.
      } on TypeError {
        // A JSON value with the wrong schema is also an invalid manifest.
      }
    } else if (!await _backup.exists()) {
      return [];
    }
    // Do not silently turn damaged packs into an empty collection.
    final recovered = await _read(_backup);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(await _backup.readAsString(), flush: true);
    await temporary.rename(file.path);
    return recovered;
  }

  Future<List<StickerPack>> _read(File input) async {
    return (jsonDecode(await input.readAsString()) as List)
        .map((json) => StickerPack.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<void> _write(String snapshot) async {
    final temporary = File('${file.path}.tmp');
    final backupTemporary = File('${_backup.path}.tmp');
    try {
      await temporary.writeAsString(snapshot, flush: true);
      if (await file.exists()) {
        // Validate before replacing the last good backup.
        await _read(file);
        await backupTemporary.writeAsString(await file.readAsString(), flush: true);
      } else {
        await backupTemporary.writeAsString(snapshot, flush: true);
      }
      await backupTemporary.rename(_backup.path);
      // The old manifest remains in place until this same-directory replacement succeeds.
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
      if (await backupTemporary.exists()) await backupTemporary.delete();
    }
  }
}
