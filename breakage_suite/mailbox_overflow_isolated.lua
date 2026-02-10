-- TITLE: Mailbox Overflow Isolated Leak Test
-- STATUS: [RUNNING]
-- OBJECTIVE: Isolate memory leak by processing in batches.
-- HYPOTHESIS: Memory usage will increase with each processed batch, indicating a cumulative leak.

-- Load the bundle and required modules.
require("init")
local FSM = require("calyx_fsm_mailbox")

-- Helper to get memory usage.
local function get_memory_kb()
	return collectgarbage("count")
end

-- --- SETUP ---
print("[BREAKAGE TEST] Initializing FSMs for isolated leak test...")

-- Create a consumer that does nothing but receive messages.
local consumer = FSM.create({
	name = "CONSUMER",
	initial = "IDLE",
	events = {
		{ name = "receive", from = "IDLE", to = "IDLE" },
	},
	callbacks = {
		onleaveIDLE = function(self, ctx)
			-- Intentionally empty.
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
			for i = 1, num_messages do
				self:send("receive", {
					to_fsm = consumer,
					data = { payload_id = ctx.data.start_id + i - 1 },
				})
			end
		end,
	},
})

-- --- EXECUTION ---
print("\n[BREAKAGE TEST] --- PHASE: BATCH PROCESSING ---")
local BATCH_SIZE = 10000
local NUM_BATCHES = 10
local total_messages = 0

local initial_memory = get_memory_kb()
print(string.format("[METRIC] Initial Memory: %.2f KB", initial_memory))

for i = 1, NUM_BATCHES do
	local start_id = total_messages + 1
	total_messages = total_messages + BATCH_SIZE

	print(string.format("\n--- BATCH %d/%d ---", i, NUM_BATCHES))

	-- Send a batch of messages.
	producer:send_batch({ data = { count = BATCH_SIZE, start_id = start_id } })
	local post_fill_memory = get_memory_kb()
	print(string.format("[METRIC] Memory after fill: %.2f KB", post_fill_memory))

	-- Process the mailbox.
	consumer:process_mailbox()
	local post_process_memory = get_memory_kb()
	print(string.format("[METRIC] Memory after process: %.2f KB", post_process_memory))

	-- Force garbage collection to reclaim any freeable memory.
	collectgarbage("collect")
	local post_gc_memory = get_memory_kb()
	local memory_delta = post_gc_memory - initial_memory

	print(
		string.format("[METRIC] Memory after GC: %.2f KB (Delta from baseline: %.2f KB)", post_gc_memory, memory_delta)
	)
	print(string.format("[METRIC] Mailbox Count: %d", consumer.mailbox:count()))

	if memory_delta > 1000 then -- If memory grows by > 1MB, flag it.
		print("[RESULT] OBSERVED: Significant memory growth detected.")
	end
end

-- --- ANALYSIS ---
print("\n[BREAKAGE TEST] --- FINAL RESULTS ---")
local final_memory = get_memory_kb()
local final_delta = final_memory - initial_memory
print(string.format("[METRIC] Final Memory: %.2f KB", final_memory))
print(string.format("[METRIC] Total Delta from Baseline: %.2f KB", final_delta))

if final_delta > 500 then
	print("[RESULT] REPRODUCED: Cumulative memory leak confirmed.")
	print("[ANALYSIS] Memory usage increases with each batch and is not reclaimed by garbage collection.")
else
	print("[RESULT] OBSERVED: No significant cumulative leak detected.")
	print("[ANALYSIS] Memory usage stabilizes after garbage collection.")
end

print("\n[BREAKAGE TEST] Test complete.")
