import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:stickers/src/fonts_api/fonts_registry.dart';
import 'package:stickers/src/globals.dart' as globals;

class _Paths extends PathProviderPlatform {
  _Paths(this.directory);
  final String directory;
  @override
  Future<String?> getApplicationDocumentsPath() async => directory;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  final registrations = <String>[];
  String? failNativeFamily;
  const native = MethodChannel('com.fluttercandies/image_editor');
  setUpAll(() async {
    temporary = await Directory.systemTemp.createTemp('native_fonts_test_');
    globals.bundledFontsDir = '${temporary.path}/bundled';
    await Directory(globals.bundledFontsDir).create();
    PathProviderPlatform.instance = _Paths(temporary.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      registrations.add(call.arguments['name']);
      if (call.arguments['name'] == failNativeFamily) {
        failNativeFamily = null;
        throw PlatformException(code: 'registration_failed');
      }
      return call.arguments['name'];
    });
    await FontsRegistry.init();
  });
  tearDownAll(() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await temporary.delete(recursive: true);
  });

  test('startup skips native registration and export registers only its used font once', () async {
    expect(registrations, isEmpty);
    expect(identical(FontsRegistry.init(), FontsRegistry.init()), isTrue);
    await FontsRegistry.prepareForExport(['sans-serif', 'Lobster', 'Lobster']);
    await FontsRegistry.prepareForExport(['Lobster']);
    expect(registrations, ['Lobster']);
    expect(await File('${globals.bundledFontsDir}/Lobster.ttf').exists(), isTrue);
  });

  test('a failed native registration can retry without restarting the app', () async {
    failNativeFamily = 'Pacifico';
    await expectLater(FontsRegistry.prepareForExport(['Pacifico']), throwsA(isA<PlatformException>()));
    await FontsRegistry.prepareForExport(['Pacifico']);
    await FontsRegistry.prepareForExport(['Pacifico']);
    expect(registrations.where((family) => family == 'Pacifico'), hasLength(2));
  });
}
