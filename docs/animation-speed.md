# Animation speed

In the video/GIF crop screen, tap the speed value beside Play to select 1.0× through 2.0× in 0.1× steps. 1.0× restores normal speed. The preview uses the chosen rate, while the timeline's start/end positions stay in source time. Clip length shows the accelerated output duration.

Done applies the rate to the cropped media before opening the sticker editor. Saving, adding text/drawing, exporting and reopening that sticker all use this accelerated background. Speed is a crop choice, not a global setting; a new import starts at 1.0×.

## Timing and frames

GIF export divides frame timestamps and total duration by the speed, rounded to WebP's whole milliseconds. Lossless conversion preserves pixels and transparency. Very short accelerated delays are merged to keep timestamps increasing and frame delays at least 10 ms. Preview position and frame timers advance at the same rate, retaining it through pause, seek and segment looping.

Video crop retimes presentation timestamps in the native MP4 encoder, then samples output-time slots at up to 24 fps. WebP export avoids resampling videos already within the requested FPS limit. This prevents an extra cadence reduction for fractional rates. Video duration is approximate within a frame because the source and encoder have discrete frame boundaries; audio is omitted as in existing sticker exports.

## Verification

`flutter test test/image_animation_test.dart test/video_speed_service_test.dart`: 13 passing tests, including accelerated variable GIF delays/pixels/alpha, source trim boundaries, changing preview speed during playback, pause/seek retention, invalid speeds and the Android speed argument.

`flutter test test/gif_crop_page_test.dart`: 1 passing integration test opens the speed menu, selects 2.0×, checks the halved clip length, and confirms Done exports the corresponding timestamps. It runs at 360×800 logical pixels with 1.5× text scaling.

`flutter run -t tool/animation_speed_smoke.dart` on Xiaomi 2412DPC0AG validates native GIF encoding, native MP4 crop, video preview speed, and final WebP export. A synthetic 550 ms GIF exports as 500/367/275 ms at 1.1×/1.5×/2.0×, with identical decoded pixels/alpha. A 60 ms GIF with short frame delays exports as 30 ms at 2.0×. A 1,600 ms video selection exports WebP durations of 1,608/1,465/1,085/791 ms at 1.0×/1.1×/1.5×/2.0×, retaining 38/35/26/19 frames and transparent padding. These are duration checks, not conversion speed benchmarks.

The synthetic video fixture is generated with `ffmpeg -f lavfi -i testsrc2=size=384x256:rate=30:duration=2 -c:v libx264 -pix_fmt yuv420p source.mp4` and copied to the app's `cache/sticker_speed_source.mp4`. The harness writes to an owned temporary directory and never saves packs or settings.

## Rollback

The export/preview API can be reverted through the speed changes in `animated_media_controller.dart`, `image_animation_encode.dart`, `crop_scale.dart`, `MainActivity.kt`, `CropAndScale.kt` and the output-frame sampling in `OverlayAndEncode.kt`. Remove the speed control/clip-length integration in `video_crop_page.dart` and `video_trim_timeline.dart` to revert the UI. Existing stickers remain readable because their speed is encoded in the media; pack and editor metadata formats do not change.
