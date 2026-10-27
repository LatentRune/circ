-- Requests, Materials view, before any profession was scanned.
SHOT = { title = "Requests: no materials yet" }
dofile(SIM_DIR .. "fixtures.lua")
Setup(nil, { noScan = true })
Slash("requests")
Advance(0.5)
Click(ButtonNamed("Materials"))
Advance(1)
