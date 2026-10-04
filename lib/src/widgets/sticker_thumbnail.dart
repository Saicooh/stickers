import 'dart:io';

import 'package:flutter/material.dart';
import 'package:stickers/src/checker_painter.dart';

/// Decode sticker previews at their displayed size; keep the full file for editing/export.
class StickerThumbnail extends StatelessWidget {
  const StickerThumbnail(this.source, {super.key});

  final String source;

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        int pixels(double size) => size.isFinite ? (size * pixelRatio).ceil().clamp(1, 512) : 512;
        return RepaintBoundary(
          child: CustomPaint(
            painter: CheckerPainter(context),
            child: Image(
              image: ResizeImage(
                FileImage(File(source)),
                width: pixels(constraints.maxWidth),
                height: pixels(constraints.maxHeight),
                policy: ResizeImagePolicy.fit,
              ),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => const Icon(Icons.broken_image_outlined),
            ),
          ),
        );
      },
    );
  }
}
