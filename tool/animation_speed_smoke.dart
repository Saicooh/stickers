// flutter run -t tool/animation_speed_smoke.dart
// Requires cache/sticker_speed_source.mp4: synthetic 2 s, 30 fps video.
// No pack/settings writes; all outputs are owned temporary test files.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:stickers/src/video/animated_media_controller.dart';
import 'package:stickers/src/video/common.dart';
import 'package:stickers/src/video/crop_scale.dart';
import 'package:stickers/src/video/image_animation.dart';
import 'package:stickers/src/video/image_animation_encode.dart';

import '../test/fixtures/transparent_gif.dart';

Future<List<Uint8List>> pixels(ImageAnimation source) async {
  final codec = await source.codec();
  final result = <Uint8List>[];
  try {
    for (var i = 0; i < source.starts.length; i++) {
      final frame = (await codec.getNextFrame()).image;
      try {
        result.add((await frame.toByteData())!.buffer.asUint8List());
      } finally {
        frame.dispose();
      }
    }
    return result;
  } finally {
    codec.dispose();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cache = await getTemporaryDirectory();
  final directory = await cache.createTemp('animation_speed_smoke_');
  final status = ValueNotifier('Checking animation speeds…');
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ValueListenableBuilder(
            valueListenable: status,
            builder: (_, value, _) => Text(value),
          ),
        ),
      ),
    ),
  );
  final crop = CropAndScaleService();
  const methods = MethodChannel('de.loicezt.stickers/methods');
  const overlayEvents = EventChannel('de.loicezt.stickers/progress_encode');
  try {
    final gif = await File('${directory.path}/source.gif').writeAsBytes(base64Decode(transparentGif));
    final animation = await ImageAnimation.load(gif);
    final baselineFile = await File(
      '${directory.path}/baseline.webp',
    ).writeAsBytes(await encodeImageAnimation(source: animation));
    final baseline = await ImageAnimation.load(baselineFile);
    final baselinePixels = await pixels(baseline);
    for (final speed in [1.1, 1.5, 2.0]) {
      final output = await File(
        '${directory.path}/gif_$speed.webp',
      ).writeAsBytes(await encodeImageAnimation(source: animation, speed: speed));
      final result = await ImageAnimation.load(output);
      final resultPixels = await pixels(result);
      if (result.duration.inMilliseconds != (550 / speed).round() || resultPixels.length != baselinePixels.length) {
        throw StateError('GIF speed did not change timing correctly');
      }
      for (var i = 0; i < baselinePixels.length; i++) {
        if (!listEquals(baselinePixels[i], resultPixels[i]) ||
            result.starts[i].inMilliseconds != (animation.starts[i].inMilliseconds / speed).round()) {
          throw StateError('GIF speed changed pixels/alpha or frame timing');
        }
      }
      debugPrint('ANIMATION_SPEED gif=$speed duration=${result.duration.inMilliseconds}ms pixels/alpha=identical');
    }
    final shortDelays = base64Decode(transparentGif);
    for (var i = 0; i < shortDelays.length - 7; i++) {
      if (shortDelays[i] == 0x21 && shortDelays[i + 1] == 0xf9 && shortDelays[i + 2] == 4) {
        shortDelays[i + 4] = 2;
        shortDelays[i + 5] = 0;
      }
    }
    final fastSource = await ImageAnimation.load(await File('${directory.path}/fast.gif').writeAsBytes(shortDelays));
    final fastResult = await ImageAnimation.load(
      await File('${directory.path}/fast.webp').writeAsBytes(
        await encodeImageAnimation(source: fastSource, speed: 2),
      ),
    );
    if (fastResult.duration.inMilliseconds != 30) throw StateError('Short accelerated delays were clamped');
    debugPrint(
      'ANIMATION_SPEED fast GIF frames=${fastResult.starts.length} duration=${fastResult.duration.inMilliseconds}ms',
    );

    for (final speed in [1.0, 1.1, 1.5, 2.0]) {
      final output = File('${directory.path}/video_$speed.mp4');
      final completed = Completer<void>();
      var running = false;
      final subscription = crop.progressStream.listen((event) {
        if (event.status == Status.RUNNING) running = true;
        if (!running || completed.isCompleted) return;
        if (event.status == Status.SUCCESS) completed.complete();
        if (event.status == Status.FAILED || event.status == Status.CANCELLED) {
          completed.completeError(StateError('Video crop failed: ${event.status}'));
        }
      });
      try {
        await crop.start(
          inputFile: '${cache.path}/sticker_speed_source.mp4',
          outputFile: output.path,
          start: const Duration(milliseconds: 200),
          end: const Duration(milliseconds: 1800),
          crop: const Rect.fromLTRB(0, 0, 1, 1),
          stretch: false,
          quarterTurns: 0,
          speed: speed,
        );
        await completed.future.timeout(const Duration(seconds: 30));
      } finally {
        await subscription.cancel();
      }
      final preview = AnimatedMediaController(output);
      try {
        await preview.initialize();
        final expectedMs = 1600 / speed;
        final durationMs = preview.value.duration.inMilliseconds;
        if ((durationMs - expectedMs).abs() > 90) {
          throw StateError('Wrong video duration: $durationMs expected $expectedMs');
        }
        await preview.setPlaybackSpeed(1.7);
        if (preview.value.playbackSpeed != 1.7) throw StateError('Native video preview did not apply speed');
        debugPrint('ANIMATION_SPEED video=$speed MP4=${durationMs}ms preview=1.7x');
      } finally {
        preview.dispose();
      }
      final assembled = Completer<void>();
      running = false;
      final overlaySubscription = overlayEvents.receiveBroadcastStream().listen((dynamic event) {
        if (event['status'] == 'RUNNING') running = true;
        if (!running || assembled.isCompleted) return;
        if (event['status'] == 'SUCCESS') assembled.complete();
        if (event['status'] == 'FAILED' || event['status'] == 'CANCELLED') {
          assembled.completeError(StateError('Video WebP export failed'));
        }
      });
      final overlay = await File(
        '${directory.path}/overlay.webp',
      ).writeAsBytes((await rootBundle.load('assets/transparent.webp')).buffer.asUint8List());
      final webp = File('${directory.path}/video_$speed.webp');
      try {
        await methods.invokeMethod<void>('startOverlay', {
          'videoFile': output.path,
          'overlayFile': overlay.path,
          'outputFile': webp.path,
          'fps': 24,
          'config': const WebPConfig(lossless: true, quality: 0, method: 0).toMap(),
        });
        await assembled.future.timeout(const Duration(seconds: 30));
      } finally {
        await overlaySubscription.cancel();
      }
      final result = await ImageAnimation.load(webp);
      if ((result.duration.inMilliseconds - 1600 / speed).abs() > 100) throw StateError('Wrong final sticker duration');
      final expectedFrames = 1600 / speed / 1000 * 24;
      if ((result.starts.length - expectedFrames).abs() > 2) {
        throw StateError('Video was resampled below its FPS limit');
      }
      final framePixels = (await pixels(result)).first;
      if (framePixels[3] != 0 || framePixels[(256 * 512 + 256) * 4 + 3] != 255) {
        throw StateError('Video transparency lost');
      }
      debugPrint(
        'ANIMATION_SPEED video=$speed sticker=${result.duration.inMilliseconds}ms frames=${result.starts.length} alpha=OK',
      );
    }
    status.value = 'ANIMATION_SPEED_OK';
    debugPrint(status.value);
  } catch (error, stack) {
    debugPrint('ANIMATION_SPEED_FAILED $error\n$stack');
    rethrow;
  } finally {
    crop.dispose();
    await directory.delete(recursive: true);
  }
}
