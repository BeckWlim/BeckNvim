Source "common.tape"
Hide
Type `bash "$BECKNVIM_DEMO_ROOT/examples/nvim.sh" docs/architecture.md`
Enter
Sleep 6s
Type "gg/Link?"
Enter
Type "zz"
Show
Sleep 2s
Ctrl+D
Sleep 2s
Ctrl+D
Sleep 2s
# Opening a file tree narrows the document and triggers a fresh layout.
Type ":NvimTreeToggle"
Enter
Sleep 1s
Type ":vertical resize 36"
Enter
Type " wl"
Sleep 2s
Type "gg/Link?"
Enter
Type "zz"
Sleep 3s
Ctrl+D
Sleep 2s
Type ":NvimTreeToggle"
Enter
Sleep 2s
Type "gg/Link?"
Enter
Type "zz"
Sleep 2s
Type " mp"
Sleep 2s
Type "/TCP fallback"
Enter
Type "c2w"
Type "TCP recovery"
Escape
Sleep 1s
Type " mp"
Sleep 2s
Type "gg/recovery"
Enter
Type "zz"
Sleep 2s
Hide
Type ":qa!"
Enter
