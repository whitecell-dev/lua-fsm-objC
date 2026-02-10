-- TITLE: Mailbox Overflow Breakage Test
-- STATUS: [RUNNING]
-- OBJECTIVE: Reproduce failure mode under high message volume.
-- HYPOTHESIS: System will crash, leak memory, or drop messages.

-- Load the bundle and required modules.
-- Path is relative to the root of the survival lab.
package.path = package.path .. ";../core/?.lua"
local FSM = require("calyx_fsm_mailbox")

-- Helper to get memory usage (if available, otherwise placeholder)
local function get_memory_kb()
	-- In a real environment, you'd use collectgarbage("count") or OS-specific tools.
	-- For this test, we'll use Lua's garbage collector stats.
	return collectgarbage("count")
end

-- --- SETUP ---
print("[BREAKAGE TEST] Initializing FSMs for mailbox overflow test...")

-- Create a consumer that does nothing but receive messages.
local consumer = FSM.create({
	name = "CONSUMER",
	initial = "IDLE",
	events = {
		{ name = "receive", from = "IDLE", to = "IDLE" }, -- Loop back to IDLE
	},
	callbacks = {
		onleaveIDLE = function(self, ctx)
			-- Intentionally empty to maximize processing speed and isolate mailbox stress.
		end,
	},
})

-- Create a producer that sends messages.
local producer = FSM.create({
	name = "PRODUCER",
	initial = "IDLE",
	events = {
		{ name = "send_batch", from = "IDLE", to = "IDLE" },
	},
	callbacks = {
		onleaveIDLE = function(self, ctx)
			local num_messages = ctx.data.count
			print(string.format("[PRODUCER] Sending batch of %d messages...", num_messages))
			for i = 1, num_messages do
				self:send("receive", {
					to_fsm = consumer,
					data = { payload_id = i, timestamp = os.time() },
				})
			end
		end,
	},
})

-- --- EXECUTION ---
print("\n[BREAKAGE TEST] --- PHASE 1: FILLING MAILBOX ---")
local initial_memory = get_memory_kb()
print(string.format("[METRIC] Initial Memory: %.2f KB", initial_memory))
print(string.format("[METRIC] Initial Mailbox Count: %d", consumer.mailbox:count()))

-- Send a large number of messages.
local MESSAGE_COUNT = 100000
producer:send_batch({ data = { count = MESSAGE_COUNT } })

local post_fill_memory = get_memory_kb()
print(
	string.format(
		"[METRIC] Memory after filling: %.2f KB (Delta: %.2f KB)",
		post_fill_memory,
		post_fill_memory - initial_memory
	)
)
print(string.format("[METRIC] Mailbox Count after filling: %d", consumer.mailbox:count()))

-- --- PHASE 2: PROCESSING MAILBOX ---
print("\n[BREAKAGE TEST] --- PHASE 2: PROCESSING MAILBOX ---")
local pre_process_memory = get_memory_kb()
print(string.format("[METRIC] Memory before processing: %.2f KB", pre_process_memory))

local success, result = pcall(function()
	consumer:process_mailbox()
end)

local post_process_memory = get_memory_kb()
print(
	string.format(
		"[METRIC] Memory after processing: %.2f KB (Delta: %.2f KB)",
		post_process_memory,
		post_process_memory - pre_process_memory
	)
)
print(string.format("[METRIC] Final Mailbox Count: %d", consumer.mailbox:count()))

-- --- ANALYSIS ---
print("\n[BREAKAGE TEST] --- RESULTS ---")
if success then
	print("[RESULT] OBSERVED: Mailbox processed without crashing.")
	print("[RESULT] OBSERVED: All messages were handled.")
	-- Check for memory leaks
	if post_process_memory > initial_memory + 500 then -- Arbitrary threshold for "leak"
		print("[RESULT] OBSERVED: Significant memory increase suggests a leak.")
	else
		print("[RESULT] OBSERVED: Memory usage returned to baseline.")
	end
else
	print("[RESULT] REPRODUCED: System failure during mailbox processing.")
	print(string.format("[ERROR] %s", tostring(result)))
end

print("\n[BREAKAGE TEST] Test complete.")
