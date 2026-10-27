-- First run on a realm where the channel isn't ready yet: Circ keeps trying, and the
-- window says it is connecting.
SHOT = { title = "First run, still connecting" }
WORLD.channelsWork = false
Boot(nil)
Advance(10)
Slash("ledger")
Advance(1)
