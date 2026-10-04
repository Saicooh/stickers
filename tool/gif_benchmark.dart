// flutter run -t tool/gif_benchmark.dart --dart-define=GIF_FILE=/path/in/app/cache/source.gif
// Reads the source without touching packs. All outputs are temporary.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:stickers/src/video/common.dart';
import 'package:stickers/src/video/image_animation.dart';
import 'package:stickers/src/video/image_animation_encode.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final status = ValueNotifier('Benchmarking GIF crop…');
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
  final temporary = await Directory.systemTemp.createTemp('gif_benchmark_');
  try {
    const path = String.fromEnvironment('GIF_FILE');
    if (path.isEmpty) throw ArgumentError('Supply GIF_FILE with a file readable by this app');
    final clock = Stopwatch()..start();
    final source = await ImageAnimation.load(File(path));
    debugPrint(
      'GIF_BENCH load=${clock.elapsedMilliseconds}ms size=${source.size} '
      'frames=${source.starts.length} duration=${source.duration.inMilliseconds}ms',
    );
    final decoder = await source.codec();
    var decodeUs = 0;
    var renderUs = 0;
    try {
      for (var i = 0; i < source.starts.length; i++) {
        clock.reset();
        final frame = await decoder.getNextFrame();
        decodeUs += clock.elapsedMicroseconds;
        try {
          clock.reset();
          await renderAnimationFrame(frame.image);
          renderUs += clock.elapsedMicroseconds;
        } finally {
          frame.image.dispose();
        }
      }
    } finally {
      decoder.dispose();
    }
    debugPrint('GIF_BENCH decode=${decodeUs / 1000}ms render/readback=${renderUs / 1000}ms');
    const configs = {
      'baseline': WebPConfig(lossless: true, quality: 100, method: 4),
      'fast': WebPConfig(lossless: true, quality: 0, method: 0),
    };
    File? reference;
    const runs = int.fromEnvironment('BENCH_RUNS', defaultValue: 3);
    for (final entry in configs.entries) {
      final times = <int>[];
      for (var run = 0; run < runs; run++) {
        debugPrint('GIF_BENCH starting ${entry.key} run=$run');
        clock.reset();
        final data = await encodeImageAnimation(source: source, config: entry.value);
        times.add(clock.elapsedMilliseconds);
        final output = await File('${temporary.path}/${entry.key}.webp').writeAsBytes(data);
        debugPrint('GIF_BENCH ${entry.key} run=$run time=${times.last}ms bytes=${data.length}');
        if (entry.key == 'baseline') {
          reference = output;
        } else {
          await compareAnimations(reference!, output);
        }
      }
      times.sort();
      debugPrint('GIF_BENCH ${entry.key} median=${times[times.length ~/ 2]}ms');
    }
    status.value = 'GIF_BENCH_OK: lossless pixels and timing match';
    debugPrint(status.value);
  } catch (error, stack) {
    status.value = 'GIF_BENCH_FAILED: $error';
    debugPrint('$error\n$stack');
    rethrow;
  } finally {
    await temporary.delete(recursive: true);
  }
}

Future<void> compareAnimations(File reference, File result) async {
  final expected = await ImageAnimation.load(reference);
  final actual = await ImageAnimation.load(result);
  if (expected.duration != actual.duration || !listEquals(expected.starts, actual.starts)) {
    throw StateError('Lossless configuration changed frame timing');
  }
  final left = await expected.codec();
  final right = await actual.codec();
  try {
    for (var i = 0; i < expected.starts.length; i++) {
      final a = (await left.getNextFrame()).image;
      final b = (await right.getNextFrame()).image;
      try {
        final x = (await a.toByteData())!.buffer.asUint8List();
        final y = (await b.toByteData())!.buffer.asUint8List();
        if (!listEquals(x, y)) throw StateError('Lossless configuration changed pixels in frame $i');
      } finally {
        a.dispose();
        b.dispose();
      }
    }
  } finally {
    left.dispose();
    right.dispose();
  }
}
