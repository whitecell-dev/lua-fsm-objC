-- breakage_suite/producer_method_instrumentation.lua
package.path = package.path .. ";../core/?.lua"
local machine = require("calyx_fsm_mailbox")

-- Monkey-patch to add logging
local original_send_batch = nil

local producer = machine.create({
	name = "TEST_PRODUCER",
	initial = "IDLE",

	events = {
		{ name = "send_batch", from = "IDLE", to = "IDLE" },
	},

	callbacks = {
		onleaveIDLE = function(fsm, ctx)
			print("[PRODUCER] In onleaveIDLE, sending 5 messages")
			for i = 1, 5 do
				-- Send messages (would need consumer)
				print("  Would send message " .. i)
			end
			return nil
		end,
	},
})

-- Get the send_batch method and wrap it
original_send_batch = producer.send_batch
producer.send_batch = function(self, params)
	print("\n=== send_batch METHOD CALLED ===")
	print("self.asyncState:", self.asyncState)
	print("self.current:", self.current)
	print("self.currentTransitioningEvent:", self.currentTransitioningEvent)
	print("params:", params and params.data.count or "none")

	-- Call original method
	local ok, result = original_send_batch(self, params)

	print("Method returned:", ok, result and result.error_type or "success")
	print("self.asyncState after:", self.asyncState)
	print("self.current after:", self.current)
	print("=== END send_batch CALL ===\n")

	return ok, result
end

print("=== FIRST CALL ===")
producer:send_batch({ data = { count = 1 } })

print("\n=== SECOND CALL ===")
producer:send_batch({ data = { count = 2 } })

print("\n=== THIRD CALL ===")
producer:send_batch({ data = { count = 3 } })
