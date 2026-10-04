# Pack backups

Use **Back up all packs** on the pack list to create one ZIP and choose where to save it in Android's share sheet. The existing pack export still creates a single-pack ZIP. Both include sticker media, tray icons, editor JSON, original backgrounds (including GIF/video extensions), and referenced image layers.

Import the ZIP through the existing import action. Packs are added alongside existing packs, with fresh identifiers when needed. Imported editor paths point to the installed assets; they do not depend on the original phone or the temporary extraction directory. Image layers, including older entries without a type, can reopen and export with their aspect ratio and transparency.

The backup includes packs only. It does not include app settings or custom/Google font files. Install the same custom fonts on another device before editing text that uses them; bundled fonts ship with the app.

## Format and failure handling

`portable_pack.dart` copies complete asset sets and rewrites references. Multi-pack archives use `packs.json` containing `{ "version": 1, "packs": [...] }`, with each pack in its own `pack_0/`, `pack_1/`, etc. Single-pack archives retain `pack.json`. The installed app manifest remains its existing list format.

The reader accepts old single-pack ZIPs, repairs older hardcoded background extensions and archived image-layer references, and rejects references outside the extraction directory. Import copies all packs before one manifest save. A failed copy or save removes only newly created packs/directories. Temporary staging is cleaned after export/import; the selected archive and its parent folder are retained.

## Verification

`flutter test test/portable_pack_test.dart`: 4 passing tests cover restoration after the original files are deleted, editable video/image/text/drawing assets, legacy repairs, invalid paths/identifiers, and image-layer reopening.

`flutter run -t tool/remaining_fork_smoke.dart` on Xiaomi 2412DPC0AG: a static and animated pack round-trip through the actual Android ZIP plugin, producing four packs alongside the originals. Sticker bytes, GIF pixels, transparency and timing remain identical. A deliberately failed manifest save rolls back the import without changing the previous manifest.

`flutter run --dart-define=SKIP_CROP_UI=true -t tool/remaining_fork_smoke.dart` also verifies a restored image layer through the native export plugin: the center remains opaque and the surrounding canvas transparent. This mode tests the batch backend directly and can run with the display locked; the crop UI was checked separately in the normal mode.

## Source and rollback

Adapted from lueefr's [multi-pack backup](https://github.com/lueefr/stickers/commit/ee280796360c3f7e82825b5a9a87a418a0f3f435), extended here to preserve editable assets.

Archive integration can be reverted through the export/import functions in `load_store.dart` and the backup action in `sticker_packs_page.dart`. Portable asset helpers and image-layer restoration/export can be reverted independently through `portable_pack.dart`, `image_layer.dart` and their `edit_page.dart` integration. Batch photo saving does not require the portable archive format.
