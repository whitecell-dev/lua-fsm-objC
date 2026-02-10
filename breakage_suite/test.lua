-- breakage_suite/test_fix.lua
require("init")
require("failure_modes/workarounds/fix_invalid_stage")

local machine = require("calyx_fsm_mailbox")

local producer = machine.create({
	name = "TEST",
	initial = "IDLE",
	events = { { name = "send_batch", from = "IDLE", to = "IDLE" } },
	callbacks = {
		onleaveIDLE = function(fsm, ctx)
			print("[PRODUCER] Sending messages for batch", ctx.data.count)
			return nil -- Synchronous
		end,
	},
})

print("=== BATCH 1 ===")
local ok1, res1 = producer:send_batch({ data = { count = 1 } })
print("Result:", ok1, res1 and res1.error_type or "success")

print("\n=== BATCH 2 ===")
local ok2, res2 = producer:send_batch({ data = { count = 2 } })
print("Result:", ok2, res2 and res2.error_type or "success")

print("\n=== BATCH 3 ===")
local ok3, res3 = producer:send_batch({ data = { count = 3 } })
print("Result:", ok3, res3 and res2.error_type or "success")
