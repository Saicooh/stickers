# Font loading

The registry initializes once. Bundled fonts are already available to Flutter through the app's assets; their native image-editor registration now happens only when exporting text that uses them. Concurrent exports share each registration, successful registrations are reused, and failed registrations can retry. Opening the text picker awaits registry initialization and safely handles a missing saved font.

Google Fonts preview downloads begin after a card remains visible for 300 ms and scrolling is slow enough. Removing a card cancels its pending timer. Concurrent requests for the same family share one download, cached previews are reused, and HTTP failures can retry. Optional catalog fields accept missing or null values, and failed HTTP responses are not saved as a font catalog.

This removes unnecessary work; no before/after startup or scrolling benchmark establishes a speed increase.

## Verification

`flutter test test/native_font_loading_test.dart`: 2 passing tests cover lazy native registration and native failure/retry.

`flutter test test/font_preview_loading_test.dart`: 4 passing tests cover nullable metadata, duplicate downloads, HTTP retry and preview lifecycle.

`flutter run -t tool/remaining_fork_smoke.dart` on Xiaomi 2412DPC0AG: the registry read 12 fonts without native registration, then registered Lobster when requested. Native text export rendered 2,243 opaque black pixels. The first registration took 41 ms in this debug run; this is a functional measurement, not a startup comparison.

## Sources and rollback

Adapted from lueefr's [deferred preview](https://github.com/lueefr/stickers/commit/47b7645506a032fd3c8727292b6198a306a4acee) and [startup](https://github.com/lueefr/stickers/commit/5eef149c714997f5dcac54c2e9d4dd6f3e6cd9a2) changes, plus asecxxth's [nullable metadata fix](https://github.com/asecxxth/stickers/commit/0755e59cab2006e8a59a61810f16e2ec9a5d8629).

Native loading can be reverted through `fonts_registry.dart`, the export/text-picker changes in `edit_page.dart`, and `edit_text_dialog.dart`. Preview scheduling and HTTP changes can be reverted independently through `fonts_search_page.dart`, `google_fonts.dart` and `fonts_models.dart`. Neither requires reverting drawing or pack features.
