import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stickers/src/video/animated_media_controller.dart';
import 'package:stickers/src/video/image_animation.dart';
import 'package:stickers/src/video/image_animation_encode.dart';

import 'fixtures/transparent_gif.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('de.loicezt.stickers/methods');
  late Directory temporary;
  late File gif;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('sticker_gif_test_');
    // Detect the contents even when a provider gives the file a different extension.
    gif = await File('${temporary.path}/animation.bin').writeAsBytes(base64Decode(transparentGif));
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    await temporary.delete(recursive: true);
  });

  test('GIF timing and frame boundaries use the original variable delays', () async {
    expect(await ImageAnimation.isSupported(gif), isTrue);
    final source = await ImageAnimation.load(gif);
    expect(source.size, const ui.Size(8, 4));
    expect(source.starts, [Duration.zero, const Duration(milliseconds: 100), const Duration(milliseconds: 400)]);
    expect(source.duration, const Duration(milliseconds: 550));
    expect(source.frameAt(const Duration(milliseconds: 399)), 1);
    expect(source.adjacentFrame(const Duration(milliseconds: 100), -1), Duration.zero);
    expect(source.adjacentFrame(const Duration(milliseconds: 100), 1), const Duration(milliseconds: 400));
    expect(source.adjacentFrame(const Duration(milliseconds: 400), 1), source.duration);
  });

  test('preview seeks backwards and generates timeline thumbnails for GIFs', () async {
    final controller = AnimatedMediaController(gif);
    try {
      await controller.initialize();
      expect(controller.value.isInitialized, isTrue);
      await controller.seekTo(const Duration(milliseconds: 420));
      await controller.seekTo(const Duration(milliseconds: 100));
      expect(controller.value.position, const Duration(milliseconds: 100));
      expect(await controller.thumbnails(), hasLength(10));
    } finally {
      controller.dispose();
    }
  });

  test('trim preserves partial frame delays, transparent pixels and GIF disposal', () async {
    final timestamps = <int>[];
    final frames = <Uint8List>[];
    int? duration;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map?;
      if (call.method == 'addImageAnimationFrame') {
        timestamps.add(args!['timestampMs'] as int);
        frames.add(args['pixels'] as Uint8List);
      }
      if (call.method == 'finishImageAnimation') {
        duration = args!['durationMs'] as int;
        return Uint8List.fromList([1]);
      }
      return null;
    });
    await encodeImageAnimation(
      source: await ImageAnimation.load(gif),
      start: const Duration(milliseconds: 50),
      end: const Duration(milliseconds: 450),
    );
    expect(timestamps, [0, 50, 350]);
    expect(duration, 400);
    List<int> pixel(int frame, int x, int y) => frames[frame].sublist((y * 512 + x) * 4, (y * 512 + x) * 4 + 4);
    expect(pixel(0, 64, 256), [255, 0, 0, 255]);
    expect(pixel(0, 256, 0).last, 0); // transparent padding
    expect(pixel(1, 64, 256).last, 0); // old red rectangle was disposed
    expect(pixel(1, 192, 256), [0, 0, 255, 255]);
  });

  test('the playhead can stop a segment partway through a long GIF frame', () async {
    final controller = AnimatedMediaController(gif);
    final reachedBoundary = Completer<void>();
    try {
      await controller.initialize();
      await controller.seekTo(const Duration(milliseconds: 100));
      controller.addListener(() {
        if (controller.value.isPlaying && controller.value.position >= const Duration(milliseconds: 150)) {
          controller.pause();
          if (!reachedBoundary.isCompleted) reachedBoundary.complete();
        }
      });
      await controller.play();
      await reachedBoundary.future.timeout(const Duration(seconds: 2));
      expect(controller.value.position, lessThan(const Duration(milliseconds: 400)));
      expect(controller.value.isPlaying, isFalse);
    } finally {
      controller.dispose();
    }
  });

  test('rotation and crop do not paint source pixels into transparent padding', () async {
    final source = await ImageAnimation.load(gif);
    final decoder = await source.codec();
    final frame = await decoder.getNextFrame();
    try {
      final rotated = await renderAnimationFrame(frame.image, quarterTurns: 1);
      int alpha(int x, int y) => rotated[(y * 512 + x) * 4 + 3];
      expect(alpha(256, 64), 255);
      expect(alpha(0, 64), 0);
      final cropped = await renderAnimationFrame(frame.image, crop: const ui.Rect.fromLTRB(0, 0, 1, .25));
      // Source pixels below the chosen top row must not spill into the padding.
      expect(cropped[(350 * 512 + 64) * 4 + 3], 0);
    } finally {
      frame.image.dispose();
      decoder.dispose();
    }
  });

  test('encoder failure releases the session and propagates the error', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'addImageAnimationFrame') throw PlatformException(code: 'TEST_FAILURE');
      return null;
    });
    await expectLater(
      encodeImageAnimation(source: await ImageAnimation.load(gif)),
      throwsA(isA<PlatformException>()),
    );
    expect(calls.last, 'cancelImageAnimation');
  });

  test('accelerated GIF export divides variable delays while preserving pixels and alpha', () async {
    final timestamps = <int>[];
    final frames = <Uint8List>[];
    int? duration;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'addImageAnimationFrame') {
        timestamps.add((call.arguments as Map)['timestampMs']);
        frames.add((call.arguments as Map)['pixels']);
      }
      if (call.method == 'finishImageAnimation') {
        duration = (call.arguments as Map)['durationMs'];
        return Uint8List.fromList([1]);
      }
      return null;
    });
    final source = await ImageAnimation.load(gif);
    await encodeImageAnimation(source: source);
    final originals = List<Uint8List>.of(frames);
    for (final speed in [1.1, 1.5, 2.0]) {
      frames.clear();
      timestamps.clear();
      await encodeImageAnimation(source: source, speed: speed);
      expect(timestamps, [0, (100 / speed).round(), (400 / speed).round()]);
      expect(duration, (550 / speed).round());
      expect(frames, hasLength(originals.length));
      for (var i = 0; i < frames.length; i++) {
        expect(frames[i], originals[i]);
      }
    }
    timestamps.clear();
    await encodeImageAnimation(
      source: source,
      speed: 2,
      start: const Duration(milliseconds: 50),
      end: const Duration(milliseconds: 450),
    );
    expect(timestamps, [0, 25, 175]);
    expect(duration, 200);
  });

  test('preview changes speed while playing and retains it across pause and seek', () async {
    final controller = AnimatedMediaController(gif);
    final reached = Completer<void>();
    final clock = Stopwatch();
    try {
      await controller.initialize();
      await controller.seekTo(const Duration(milliseconds: 100));
      await controller.play();
      await controller.setPlaybackSpeed(2);
      clock.start();
      controller.addListener(() {
        if (controller.value.position >= const Duration(milliseconds: 200)) {
          controller.pause();
          if (!reached.isCompleted) reached.complete();
        }
      });
      await reached.future.timeout(const Duration(seconds: 2));
      expect(
        (controller.value.position - const Duration(milliseconds: 100)).inMicroseconds,
        closeTo(clock.elapsedMicroseconds * 2, 15000),
      );
      await controller.seekTo(Duration.zero);
      expect(controller.value.playbackSpeed, 2);
      await controller.setPlaybackSpeed(1.1);
      expect(controller.value.playbackSpeed, 1.1);
    } finally {
      controller.dispose();
    }
  });

  test('invalid speeds fail before starting the native encoder', () async {
    final source = await ImageAnimation.load(gif);
    var called = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async {
      called = true;
      return null;
    });
    for (final speed in [0.0, .9, 2.1, double.nan, double.infinity]) {
      await expectLater(encodeImageAnimation(source: source, speed: speed), throwsArgumentError);
    }
    expect(called, isFalse);
  });

  test('crop progress reaches completion only after the native container is assembled', () async {
    final progress = <double>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'finishImageAnimation') {
        expect(progress.last, closeTo(.95, .001));
        return Uint8List.fromList([1]);
      }
      return null;
    });
    await encodeImageAnimation(source: await ImageAnimation.load(gif), onProgress: progress.add);
    expect(progress.first, 0);
    expect(progress.last, 1);
    expect(progress, orderedEquals([...progress]..sort()));
  });

  test('submillisecond trim edges cannot send duplicate WebP frame timestamps', () async {
    final timestamps = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'addImageAnimationFrame') {
        timestamps.add((call.arguments as Map)['timestampMs'] as int);
      }
      if (call.method == 'finishImageAnimation') {
        expect((call.arguments as Map)['durationMs'], 350);
        return Uint8List.fromList([1]);
      }
      return null;
    });
    await encodeImageAnimation(
      source: await ImageAnimation.load(gif),
      start: const Duration(microseconds: 99900),
      end: const Duration(microseconds: 449900),
    );
    expect(timestamps, [0, 300]);
  });

  test('cleanup failure does not hide the original encoder error and a retry can succeed', () async {
    var failed = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'addImageAnimationFrame' && !failed) {
        failed = true;
        throw PlatformException(code: 'ENCODE_FAILED');
      }
      if (call.method == 'cancelImageAnimation') throw PlatformException(code: 'CLEANUP_FAILED');
      if (call.method == 'finishImageAnimation') return Uint8List.fromList([1]);
      return null;
    });
    final source = await ImageAnimation.load(gif);
    await expectLater(
      encodeImageAnimation(source: source),
      throwsA(isA<PlatformException>().having((error) => error.code, 'code', 'ENCODE_FAILED')),
    );
    expect(await encodeImageAnimation(source: source), [1]);
  });
}
