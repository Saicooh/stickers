# Drawing updates

Moving the brush now signals the drawing painter directly, instead of calling `setState` on the entire editor. Drawing, text and image layers have separate repaint boundaries. Each stroke appends new points to a cached path; changing the display scale rebuilds that path. Rounded caps/joins and single-point dots are retained, as are serialized points and native export options.

Undo and redo notify the painter immediately. Starting a stroke still updates the editor controls.

## Verification

`flutter test test/drawing_repaint_test.dart`: 2 passing tests verify rasterized ink appears, disappears on undo and reappears on redo while the surrounding builder runs once, and that appended/rescaled paths retain their points through JSON restoration.

Runtime boundary: Flutter raster painting is exercised in the widget test. This change does not alter the native export format; no measured frame-rate improvement is claimed.

## Sources and rollback

Adapted from lueefr's [painting](https://github.com/lueefr/stickers/commit/61955db3e5f52b614946ee267eae48277158ab79) and [repaint](https://github.com/lueefr/stickers/commit/e8404031bae482189dbe3ac5c4dd677179e8d75c) changes.

Reverting `draw_layer.dart` and the painting/boundary notifications in `edit_page.dart` removes this behavior without changing pack storage, imports or font loading.
