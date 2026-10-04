import 'package:flutter/cupertino.dart';
import 'package:image_editor/image_editor.dart';
import 'package:stickers/src/pages/edit_page.dart';

class DrawLayer extends StatelessWidget implements EditorLayer {
  final DrawingPainter painter = DrawingPainter();

  static DrawLayer fromJson(Map<String, dynamic> json) {
    final layer = DrawLayer();
    layer.painter.strokes = json["strokes"].map<Stroke>((stroke) => Stroke.fromJson(stroke)).toList();
    return layer;
  }

  DrawOption get drawOption {
    DrawOption r = DrawOption();
    for (final stroke in painter.strokes) {
      if (stroke.points.isEmpty) continue;
      final linePaint = DrawPaint(paintingStyle: PaintingStyle.stroke, color: stroke.color, lineWeight: stroke.width);
      final fillPaint = DrawPaint(paintingStyle: PaintingStyle.fill, color: stroke.color, lineWeight: stroke.width);
      Offset last = stroke.points.first;
      for (final point in stroke.points) {
        r.addDrawPart(LineDrawPart(start: last, end: point, paint: linePaint));
        r.addDrawPart(
          OvalDrawPart(
            rect: Rect.fromLTWH(
              point.dx - (stroke.width) / 2,
              point.dy - (stroke.width) / 2,
              stroke.width,
              stroke.width,
            ),
            paint: fillPaint,
          ),
        );
        last = point;
      }
    }
    return r;
  }

  DrawLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(painter: painter),
      ),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      "type": "draw",
      "strokes": painter.strokes.map((e) => e.toJson()).toList(),
    };
  }
}

class Stroke {
  final Color color;
  final double width;
  List<Offset> points = [];
  final Path _path = Path();
  int _pathPoints = 0;
  double? _pathScale;

  Path pathFor(double scale) {
    if (_pathScale != scale || points.length < _pathPoints) {
      _path.reset();
      _pathPoints = 0;
      _pathScale = scale;
    }
    for (; _pathPoints < points.length; _pathPoints++) {
      final point = points[_pathPoints] * scale;
      if (_pathPoints == 0) {
        _path.moveTo(point.dx, point.dy);
      } else {
        _path.lineTo(point.dx, point.dy);
      }
    }
    return _path;
  }

  Stroke(this.color, this.width);

  static Stroke fromJson(Map<String, dynamic> json) {
    Stroke s = Stroke(
      Color(json["color"]),
      json["width"],
    );
    s.points = json["points"].map<Offset>((p) => Offset(p["x"], p["y"])).toList();
    return s;
  }

  Map<String, dynamic> toJson() {
    return {
      "color": color.toARGB32(),
      "width": width,
      "points": points
          .map(
            (point) => {
              "x": point.dx,
              "y": point.dy,
            },
          )
          .toList(),
    };
  }
}

class DrawingPainter extends CustomPainter {
  List<Stroke> strokes = [];
  double _scaleFactor = 1;
  double get scaleFactor => _scaleFactor;
  set scaleFactor(double value) {
    if (_scaleFactor == value) return;
    _scaleFactor = value;
    changed();
  }

  final ValueNotifier<int> changes;

  DrawingPainter() : this._(ValueNotifier<int>(0));
  DrawingPainter._(this.changes) : super(repaint: changes);

  void changed() => changes.value++;

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint();
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;
    paint.style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      paint.color = stroke.color;
      paint.strokeWidth = stroke.width * scaleFactor;
      if (stroke.points.isEmpty) continue;
      if (stroke.points.length == 1) {
        canvas.drawCircle(
          stroke.points.first * scaleFactor,
          stroke.width * scaleFactor / 2,
          Paint()..color = stroke.color,
        );
      } else {
        canvas.drawPath(stroke.pathFor(scaleFactor), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate != this;
  }
}
