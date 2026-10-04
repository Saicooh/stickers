# Static overlay work during video export

`OverlayGL` now resolves shader attributes/uniforms once per EGL context and
uploads the editor's static overlay once per export. Frame rendering only binds
the textures, updates the video's transform and draws the two quads. A new context
is created for every export, so a later sticker gets its own overlay.

The idea comes from [lueefr/stickers, e840403](https://github.com/lueefr/stickers/commit/e8404031bae482189dbe3ac5c4dd677179e8d75c).
This implementation makes the fixed overlay part of setup rather than caching
bitmap identity during frame rendering. GIF export uses a separate pipeline.

## Phone validation

Xiaomi 2412DPC0AG, debug build, synthetic 384 × 256 H.264 video (2 s at 30 FPS),
512 × 512 transparent WebP overlay with an opaque red center. Both builds use
lossless WebP quality 0/method 0 to compare pixels directly.

| Export | Run 1 | Run 2 | Run 3 | Median |
| --- | ---: | ---: | ---: | ---: |
| Previous | 1,119 ms | 1,881 ms | 1,899 ms | 1,881 ms |
| Upload once | 1,043 ms | 1,963 ms | 1,962 ms | 1,962 ms |

All three new exports match the reference's 60 decoded frames and timestamps
exactly, including the red overlay and transparent letterbox. Output size stays
3,435,506 bytes. Overlay uploads drop from 60 to 1 (59 MiB of repeated RGBA upload
input avoided for this clip), but this test does **not** establish an end-to-end
speedup. The measured median is 4.3% higher; GPU draw/upload work is only part of
decode, readback and encoding. No export speed claim is made.

## Reproduce

Create `source.mp4` using FFmpeg's `testsrc2=size=384x256:rate=30:duration=2`, H.264,
and `yuv420p`. Create a lossless 512 px RGBA WebP with a transparent background and
a red rectangle from (200, 200) to (312, 312). Copy both into the debug app's
`cache/fork_video_bench` directory using `adb push` followed by `run-as` copying.

Run `flutter run -t tool/video_overlay_benchmark.dart --dart-define=BENCH_LABEL=baseline`
on the previous native code, then rebuild with `BENCH_LABEL=optimized`. The harness
only writes to that cache directory and compares every new frame to `baseline-0.webp`.
Reinstall the normal `lib/main.dart` build as an update after running the harness.

Rollback: revert this commit; no pack data, encoder settings or source files change.
