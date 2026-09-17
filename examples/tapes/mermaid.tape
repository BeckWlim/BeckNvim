Source "common.tape"
Set Width 1200
Set Height 900
Set FontSize 24
Hide
Type `bash "$BECKNVIM_DEMO_ROOT/examples/nvim.sh" docs/mermaid.md`
Enter
Sleep 6s
Type "gg"
Show
Sleep 2s
# The rendered diagram is real text: move, select, and copy a label.
Type "/Request"
Enter
Sleep 1s
Type "3l"
Sleep 1s
Type "3h"
Sleep 1s
Type "viw"
Sleep 1500ms
Type "y"
Type ":echo 'Copied: ' . @0"
Enter
Sleep 2s
# Show the short Mermaid source and edit a node label.
Type " mp"
Sleep 2s
Type "gg/Store]"
Enter
Sleep 1s
Type "ciwFetch"
Escape
Sleep 1s
Type " mp"
Sleep 3s
# Quick edits in prose return to the diagram preview on Escape.
Type "/sentence"
Enter
Type "ciw"
Sleep 1s
Type "note"
Escape
Sleep 2s
Type ":w"
Enter
Sleep 2s
Type "gg"
Sleep 2s
Hide
Type ":qa!"
Enter
