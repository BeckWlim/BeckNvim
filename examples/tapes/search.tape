Source "common.tape"
Hide
Type `bash "$BECKNVIM_DEMO_ROOT/examples/nvim.sh" mooncake-transfer-engine/include/transfer_engine.h +70`
Enter
Sleep 5s
Show
Sleep 1s
# Search definitions throughout the real Mooncake checkout.
Type " fw"
Sleep 1s
Type@0ms "submitTransfer"
Wait+Screen /Function/
Sleep 2s
Down
Sleep 1s
Down
Sleep 1s
Tab
Type "jjjj"
Sleep 2s
Tab
Enter
Sleep 2s
# A second query shows types as well as function definitions.
Type " fw"
Sleep 1s
Type@0ms "MasterService"
Sleep 2s
Down
Sleep 1500ms
Ctrl+Q
Sleep 700ms
Type " fw"
Sleep 700ms
Type@0ms "PeerLiveness"
Wait+Screen /Enum/
Sleep 2s
Enter
Sleep 1500ms
Hide
Type ":qa!"
Enter
