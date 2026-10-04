import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/globals.dart' as globals;
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/pages/multi_crop_page.dart';

void main() {
  late Directory temporary;
  late StickerPack pack;
  late Uint8List image;
  late List<String> paths;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('multi_crop_test_');
    globals.packsDir = temporary.path;
    pack = StickerPack('Photos', 'Test', 'id', [], '0', false);
    globals.packs = [pack];
    image = (await rootBundle.load('assets/transparent.webp')).buffer.asUint8List();
    paths = [];
    for (final name in ['good.webp', 'bad.webp']) {
      paths.add((await File('${temporary.path}/$name').writeAsBytes(image)).path);
    }
  });
  tearDown(() async => temporary.delete(recursive: true));

  Future<void> open(WidgetTester tester, Future<Uint8List> Function(String, StickerPack) prepare) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MultiCropPage(pack: pack, paths: paths, prepare: prepare),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  Future<void> waitForSave(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump();
      if (pack.stickers.isNotEmpty && find.byType(MultiCropPage).evaluate().isEmpty) break;
    }
    await tester.pumpAndSettle();
  }

  testWidgets('failed photo keeps the batch unpublished, removal and retry reuse the prepared good photo', (
    tester,
  ) async {
    var calls = 0;
    await open(tester, (path, _) async {
      calls++;
      if (path == paths.last) throw const FormatException('Bad photo');
      return image;
    });
    await tester.tap(find.text('Save 2 stickers'));
    await tester.pumpAndSettle();
    expect(pack.stickers, isEmpty);
    expect(find.text('Some photos could not be processed. Crop or remove them before saving.'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pump();
    await tester.tap(find.text('Save 1 sticker'));
    await waitForSave(tester);
    expect(pack.stickers, hasLength(1));
    expect(calls, 2);
    expect(pack.stickers.single.editorData, isNotNull);
  });

  testWidgets('individual crop can be cancelled without saving and an empty review cannot submit', (tester) async {
    await open(tester, (_, _) async => image);
    await tester.tap(find.byIcon(Icons.crop).first);
    await tester.pumpAndSettle();
    expect(find.byType(CropPage), findsOneWidget);
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump();
      if (tester.widget<CropPage>(find.byType(CropPage)).editorKey.currentState != null) break;
    }
    Navigator.of(tester.element(find.byType(CropPage))).pop();
    await tester.pumpAndSettle();
    expect(pack.stickers, isEmpty);
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    final save = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(save.onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
