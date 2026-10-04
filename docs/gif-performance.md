# GIF crop performance

The GIF crop step creates a lossless, editable WebP background. It previously
used `quality: 100, method: 4`. For **lossless** WebP, quality specifies compression
effort, not visual fidelity. That setting spent most of the crop time searching
for a smaller background. The default now uses `quality: 0, method: 0`. Final
sticker export still uses the existing lossy configuration and 500 KiB limit.

Measured on Android model 2412DPC0AG in a debug build, with a 739,524-byte GIF:
160 × 200 pixels, 57 frames, 3,790 ms, exported without trimming to 512 × 512.

| Lossless configuration | Three conversion times | Median | Background bytes |
| --- | --- | --- | --- |
| Previous: quality 100, method 4 | 33,182 / 33,960 / 34,799 ms | 33,960 ms | 10,564,292 |
| Current: quality 0, method 0 | 3,153 / 3,180 / 3,105 ms | 3,153 ms | 12,680,396 |

This is a 90.7% reduction for this source and device. Frame decoding and
render/readback together took about 350 ms. Conversion times exclude writing
the background and initializing the editor. Other GIFs and devices will differ.
All 57 decoded frames matched pixel for pixel, including alpha, and their start
times and total duration matched. No frames were dropped.

The tradeoff is a larger background: about 2 MiB more for this GIF. That file
becomes the saved editing background when adding the sticker to a pack.

## Verification

- `flutter test --no-pub test/image_animation_test.dart`: 9 tests passed, covering
  disposal, alpha, rotation, partial-frame trimming, millisecond rounding,
  progress completion and error cleanup.
- `flutter run --no-pub -d DEVICE -t tool/gif_benchmark.dart --dart-define=GIF_FILE=PATH`:
  `GIF_BENCH_OK`. Uses three runs per configuration and compares decoded pixels
  and timing. The source must be readable by the app; outputs are temporary.
- `flutter run --no-pub -d DEVICE -t tool/gif_smoke.dart`: `GIF_SMOKE_OK` for
  transparency, disposal, rotation, trim, fractional edges and background re-encoding.
- Rollback boundary: the lossless default, progress reporting and cleanup in
  `image_animation_encode.dart`, descriptor cleanup in `image_animation.dart`,
  and native finalization in `ImageAnimationEncoder.kt` / `libwebp_connector.cpp`.
  The filtered gallery selector and the existing video/crop controls are independent.
