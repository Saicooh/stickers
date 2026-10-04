# Pack manifest writes

Pack saves take a JSON snapshot immediately and run in invocation order. Each
snapshot is written and flushed to `packs.json.tmp`, then replaces `packs.json`
in the same directory. A validated previous manifest is retained as
`packs.json.bak`; the first save also creates a backup. A failed save reports its
error and leaves later retries possible.

Startup recovers a missing, truncated or incorrectly structured primary manifest
from the backup. Invalid primary and backup files report failure rather than
silently showing an empty collection. The manifest remains the original JSON
list format with sticker source paths, editable metadata paths and pack settings.
There is no data migration.

Pack edits now bump the WhatsApp image version before saving, await that save,
and sticker creation performs one manifest write. Quick mode waits for the new
sticker to be saved before sending the pack to WhatsApp. Import waits for its
manifest write and deletes only its own extracted temporary folder; it no longer
deletes the source archive's parent directory.

This adapts the serialized/atomic save idea from
[BEFICENT/stickers, ce3ef6f](https://github.com/BEFICENT/stickers/commit/ce3ef6f2adf9c270af4f5fffdb654acdbf4f072d)
without adopting that fork's new manifest schema or service architecture.

Tests cover mutable overlapping saves, legacy paths/settings, image versions,
corrupt/missing manifests, filesystem write failure, retry and first-save recovery.
`tool/fork_optimizations_smoke.dart` also checks replacement/recovery on Android
using a temporary manifest and synthetic assets, never real packs.

The backup protects one previous manifest, not deleted image files or editor
assets. Media deletion/replacement is still separate from the metadata write.
It cannot restore deliberately deleted stickers or guarantee recovery from every
power-loss/filesystem failure.

Rollback: revert the storage commit. Existing `packs.json` remains readable by the
previous app; `.bak` and `.tmp` files are ignored by its loader.
