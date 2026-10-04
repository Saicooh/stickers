import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/globals.dart';

Future<Uint8List> prepareUncroppedSticker(String path, StickerPack pack) async {
  final bytes = await File(path).readAsBytes();
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final codec = await descriptor.instantiateCodec(targetWidth: 1, targetHeight: 1);
    try {
      if (codec.frameCount != 1) throw const FormatException('Choose a still photo for a static pack');
    } finally {
      codec.dispose();
    }
    return await cropSticker(
      ui.Rect.fromLTWH(0, 0, descriptor.width.toDouble(), descriptor.height.toDouble()),
      bytes,
      pack,
      0,
      0,
    );
  } finally {
    descriptor?.dispose();
    buffer.dispose();
  }
}

/// Publish the whole batch with one manifest save. Keep editable backgrounds and roll back failed writes.
Future<void> saveStickerBatch(StickerPack pack, List<Uint8List> images) async {
  if (images.isEmpty) return;
  if (pack.animated || pack.stickers.length + images.length > 30 || !packs.contains(pack)) {
    throw StateError('The selected photos do not fit in this static pack');
  }
  final parent = await Directory('$packsDir/${pack.id}').create(recursive: true);
  final directory = await parent.createTemp('batch_');
  final added = <Sticker>[];
  String? previousVersion;
  try {
    for (var i = 0; i < images.length; i++) {
      final source = File('${directory.path}/$i.webp');
      await source.writeAsBytes(images[i], flush: true);
      final background = File('${directory.path}/$i/background.webp');
      await background.parent.create();
      await source.copy(background.path);
      final editor = await File(
        '${directory.path}/$i.json',
      ).writeAsString(jsonEncode({'background': background.path, 'layers': []}), flush: true);
      added.add(Sticker(source.path, ['❤'], editor.path));
    }
    if (pack.stickers.length + added.length > 30 || !packs.contains(pack)) {
      throw StateError('Pack changed while saving');
    }
    pack.stickers.addAll(added);
    previousVersion = pack.imageDataVersion;
    await pack.onEdit();
  } catch (_) {
    pack.stickers.removeWhere(added.contains);
    if (previousVersion != null) pack.imageDataVersion = previousVersion;
    await directory.delete(recursive: true);
    rethrow;
  }
}
