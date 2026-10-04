import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

enum AnimatedMediaSource { video, gif }

class AnimatedMediaPicker {
  static const _channel = MethodChannel('de.loicezt.stickers/methods');

  Future<String?> pick(AnimatedMediaSource source) async {
    if (source == AnimatedMediaSource.video) {
      return (await ImagePicker().pickVideo(source: ImageSource.gallery))?.path;
    }
    final path = await _channel.invokeMethod<String>('pickGif');
    if (path == null) return null;
    // MIME metadata can be wrong. Verify both GIF contents and animation before editing.
    final file = File(path);
    try {
      final input = await file.open();
      final String header;
      try {
        header = String.fromCharCodes(await input.read(6));
      } finally {
        await input.close();
      }
      if (header != 'GIF87a' && header != 'GIF89a') throw PlatformException(code: 'INVALID_GIF');
      final codec = await ui.instantiateImageCodec(await file.readAsBytes(), targetWidth: 1);
      try {
        if (codec.frameCount < 2) throw PlatformException(code: 'INVALID_GIF');
      } finally {
        codec.dispose();
      }
      return path;
    } catch (_) {
      await file.delete();
      rethrow;
    }
  }
}
