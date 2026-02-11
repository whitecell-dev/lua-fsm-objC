#!/usr/bin/env lua
-- ============================================================================
-- example_production.lua
-- CALYX FSM Production Example
-- Demonstrates all hardened features: ring buffer, deterministic clock,
-- Result format, frozen API, backpressure handling
-- ============================================================================

local hardened = require("hardened")
hardened.enable_strict_mode()

local CALYX = require("init")

print(
	"═══════════════════════════════════════════════════"
)
print("  CALYX FSM PRODUCTION EXAMPLE")
print("  Version: " .. CALYX.VERSION)
print(
	"═══════════════════════════════════════════════════\n"
)

-- ============================================================================
-- EXAMPLE 1: BASIC FSM WITH RESULT FORMAT
-- ============================================================================

print("Example 1: Basic FSM with Result Format")
print(
	"─────────────────────────────────────────\n"
)

local basic_fsm = CALYX.create({
	initial = "idle",
	debug = true, -- Enable for this example
	events = {
		{ name = "start", from = "idle", to = "running" },
		{ name = "pause", from = "running", to = "paused" },
		{ name = "resume", from = "paused", to = "running" },
		{ name = "stop", from = { "running", "paused" }, to = "idle" },
	},
	callbacks = {
		onbeforestart = function(fsm, ctx)
			print(string.format("  [BEFORE] Starting FSM (tick=%d)", ctx.tick))
		end,
		onenterrunning = function(fsm, ctx)
			print(string.format("  [ENTER] Now running (tick=%d)", ctx.tick))
		end,
	},
})

-- Successful transition
print("Starting FSM...")
local result = basic_fsm:start()
if result.ok then
	print("✅ Success! State:", basic_fsm.current, "Tick:", result.tick)
else
	print("❌ Error:", result.code, "-", result.message)
end

-- Invalid transition
print("\nTrying invalid transition (start again)...")
result = basic_fsm:start()
if not result.ok then
	print("✅ Correctly rejected! Code:", result.code)
	print("   Message:", result.message)
	print("   Details:", result.details.current, "→", result.details.event)
end

print("\n")

-- ============================================================================
-- EXAMPLE 2: MAILBOX WITH RING BUFFER AND BACKPRESSURE
-- ============================================================================

print("Example 2: Mailbox with Ring Buffer")
print(
	"─────────────────────────────────────────\n"
)

local backpressure_count = 0

local mailbox_fsm = CALYX.create({
	kind = "mailbox",
	initial = "idle",
	mailbox_size = 5, -- Small size to demonstrate overflow
	overflow_policy = "drop_oldest",
	debug = true,

	on_backpressure = function(stats)
		backpressure_count = backpressure_count + 1
		print(string.format("  [BACKPRESSURE] Queue at %d%% capacity", math.floor(stats.utilization)))
	end,

	events = {
		{ name = "process", from = "idle", to = "processing" },
		{ name = "complete", from = "processing", to = "idle" },
	},
})

-- Send messages
print("Sending 10 messages to a mailbox with size=5...")
for i = 1, 10 do
	local result = mailbox_fsm:send("process", {
		data = { id = i, payload = "data_" .. i },
	})

	if result.ok then
		print(string.format("  ✅ Message %d sent (queued=%d)", i, result.data.count))
	else
		print(string.format("  ⚠️  Message %d: %s", i, result.code))
	end
end

print(string.format("\nBackpressure triggered %d times\n", backpressure_count))

-- Show stats
local stats = mailbox_fsm:mailbox_stats()
print("Mailbox Stats:")
print(string.format("  Queued: %d/%d", stats.queued, stats.max_size))
print(string.format("  Dropped: %d", stats.dropped))
print(string.format("  Utilization: %.1f%%", stats.utilization))
print(string.format("  Free slots: %d\n", stats.free_slots))

-- Process mailbox
print("Processing mailbox...")
local result = mailbox_fsm:process_mailbox()
if result.ok then
	print(
		string.format(
			"✅ Processed: %d, Failed: %d, Remaining: %d",
			result.data.processed,
			result.data.failed,
			result.data.remaining
		)
	)
end

print("\n")

-- ============================================================================
-- EXAMPLE 3: DETERMINISTIC CLOCK
-- ============================================================================

print("Example 3: Deterministic Clock")
print(
	"─────────────────────────────────────────\n"
)

local clock = CALYX.diagnostics.clock

print("Initial tick:", clock:now())

-- Reset clock
clock:reset(100)
print("After reset(100):", clock:now())

-- Advance manually
clock:advance()
clock:advance()
print("After 2 advances:", clock:now())

-- Create FSM and watch clock advance
local fsm = CALYX.create({
	initial = "a",
	debug = false,
	events = {
		{ name = "go", from = "a", to = "b" },
	},
})

local tick_before = clock:now()
fsm:go()
local tick_after = clock:now()

print(string.format("Clock advanced during transition: %d → %d", tick_before, tick_after))

print("\n")

-- ============================================================================
-- EXAMPLE 4: API FREEZE ENFORCEMENT
-- ============================================================================

print("Example 4: API Freeze Enforcement")
print(
	"─────────────────────────────────────────\n"
)

print("Attempting to modify frozen API...")
local ok, err = pcall(function()
	CALYX.malicious_method = function()
		print("hacked!")
	end
end)

if not ok then
	print("✅ Correctly prevented!")
	print("   Error:", string.match(tostring(err), "frozen") and "API is frozen" or tostring(err))
else
	print("❌ ERROR: API was mutated!")
end

print("\nAttempting to add field to FSM instance...")
local fsm = CALYX.create({
	initial = "idle",
	events = { { name = "go", from = "idle", to = "done" } },
})

ok, err = pcall(function()
	fsm.malicious_field = "pwned"
end)

if not ok then
	print("✅ Correctly prevented!")
	print("   Error:", string.match(tostring(err), "locked") and "Instance is locked" or tostring(err))
else
	print("❌ ERROR: Instance was mutated!")
end

print("\nMutable fields still work:")
print("  Before:", fsm.current)
fsm.current = "test"
print("  After:", fsm.current)

print("\n")

-- ============================================================================
-- EXAMPLE 5: HIGH-THROUGHPUT STRESS TEST
-- ============================================================================

print("Example 5: High-Throughput Stress Test")
print(
	"─────────────────────────────────────────\n"
)

local stress_fsm = CALYX.create({
	kind = "mailbox",
	initial = "idle",
	mailbox_size = 2000,
	overflow_policy = "reject",
	debug = false, -- Silent for performance

	events = {
		{ name = "tick", from = "idle", to = "idle" },
	},
})

local start_mem = collectgarbage("count")
local start_time = os.clock()

-- Send 1000 messages
print("Sending 1000 messages...")
local sent = 0
for i = 1, 1000 do
	local result = stress_fsm:send("tick", {
		data = { seq = i },
	})
	if result.ok then
		sent = sent + 1
	end
end

local send_time = os.clock() - start_time

-- Process all
print("Processing mailbox...")
local process_start = os.clock()
local result = stress_fsm:process_mailbox()
local process_time = os.clock() - process_start

local end_mem = collectgarbage("count")

-- Results
print(string.format("✅ Sent: %d messages in %.3f seconds (%.0f msg/sec)", sent, send_time, sent / send_time))

if result.ok then
	print(
		string.format(
			"✅ Processed: %d messages in %.3f seconds (%.0f msg/sec)",
			result.data.processed,
			process_time,
			result.data.processed / process_time
		)
	)
end

print(string.format("   Memory growth: %.2f KB", end_mem - start_mem))
print(string.format("   Per-message memory: %.3f KB", (end_mem - start_mem) / 1000))

print("\n")

-- ============================================================================
-- EXAMPLE 6: UNIFIED CREATE() ROUTING
-- ============================================================================

print("Example 6: Unified create() API")
print(
	"─────────────────────────────────────────\n"
)

-- Default (sync)
local sync1 = CALYX.create({
	initial = "idle",
	events = { { name = "go", from = "idle", to = "done" } },
})
print("sync1 (default):", sync1.mailbox and "has mailbox" or "no mailbox")

-- Explicit objc
local sync2 = CALYX.create({
	kind = "objc",
	initial = "idle",
	events = { { name = "go", from = "idle", to = "done" } },
})
print("sync2 (kind=objc):", sync2.mailbox and "has mailbox" or "no mailbox")

-- Mailbox
local async = CALYX.create({
	kind = "mailbox",
	initial = "idle",
	events = { { name = "go", from = "idle", to = "done" } },
})
print("async (kind=mailbox):", async.mailbox and "has mailbox ✅" or "no mailbox")

print("\n")

-- ============================================================================
-- SUMMARY
-- ============================================================================

print(
	"═══════════════════════════════════════════════════"
)
print("  SUMMARY")
print(
	"═══════════════════════════════════════════════════"
)
print("✅ Result format: Consistent error handling")
print("✅ Ring buffer: O(1) mailbox operations")
print("✅ Deterministic clock: Replay-ready")
print("✅ API freeze: Production-safe")
print("✅ High throughput: 1000+ msg/sec")
print("✅ Backpressure: Observable and configurable")
print(
	"═══════════════════════════════════════════════════\n"
)
