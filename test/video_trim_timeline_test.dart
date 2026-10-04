import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/video/trim_range.dart';
import 'package:stickers/src/widgets/video_trim_timeline.dart';

void main() {
  testWidgets('one filmstrip trims by its handles and scrubs when tapped inside', (tester) async {
    RangeValues? changedRange;
    Duration? soughtTime;
    TrimEdge? selectedEdge;
    final playhead = ValueNotifier(const Duration(seconds: 3));
    addTearDown(playhead.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: VideoTrimTimeline(
                duration: const Duration(seconds: 10),
                range: const RangeValues(.2, .8),
                playhead: playhead,
                thumbnails: const [],
                enabled: true,
                onRangeChangeStart: () {},
                onRangeChanged: (value) => changedRange = value,
                onRangeChangeEnd: () {},
                onSeekStart: () {},
                onSeekChanged: (value) => soughtTime = value,
                onSeekEnd: (value) => soughtTime = value,
                onEdgeSelected: (edge) => selectedEdge = edge,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('0:02.000'), findsOneWidget);
    expect(find.text('0:06.000'), findsOneWidget);
    expect(find.text('0:08.000'), findsOneWidget);
    expect(tester.takeException(), isNull);

    playhead.value = const Duration(seconds: 4);
    await tester.pump();
    expect(find.text('0:04.000'), findsOneWidget);

    final timeline = tester.getRect(
      find.descendant(of: find.byType(VideoTrimTimeline), matching: find.byType(Listener)),
    );
    await tester.dragFrom(
      Offset(timeline.left + 16 + (timeline.width - 32) * .2, timeline.center.dy),
      const Offset(35, 0),
    );
    await tester.pump();
    expect(changedRange?.start, greaterThan(.2));
    expect(selectedEdge, TrimEdge.start);

    changedRange = null;
    await tester.dragFrom(
      Offset(timeline.left + 16 + (timeline.width - 32) * .8, timeline.center.dy),
      const Offset(-35, 0),
    );
    await tester.pump();
    expect(changedRange?.end, lessThan(.8));
    expect(selectedEdge, TrimEdge.end);

    changedRange = null;
    await tester.tapAt(timeline.center);
    await tester.pump();
    expect(soughtTime, isNotNull);
    expect((soughtTime! - const Duration(seconds: 5)).abs(), lessThan(const Duration(milliseconds: 20)));
    expect(changedRange, isNull);

    soughtTime = null;
    await tester.dragFrom(timeline.center, const Offset(30, 0));
    await tester.pump();
    expect(soughtTime, isNull);
    expect(changedRange!.start, greaterThan(.2));
    expect(changedRange!.end, greaterThan(.8));
    expect(changedRange!.end - changedRange!.start, closeTo(.6, .000001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging the segment preserves its length through rebuilds and clamps to both edges', (tester) async {
    var range = const RangeValues(.2, .8);
    var starts = 0;
    var ends = 0;
    Duration? soughtTime;
    final timeline = await _pumpTimeline(
      tester,
      onRangeChanged: (value) => range = value,
      onRangeChangeStart: () => starts++,
      onRangeChangeEnd: () => ends++,
      onSeekChanged: (value) => soughtTime = value,
    );
    final trackWidth = timeline.width - 32;
    final gesture = await tester.startGesture(timeline.center);

    await gesture.moveBy(Offset(trackWidth * .1, 0));
    await tester.pump();
    expect(range.start, closeTo(.3, .000001));
    expect(range.end, closeTo(.9, .000001));

    await gesture.moveBy(Offset(trackWidth * .5, 0));
    await tester.pump();
    expect(range.start, closeTo(.4, .000001));
    expect(range.end, 1);

    // Moving back after reaching the edge still follows the original pointer-down position.
    await gesture.moveBy(Offset(-trackWidth * .55, 0));
    await tester.pump();
    expect(range.start, closeTo(.25, .000001));
    expect(range.end, closeTo(.85, .000001));

    await gesture.moveBy(Offset(-trackWidth, 0));
    await tester.pump();
    expect(range.start, 0);
    expect(range.end, closeTo(.6, .000001));
    await gesture.up();
    await tester.pump();

    expect(starts, 1);
    expect(ends, 1);
    expect(soughtTime, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the center of a short segment remains draggable between overlapping handle hit areas', (tester) async {
    var range = const RangeValues(.49, .50);
    final timeline = await _pumpTimeline(tester, range: range, onRangeChanged: (value) => range = value);
    final trackWidth = timeline.width - 32;
    final center = Offset(timeline.left + 16 + trackWidth * .495, timeline.center.dy);

    await tester.dragFrom(center, Offset(trackWidth * .1, 0));
    await tester.pump();
    expect(range.start, closeTo(.59, .000001));
    expect(range.end, closeTo(.60, .000001));
    expect(const Duration(seconds: 10) * (range.end - range.start), const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging outside the segment still scrubs without moving the selection', (tester) async {
    RangeValues? changedRange;
    Duration? soughtTime;
    final timeline = await _pumpTimeline(
      tester,
      onRangeChanged: (value) => changedRange = value,
      onSeekChanged: (value) => soughtTime = value,
    );
    final trackWidth = timeline.width - 32;
    await tester.dragFrom(
      Offset(timeline.left + 16 + trackWidth * .02, timeline.center.dy),
      Offset(trackWidth * .45, 0),
    );
    await tester.pump();
    expect(soughtTime, isNotNull);
    expect(soughtTime!, greaterThan(const Duration(seconds: 2)));
    expect(changedRange, isNull);
  });

  testWidgets('a vertical drag inside the segment does not edit or seek', (tester) async {
    var changes = 0;
    final timeline = await _pumpTimeline(
      tester,
      onRangeChanged: (_) => changes++,
      onSeekChanged: (_) => changes++,
    );
    await tester.dragFrom(timeline.center, const Offset(0, 40));
    await tester.pump();
    expect(changes, 0);
  });

  testWidgets('a disabled timeline cannot move its selected segment', (tester) async {
    var changes = 0;
    final timeline = await _pumpTimeline(
      tester,
      enabled: false,
      onRangeChanged: (_) => changes++,
      onSeekChanged: (_) => changes++,
    );
    await tester.dragFrom(timeline.center, const Offset(40, 0));
    await tester.pump();
    expect(changes, 0);
  });

  testWidgets('cancelling a segment drag releases the pointer for another drag', (tester) async {
    var range = const RangeValues(.2, .8);
    var ends = 0;
    final timeline = await _pumpTimeline(
      tester,
      onRangeChanged: (value) => range = value,
      onRangeChangeEnd: () => ends++,
    );
    final gesture = await tester.startGesture(timeline.center);
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.cancel();
    await tester.pump();
    expect(ends, 1);

    final center = Offset(
      timeline.left + 16 + (timeline.width - 32) * (range.start + range.end) / 2,
      timeline.center.dy,
    );
    await tester.dragFrom(center, const Offset(-30, 0));
    await tester.pump();
    expect(range.start, closeTo(.2, .000001));
    expect(range.end, closeTo(.8, .000001));
    expect(ends, 2);
    expect(tester.takeException(), isNull);
  });
}

Future<Rect> _pumpTimeline(
  WidgetTester tester, {
  RangeValues range = const RangeValues(.2, .8),
  bool enabled = true,
  ValueChanged<RangeValues>? onRangeChanged,
  VoidCallback? onRangeChangeStart,
  VoidCallback? onRangeChangeEnd,
  ValueChanged<Duration>? onSeekChanged,
}) async {
  final playhead = ValueNotifier(const Duration(seconds: 3));
  addTearDown(playhead.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: StatefulBuilder(
              builder: (context, setState) => VideoTrimTimeline(
                duration: const Duration(seconds: 10),
                range: range,
                playhead: playhead,
                thumbnails: const [],
                enabled: enabled,
                onRangeChangeStart: onRangeChangeStart ?? () {},
                onRangeChanged: (value) {
                  setState(() => range = value);
                  onRangeChanged?.call(value);
                },
                onRangeChangeEnd: onRangeChangeEnd ?? () {},
                onSeekStart: () {},
                onSeekChanged: onSeekChanged ?? (_) {},
                onSeekEnd: (_) {},
                onEdgeSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return tester.getRect(find.descendant(of: find.byType(VideoTrimTimeline), matching: find.byType(Listener)));
}
