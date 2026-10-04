import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stickers/src/data/batch_import.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/globals.dart' as globals;

void main() {
  late Directory temporary;
  late StickerPack pack;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('batch_test_');
    globals.packsDir = temporary.path;
    pack = StickerPack('Batch', 'Author', 'id', [], '4', false);
    globals.packs = [pack];
    await savePacks(globals.packs);
  });
  tearDown(() async => temporary.delete(recursive: true));
  test('whole batch is persisted once with editable backgrounds and one version bump', () async {
    await saveStickerBatch(pack, [
      Uint8List.fromList([1, 2, 3]),
      Uint8List.fromList([4, 5, 6]),
    ]);
    final saved = (await getPacks()).single;
    expect(saved.stickers, hasLength(2));
    expect(saved.imageDataVersion, '5');
    final editor = jsonDecode(await File(saved.stickers.first.editorData!).readAsString());
    expect(await File(editor['background']).readAsBytes(), [1, 2, 3]);
    final backup = jsonDecode(await File('${globals.packsDir}/packs.json.bak').readAsString());
    expect(backup.single['imageDataVersion'], '4');
    expect(backup.single['stickers'], isEmpty);
  });
  test('failed manifest write rolls back all new entries and files, and retry does not duplicate', () async {
    final blocker = await Directory('${globals.packsDir}/packs.json.bak.tmp').create();
    await expectLater(
      saveStickerBatch(pack, [
        Uint8List.fromList([1]),
      ]),
      throwsA(isA<FileSystemException>()),
    );
    expect(pack.stickers, isEmpty);
    expect(pack.imageDataVersion, '4');
    expect(await Directory('${globals.packsDir}/id').list().toList(), isEmpty);
    expect((await getPacks()).single.stickers, isEmpty);
    await blocker.delete();
    await saveStickerBatch(pack, [
      Uint8List.fromList([1]),
    ]);
    expect((await getPacks()).single.stickers, hasLength(1));
  });
  test('animated packs and overflowing selections are rejected before writing', () async {
    pack.animated = true;
    await expectLater(
      saveStickerBatch(pack, [
        Uint8List.fromList([1]),
      ]),
      throwsStateError,
    );
    pack.animated = false;
    pack.stickers.addAll(List.generate(30, (_) => Sticker('existing.webp', ['❤'], null)));
    await expectLater(
      saveStickerBatch(pack, [
        Uint8List.fromList([1]),
      ]),
      throwsStateError,
    );
    expect(await Directory('${globals.packsDir}/id').exists(), isFalse);
  });
}
