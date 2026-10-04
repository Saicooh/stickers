import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stickers/src/video/trim_range.dart';

void main() {
  const duration = Duration(seconds: 10);
  const range = RangeValues(.2, .8);

  test('moving a selection shifts both boundaries and preserves its duration', () {
    for (final delta in [-.1, .1]) {
      final moved = shiftTrimRange(range, delta);
      expect(moved.start, closeTo(range.start + delta, .000001));
      expect(moved.end, closeTo(range.end + delta, .000001));
      expect(moved.end - moved.start, closeTo(range.end - range.start, .000001));
    }
  });

  test('moving past either video edge clamps the whole selection without shrinking it', () {
    final left = shiftTrimRange(range, -2);
    expect(left.start, 0);
    expect(left.end, closeTo(.6, .000001));

    final right = shiftTrimRange(range, 2);
    expect(right.start, closeTo(.4, .000001));
    expect(right.end, 1);
  });

  test('a selection spanning the full video cannot move', () {
    const fullRange = RangeValues(0, 1);
    expect(shiftTrimRange(fullRange, -1), fullRange);
    expect(shiftTrimRange(fullRange, 1), fullRange);
  });

  test('moving the start by a source frame changes only the start of the clip', () {
    final shorter = moveTrimBoundary(
      duration: duration,
      range: range,
      edge: TrimEdge.start,
      frame: const Duration(microseconds: 2033333),
    )!;
    expect(shorter.start, closeTo(.2033333, .0000001));
    expect(shorter.end, range.end);

    final longer = moveTrimBoundary(
      duration: duration,
      range: range,
      edge: TrimEdge.start,
      frame: const Duration(microseconds: 1966667),
    )!;
    expect(longer.start, lessThan(range.start));
    expect(longer.end, range.end);
  });

  test('moving the end by a source frame changes only the end of the clip', () {
    final shorter = moveTrimBoundary(
      duration: duration,
      range: range,
      edge: TrimEdge.end,
      frame: const Duration(microseconds: 7966667),
    )!;
    expect(shorter.end, lessThan(range.end));
    expect(shorter.start, range.start);

    final longer = moveTrimBoundary(
      duration: duration,
      range: range,
      edge: TrimEdge.end,
      frame: const Duration(microseconds: 8033333),
    )!;
    expect(longer.end, greaterThan(range.end));
    expect(longer.start, range.start);

    final fullVideo = moveTrimBoundary(duration: duration, range: range, edge: TrimEdge.end, frame: duration)!;
    expect(fullVideo.end, 1);
  });

  test('rejects frame changes that would make the clip shorter than 100 ms', () {
    expect(
      moveTrimBoundary(duration: duration, range: range, edge: TrimEdge.start, frame: const Duration(seconds: 8)),
      isNull,
    );
    expect(
      moveTrimBoundary(duration: duration, range: range, edge: TrimEdge.end, frame: const Duration(seconds: 2)),
      isNull,
    );
  });

  test('playback restarts at the selected start after trimming or reaching the end', () {
    expect(
      playbackRestartPosition(
        duration: duration,
        range: range,
        position: const Duration(seconds: 8),
        selectionChanged: false,
        completed: true,
      ),
      const Duration(seconds: 2),
    );
    expect(
      playbackRestartPosition(
        duration: duration,
        range: range,
        position: const Duration(seconds: 5),
        selectionChanged: true,
        completed: false,
      ),
      const Duration(seconds: 2),
    );
    expect(
      playbackRestartPosition(
        duration: duration,
        range: range,
        position: const Duration(seconds: 5),
        selectionChanged: false,
        completed: false,
      ),
      isNull,
    );
    expect(
      playbackRestartPosition(
        duration: duration,
        range: range,
        position: const Duration(milliseconds: 7980),
        selectionChanged: false,
        completed: false,
      ),
      const Duration(seconds: 2),
    );
  });
}
