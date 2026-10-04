# Batch photo persistence

## Batch persistence

`saveStickerBatch` writes owned media/editor files, rechecks pack capacity, then publishes the whole batch through one awaited manifest save and one version increment. A failed write/save removes all entries/files created by that batch and restores the previous version. The pack must still exist and must be static. The review prevents leaving or changing the selection while saving.

This is rollback on a reported failure, not a journal guaranteeing recovery from process termination between every filesystem operation.

## Verification

`flutter test test/batch_import_test.dart`: 3 passing tests cover editable backgrounds, one save/version bump, filesystem failure and retry without duplicates, and capacity/type limits.

`flutter run -t tool/remaining_fork_smoke.dart` on Xiaomi 2412DPC0AG saves two generated photos as editable 512x512 stickers with version 1 through the native crop/encode plugin.

## Source and rollback

Adapted from medy17's [batch import](https://github.com/medy17/stickers/commit/82a6ced15d9a9a63fa333950fba563effc93f9dd) with editable data retention and failure rollback.

Remove `batch_import.dart` and its tests to remove the batch persistence API. Existing saved stickers use the normal pack/editor format and remain compatible.
