import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/pages/video_crop_page.dart';

import 'fixtures/transparent_gif.dart';

void main() {
  testWidgets('GIF crop reports frame progress without a video service and opens the editable background', (
    tester,
  ) async {
    const channel = MethodChannel('de.loicezt.stickers/methods');
    final temporary = (await tester.runAsync(() => Directory.systemTemp.createTemp('gif_crop_page_test_')))!;
    final gif = (await tester.runAsync(
      () => File('${temporary.path}/source.gif').writeAsBytes(base64Decode(transparentGif)),
    ))!;
    mediaCacheDir = temporary.path;
    final assembling = Completer<void>();
    final finish = Completer<void>();
    EditArguments? edit;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      // There must be no startTrim/cancelTrim calls when importing a GIF.
      expect(call.method, isIn(['beginImageAnimation', 'addImageAnimationFrame', 'finishImageAnimation']));
      if (call.method == 'beginImageAnimation') {
        final config = (call.arguments as Map)['config'] as Map;
        expect(config['lossless'], isTrue);
        expect(config['method'], 0);
        expect(config['quality'], 0);
      }
      if (call.method == 'finishImageAnimation') {
        assembling.complete();
        await finish.future;
        return Uint8List.fromList([1, 2, 3]);
      }
      return null;
    });
    try {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: VideoCropPage(
            pack: StickerPack('Animated', 'Author', 'test', [], '1', true),
            index: 0,
            imagePath: gif.path,
          ),
          onGenerateRoute: (settings) {
            expect(settings.name, '/edit');
            edit = settings.arguments as EditArguments;
            return MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Sticker editor')));
          },
        ),
      );
      await tester.runAsync(() async {
        // Let file IO, Flutter frame decoding and thumbnail generation complete.
        for (var i = 0; i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          if (tester.widget<FilledButton>(find.byType(FilledButton)).onPressed != null) break;
          await tester.pump();
        }
      });
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
      await tester.runAsync(() async {
        await tester.tap(find.text('Done'));
        for (var i = 0; i < 100 && !assembling.isCompleted; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }
        await assembling.future.timeout(const Duration(seconds: 5));
      });
      await tester.pump();
      expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, closeTo(.95, .001));
      expect(edit, isNull);
      await tester.runAsync(() async {
        finish.complete();
        for (var i = 0; i < 100 && edit == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('Sticker editor'), findsOneWidget);
      expect(edit?.type, MediaType.video);
      await tester.runAsync(() async {
        expect(await File(edit!.mediaPath!).readAsBytes(), [1, 2, 3]);
        expect(await gif.readAsBytes(), base64Decode(transparentGif));
      });
    } finally {
      if (!finish.isCompleted) finish.complete();
      await tester.pumpWidget(const SizedBox());
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      await tester.runAsync(() => temporary.delete(recursive: true));
    }
  });
}
