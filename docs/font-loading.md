# Font loading

The registry initializes once. Bundled fonts are already available to Flutter through the app's assets; their native image-editor registration now happens only when exporting text that uses them. Concurrent exports share each registration, successful registrations are reused, and failed registrations can retry. Opening the text picker awaits registry initialization and safely handles a missing saved font.

This removes unnecessary startup work; no before/after benchmark establishes a startup speed increase.

## Verification

`flutter test test/native_font_loading_test.dart`: 2 passing tests cover lazy native registration and native failure/retry.

`flutter run -t tool/remaining_fork_smoke.dart` on Xiaomi 2412DPC0AG: the registry read 12 fonts without native registration, then registered Lobster when requested. Native text export rendered 2,243 opaque black pixels. The first registration took 41 ms in this debug run; this is a functional measurement, not a startup comparison.

## Source and rollback

Adapted from lueefr's [startup](https://github.com/lueefr/stickers/commit/5eef149c714997f5dcac54c2e9d4dd6f3e6cd9a2) change.

Revert `fonts_registry.dart`, the export/text-picker changes in `edit_page.dart`, and `edit_text_dialog.dart` to remove native lazy loading without changing drawing or pack features.
