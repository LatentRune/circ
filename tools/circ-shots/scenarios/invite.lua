-- Bob invites Alice to his ledger. Debug is on, so a failure shows in chat.
SHOT = { title = "Invite received" }
dofile(SIM_DIR .. "fixtures.lua")
Setup({ debug = true })
Send("Bob-Realm", "INVITE", { c = "circAB12trade" }, true)
Advance(1)
