import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stickers/src/widgets/sticker_thumbnail.dart';

import 'fixtures/transparent_gif.dart';

void main() {
  late Directory temporary;
  setUp(() async => temporary = await Directory.systemTemp.createTemp('thumbnail_test_'));
  tearDown(() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await temporary.delete(recursive: true);
  });

  Future<File> picture(int width, int height) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.red, BlendMode.src);
    final drawing = recorder.endRecording();
    final image = await drawing.toImage(width, height);
    try {
      return await File(
        '${temporary.path}/$width-$height.png',
      ).writeAsBytes((await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
    } finally {
      image.dispose();
      drawing.dispose();
    }
  }

  Future<void> show(WidgetTester tester, File file, {double ratio = 2, double size = 84}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(devicePixelRatio: ratio),
          child: Center(
            child: SizedBox.square(dimension: size, child: StickerThumbnail(file.path)),
          ),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump();
      if (tester.widget<RawImage>(find.byType(RawImage)).image != null) break;
    }
  }

  testWidgets('512px sticker is decoded at visible physical size with less pixel memory', (tester) async {
    final file = (await tester.runAsync(() => picture(512, 512)))!;
    await show(tester, file);
    final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(Size(image.width.toDouble(), image.height.toDouble()), const Size(168, 168));
    expect(image.width * image.height * 4, lessThan(512 * 512 * 4 / 8));
    await show(tester, file, ratio: 4, size: 200);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image!.width, 512);
  });

  testWidgets('non-square images preserve aspect ratio', (tester) async {
    final file = (await tester.runAsync(() => picture(512, 256)))!;
    await show(tester, file);
    final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(image.width, 168);
    expect(image.height, 84);
  });

  testWidgets('animated transparent previews still advance frames', (tester) async {
    final file = (await tester.runAsync(
      () => File('${temporary.path}/animated.gif').writeAsBytes(base64Decode(transparentGif)),
    ))!;
    await show(tester, file);
    final first = tester.widget<RawImage>(find.byType(RawImage)).image!;
    final firstPixels = (await tester.runAsync(() => first.toByteData()))!.buffer.asUint8List();
    expect(firstPixels.where((p) => p == 0), isNotEmpty);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    final second = tester.widget<RawImage>(find.byType(RawImage)).image!;
    final secondPixels = (await tester.runAsync(() => second.toByteData()))!.buffer.asUint8List();
    expect(secondPixels, isNot(orderedEquals(firstPixels)));
  });
}
