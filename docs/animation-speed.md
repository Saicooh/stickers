# Animation timing APIs

Animated media preview and crop/export APIs accept a speed between 1.0 and 2.0, defaulting to 1.0. Native video crop applies it to the editable MP4; image animation export applies it to frame timestamps and duration. Media and pack metadata remain compatible with existing editors.

## Timing and frames

GIF export divides frame timestamps and total duration by the speed, rounded to WebP's whole milliseconds. Lossless conversion preserves pixels and transparency. Very short accelerated delays are merged to keep timestamps increasing and frame delays at least 10 ms. Preview position and frame timers advance at the same rate, retaining it through pause, seek and segment looping.

Video crop retimes presentation timestamps in the native MP4 encoder, then samples output-time slots at up to 24 fps. WebP export avoids resampling videos already within the requested FPS limit. This prevents an extra cadence reduction for fractional rates. Video duration is approximate within a frame because the source and encoder have discrete frame boundaries; audio is omitted as in existing sticker exports.

## Verification

`flutter test test/image_animation_test.dart test/video_speed_service_test.dart`: 13 passing tests, including accelerated variable GIF delays/pixels/alpha, source trim boundaries, changing preview speed during playback, pause/seek retention, invalid speeds and the Android speed argument.

Native runtime verification uses `tool/animation_speed_smoke.dart` on Xiaomi 2412DPC0AG: GIF durations are 500/367/275 ms at 1.1/1.5/2.0x with identical pixels/alpha. The 1,600 ms video selection exports WebP durations 1,608/1,465/1,085/791 ms at 1.0/1.1/1.5/2.0x, retaining 38/35/26/19 frames and transparent padding. This measures output timing, not encoding throughput.

## Rollback

Revert the speed changes in `animated_media_controller.dart`, `image_animation_encode.dart`, `crop_scale.dart`, `MainActivity.kt`, `CropAndScale.kt` and the output-frame sampling in `OverlayAndEncode.kt`. Existing stickers remain readable because their speed is encoded in the media; pack and editor metadata formats do not change.
