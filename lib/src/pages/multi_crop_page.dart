import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/data/batch_import.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/dialogs/error_dialog.dart';
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/pages/default_page.dart';
import 'package:stickers/src/widgets/sticker_thumbnail.dart';

class _Photo {
  _Photo(this.path);
  final String path;
  Uint8List? crop;
  bool failed = false;
}

class MultiCropPage extends StatefulWidget {
  const MultiCropPage({super.key, required this.pack, required this.paths, this.prepare = prepareUncroppedSticker});
  final StickerPack pack;
  final List<String> paths;
  final Future<Uint8List> Function(String, StickerPack) prepare;

  @override
  State<MultiCropPage> createState() => _MultiCropPageState();
}

class _MultiCropPageState extends State<MultiCropPage> {
  late final _photos = widget.paths.map(_Photo.new).toList();
  bool _saving = false;
  bool _cropping = false;
  int _prepared = 0;

  Future<void> _crop(_Photo photo) async {
    setState(() => _cropping = true);
    try {
      final data = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          builder: (_) => CropPage(
            pack: widget.pack,
            index: 0,
            imagePath: photo.path,
            returnCrop: true,
          ),
        ),
      );
      if (mounted && data != null) {
        setState(() {
          photo.crop = data;
          photo.failed = false;
        });
      }
    } finally {
      if (mounted) setState(() => _cropping = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _prepared = 0;
    });
    try {
      final images = <Uint8List>[];
      for (final photo in _photos) {
        try {
          images.add(photo.crop ??= await widget.prepare(photo.path, widget.pack));
          photo.failed = false;
        } catch (_) {
          photo.failed = true;
        }
        if (!mounted) return;
        setState(() => _prepared++);
      }
      if (_photos.any((photo) => photo.failed)) return;
      await saveStickerBatch(widget.pack, images);
      if (!mounted) return;
      setState(() => _saving = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => ErrorDialog(
          title: AppLocalizations.of(context)!.couldntExportSticker,
          message: error.toString(),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final busy = _saving || _cropping;
    return PopScope(
      canPop: !_saving,
      child: DefaultActivity(
        appBar: AppBar(title: Text(l10n.reviewStickers)),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: _photos.length,
                  itemBuilder: (context, index) {
                    final photo = _photos[index];
                    return ListTile(
                      leading: SizedBox.square(
                        dimension: 64,
                        child: photo.crop == null
                            ? StickerThumbnail(photo.path)
                            : Image.memory(
                                photo.crop!,
                                cacheWidth: (64 * MediaQuery.devicePixelRatioOf(context)).ceil(),
                                fit: BoxFit.contain,
                              ),
                      ),
                      title: Text(File(photo.path).uri.pathSegments.last, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: photo.failed
                          ? Text(l10n.couldntLoadMedia, style: TextStyle(color: Theme.of(context).colorScheme.error))
                          : null,
                      onTap: busy ? null : () => _crop(photo),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: l10n.cropYourSticker,
                            onPressed: busy ? null : () => _crop(photo),
                            icon: const Icon(Icons.crop),
                          ),
                          IconButton(
                            tooltip: l10n.delete,
                            onPressed: busy ? null : () => setState(() => _photos.remove(photo)),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_photos.any((photo) => photo.failed)) Text(l10n.batchImportErrors),
                    if (_saving) ...[
                      LinearProgressIndicator(value: _prepared / _photos.length),
                      Text(l10n.savingStickers(_prepared, _photos.length)),
                    ],
                    FilledButton.icon(
                      onPressed: busy || _photos.isEmpty ? null : _save,
                      icon: const Icon(Icons.check),
                      label: Text(l10n.saveAllStickers(_photos.length)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
