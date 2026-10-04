// Run on Android: flutter run -t tool/gif_smoke.dart
// Exercises the native encoder using temporary files without opening any packs.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:stickers/src/video/image_animation.dart';
import 'package:stickers/src/video/image_animation_encode.dart';

import '../test/fixtures/transparent_gif.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final status = ValueNotifier('Checking GIF export…');
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ValueListenableBuilder(
            valueListenable: status,
            builder: (context, value, _) => Text(value),
          ),
        ),
      ),
    ),
  );
  final temporary = await Directory.systemTemp.createTemp('gif_smoke_');
  try {
    final gif = await File('${temporary.path}/source.gif').writeAsBytes(base64Decode(transparentGif));
    final source = await ImageAnimation.load(gif);
    final data = await encodeImageAnimation(source: source);
    final webp = await File('${temporary.path}/source.webp').writeAsBytes(data);
    final decoded = await ImageAnimation.load(webp);
    if (decoded.starts.length != 3 || decoded.duration != const Duration(milliseconds: 550)) {
      throw StateError('Export changed frame timing: ${decoded.starts}, ${decoded.duration}');
    }
    final codec = await decoded.codec();
    try {
      for (var i = 0; i < 3; i++) {
        final frame = await codec.getNextFrame();
        try {
          if (frame.image.width != 512 || frame.image.height != 512) throw StateError('Invalid sticker size');
          final pixels = (await frame.image.toByteData(
            format: ui.ImageByteFormat.rawStraightRgba,
          ))!.buffer.asUint8List();
          if (pixels[3] != 0) throw StateError('Lost transparent padding');
          if (i == 1 && pixels[(256 * 512 + 64) * 4 + 3] != 0) throw StateError('Lost GIF disposal');
        } finally {
          frame.image.dispose();
        }
      }
    } finally {
      codec.dispose();
    }
    final trimmed = await encodeImageAnimation(
      source: source,
      start: const Duration(milliseconds: 50),
      end: const Duration(milliseconds: 450),
      quarterTurns: 1,
    );
    final trimmedFile = await File('${temporary.path}/trimmed.webp').writeAsBytes(trimmed);
    final trimmedSource = await ImageAnimation.load(trimmedFile);
    if (trimmedSource.duration != const Duration(milliseconds: 400)) throw StateError('Lost partial frame duration');
    // The cropped WebP must also remain usable as the saved editor background.
    await encodeImageAnimation(source: trimmedSource);
    status.value = 'GIF_SMOKE_OK: 3 frames, timing, alpha, trim and re-encoding';
    debugPrint(status.value);
  } catch (error, stack) {
    status.value = 'GIF_SMOKE_FAILED: $error';
    debugPrint('$error\n$stack');
    rethrow;
  } finally {
    await temporary.delete(recursive: true);
  }
}
