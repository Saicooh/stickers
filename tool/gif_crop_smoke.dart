// flutter run -t tool/gif_crop_smoke.dart --dart-define=GIF_FILE=/path/in/app/cache/source.gif
// Exercises Done on the real crop page. Never saves a pack or edits the source.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/pages/video_crop_page.dart';
import 'package:stickers/src/video/animated_media_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const path = String.fromEnvironment('GIF_FILE');
  if (path.isEmpty) throw ArgumentError('Supply GIF_FILE with a file readable by this app');
  final temporary = await Directory.systemTemp.createTemp('gif_crop_smoke_');
  mediaCacheDir = temporary.path;
  final cropKey = GlobalKey();
  final opened = Completer<EditArguments>();
  runApp(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: VideoCropPage(
        key: cropKey,
        pack: StickerPack('Smoke test', 'Test', 'unused', [], '1', true),
        index: 0,
        imagePath: path,
      ),
      onGenerateRoute: (settings) {
        if (settings.name != '/edit') throw StateError('Unexpected route: ${settings.name}');
        opened.complete(settings.arguments as EditArguments);
        return MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Center(child: Text('Checking crop…'))),
        );
      },
    ),
  );
  AnimatedMediaController? editor;
  try {
    FilledButton? done;
    void findDone(Element element) {
      if (element.widget is FilledButton) done = element.widget as FilledButton;
      element.visitChildElements(findDone);
    }

    final clock = Stopwatch()..start();
    while (done?.onPressed == null && clock.elapsed < const Duration(seconds: 15)) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      (cropKey.currentContext as Element?)?.visitChildElements(findDone);
    }
    if (done?.onPressed == null) throw StateError('Crop page never became ready');
    clock.reset();
    done!.onPressed!();
    final args = await opened.future.timeout(const Duration(minutes: 3));
    final cropMs = clock.elapsedMilliseconds;
    editor = AnimatedMediaController(File(args.mediaPath!));
    await editor.initialize();
    debugPrint(
      'GIF_CROP_SMOKE_OK crop=${cropMs}ms done-to-editor-ready=${clock.elapsedMilliseconds}ms '
      'frames=${editor.animation!.starts.length} duration=${editor.value.duration.inMilliseconds}ms',
    );
  } catch (error, stack) {
    debugPrint('GIF_CROP_SMOKE_FAILED: $error\n$stack');
    rethrow;
  } finally {
    editor?.dispose();
    await temporary.delete(recursive: true);
  }
}
