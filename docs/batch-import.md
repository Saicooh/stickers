# Multiple photos

In a static pack, use **Add several photos** to select up to the remaining capacity of 30 stickers. Review the selection, tap a photo or its crop button to use the normal crop screen, and remove any unwanted photos. **Save** prepares the remaining photos sequentially at 512×512, preserving aspect ratio unless an individual crop uses Stretch.

Each saved sticker keeps an editable background for later text/drawing changes. Uncropped files are checked for animation before static conversion. A failed photo is marked in the review; crop or remove it and retry. Already prepared photos are reused. Animated packs retain their separate video/GIF selector.

## Batch persistence

`saveStickerBatch` writes owned media/editor files, rechecks pack capacity, then publishes the whole batch through one awaited manifest save and one version increment. A failed write/save removes all entries/files created by that batch and restores the previous version. The pack must still exist and must be static. The review prevents leaving or changing the selection while saving.

This is rollback on a reported failure, not a journal guaranteeing recovery from process termination between every filesystem operation.

## Verification

`flutter test test/batch_import_test.dart test/multi_crop_page_test.dart`: 5 passing tests cover editable backgrounds, one save/version bump, filesystem failure and retry without duplicates, capacity/type limits, bad-photo removal/retry, crop cancellation and empty selections.

`flutter run -t tool/remaining_fork_smoke.dart` on Xiaomi 2412DPC0AG: invoke the real review/crop callbacks on two generated photos, confirm the crop, and save two editable 512×512 stickers with version 1. The native crop/encode plugin runs on the phone. Synthetic packs use temporary directories; user packs are untouched.

## Source and rollback

Adapted from medy17's [batch import](https://github.com/medy17/stickers/commit/82a6ced15d9a9a63fa333950fba563effc93f9dd) with editable data retention and failure rollback.

Removing `multi_crop_page.dart`, the multiple-photo action in `sticker_pack_page.dart`, and `CropPage.returnCrop` removes the new review flow while keeping single-photo creation. Removing `batch_import.dart` and its tests removes the batch persistence API. Existing saved stickers remain compatible with the normal pack/editor format.
