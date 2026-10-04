import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stickers/src/widgets/draw_layer.dart';

void main() {
  testWidgets('drawing, undo and redo repaint ink without rebuilding the page', (tester) async {
    final painter = DrawingPainter();
    var builds = 0;
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox.square(
            dimension: 100,
            child: Builder(
              builder: (_) {
                builds++;
                return RepaintBoundary(
                  key: key,
                  child: CustomPaint(painter: painter),
                );
              },
            ),
          ),
        ),
      ),
    );
    Future<int> alphaAt(int x, int y) async {
      final image = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
      try {
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
        return bytes[(y * 100 + x) * 4 + 3];
      } finally {
        image.dispose();
      }
    }

    final stroke = Stroke(Colors.red, 10)..points.addAll([const Offset(10, 50), const Offset(90, 50)]);
    painter.strokes.add(stroke);
    painter.changed();
    await tester.pump();
    expect(await tester.runAsync(() => alphaAt(50, 50)), 255);
    painter.strokes.clear();
    painter.changed();
    await tester.pump();
    expect(await tester.runAsync(() => alphaAt(50, 50)), 0);
    painter.strokes.add(stroke);
    painter.changed();
    await tester.pump();
    expect(await tester.runAsync(() => alphaAt(50, 50)), 255);
    expect(builds, 1);
    await tester.pumpWidget(const SizedBox());
    painter.changes.dispose();
  });

  test('cached strokes preserve points, growing paths and scaling after undo', () {
    final stroke = Stroke(Colors.red, 10)..points.addAll([Offset.zero, const Offset(10, 0)]);
    expect(stroke.pathFor(1).computeMetrics().single.length, 10);
    stroke.points.add(const Offset(20, 0));
    expect(stroke.pathFor(1).computeMetrics().single.length, 20);
    expect(stroke.pathFor(2).computeMetrics().single.length, 40);
    final restored = Stroke.fromJson(stroke.toJson());
    expect(restored.points, stroke.points);
    expect(restored.pathFor(1).computeMetrics().single.length, 20);
  });
}
