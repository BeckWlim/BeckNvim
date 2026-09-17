Source "common.tape"
Set Width 1200
Set Height 900
Set FontSize 24
Hide
Type `bash "$BECKNVIM_DEMO_ROOT/examples/nvim.sh" docs/table.md`
Enter
Sleep 6s
Type "gg"
Show
Sleep 2s
# Move through continuation lines inside a wrapped cell.
Type "/whole"
Enter
Sleep 1s
Type "j"
Sleep 1s
Type "k"
Sleep 1s
# Select and copy visible text; show the actual yank register.
Type "viw"
Sleep 1500ms
Type "y"
Type ":echo 'Copied: ' . @0"
Enter
Sleep 2s
# A normal change command edits the mapped source cell.
Type "/Draft"
Enter
Sleep 1s
Type "ciw"
Sleep 1s
Type "Ready"
Escape
Type "gg"
Sleep 3s
Type "u"
Type "gg"
Sleep 2s
Ctrl+R
Type "gg"
Sleep 2s
Type ":w"
Enter
Sleep 2s
Hide
Type ":qa!"
Enter
