import 'dart:convert';
import 'dart:io';

import 'package:stickers/src/data/sticker_pack.dart';

/// Copies a pack and every referenced editor asset, rewriting paths for the destination.
Future<Map<String, dynamic>> copyPackAssets(
  StickerPack pack,
  Directory destination, {
  String prefix = '',
  bool relativePaths = true,
}) async {
  String reference(String relative) => relativePaths ? relative : '${destination.path}/$relative';
  Future<String> copy(String source, String relative) async {
    final output = File('${destination.path}/$relative');
    await output.parent.create(recursive: true);
    await File(source).copy(output.path);
    return reference(relative);
  }

  final data = Map<String, dynamic>.from(pack.toJson());
  await destination.create(recursive: true);
  for (var i = 0; i < pack.stickers.length; i++) {
    final sticker = pack.stickers[i];
    data['stickers'][i]['source'] = await copy(sticker.source, '$prefix$i.webp');
    if (sticker.editorData != null) {
      final editor = jsonDecode(await File(sticker.editorData!).readAsString()) as Map<String, dynamic>;
      final background = editor['background'] as String;
      final name = File(background).uri.pathSegments.last;
      final extension = name.contains('.') ? name.split('.').last : 'bin';
      editor['background'] = await copy(background, '$prefix$i/background.$extension');
      var imageIndex = 0;
      for (final layer in editor['layers'] as List) {
        if (layer['source'] is String) {
          layer['source'] = await copy(layer['source'], '$prefix$i/${imageIndex++}.webp');
        }
      }
      final editorPath = '$prefix$i.json';
      final output = File('${destination.path}/$editorPath');
      await output.writeAsString(jsonEncode(editor), flush: true);
      data['stickers'][i]['editorData'] = reference(editorPath);
    }
  }
  if (pack.trayIcon != null) data['trayIcon'] = await copy(pack.trayIcon!, '${prefix}tray.webp');
  return data;
}

/// The multi-pack format is separate from the app's legacy list manifest.
Future<void> writePackBackup(List<StickerPack> packs, Directory destination) async {
  final entries = <Map<String, dynamic>>[];
  for (var i = 0; i < packs.length; i++) {
    entries.add(await copyPackAssets(packs[i], destination, prefix: 'pack_$i/'));
  }
  await File('${destination.path}/packs.json').writeAsString(jsonEncode({'version': 1, 'packs': entries}), flush: true);
}

Future<String> resolvePackFile(Directory root, String relative) async {
  if (relative.isEmpty ||
      relative.startsWith('/') ||
      relative.contains('\\') ||
      relative.contains(':') ||
      relative.split('/').any((part) => part == '..' || part == '.' || part.isEmpty)) {
    throw const FormatException('Invalid pack asset path');
  }
  final file = File('${root.path}/$relative');
  if (!await file.exists()) throw FormatException('Missing pack asset: $relative');
  final resolvedRoot = await root.resolveSymbolicLinks();
  final resolved = await file.resolveSymbolicLinks();
  if (!resolved.startsWith('$resolvedRoot${Platform.pathSeparator}')) {
    throw const FormatException('Pack asset outside archive');
  }
  return file.absolute.path;
}

/// Reads both older single-pack ZIPs and complete multi-pack backups.
Future<List<StickerPack>> readPackBackup(Directory root) async {
  final manifest = File('${root.path}/packs.json');
  final List entries;
  if (await manifest.exists()) {
    final data = jsonDecode(await manifest.readAsString());
    if (data is! Map || data['version'] != 1 || data['packs'] is! List) {
      throw const FormatException('Invalid pack backup manifest');
    }
    entries = data['packs'];
    if (entries.isEmpty) throw const FormatException('Empty pack backup');
  } else {
    entries = [jsonDecode(await File('${root.path}/pack.json').readAsString())];
  }
  final result = <StickerPack>[];
  for (final entry in entries) {
    final pack = StickerPack.fromJson(entry);
    if (pack.id.isEmpty || pack.id == '.' || pack.id == '..' || pack.id.contains(RegExp(r'[/\\:]'))) {
      throw const FormatException('Invalid pack identifier');
    }
    for (final sticker in pack.stickers) {
      sticker.source = await resolvePackFile(root, sticker.source);
      if (sticker.editorData != null) {
        final relative = sticker.editorData!;
        final editorFile = File(await resolvePackFile(root, relative));
        final editor = jsonDecode(await editorFile.readAsString());
        final assetDirectory = relative.replaceFirst(RegExp(r'\.json$'), '');
        String background = editor['background'];
        // Older exports hardcoded .webp even when the actual editable source was a video.
        if (!await File('${root.path}/$background').exists() && background == '$assetDirectory/background.webp') {
          final candidates = await Directory(
            '${root.path}/$assetDirectory',
          ).list().where((file) => file is File && file.uri.pathSegments.last.startsWith('background.')).toList();
          if (candidates.length == 1) background = '$assetDirectory/${candidates.single.uri.pathSegments.last}';
        }
        editor['background'] = await resolvePackFile(root, background);
        for (final layer in editor['layers'] as List) {
          if (layer['source'] is String) {
            String source = layer['source'];
            // Legacy image layers used their original absolute paths. Only read the archived copy.
            if (source.startsWith('/') || source.contains(':') || source.contains('\\')) {
              source = '$assetDirectory/${source.replaceAll('\\', '/').split('/').last}';
            }
            layer['source'] = await resolvePackFile(root, source);
          }
        }
        await editorFile.writeAsString(jsonEncode(editor), flush: true);
        sticker.editorData = editorFile.path;
      }
    }
    if (pack.trayIcon != null) pack.trayIcon = await resolvePackFile(root, pack.trayIcon!);
    result.add(pack);
  }
  return result;
}
