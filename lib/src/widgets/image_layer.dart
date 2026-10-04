import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:image_editor/image_editor.dart';
import 'package:stickers/src/pages/edit_page.dart';

// The editor updates asset paths when saving a sticker.
// ignore: must_be_immutable
class ImageLayer extends StatelessWidget implements EditorLayer {
  String source;

  ImageLayer({super.key, required this.source});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(child: Image.file(File(source), fit: BoxFit.contain));
  }

  Future<MixImageOption> exportOption() async {
    final bytes = await File(source).readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final size = applyBoxFit(
        BoxFit.contain,
        Size(descriptor.width.toDouble(), descriptor.height.toDouble()),
        const Size.square(512),
      ).destination;
      return MixImageOption(
        target: MemoryImageSource(bytes),
        x: ((512 - size.width) / 2).round(),
        y: ((512 - size.height) / 2).round(),
        width: size.width.round(),
        height: size.height.round(),
      );
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'image',
      'source': source,
    };
  }

  factory ImageLayer.fromJson(Map<String, dynamic> json) {
    return ImageLayer(
      source: json['source'] as String,
    );
  }
}
