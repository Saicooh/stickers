import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:stickers/src/data/portable_pack.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/pages/edit_page.dart';
import 'package:stickers/src/widgets/image_layer.dart';

void main() {
  late Directory temporary;
  late Directory backup;
  late StickerPack pack;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('portable_test_');
    backup = await Directory('${temporary.path}/backup').create();
    final source = await Directory('${temporary.path}/original').create();
    for (final name in ['sticker.webp', 'background.mp4', 'image.webp', 'tray.webp']) {
      await File('${source.path}/$name').writeAsString('content:$name');
    }
    final editor = await File('${source.path}/editor.json').writeAsString(
      jsonEncode({
        'background': '${source.path}/background.mp4',
        'layers': [
          {'type': 'image', 'source': '${source.path}/image.webp'},
          {'type': 'text', 'text': 'Hola', 'fontName': 'Lobster'},
          {
            'type': 'draw',
            'strokes': [
              {
                'points': [
                  {'x': 1, 'y': 2},
                ],
              },
            ],
          },
        ],
      }),
    );
    pack = StickerPack(
      'Title',
      'Author',
      'pack',
      [
        Sticker('${source.path}/sticker.webp', ['🙂'], editor.path),
      ],
      '8',
      true,
      trayIcon: '${source.path}/tray.webp',
    );
  });
  tearDown(() async => temporary.delete(recursive: true));

  test('all packs retain video backgrounds, image layers and metadata after original files are gone', () async {
    await writePackBackup([pack, pack], backup);
    await Directory('${temporary.path}/original').delete(recursive: true);
    final loaded = await readPackBackup(backup);
    expect(loaded, hasLength(2));
    expect(loaded[0].stickers.single.source, isNot(loaded[1].stickers.single.source));
    final restored = await Directory('${temporary.path}/restored').create();
    final data = await copyPackAssets(loaded.first, restored, relativePaths: false);
    final result = StickerPack.fromJson(data);
    expect(result.animated, isTrue);
    expect(result.imageDataVersion, '8');
    expect(result.stickers.single.emojis, ['🙂']);
    expect(await File(result.stickers.single.source).readAsString(), 'content:sticker.webp');
    final editor = jsonDecode(await File(result.stickers.single.editorData!).readAsString());
    expect(await File(editor['background']).readAsString(), 'content:background.mp4');
    expect(await File(editor['layers'][0]['source']).readAsString(), 'content:image.webp');
    expect(editor['layers'][1]['text'], 'Hola');
    expect(editor['layers'][2]['strokes'][0]['points'][0]['x'], 1);
    await backup.delete(recursive: true);
    expect(await File(editor['background']).exists(), isTrue);
  });

  test('older single-pack backups repair hardcoded background extensions and absolute layer references', () async {
    final data = await copyPackAssets(pack, backup);
    final editorFile = File('${backup.path}/0.json');
    final editor = jsonDecode(await editorFile.readAsString());
    editor['background'] = '0/background.webp';
    editor['layers'][0]['source'] = '/old/phone/packs/pack/0/0.webp';
    await editorFile.writeAsString(jsonEncode(editor));
    await File('${backup.path}/pack.json').writeAsString(jsonEncode(data));
    final result = (await readPackBackup(backup)).single;
    final repaired = jsonDecode(await File(result.stickers.single.editorData!).readAsString());
    expect(repaired['background'], endsWith('background.mp4'));
    expect(await File(repaired['layers'][0]['source']).readAsString(), 'content:image.webp');
  });

  test('archive references cannot escape their extraction directory', () async {
    for (final path in ['../outside', '/absolute', 'C:/outside', 'a/../../outside', 'a\\outside']) {
      await expectLater(resolvePackFile(backup, path), throwsFormatException);
    }
    final data = pack.toJson();
    data['id'] = '../existing-pack';
    await File('${backup.path}/pack.json').writeAsString(jsonEncode(data));
    await expectLater(readPackBackup(backup), throwsFormatException);
  });

  test('restored image layers can reopen in the editor, including legacy layers without a type', () {
    for (final data in [
      {'type': 'image', 'source': '/pack/0/0.webp'},
      {'source': '/pack/0/0.webp'},
    ]) {
      final layer = EditorLayer.fromJson(data, GlobalKey()) as ImageLayer;
      expect(layer.source, '/pack/0/0.webp');
      expect(layer.toJson()['type'], 'image');
    }
  });
}
