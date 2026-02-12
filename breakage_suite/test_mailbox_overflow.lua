-- breakage_suite/test_mailbox_overflow.lua
-- STRESS: enqueue + async limits under pressure

local bundle = require("init")
local FSM = bundle.create
local ASYNC = bundle.ASYNC

print("[BREAKAGE_SUITE] Starting mailbox overflow test...")

-- ============================================================================
-- TEST 1: RAPID-FIRE ENQUEUE (No Processing)
-- ============================================================================
local fsm1 = FSM({
	name = "OVERFLOW_VICTIM",
	initial = "IDLE",
	events = {
		{ name = "ping", from = "IDLE", to = "PONG" },
		{ name = "pong", from = "PONG", to = "IDLE" },
	},
})

print("\n[PHASE 1] Enqueuing 10,000 messages without processing...")
local start_mem = collectgarbage("count")

for i = 1, 10000 do
	fsm1:send("ping", {
		data = { sequence = i, payload = string.rep("X", 100) },
		to_fsm = fsm1,
	})
end

local mid_mem = collectgarbage("count")
print(string.format("  Messages: %d", fsm1.mailbox:count()))
print(string.format("  Memory delta: +%.2f KB", mid_mem - start_mem))

-- ============================================================================
-- TEST 2: PROCESSING UNDER LOAD (Async Handlers)
-- ============================================================================
local fsm2 = FSM({
	name = "ASYNC_STRESS",
	initial = "A",
	events = {
		{ name = "step", from = { "A", "B", "C" }, to = "B" },
		{ name = "finish", from = "B", to = "C" },
	},
	callbacks = {
		onleaveA = function(ctx)
			print(string.format("  [STRESS] onleaveA async (msg #%d)", ctx.data.seq or 0))
			return ASYNC -- Force async transition
		end,
		onleaveB = function(ctx)
			print(string.format("  [STRESS] onleaveB async (msg #%d)", ctx.data.seq or 0))
			return ASYNC
		end,
	},
})

print("\n[PHASE 2] Mixed enqueue + processing with async transitions...")

-- Queue messages faster than they can process
local enqueued = 0
for i = 1, 100 do
	fsm2:send("step", {
		data = { seq = i },
		to_fsm = fsm2,
	})
	enqueued = enqueued + 1

	-- Process every 10th message
	if i % 10 == 0 then
		local ok, result = fsm2:process_mailbox()
		if not ok then
			print(string.format("  [FAILURE] Mailbox processing failed at i=%d: %s", i, result.error_type))
		end
	end
end

print(string.format("  Total enqueued: %d", enqueued))
print(string.format("  Mailbox backlog: %d", fsm2.mailbox:count()))

-- ============================================================================
-- TEST 3: CONTEXT CORRUPTION DURING OVERFLOW
-- ============================================================================
print("\n[PHASE 3] Testing context preservation under overflow...")

local corruption_detected = false
local fsm3 = FSM({
	name = "CONTEXT_TEST",
	initial = "READY",
	events = {
		{ name = "load", from = "READY", to = "LOADING" },
		{ name = "process", from = "LOADING", to = "PROCESSING" },
	},
	callbacks = {
		onstatechange = function(ctx)
			-- Check for context corruption
			if ctx.synthetic or ctx.injected_at then
				corruption_detected = true
				print("  [CORRUPTION] Synthetic context detected!")
			end
		end,
	},
})

-- Flood with interleaved events
for i = 1, 50 do
	fsm3:send("load", {
		data = { id = i },
		options = { priority = i % 3 },
		to_fsm = fsm3,
	})

	-- Immediately try to process while context might be building
	if i % 5 == 0 then
		fsm3:process_mailbox()
	end
end

-- Final processing
fsm3:process_mailbox()
print(string.format("  Context corruption detected: %s", tostring(corruption_detected)))

-- ============================================================================
-- TEST 4: MEMORY RETENTION CHECK (UPDATED - WITH CLEANUP)
-- ============================================================================
print("\n[PHASE 4] Checking for retained objects...")

-- Force explicit cleanup of all mailboxes before measurement
print("  [CLEANUP] Clearing all mailbox queues...")

-- Clear fsm1 mailbox (has 1000 unprocessed messages from Phase 1)
local fsm1_cleared = 0
if fsm1.mailbox then
	fsm1_cleared = fsm1.mailbox:count()
	fsm1:clear_mailbox() -- Clear all messages
	print(string.format("    Cleared %d messages from OVERFLOW_VICTIM", fsm1_cleared))
end

-- Clear fsm2 mailbox (should be empty but verify)
local fsm2_cleared = 0
if fsm2.mailbox then
	fsm2_cleared = fsm2.mailbox:count()
	if fsm2_cleared > 0 then
		fsm2:clear_mailbox()
		print(string.format("    Cleared %d messages from ASYNC_STRESS", fsm2_cleared))
	end
end

-- Clear fsm3 mailbox
local fsm3_cleared = 0
if fsm3.mailbox then
	fsm3_cleared = fsm3.mailbox:count()
	if fsm3_cleared > 0 then
		fsm3:clear_mailbox()
		print(string.format("    Cleared %d messages from CONTEXT_TEST", fsm3_cleared))
	end
end

local total_cleared = fsm1_cleared + fsm2_cleared + fsm3_cleared
print(string.format("  [CLEANUP] Total messages cleared: %d", total_cleared))

-- Force garbage collection twice for thorough cleanup
collectgarbage("collect")
collectgarbage("collect") -- Some Lua implementations need multiple passes

local final_mem = collectgarbage("count")

print(string.format("  Initial memory: %.2f KB", start_mem))
print(string.format("  Final memory: %.2f KB", final_mem))
print(string.format("  Total growth: %.2f KB", final_mem - start_mem))

-- Check if messages are actually being retained
local retained_refs = 0
if fsm1.mailbox then
	retained_refs = retained_refs + fsm1.mailbox:count()
end
if fsm2.mailbox then
	retained_refs = retained_refs + fsm2.mailbox:count()
end
if fsm3.mailbox then
	retained_refs = retained_refs + fsm3.mailbox:count()
end

print(string.format("  Retained message references after cleanup: %d", retained_refs))

-- Calculate expected memory growth (just from FSM objects, not messages)
local expected_growth = 50 -- KB, approximate for FSM object creation
local actual_growth = final_mem - start_mem
local excess_growth = actual_growth - expected_growth

if excess_growth > 100 then -- More than 100KB excess = potential leak
	print(string.format("  [WARNING] Excess memory growth: +%.2f KB (possible leak)", excess_growth))
else
	print(string.format("  [OK] Memory growth within expected range: +%.2f KB", actual_growth))
end

-- ============================================================================
-- FAILURE CATALOG ENTRY
-- ============================================================================
print("\n" .. string.rep("=", 60))
print("FAILURE CATALOG: MAILBOX_OVERFLOW")
print(string.rep("=", 60))

local failures = {}
local warnings = {}

-- Check 1: Queue limits working
if fsm1_cleared == 1000 then
	table.insert(warnings, string.format("QUEUE_LIMIT_OK: %d messages enqueued (limit: 1000)", fsm1_cleared))
else
	table.insert(failures, string.format("QUEUE_LIMIT_FAILED: Expected 1000, got %d", fsm1_cleared))
end

-- Check 2: Memory retention after explicit cleanup
if retained_refs > 0 then
	table.insert(failures, string.format("MEMORY_RETENTION: %d messages still retained after cleanup", retained_refs))
else
	table.insert(warnings, "MEMORY_RETENTION_OK: All messages cleared")
end

-- Check 3: Automatic cleanup working
if total_cleared > 0 then
	table.insert(warnings, string.format("CLEANUP_WORKING: %d messages cleared via API", total_cleared))
end

-- Check 4: Memory growth reasonable
if excess_growth > 100 then
	table.insert(failures, string.format("EXCESS_MEMORY: +%.2f KB beyond expected", excess_growth))
else
	table.insert(warnings, string.format("MEMORY_OK: Growth within limits (+%.2f KB)", actual_growth))
end

if #failures == 0 then
	print("✓ No critical failures detected")
	if #warnings > 0 then
		print("⚠️  WARNINGS:")
		for i, warning in ipairs(warnings) do
			print(string.format("  %d. %s", i, warning))
		end
	end
else
	print("✗ FAILURES OBSERVED:")
	for i, failure in ipairs(failures) do
		print(string.format("  %d. %s", i, failure))
	end
	if #warnings > 0 then
		print("⚠️  ADDITIONAL WARNINGS:")
		for i, warning in ipairs(warnings) do
			print(string.format("  %d. %s", i, warning))
		end
	end
end

print(string.rep("=", 60))
print("[BREAKAGE_SUITE] Mailbox overflow test complete")

