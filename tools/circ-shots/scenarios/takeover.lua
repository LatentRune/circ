-- Someone sets a password on the ledger channel: Circ should ask to move. Debug is on.
SHOT = { title = "Takeover detected" }
dofile(SIM_DIR .. "fixtures.lua")
Setup({ debug = true })
local chan = CircDB.union.name
FireEvent("CHAT_MSG_CHANNEL_NOTICE_USER", "PASSWORD_CHANGED", "Griefer", "", "5. " .. chan, "", "", 0, 5, chan)
Advance(1)
