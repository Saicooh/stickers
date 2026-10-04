# Sticker preview memory

Pack strips, pack grids and the sticker selector now decode images at the visible
physical size (logical bounds × device pixel ratio), capped at the original 512 px.
`ResizeImagePolicy.fit` preserves aspect ratio. Animated images remain animated and
transparent previews keep the checkerboard. Editing/export still uses the original
files. Each preview has a repaint boundary, and the bounded horizontal strip no
longer needs `shrinkWrap`.

This adapts the thumbnail idea in [lueefr/stickers, e840403](https://github.com/lueefr/stickers/commit/e8404031bae482189dbe3ac5c4dd677179e8d75c)
to device density rather than a fixed decode size. Pack tray icons and large editor
previews retain their existing image providers; overwriting a tray still uses its
existing cache eviction.

## Validation

- Widget tests decode real 512 px images, verify rectangular aspect ratio and
  advance an animated GIF with transparent frames.
- On Xiaomi 2412DPC0AG, an 84 logical px preview decodes at 273 × 273:
  298,116 bytes of RGBA pixels versus 1,048,576 bytes at 512 × 512 (71.6% less).
  This measures one decoded frame, not total app memory or scroll FPS.
- `flutter run -t tool/fork_optimizations_smoke.dart` uses synthetic assets and a
  temporary manifest, never user packs.

Rollback: revert the preview commit; original images and pack metadata are unchanged.
