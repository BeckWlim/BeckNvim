# Release checklist

A table with wrapped prose, a long identifier, and aligned short cells.

| Item | Owner | Status | Checks | Notes |
| :--- | :---: | :--- | ---: | :--- |
| Parser | Maya | Ready | 12 | Keep whole words together when a description continues onto the next display line. |
| Preview | Chen | Draft | 8 | Wrapped descriptions keep each row aligned, while short cells leave blank space below. |
| [Workspace](../README.md) | Alex | Review | 3 | `preview_buffer_refresh_after_external_source_changes` is split only when it cannot fit. |

## Try it

- Use `h j k l` or `/` to move; `viw` then `y` copies a word.
- Find Draft, type `ciwReady`, then press Esc to refresh the preview.
- Press `u` to undo; use `:w` to save the source.
