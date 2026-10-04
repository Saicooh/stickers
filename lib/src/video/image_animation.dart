import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// GIF/WebP frames are decoded by Flutter, including disposal, blending and alpha.
/// Only the current decoded frame is retained, even for long animations.
class ImageAnimation {
  final Uint8List bytes;
  final List<Duration> starts;
  final Duration duration;
  final ui.Size size;

  ImageAnimation._(this.bytes, this.starts, this.duration, this.size);

  static Future<bool> isSupported(File file) async {
    final input = await file.open();
    try {
      final header = await input.read(12);
      return (header.length >= 6 && String.fromCharCodes(header.take(6)) == 'GIF87a') ||
          (header.length >= 6 && String.fromCharCodes(header.take(6)) == 'GIF89a') ||
          (header.length == 12 &&
              String.fromCharCodes(header.take(4)) == 'RIFF' &&
              String.fromCharCodes(header.skip(8)) == 'WEBP');
    } finally {
      await input.close();
    }
  }

  static Future<ImageAnimation> load(File file) async {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1);
    final starts = <Duration>[];
    var duration = Duration.zero;
    try {
      for (var i = 0; i < codec.frameCount; i++) {
        starts.add(duration);
        final frame = await codec.getNextFrame();
        duration += frame.duration > Duration.zero ? frame.duration : const Duration(milliseconds: 100);
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        final size = ui.Size(descriptor.width.toDouble(), descriptor.height.toDouble());
        return ImageAnimation._(bytes, starts, duration, size);
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }

  Future<ui.Codec> codec({int? maxDimension}) {
    final scale = maxDimension == null ? 1.0 : math.min(1.0, maxDimension / math.max(size.width, size.height));
    return ui.instantiateImageCodec(
      bytes,
      targetWidth: math.max(1, (size.width * scale).round()),
      targetHeight: math.max(1, (size.height * scale).round()),
    );
  }

  int frameAt(Duration position) {
    var low = 0;
    var high = starts.length;
    while (low + 1 < high) {
      final middle = (low + high) ~/ 2;
      if (starts[middle] <= position) {
        low = middle;
      } else {
        high = middle;
      }
    }
    return low;
  }

  Duration adjacentFrame(Duration position, int direction) {
    if (direction < 0) {
      return starts.lastWhere((time) => time < position, orElse: () => Duration.zero);
    }
    return starts.firstWhere((time) => time > position, orElse: () => duration);
  }

  Future<List<Uint8List?>> thumbnails() async {
    final decoder = await codec(maxDimension: 160);
    final result = <Uint8List?>[];
    var index = -1;
    ui.Image? image;
    try {
      for (var i = 0; i < 10; i++) {
        final target = frameAt(duration * (i / 10));
        while (index < target) {
          image?.dispose();
          image = (await decoder.getNextFrame()).image;
          index++;
        }
        result.add((await image!.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
      }
      return result;
    } finally {
      image?.dispose();
      decoder.dispose();
    }
  }
}
