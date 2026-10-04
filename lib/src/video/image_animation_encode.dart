import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'common.dart';
import 'image_animation.dart';

/// Streams straight-alpha RGBA frames to the existing libwebp encoder.
/// No video intermediate is used, so transparent GIFs stay transparent.
/// The lossless default favors speed for editable backgrounds. In lossless
/// mode, quality controls compression effort, not pixel fidelity.
Future<Uint8List> encodeImageAnimation({
  required ImageAnimation source,
  Duration start = Duration.zero,
  Duration? end,
  ui.Rect crop = const ui.Rect.fromLTRB(0, 0, 1, 1),
  bool stretch = false,
  int quarterTurns = 0,
  double speed = 1,
  File? overlay,
  WebPConfig config = const WebPConfig(lossless: true, quality: 0, method: 0),
  int? fps,
  void Function(double)? onProgress,
}) async {
  const channel = MethodChannel('de.loicezt.stickers/methods');
  if (!speed.isFinite || speed < 1 || speed > 2) {
    throw ArgumentError.value(speed, 'speed', 'Must be between 1 and 2');
  }
  var stop = end ?? source.duration;
  if (start < Duration.zero || stop > source.duration || stop <= start) {
    throw ArgumentError('Invalid animation trim range');
  }
  // Timeline drags have microsecond precision; WebP timestamps are whole ms.
  // Snap both edges before selecting frames to avoid two frames at timestamp 0.
  start = Duration(milliseconds: (start.inMicroseconds / 1000).round());
  stop = Duration(milliseconds: (stop.inMicroseconds / 1000).round());
  if (stop <= start) throw ArgumentError('Animation trim range must cover at least one millisecond');
  if (fps != null && fps <= 0) throw ArgumentError.value(fps, 'fps', 'Must be positive');
  final durationMs = math.max(speed == 1 ? 1 : 10, ((stop - start).inMilliseconds / speed).round());
  final decoder = await source.codec();
  ui.Image? overlayImage;
  var started = false;
  try {
    if (overlay != null) {
      final overlayCodec = await ui.instantiateImageCodec(await overlay.readAsBytes());
      try {
        overlayImage = (await overlayCodec.getNextFrame()).image;
      } finally {
        overlayCodec.dispose();
      }
    }
    await channel.invokeMethod<void>('beginImageAnimation', {'config': config.toMap()});
    started = true;
    onProgress?.call(0);
    var lastTimestamp = -1;
    for (var i = 0; i < source.starts.length; i++) {
      final frameStart = source.starts[i];
      if (frameStart >= stop) break;
      final frameEnd = i + 1 < source.starts.length ? source.starts[i + 1] : source.duration;
      final frame = await decoder.getNextFrame();
      try {
        if (frameEnd <= start) continue;
        final timestamp = math.max(0, ((frameStart - start).inMilliseconds / speed).round());
        if (timestamp <= lastTimestamp) continue;
        // Very short WebP delays may be clamped by players. Merge accelerated
        // frames rather than creating delays shorter than 10 ms.
        if (speed > 1 && (timestamp > durationMs - 10 || (lastTimestamp >= 0 && timestamp - lastTimestamp < 10))) {
          continue;
        }
        if (lastTimestamp >= 0 && fps != null && timestamp - lastTimestamp < 1000 / fps) continue;
        final pixels = await renderAnimationFrame(
          frame.image,
          crop: crop,
          stretch: stretch,
          quarterTurns: quarterTurns,
          overlay: overlayImage,
        );
        await channel.invokeMethod<void>('addImageAnimationFrame', {'pixels': pixels, 'timestampMs': timestamp});
        lastTimestamp = timestamp;
        // Leave room for the native encoder to assemble the final container.
        onProgress?.call(.95 * ((frameEnd - start).inMicroseconds / (stop - start).inMicroseconds).clamp(0, 1));
      } finally {
        frame.image.dispose();
      }
    }
    final data = await channel.invokeMethod<Uint8List>(
      'finishImageAnimation',
      {'durationMs': durationMs},
    );
    if (data == null || data.isEmpty) throw StateError('Could not encode image animation');
    started = false;
    onProgress?.call(1);
    return data;
  } finally {
    decoder.dispose();
    overlayImage?.dispose();
    if (started) {
      try {
        await channel.invokeMethod<void>('cancelImageAnimation');
      } on PlatformException {
        // Keep the original export failure if native cleanup also fails.
      }
    }
  }
}

Future<Uint8List> renderAnimationFrame(
  ui.Image image, {
  ui.Rect crop = const ui.Rect.fromLTRB(0, 0, 1, 1),
  bool stretch = false,
  int quarterTurns = 0,
  ui.Image? overlay,
}) async {
  final turns = quarterTurns % 4;
  final width = (turns.isOdd ? image.height : image.width).toDouble();
  final height = (turns.isOdd ? image.width : image.height).toDouble();
  final area = ui.Rect.fromLTRB(crop.left * width, crop.top * height, crop.right * width, crop.bottom * height);
  final sx = stretch ? 512 / area.width : math.min(512 / area.width, 512 / area.height);
  final sy = stretch ? 512 / area.height : sx;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.save();
  canvas.clipRect(const ui.Rect.fromLTWH(0, 0, 512, 512));
  canvas.translate((512 - area.width * sx) / 2, (512 - area.height * sy) / 2);
  canvas.scale(sx, sy);
  canvas.translate(-area.left, -area.top);
  canvas.clipRect(area);
  switch (turns) {
    case 1:
      canvas.translate(image.height.toDouble(), 0);
    case 2:
      canvas.translate(image.width.toDouble(), image.height.toDouble());
    case 3:
      canvas.translate(0, image.width.toDouble());
  }
  canvas.rotate(turns * math.pi / 2);
  canvas.drawImage(image, ui.Offset.zero, ui.Paint()..filterQuality = ui.FilterQuality.medium);
  canvas.restore();
  if (overlay != null) canvas.drawImage(overlay, ui.Offset.zero, ui.Paint());
  final picture = recorder.endRecording();
  try {
    final output = await picture.toImage(512, 512);
    try {
      return (await output.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!.buffer.asUint8List();
    } finally {
      output.dispose();
    }
  } finally {
    picture.dispose();
  }
}
