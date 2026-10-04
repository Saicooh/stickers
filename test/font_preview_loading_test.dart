import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/fonts_api/fonts_models.dart';
import 'package:stickers/src/fonts_api/fonts_registry.dart';
import 'package:stickers/src/fonts_api/google_fonts.dart';
import 'package:stickers/src/globals.dart' as globals;
import 'package:stickers/src/pages/fonts_search_page.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.directory);
  final String directory;
  @override
  Future<String?> getApplicationDocumentsPath() async => directory;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  WebFont font(String family) => WebFont.fromJson({
    'family': family,
    'variants': ['regular'],
    'files': {'regular': 'https://example.com/font.ttf'},
  });
  setUpAll(() async {
    temporary = await Directory.systemTemp.createTemp('fonts_test_');
    globals.bundledFontsDir = '${temporary.path}/bundled';
    globals.fontsCacheDir = '${temporary.path}/cache';
    await Directory(globals.bundledFontsDir).create();
    PathProviderPlatform.instance = _Paths(temporary.path);
    await FontsRegistry.init();
  });
  tearDownAll(() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await temporary.delete(recursive: true);
  });

  test('nullable Google Fonts fields parse without losing downloadable files', () {
    final reply = GoogleFontsReply.fromJson({
      'items': [
        {
          'family': 'Example',
          'variants': ['regular'],
          'files': {'regular': 'https://example.com/font.ttf'},
          'menu': null,
          'subsets': null,
        },
      ],
    });
    expect(reply.items.single.menu, '');
    expect(reply.items.single.files['regular'], 'https://example.com/font.ttf');
    expect(GoogleFontsReply.fromJson({}).items, isEmpty);
  });

  test('duplicate preview requests share downloads and failed downloads can retry', () async {
    var requests = 0;
    final bytes = (await rootBundle.load('assets/fonts/Lobster.ttf')).buffer.asUint8List();
    final client = MockClient((request) async {
      requests++;
      return request.url.host == 'fonts.googleapis.com'
          ? http.Response('@font-face { src: url(https://example.com/font.ttf); }', 200)
          : http.Response.bytes(bytes, 200);
    });
    final a = downloadAndRegisterFontPreview(font('Preview Test'), client: client);
    final b = downloadAndRegisterFontPreview(font('Preview Test'), client: client);
    expect(identical(a, b), isTrue);
    await Future.wait([a, b]);
    expect(requests, 2);
    await downloadAndRegisterFontPreview(font('Preview Test'), client: client);
    expect(requests, 2);
    final bad = MockClient((_) async => http.Response('offline', 503));
    await expectLater(downloadAndRegisterFontPreview(font('Retry Test'), client: bad), throwsA(isA<HttpException>()));
    await downloadAndRegisterFontPreview(font('Retry Test'), client: client);
    expect(requests, 4);
    client.close();
    bad.close();
  });

  Widget preview(String family, Future<void> Function(WebFont) loader) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: GoogleFontPreview(font(family), loadPreview: loader)),
  );
  testWidgets('a preview removed during a fling never starts its download', (tester) async {
    var calls = 0;
    await tester.pumpWidget(preview('Brief', (_) async => calls++));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 0);
  });
  testWidgets('reused preview state downloads only the current family after settling', (tester) async {
    final calls = <String>[];
    Future<void> load(WebFont font) async => calls.add(font.family);
    await tester.pumpWidget(preview('Before', load));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(preview('After', load));
    await tester.pump(const Duration(milliseconds: 310));
    await tester.pump();
    expect(calls, ['After']);
    await tester.pumpWidget(const SizedBox());
  });
}
