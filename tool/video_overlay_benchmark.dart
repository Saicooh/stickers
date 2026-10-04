// flutter run -t tool/video_overlay_benchmark.dart --dart-define=BENCH_LABEL=baseline
// Input: cache/fork_video_bench/source.mp4 and overlay.webp. Only writes to this cache directory.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:stickers/src/video/common.dart';
import 'package:stickers/src/video/image_animation.dart';

import 'gif_benchmark.dart' show compareAnimations;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final status = ValueNotifier('Benchmarking video overlay…');
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
  const methods = MethodChannel('de.loicezt.stickers/methods');
  const events = EventChannel('de.loicezt.stickers/progress_encode');
  const label = String.fromEnvironment('BENCH_LABEL', defaultValue: 'baseline');
  const runs = int.fromEnvironment('BENCH_RUNS', defaultValue: 3);
  final directory = Directory('${(await getTemporaryDirectory()).path}/fork_video_bench');
  if (!await File('${directory.path}/source.mp4').exists()) throw StateError('Missing benchmark video');
  Completer<void>? completion;
  var running = false;
  final subscription = events.receiveBroadcastStream().listen((dynamic data) {
    if (data['status'] == 'RUNNING') running = true;
    if (!running || completion == null || completion.isCompleted) return;
    if (data['status'] == 'SUCCESS') completion.complete();
    if (data['status'] == 'FAILED' || data['status'] == 'CANCELLED') {
      completion.completeError(StateError('Video export ${data['status']}'));
    }
  });
  try {
    final times = <int>[];
    for (var run = 0; run < runs; run++) {
      completion = Completer<void>();
      running = false;
      final output = File('${directory.path}/$label-$run.webp');
      final clock = Stopwatch()..start();
      await methods.invokeMethod<void>('startOverlay', {
        'videoFile': '${directory.path}/source.mp4',
        'overlayFile': '${directory.path}/overlay.webp',
        'outputFile': output.path,
        'fps': 30,
        'config': const WebPConfig(lossless: true, quality: 0, method: 0).toMap(),
      });
      await completion.future.timeout(const Duration(seconds: 60));
      times.add(clock.elapsedMilliseconds);
      final source = await ImageAnimation.load(output);
      final codec = await source.codec();
      try {
        final frame = (await codec.getNextFrame()).image;
        try {
          final pixels = (await frame.toByteData())!.buffer.asUint8List();
          final center = (256 * 512 + 256) * 4;
          if (pixels[center] != 255 || pixels[center + 1] != 0 || pixels[center + 3] != 255) {
            throw StateError('Opaque red overlay missing at center');
          }
          if (pixels[3] != 0) throw StateError('Letterbox transparency lost');
        } finally {
          frame.dispose();
        }
      } finally {
        codec.dispose();
      }
      if (label != 'baseline') await compareAnimations(File('${directory.path}/baseline-0.webp'), output);
      debugPrint(
        'VIDEO_BENCH $label run=$run time=${times.last}ms frames=${source.starts.length} bytes=${await output.length()}',
      );
    }
    times.sort();
    debugPrint('VIDEO_BENCH $label median=${times[times.length ~/ 2]}ms');
    status.value = 'VIDEO_BENCH_OK $label';
    debugPrint(status.value);
  } catch (error, stack) {
    status.value = 'VIDEO_BENCH_FAILED $error';
    debugPrint('$error\n$stack');
    rethrow;
  } finally {
    await subscription.cancel();
  }
}
