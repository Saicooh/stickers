import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/pack_store.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/globals.dart' as globals;

void main() {
  late Directory temporary;
  late File manifest;
  late PackStore store;
  late StickerPack pack;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('pack_store_test_');
    manifest = File('${temporary.path}/packs.json');
    store = PackStore(manifest);
    pack = StickerPack(
      'Test',
      'Author',
      'id',
      [
        Sticker('/packs/id/0.webp', ['❤'], '/packs/id/0.json'),
      ],
      '17',
      true,
      trayIcon: '/packs/id/tray.webp',
      publisherWebsite: 'https://example.com',
    );
  });
  tearDown(() async => temporary.delete(recursive: true));

  test('legacy list manifest preserves editable asset paths and metadata', () async {
    await manifest.writeAsString(jsonEncode([pack.toJson()]));
    final loaded = await store.load();
    expect(loaded.single.toJson(), pack.toJson());
    loaded.single.title = 'Edited';
    await store.save(loaded);
    expect(jsonDecode(await manifest.readAsString()), isA<List>());
    expect((await store.load()).single.stickers.single.editorData, '/packs/id/0.json');
    expect((await store.load()).single.imageDataVersion, '17');
  });

  test('overlapping saves snapshot mutable lists and commit in invocation order', () async {
    final first = store.save([pack]);
    pack.stickers.single.emojis.add('🙂');
    pack.title = 'Second';
    final second = store.save([pack]);
    pack.stickers.single.emojis.clear();
    pack.title = 'Unsaved';
    await Future.wait([first, second]);
    final saved = (await store.load()).single;
    expect(saved.title, 'Second');
    expect(saved.stickers.single.emojis, ['❤', '🙂']);
    final backup = jsonDecode(await File('${manifest.path}.bak').readAsString()) as List;
    expect(backup.single['title'], 'Test');
    expect(backup.single['stickers'][0]['emojis'], ['❤']);
  });

  for (final damage in ['truncated', 'schema', 'missing']) {
    test('recovers a $damage primary manifest from the last good backup', () async {
      await store.save([pack]);
      pack.title = 'Second';
      await store.save([pack]);
      switch (damage) {
        case 'truncated':
          await manifest.writeAsString('[{"id":');
        case 'schema':
          await manifest.writeAsString('[{"title":42}]');
        case 'missing':
          await manifest.delete();
      }
      expect((await store.load()).single.title, 'Test');
      expect((jsonDecode(await manifest.readAsString()) as List).single['title'], 'Test');
      await store.save([pack]);
      expect((await store.load()).single.title, 'Second');
    });
  }

  test('damaged primary and backup report failure and preserve the original files', () async {
    await manifest.writeAsString('broken primary');
    final backup = File('${manifest.path}.bak');
    await backup.writeAsString('broken backup');
    await expectLater(store.load(), throwsFormatException);
    await expectLater(store.save([pack]), throwsFormatException);
    expect(await manifest.readAsString(), 'broken primary');
    expect(await backup.readAsString(), 'broken backup');
  });

  test('write failure keeps the previous primary and a later retry succeeds', () async {
    await store.save([pack]);
    final previous = await manifest.readAsString();
    // An actual filesystem failure while preparing the backup, before replacing the primary.
    final blocker = await Directory('${manifest.path}.bak.tmp').create();
    pack.title = 'Retry';
    await expectLater(store.save([pack]), throwsA(isA<FileSystemException>()));
    expect(await manifest.readAsString(), previous);
    expect(await File('${manifest.path}.tmp').exists(), isFalse);
    await blocker.delete();
    await store.save([pack]);
    expect((await store.load()).single.title, 'Retry');
  });

  test('new installation returns a growable list', () async {
    final loaded = await store.load();
    loaded.add(pack);
    expect(loaded, hasLength(1));
  });

  test('the first saved manifest can also recover after corruption', () async {
    await store.save([pack]);
    await manifest.writeAsString('incomplete');
    expect((await store.load()).single.toJson(), pack.toJson());
  });

  test('pack edit persists the bumped WhatsApp image version', () async {
    globals.packsDir = temporary.path;
    globals.packs = [pack];
    await pack.onEdit();
    expect((await getPacks()).single.imageDataVersion, '18');
  });
}
