// flutter run -t tool/remaining_fork_smoke.dart
// Add --dart-define=SKIP_CROP_UI=true for backend/native checks without a visible crop route.
// Synthetic photos/GIF and temporary packs only. Does not change user packs, fonts or preferences.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_editor/image_editor.dart';
import 'package:path_provider/path_provider.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/data/batch_import.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/fonts_api/fonts_registry.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/pages/multi_crop_page.dart';
import 'package:stickers/src/video/image_animation.dart';
import 'package:stickers/src/video/image_animation_encode.dart';
import 'package:stickers/src/widgets/draw_layer.dart';
import 'package:stickers/src/widgets/image_layer.dart';

import '../test/fixtures/transparent_gif.dart';
import 'gif_benchmark.dart' show compareAnimations;

final navigation = GlobalKey<NavigatorState>();

T? findWidget<T extends Widget>(bool Function(T) accept) {
  T? result;
  void visit(Element element) {
    final widget = element.widget;
    if (widget is T && accept(widget)) result = widget;
    element.visitChildElements(visit);
  }

  final context = navigation.currentContext;
  if (context != null) visit(context as Element);
  return result;
}

Future<void> waitUntil(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) throw StateError('UI did not become ready');
    await Future<void>.delayed(const Duration(milliseconds: 32));
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const skipCropUi = bool.fromEnvironment('SKIP_CROP_UI');
  final temporary = await (await getTemporaryDirectory()).createTemp('remaining_fork_smoke_');
  packsDir = '${temporary.path}/packs';
  mediaCacheDir = '${temporary.path}/media';
  exportCacheDir = '${temporary.path}/exports';
  bundledFontsDir = '${temporary.path}/fonts';
  for (final path in [packsDir, mediaCacheDir, exportCacheDir, bundledFontsDir]) {
    await Directory(path).create();
  }
  final status = ValueNotifier('Checking batch crop, native fonts and complete backup…');
  runApp(
    MaterialApp(
      navigatorKey: navigation,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: ValueListenableBuilder(valueListenable: status, builder: (_, value, _) => Text(value)),
        ),
      ),
    ),
  );
  try {
    final paths = <String>[];
    for (var i = 0; i < 2; i++) {
      final recorder = ui.PictureRecorder();
      final size = i == 0 ? const Size(640, 320) : const Size(240, 400);
      Canvas(recorder).drawRect(
        Rect.fromLTWH(32, 32, size.width - 64, size.height - 64),
        Paint()..color = i == 0 ? Colors.blue : Colors.green,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(size.width.toInt(), size.height.toInt());
      try {
        paths.add(
          (await File(
            '${temporary.path}/photo_$i.png',
          ).writeAsBytes((await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List())).path,
        );
      } finally {
        image.dispose();
        picture.dispose();
      }
    }
    final photoPack = StickerPack('Photos', 'Test', 'photos', [], '0', false);
    packs = [photoPack];
    await savePacks(packs);
    if (skipCropUi) {
      final images = <Uint8List>[];
      for (final path in paths) {
        images.add(await prepareUncroppedSticker(path, photoPack));
      }
      await saveStickerBatch(photoPack, images);
    } else {
      await waitUntil(() => navigation.currentState != null);
      final closed = navigation.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => MultiCropPage(pack: photoPack, paths: paths),
        ),
      );
      await waitUntil(
        () =>
            findWidget<IconButton>(
              (button) => button.icon is Icon && (button.icon as Icon).icon == Icons.crop && button.onPressed != null,
            ) !=
            null,
      );
      findWidget<IconButton>((button) => button.icon is Icon && (button.icon as Icon).icon == Icons.crop)!.onPressed!();
      await waitUntil(() => findWidget<CropPage>((page) => page.editorKey.currentState?.getCropRect() != null) != null);
      findWidget<FilledButton>((button) => button.child is Text && (button.child as Text).data == 'Done')!.onPressed!();
      await waitUntil(() => findWidget<CropPage>((_) => true) == null);
      await waitUntil(() => findWidget<FilledButton>((button) => button.onPressed != null) != null);
      findWidget<FilledButton>((button) => button.onPressed != null)!.onPressed!();
      await closed.timeout(const Duration(seconds: 30));
    }
    if (photoPack.stickers.length != 2 || photoPack.imageDataVersion != '1') throw StateError('Batch not saved once');
    for (final sticker in photoPack.stickers) {
      final buffer = await ui.ImmutableBuffer.fromFilePath(sticker.source);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        if (descriptor.width != 512 || descriptor.height != 512) throw StateError('Sticker is not 512 square');
      } finally {
        descriptor.dispose();
        buffer.dispose();
      }
      final editor = jsonDecode(await File(sticker.editorData!).readAsString());
      if (!await File(editor['background']).exists()) throw StateError('Editable background missing');
    }
    debugPrint('REMAINING_SMOKE batch=2 editable stickers version=1 cropUI=${skipCropUi ? 'skipped' : 'OK'}');

    await FontsRegistry.init();
    final clock = Stopwatch()..start();
    await FontsRegistry.prepareForExport(['Lobster']);
    final registerMs = clock.elapsedMilliseconds;
    clock.reset();
    await FontsRegistry.prepareForExport(['Lobster']);
    final option = ImageEditorOption()
      ..addOption(
        AddTextOption()..addText(
          EditorText(
            transform: Matrix4.identity(),
            text: 'Hola',
            fontName: 'Lobster',
            fontSize: 64,
            textColor: Colors.black,
          ),
        ),
      )
      ..outputFormat = const OutputFormat.png();
    final text = (await ImageEditor.editImage(
      image: await File(paths.first).readAsBytes(),
      imageEditorOption: option,
    ))!;
    final codec = await ui.instantiateImageCodec(text);
    final frame = (await codec.getNextFrame()).image;
    final pixels = (await frame.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
    var black = 0;
    for (var i = 0; i < pixels.length; i += 4) {
      if (pixels[i] == 0 && pixels[i + 1] == 0 && pixels[i + 2] == 0 && pixels[i + 3] > 0) black++;
    }
    frame.dispose();
    codec.dispose();
    if (black < 10) throw StateError('Native font did not render text');
    debugPrint('REMAINING_SMOKE font registration=${registerMs}ms native text pixels=$black');

    final gif = await File('${temporary.path}/original.gif').writeAsBytes(base64Decode(transparentGif));
    final animation = await ImageAnimation.load(gif);
    final webp = await File(
      '${temporary.path}/animation.webp',
    ).writeAsBytes(await encodeImageAnimation(source: animation));
    final drawing = DrawLayer()
      ..painter.strokes.add(Stroke(Colors.red, 8)..points.addAll([const Offset(10, 10), const Offset(40, 40)]));
    final editable = await File('${temporary.path}/animation.json').writeAsString(
      jsonEncode({
        'background': gif.path,
        'layers': [
          drawing.toJson(),
          {'type': 'image', 'source': paths.first},
        ],
      }),
    );
    final animated = StickerPack(
      'Animation',
      'Test',
      'animation',
      [
        Sticker(webp.path, ['❤'], editable.path),
      ],
      '3',
      true,
    );
    packs.add(animated);
    await savePacks(packs);
    final archive = await createPackArchive(packs);
    await importPack(archive);
    if (packs.length != 4) throw StateError('Backup did not restore both packs');
    for (var i = 0; i < 2; i++) {
      final original = packs[i];
      final imported = packs[i + 2];
      for (var j = 0; j < original.stickers.length; j++) {
        if (!listEquals(
          await File(original.stickers[j].source).readAsBytes(),
          await File(imported.stickers[j].source).readAsBytes(),
        )) {
          throw StateError('Backup changed sticker bytes');
        }
      }
    }
    await compareAnimations(webp, File(packs.last.stickers.single.source));
    final editor = jsonDecode(await File(packs.last.stickers.single.editorData!).readAsString());
    if (!listEquals(await File(editor['background']).readAsBytes(), await gif.readAsBytes())) {
      throw StateError('GIF background changed');
    }
    if (!await File(editor['layers'][1]['source']).exists()) throw StateError('Image layer missing after restore');
    final imageOption = ImageEditorOption()
      ..addOption(await ImageLayer.fromJson(editor['layers'][1]).exportOption())
      ..outputFormat = const OutputFormat.png();
    final mixed = (await ImageEditor.editImage(
      image: (await rootBundle.load('assets/transparent.webp')).buffer.asUint8List(),
      imageEditorOption: imageOption,
    ))!;
    final mixedCodec = await ui.instantiateImageCodec(mixed);
    final mixedFrame = (await mixedCodec.getNextFrame()).image;
    final mixedPixels = (await mixedFrame.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
    mixedFrame.dispose();
    mixedCodec.dispose();
    if (mixedPixels[(256 * 512 + 256) * 4 + 3] != 255 || mixedPixels[3] != 0) {
      throw StateError('Restored image layer did not export with transparency');
    }
    debugPrint('REMAINING_SMOKE restored image layer native export=OK');
    final previous = await File('$packsDir/packs.json').readAsString();
    final blocker = await Directory('$packsDir/packs.json.bak.tmp').create();
    try {
      await importPack(archive);
      throw StateError('Expected failed manifest save');
    } on FileSystemException {
      if (packs.length != 4 || await File('$packsDir/packs.json').readAsString() != previous) {
        throw StateError('Failed import damaged packs');
      }
    }
    await blocker.delete();
    debugPrint('REMAINING_SMOKE backup=4 packs GIF timing/alpha=identical rollback=OK');
    status.value = 'REMAINING_SMOKE_OK';
    debugPrint(status.value);
  } catch (error, stack) {
    status.value = 'REMAINING_SMOKE_FAILED $error';
    debugPrint('$error\n$stack');
    rethrow;
  } finally {
    runApp(
      MaterialApp(
        home: Scaffold(body: Center(child: Text(status.value))),
      ),
    );
    if (!skipCropUi) await WidgetsBinding.instance.endOfFrame;
    await temporary.delete(recursive: true);
  }
}
