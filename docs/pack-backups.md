# Portable pack assets

The portable pack API copies sticker media, tray icons, editor JSON, original backgrounds (including GIF/video extensions), and referenced image layers. It rewrites paths for the archive or installed destination. Image layers, including older entries without a type, can reopen and export with their aspect ratio and transparency.

## Format and failure handling

`portable_pack.dart` copies complete asset sets and rewrites references. Multi-pack archives use `packs.json` containing `{ "version": 1, "packs": [...] }`, with each pack in its own `pack_0/`, `pack_1/`, etc. Single-pack archives retain `pack.json`. The installed app manifest remains its existing list format.

The reader accepts old single-pack ZIPs, repairs older hardcoded background extensions and archived image-layer references, and rejects references outside the extraction directory. The helpers do not publish installed packs; the caller decides when to save its manifest.

## Verification

`flutter test test/portable_pack_test.dart`: 4 passing tests cover restoration after original files are deleted, editable assets, legacy repairs, invalid paths/identifiers and image-layer reopening.

The real Android image export and archive integration are exercised by `flutter run -t tool/remaining_fork_smoke.dart` on Xiaomi 2412DPC0AG.

## Source and rollback

Adapted from lueefr's [multi-pack backup](https://github.com/lueefr/stickers/commit/ee280796360c3f7e82825b5a9a87a418a0f3f435), extended to preserve editable assets.

Revert `portable_pack.dart`, `image_layer.dart` and their image-layer `edit_page.dart` integration to remove these helpers. Batch saving and font/drawing optimizations do not require the portable archive format.
