// flutter run -t tool/fork_optimizations_smoke.dart
// Uses synthetic assets and a temporary pack manifest; never reads or writes user packs.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:stickers/src/data/pack_store.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/widgets/sticker_thumbnail.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final temporary = await (await getTemporaryDirectory()).createTemp('fork_smoke_');
  final status = ValueNotifier('Checking previews and pack storage…');
  final previewKey = GlobalKey();
  try {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(const Rect.fromLTWH(64, 64, 384, 384), Paint()..color = Colors.red);
    final drawing = recorder.endRecording();
    final image = await drawing.toImage(512, 512);
    final file = File('${temporary.path}/source.png');
    try {
      await file.writeAsBytes((await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
    } finally {
      image.dispose();
      drawing.dispose();
    }
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(dimension: 84, child: StickerThumbnail(file.path, key: previewKey)),
                ValueListenableBuilder(valueListenable: status, builder: (context, value, _) => Text(value)),
              ],
            ),
          ),
        ),
      ),
    );

    ui.Image? decoded;
    void findImage(Element element) {
      final widget = element.widget;
      if (widget is RawImage && widget.image != null) decoded = widget.image;
      element.visitChildren(findImage);
    }

    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (decoded == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (previewKey.currentContext != null) findImage(previewKey.currentContext! as Element);
    }
    if (decoded == null) throw StateError('Thumbnail did not load');
    final width = decoded!.width;
    final height = decoded!.height;
    if (width >= 512 || width != height) throw StateError('Thumbnail is not downsampled square');
    debugPrint('FORK_SMOKE thumbnail=${width}x$height bytes=${width * height * 4} fullBytes=${512 * 512 * 4}');

    final manifest = File('${temporary.path}/packs.json');
    final store = PackStore(manifest);
    final pack = StickerPack(
      'Synthetic',
      'Test',
      'smoke',
      [
        Sticker(file.path, ['❤'], null),
      ],
      '0',
      false,
    );
    final first = store.save([pack]);
    pack.title = 'Second';
    pack.stickers.single.emojis.add('🙂');
    final second = store.save([pack]);
    pack.stickers.single.emojis.clear();
    await Future.wait([first, second]);
    final saved = (await store.load()).single;
    if (saved.title != 'Second' || saved.stickers.single.emojis.length != 2) throw StateError('Snapshot/order lost');
    await manifest.writeAsString('[broken');
    if ((await store.load()).single.title != 'Synthetic') throw StateError('Corrupt manifest recovery failed');
    await manifest.delete();
    if ((await store.load()).single.title != 'Synthetic') throw StateError('Missing manifest recovery failed');
    final content = await manifest.readAsString();
    final blocker = await Directory('${manifest.path}.bak.tmp').create();
    try {
      await store.save([pack]);
      throw StateError('Expected filesystem failure');
    } on FileSystemException {
      if (await manifest.readAsString() != content) throw StateError('Failed save damaged primary');
    }
    await blocker.delete();
    await store.save([pack]);
    if ((jsonDecode(await manifest.readAsString()) as List).single['title'] != 'Second') {
      throw StateError('Retry failed');
    }
    status.value = 'FORK_SMOKE_OK';
    debugPrint(status.value);
  } catch (error, stack) {
    status.value = 'FORK_SMOKE_FAILED $error';
    debugPrint('$error\n$stack');
    rethrow;
  } finally {
    // Unmount the preview before deleting its source.
    runApp(
      MaterialApp(
        home: Scaffold(body: Center(child: Text(status.value))),
      ),
    );
    await WidgetsBinding.instance.endOfFrame;
    await temporary.delete(recursive: true);
  }
}
