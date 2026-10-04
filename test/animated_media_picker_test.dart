import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/pages/sticker_pack_page.dart';
import 'package:stickers/src/video/animated_media_picker.dart';

import 'fixtures/transparent_gif.dart';

class _VideoPicker extends ImagePickerPlatform {
  int videoCalls = 0;

  @override
  Future<XFile?> getVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async {
    expect(source, ImageSource.gallery);
    videoCalls++;
    return XFile('selected.mp4');
  }

  @override
  Future<List<XFile>> getMedia({required MediaOptions options}) =>
      throw StateError('Animated packs must never open the unrestricted image/video picker');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('de.loicezt.stickers/methods');
  late Directory temporary;
  final originalPicker = ImagePickerPlatform.instance;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('animated_picker_test_');
  });
  tearDown(() async {
    ImagePickerPlatform.instance = originalPicker;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    await temporary.delete(recursive: true);
  });

  void selectedGif(String? path) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'pickGif');
      return path;
    });
  }

  test('GIF selection preserves animated GIF bytes without relying on the file extension', () async {
    final bytes = base64Decode(transparentGif);
    final file = await File('${temporary.path}/picked.bin').writeAsBytes(bytes);
    selectedGif(file.path);
    expect(await AnimatedMediaPicker().pick(AnimatedMediaSource.gif), file.path);
    expect(await file.readAsBytes(), bytes);
  });

  test('a PNG presented as a GIF is rejected and never reaches the editor', () async {
    final file = await File('${temporary.path}/photo.gif').writeAsBytes(
      base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='),
    );
    selectedGif(file.path);
    await expectLater(
      AnimatedMediaPicker().pick(AnimatedMediaSource.gif),
      throwsA(isA<PlatformException>().having((error) => error.code, 'code', 'INVALID_GIF')),
    );
    expect(await file.exists(), isFalse);
  });

  test('a single-frame GIF cannot become a static sticker inside an animated pack', () async {
    final file = await File('${temporary.path}/still.gif').writeAsBytes(
      base64Decode('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'),
    );
    selectedGif(file.path);
    await expectLater(
      AnimatedMediaPicker().pick(AnimatedMediaSource.gif),
      throwsA(isA<PlatformException>().having((error) => error.code, 'code', 'INVALID_GIF')),
    );
  });

  test('cancelling GIF selection does not start an import', () async {
    selectedGif(null);
    expect(await AnimatedMediaPicker().pick(AnimatedMediaSource.gif), isNull);
  });

  testWidgets('animated pack offers filtered GIF/video sources and routes video to crop', (tester) async {
    final picker = _VideoPicker();
    ImagePickerPlatform.instance = picker;
    EditArguments? cropped;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: StickerPackPage(StickerPack('Animated', 'Author', 'test', [], '1', true), () {})),
        onGenerateRoute: (settings) {
          expect(settings.name, '/crop_video');
          cropped = settings.arguments as EditArguments;
          return MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Crop editor')));
        },
      ),
    );
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('Video'), findsOneWidget);
    expect(find.text('GIF'), findsOneWidget);
    expect(picker.videoCalls, 0);
    await tester.tap(find.text('Video'));
    await tester.pumpAndSettle();
    expect(picker.videoCalls, 1);
    expect(cropped?.mediaPath, 'selected.mp4');
    expect(find.text('Crop editor'), findsOneWidget);
  });

  testWidgets('a photo returned by the GIF provider shows an error without opening crop', (tester) async {
    var routed = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'pickGif');
      throw PlatformException(code: 'INVALID_GIF');
    });
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: StickerPackPage(StickerPack('Animated', 'Author', 'test', [], '1', true), () {})),
        onGenerateRoute: (_) {
          routed = true;
          return MaterialPageRoute<void>(builder: (_) => const Scaffold());
        },
      ),
    );
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GIF'));
    await tester.pumpAndSettle();
    expect(routed, isFalse);
    expect(find.text('Choose a video or an animated GIF for this pack.'), findsOneWidget);
  });
}
