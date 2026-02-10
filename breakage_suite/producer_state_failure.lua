-- TITLE: Producer State Failure Test
-- STATUS: [RUNNING]
-- OBJECTIVE: Isolate the producer's failure to send subsequent message batches.
-- HYPOTHESIS: The producer will successfully send the first batch, but the second batch will not be delivered.

-- Load the bundle and required modules.
package.path = package.path .. ";../core/?.lua"
local FSM = require("calyx_fsm_mailbox")

-- --- SETUP ---
print("[BREAKAGE TEST] Initializing FSMs for producer state failure test...")

-- Create a passive consumer that does NOT process its mailbox.
local consumer = FSM.create({
	name = "CONSUMER",
	initial = "IDLE",
	events = {
		{ name = "receive", from = "IDLE", to = "IDLE" },
	},
	callbacks = {
		onleaveIDLE = function(self, ctx)
			-- Intentionally empty. We are only interested in the mailbox count.
		end,
	},
})

-- Create a producer.
local producer = FSM.create({
	name = "PRODUCER",
	initial = "IDLE",
	events = {
		{ name = "send_batch", from = "IDLE", to = "IDLE" },
	},
	callbacks = {
		onleaveIDLE = function(self, ctx)
			local num_messages = ctx.data.count
			print(string.format("[PRODUCER] Callback triggered to send %d messages.", num_messages))
			for i = 1, num_messages do
				self:send("receive", {
					to_fsm = consumer,
					data = { payload_id = i },
				})
			end
		end,
	},
})

-- --- EXECUTION ---
print("\n[BREAKAGE TEST] --- PHASE 1: FIRST BATCH ---")
print(string.format("[METRIC] Producer state before: %s", producer.current))
print(string.format("[METRIC] Consumer mailbox count before: %d", consumer.mailbox:count()))

-- Send the first batch.
producer:send_batch({ data = { count = 100 } })

print(string.format("[METRIC] Producer state after: %s", producer.current))
print(string.format("[METRIC] Consumer mailbox count after batch 1: %d", consumer.mailbox:count()))

print("\n[BREAKAGE TEST] --- PHASE 2: SECOND BATCH ---")
print(string.format("[METRIC] Producer state before: %s", producer.current))

-- Send the second batch.
producer:send_batch({ data = { count = 100 } })

print(string.format("[METRIC] Producer state after: %s", producer.current))
print(string.format("[METRIC] Consumer mailbox count after batch 2: %d", consumer.mailbox:count()))

-- --- ANALYSIS ---
print("\n[BREAKAGE TEST] --- RESULTS ---")
local final_count = consumer.mailbox:count()
if final_count == 100 then
	print("[RESULT] REPRODUCED: Producer failed to send the second batch of messages.")
	print("[ANALYSIS] The mailbox count did not increase after the second send_batch call.")
elseif final_count == 200 then
	print("[RESULT] OBSERVED: Producer successfully sent both batches.")
	print("[ANALYSIS] The previous test failure may have been caused by the processing step.")
else
	print(string.format("[RESULT] INCONCLUSIVE: Unexpected final mailbox count: %d", final_count))
end

print("\n[BREAKAGE TEST] Test complete.")
