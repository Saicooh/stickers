import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:image_editor/image_editor.dart';
import 'package:share_plus/share_plus.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/data/pack_store.dart';
import 'package:stickers/src/data/portable_pack.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/util.dart';
import 'package:stickers/src/widgets/image_layer.dart';

import 'editor_data.dart';

PackStore? _store;

PackStore get _packStore {
  final path = "$packsDir/packs.json";
  if (_store?.file.path != path) _store = PackStore(File(path));
  return _store!;
}

Future<void> savePacks(List<StickerPack> packs) => _packStore.save(packs);

Future<void> exportPack(StickerPack pack) async {
  final archive = await createPackArchive([pack], singlePack: true);
  await SharePlus.instance.share(ShareParams(files: [XFile(archive.path)]));
}

Future<File> createPackArchive(List<StickerPack> packs, {bool singlePack = false}) async {
  if (packs.isEmpty) throw StateError('No packs to export');
  final snapshot = packs.map((pack) => StickerPack.fromJson(jsonDecode(jsonEncode(pack.toJson())))).toList();
  Directory exportDir = Directory(exportCacheDir);
  await exportDir.create(recursive: true);
  final packDir = await exportDir.createTemp('backup_');
  final title = singlePack ? snapshot.single.title.replaceAll(RegExp(r'[^\w !&-]'), '_') : 'Sticker-backup';
  final zipFile = File('${exportDir.path}/${title}_${uid()}.zip');
  try {
    if (singlePack) {
      final data = await copyPackAssets(snapshot.single, packDir);
      await File('${packDir.path}/pack.json').writeAsString(jsonEncode(data), flush: true);
    } else {
      await writePackBackup(snapshot, packDir);
    }
    await ZipFile.createFromDirectory(sourceDir: packDir, zipFile: zipFile);
    return zipFile;
  } catch (_) {
    if (await zipFile.exists()) await zipFile.delete();
    rethrow;
  } finally {
    await packDir.delete(recursive: true);
  }
}

Future<void> importPack(File f) async {
  //TODO show progress
  Stopwatch sw = Stopwatch()..start();
  Directory importDir = Directory(mediaCacheDir);
  await importDir.create(recursive: true);
  Directory unzipDir = await importDir.createTemp('import_');
  try {
    await ZipFile.extractToDirectory(zipFile: f, destinationDir: unzipDir);
    debugPrint("Unzip t=${sw.elapsedMilliseconds}ms");

    List<StickerPack> packsToAdd = [];

    switch (f.path.split(".").last.toLowerCase()) {
      case "wastickers":
        final dirContents = unzipDir.listSync();
        final pack = StickerPack(
          (await File("${unzipDir.path}/title.txt").readAsString()).replaceAll("\n", ""),
          (await File("${unzipDir.path}/author.txt").readAsString()).replaceAll("\n", ""),
          uid(),
          dirContents
              .map((entry) => entry.path)
              .where((path) => path.toLowerCase().endsWith(".webp"))
              .map((path) => Sticker(path, ["❤"], null))
              .toList(),
          "1000",
          false, // It's not possible to directly export animated packs from that app.
          trayIcon: dirContents.where((entry) => entry.path.toLowerCase().endsWith(".png")).firstOrNull?.path,
        );
        packsToAdd.add(pack);
        break;
      case "stickify":
        final dirs = unzipDir.listSync().whereType<Directory>();
        for (final dir in dirs) {
          final json = jsonDecode(File("${dir.path}/contents.json").readAsStringSync());
          for (final packJson in json["sticker_packs"]) {
            final pack = StickerPack(
              packJson["name"],
              packJson["publisher"],
              packJson["identifier"],
              (packJson["stickers"] as List)
                  .map(
                    (sticker) => Sticker(
                      "${dir.path}/${sticker["image_file"]}",
                      (sticker["emojis"] as List).isEmpty ? ["❤"] : sticker["emojis"],
                      null,
                    ),
                  )
                  .toList(),
              packJson["image_data_version"],
              packJson["animated_sticker_pack"],
              publisherWebsite: packJson["publisher_website"],
              licenseAgreementWebsite: packJson["license_agreement_website"],
              privacyPolicyWebsite: packJson["privacy_policy_website"],
            );
            packsToAdd.add(pack);
          }
        }
        break;
      default:
        packsToAdd.addAll(await readPackBackup(unzipDir));
    }
    debugPrint("Parse t=${sw.elapsedMilliseconds}ms");

    final created = <Directory>[];
    final installed = <StickerPack>[];
    try {
      for (final pack in packsToAdd) {
        if (pack.id.isEmpty || pack.id == '.' || pack.id == '..' || pack.id.contains(RegExp(r'[/\\:]'))) {
          throw const FormatException('Invalid pack identifier');
        }
        while (packs.any((p) => p.id == pack.id) ||
            installed.any((p) => p.id == pack.id) ||
            await Directory('$packsDir/${pack.id}').exists()) {
          pack.id = "${pack.id}_";
        }
        final directory = await Directory('$packsDir/${pack.id}').create(recursive: true);
        created.add(directory);
        final data = await copyPackAssets(pack, directory, relativePaths: false);
        debugPrint("[${pack.id}] Copy t=${sw.elapsedMilliseconds}ms");
        installed.add(StickerPack.fromJson(data));
      }
      packs.addAll(installed);
      await savePacks(packs);
    } catch (_) {
      packs.removeWhere(installed.contains);
      for (final directory in created) {
        await directory.delete(recursive: true);
      }
      rethrow;
    }
  } finally {
    // Only remove the directory created by this import, never the archive's parent folder.
    await unzipDir.delete(recursive: true);
  }
}

Future<List<StickerPack>> getPacks() => _packStore.load();

Future<Uint8List> cropSticker(
  Rect cropRect,
  Uint8List rawImageData,
  StickerPack pack,
  int index,
  double rotation, [
  bool stretch = false,
]) async {
  // Apply crop then scale then put on 512x512 transparent image in center

  final crop = ImageEditorOption();
  Size oldSize = cropRect.size;
  crop.addOption(RotateOption(rotation.toInt()));
  crop.addOption(ClipOption.fromRect(cropRect));
  Size newSize;
  // Make the longest border exactly 512 pixels wide, preserving aspect ratio if we're not stretching
  if (!stretch) {
    if (oldSize.height > oldSize.width) {
      newSize = Size(oldSize.width * 512 / oldSize.height, 512);
    } else {
      newSize = Size(512, oldSize.height * 512 / oldSize.width);
    }
  } else {
    newSize = Size(512, 512);
  }
  crop.addOption(
    ScaleOption(
      newSize.width.toInt(),
      newSize.height.toInt(),
    ),
  );
  crop.outputFormat = const OutputFormat.png(); // Ensure the format supports transparency
  final intermediate = (await ImageEditor.editImage(image: rawImageData, imageEditorOption: crop))!;

  final option = ImageMergeOption(
    canvasSize: const Size.square(512),
    format: const OutputFormat.webp_lossy(50),
  );

  option.addImage(
    MergeImageConfig(
      image: MemoryImageSource(intermediate),
      position: ImagePosition(
        Offset((512 - newSize.width) / 2, (512 - newSize.height) / 2),
        newSize,
      ),
    ),
  );
  return (await ImageMerger.mergeToMemory(option: option))!;
}

/// Adds a sticker to a sticker pack
/// Copies the file to the required place
///
/// If [index] is 30 it changes the tray icon.
Future<void> addToPack(
  StickerPack pack,
  int index,
  Uint8List data, [
  EditorData? editorData,
  bool replace = false,
]) async {
  Directory("$packsDir/${pack.id}").createSync(recursive: true);
  File stickerFile;
  File? editorDataFile;

  if (index == 30) {
    stickerFile = File("$packsDir/${pack.id}/tray.webp");
    await stickerFile.writeAsBytes(data);
    pack.trayIcon = stickerFile.path;
  } else {
    // This is enough to avoid filename collisions
    final String filename = "${index}_${uid()}";

    if (editorData != null) {
      await Directory("$packsDir/${pack.id}/$filename/").create(recursive: true);
      final backgroundPath = "$packsDir/${pack.id}/$filename/background.${editorData.background.split(".").last}";
      await File(editorData.background).rename(backgroundPath);
      editorData.background = backgroundPath;

      for (int i = 0; i < editorData.layers.length; i++) {
        if (editorData.layers[i] is ImageLayer) {
          final ImageLayer layer = editorData.layers[i] as ImageLayer;
          await File(layer.source).rename("$packsDir/${pack.id}/$filename/$i.webp");
          layer.source = "$packsDir/${pack.id}/$filename/$i.webp";
        }
      }

      editorDataFile = File("$packsDir/${pack.id}/$filename.json");
      await editorDataFile.writeAsString(jsonEncode(editorData.toJson()));
    }
    stickerFile = File("$packsDir/${pack.id}/$filename.webp");
    await stickerFile.writeAsBytes(data);
    if (replace) {
      await File(pack.stickers[index].source).delete();
      if (pack.stickers[index].editorData != null) {
        await File(pack.stickers[index].editorData!).delete();
        await Directory(pack.stickers[index].editorData!.replaceAll(RegExp(".json\$"), "")).delete(recursive: true);
      }
      pack.stickers[index].source = stickerFile.path;
      pack.stickers[index].editorData = editorDataFile?.path;
    } else {
      pack.stickers.add(Sticker(stickerFile.path, ["❤"], editorDataFile?.path));
    }
  }

  await FileImage(stickerFile).evict();
  await pack.onEdit();
  // Clear media cache after adding a sticker
  print("Clearing media cache");
  Directory(mediaCacheDir).list().listen((entry) => entry.delete());
}

Future<File> saveTemp(Uint8List data) async {
  File output = File("$mediaCacheDir/${uid()}.tmp.webp");
  await output.writeAsBytes(data);
  return output;
}
