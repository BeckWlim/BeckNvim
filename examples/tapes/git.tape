Source "common.tape"
Hide
Type `bash "$BECKNVIM_DEMO_ROOT/examples/nvim.sh" mooncake-transfer-engine/include/transfer_engine.h +70`
Enter
Sleep 5s
Show
Sleep 1s
# Review a real remote-tracking branch without checking it out.
Type " de"
Sleep 1s
Type@40ms "upstream/codex/placement-mechanism"
Wait+Screen /REMOTE.*BRANCH/
Sleep 1500ms
Enter
Sleep 4s
# This commit introduces explicit placement group kinds (three changed files).
Type "/48b3ca"
Enter
Sleep 1s
Enter
Type "j"
Enter
Sleep 3s
# Move HEAD only in the disposable clone, then open its exact commit diff.
Type " dm"
Wait+Screen /CURRENT.*DETACHED/
Sleep 1s
Enter
Type "j"
Enter
Sleep 3s
# #3704 is the public PR for the placement branch.
Type " de"
Sleep 1s
Type "#3704"
Wait+Screen /PULL R/
Sleep 1s
Escape
Type "gg"
Sleep 1500ms
Enter
Wait+Screen /GitHub #3704/
Sleep 3s
Ctrl+D
Sleep 2s
Ctrl+Q
Sleep 700ms
Ctrl+Q
Sleep 700ms
Ctrl+Q
Sleep 1s
Hide
Type ":qa!"
Enter
