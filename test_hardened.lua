#!/usr/bin/env lua
-- ============================================================================
-- test_hardened.lua
-- CALYX FSM Production Hardening Test Suite
-- Tests: Result format, ring buffer, deterministic clock, API freeze
-- ============================================================================

local hardened = require("hardened")
hardened.enable_strict_mode()

local CALYX = require("init")

-- ============================================================================
-- TEST FRAMEWORK
-- ============================================================================

local Tests = {
	passed = 0,
	failed = 0,
	tests = {},
}

function Tests:run(name, fn)
	io.write(string.format("[ TEST ] %s ... ", name))

	local ok, err = pcall(fn)

	if ok then
		self.passed = self.passed + 1
		print("✅ PASS")
	else
		self.failed = self.failed + 1
		print("❌ FAIL")
		print("  Error: " .. tostring(err))
	end

	table.insert(self.tests, { name = name, passed = ok, error = err })
end

function Tests:summary()
	print(
		string.format(
			"\n═══════════════════════════════════════════════════"
		)
	)
	print(string.format("  TEST SUMMARY"))
	print(
		string.format(
			"═══════════════════════════════════════════════════"
		)
	)
	print(string.format("  Total:  %d", self.passed + self.failed))
	print(string.format("  Passed: %d ✅", self.passed))
	print(string.format("  Failed: %d ❌", self.failed))
	print(
		string.format(
			"═══════════════════════════════════════════════════"
		)
	)

	if self.failed > 0 then
		print("\nFailed tests:")
		for _, test in ipairs(self.tests) do
			if not test.passed then
				print(string.format("  - %s", test.name))
			end
		end
	end
end

-- ============================================================================
-- TEST 1: API FREEZE
-- ============================================================================

Tests:run("API should be frozen (immutable)", function()
	local ok, err = pcall(function()
		CALYX.new_method = function() end
	end)

	assert(not ok, "API should reject new fields")
	assert(
		string.match(tostring(err), "frozen") or string.match(tostring(err), "modify"),
		"Error should mention frozen/modify"
	)
end)

-- ============================================================================
-- TEST 2: UNIFIED CREATE() WITH ROUTING
-- ============================================================================

Tests:run("create() should route to objc FSM by default", function()
	local fsm = CALYX.create({
		initial = "idle",
		events = {
			{ name = "start", from = "idle", to = "running" },
		},
	})

	assert(fsm ~= nil, "FSM should be created")
	assert(fsm.current == "idle", "Initial state should be idle")
end)

Tests:run("create({kind='mailbox'}) should route to mailbox FSM", function()
	local fsm = CALYX.create({
		kind = "mailbox",
		initial = "idle",
		events = {
			{ name = "start", from = "idle", to = "running" },
		},
	})

	assert(fsm ~= nil, "FSM should be created")
	assert(fsm.mailbox ~= nil, "Mailbox should exist")
	assert(fsm.current == "idle", "Initial state should be idle")
end)

Tests:run("create({kind='invalid'}) should error", function()
	local ok, err = pcall(function()
		CALYX.create({ kind = "invalid" })
	end)

	assert(not ok, "Should error on invalid kind")
	assert(string.match(tostring(err), "Unknown FSM kind"), "Error should mention unknown kind")
end)

-- ============================================================================
-- TEST 3: RESULT FORMAT CONSISTENCY
-- ============================================================================

Tests:run("Successful transition returns Result table", function()
	local fsm = CALYX.create({
		initial = "idle",
		events = {
			{ name = "start", from = "idle", to = "running" },
		},
	})

	local result = fsm:start()

	assert(type(result) == "table", "Result should be a table")
	assert(result.ok == true, "Result should have ok=true")
	assert(result.data ~= nil, "Result should have data field")
	assert(result.tick ~= nil, "Result should have tick field")
end)

Tests:run("Invalid transition returns error Result", function()
	local fsm = CALYX.create({
		initial = "idle",
		events = {
			{ name = "start", from = "idle", to = "running" },
		},
	})

	-- Try invalid transition
	local result = fsm:start() -- Move to running
	result = fsm:start() -- Try to start again (invalid)

	assert(type(result) == "table", "Result should be a table")
	assert(result.ok == false, "Result should have ok=false")
	assert(result.code ~= nil, "Result should have error code")
	assert(result.message ~= nil, "Result should have error message")
end)

-- ============================================================================
-- TEST 4: DETERMINISTIC CLOCK
-- ============================================================================

Tests:run("Clock should advance with transitions", function()
	local fsm = CALYX.create({
		initial = "idle",
		events = {
			{ name = "start", from = "idle", to = "running" },
			{ name = "stop", from = "running", to = "idle" },
		},
	})

	local start_tick = CALYX.diagnostics.clock:now()

	fsm:start()
	local after_start = CALYX.diagnostics.clock:now()

	fsm:stop()
	local after_stop = CALYX.diagnostics.clock:now()

	assert(after_start > start_tick, "Clock should advance after transition")
	assert(after_stop > after_start, "Clock should continue advancing")
end)

Tests:run("Clock reset should work", function()
	local clock = CALYX.diagnostics.clock

	clock:reset(0)
	assert(clock:now() == 0, "Clock should reset to 0")

	clock:advance()
	assert(clock:now() == 1, "Clock should be at 1 after advance")

	clock:reset(100)
	assert(clock:now() == 100, "Clock should reset to 100")
end)

-- ============================================================================
-- TEST 5: RING BUFFER MAILBOX
-- ============================================================================

Tests:run("Mailbox should use ring buffer (O(1) operations)", function()
	local fsm = CALYX.create({
		kind = "mailbox",
		mailbox_size = 10,
		initial = "idle",
		events = {
			{ name = "msg", from = "idle", to = "idle" },
		},
	})

	-- Send 5 messages
	for i = 1, 5 do
		local result = fsm:send("msg", { data = { count = i } })
		assert(result.ok == true, "Send should succeed")
	end

	local stats = fsm:mailbox_stats()
	assert(stats.queued == 5, "Should have 5 messages queued")
	assert(stats.max_size == 10, "Max size should be 10")
end)

Tests:run("Mailbox should reject messages when full (overflow_policy=reject)", function()
	local fsm = CALYX.create({
		kind = "mailbox",
		mailbox_size = 3,
		overflow_policy = "reject",
		initial = "idle",
		events = {
			{ name = "msg", from = "idle", to = "idle" },
		},
	})

	-- Fill mailbox
	for i = 1, 3 do
		fsm:send("msg")
	end

	-- Try to overflow
	local result = fsm:send("msg")
	assert(result.ok == false, "Should reject when full")
	assert(result.code == CALYX.ERRORS.QUEUE_FULL, "Error should be QUEUE_FULL")
end)

Tests:run("Mailbox should drop oldest when full (overflow_policy=drop_oldest)", function()
	local fsm = CALYX.create({
		kind = "mailbox",
		mailbox_size = 3,
		overflow_policy = "drop_oldest",
		initial = "idle",
		events = {
			{ name = "msg", from = "idle", to = "idle" },
		},
	})

	-- Fill mailbox
	for i = 1, 3 do
		fsm:send("msg", { data = { id = i } })
	end

	-- Overflow (should drop first message)
	local result = fsm:send("msg", { data = { id = 4 } })
	assert(result.ok == true, "Should accept message after dropping oldest")

	local stats = fsm:mailbox_stats()
	assert(stats.queued == 3, "Should still have 3 messages")
end)

-- ============================================================================
-- test_hardened.lua (FIXED - Better error matching)
-- ============================================================================

-- ... (keep existing code) ...

-- ============================================================================
-- TEST 6: METATABLE PROTECTION
-- ============================================================================

Tests:run("FSM instance should prevent new field creation", function()
	local fsm = CALYX.create({
		initial = "idle",
		events = {
			{ name = "start", from = "idle", to = "running" },
		},
	})

	local ok, err = pcall(function()
		fsm.malicious_field = "hacked"
	end)

	assert(not ok, "Should prevent new field creation")
	-- FIX: Match the actual error message from Core.lock_metatable
	assert(
		string.match(tostring(err), "Cannot modify FSM: attempted to set field 'malicious_field'")
			or string.match(tostring(err), "locked")
			or string.match(tostring(err), "modify")
			or string.match(tostring(err), "set"),
		"Error should mention locked/modify/set, got: " .. tostring(err)
	)
end)

Tests:run("FSM instance should allow mutable state fields", function()
	local fsm = CALYX.create({
		initial = "idle",
		events = {
			{ name = "start", from = "idle", to = "running" },
		},
	})

	-- current should always be settable
	local ok1, err1 = pcall(function()
		fsm.current = "test"
	end)
	assert(ok1, "Should allow setting current, got error: " .. tostring(err1))

	-- FIX: Create a mailbox FSM specifically for asyncState test
	local mailbox_fsm = CALYX.create({
		kind = "mailbox",
		initial = "idle",
		events = {
			{ name = "start", from = "idle", to = "running" },
		},
	})

	local ok2, err2 = pcall(function()
		mailbox_fsm.asyncState = "test"
	end)
	assert(ok2, "Should allow setting asyncState on mailbox FSM, got error: " .. tostring(err2))
end)

-- ============================================================================
-- TEST 7: HIGH THROUGHPUT (STRESS TEST)
-- ============================================================================

Tests:run("Mailbox should handle 1000 messages without GC issues", function()
	local fsm = CALYX.create({
		kind = "mailbox",
		mailbox_size = 2000,
		debug = true,
		initial = "idle",
		events = {
			{ name = "msg", from = "idle", to = "idle" }, -- Self-transition
		},
	})

	local start_mem = collectgarbage("count")

	-- Send 1000 messages
	for i = 1, 1000 do
		local result = fsm:send("msg", { data = { count = i } })
		assert(
			result.ok == true,
			string.format("Send %d should succeed, got error: %s", i, result.message or "unknown")
		)
	end

	-- Verify messages were enqueued
	local stats = fsm:mailbox_stats()
	assert(stats.queued == 1000, string.format("Should have 1000 messages queued, got %d", stats.queued))

	-- Process all
	local result = fsm:process_mailbox()
	assert(result.ok == true, "Processing should succeed, got error: " .. tostring(result.message))
	assert(
		result.data.processed == 1000,
		string.format(
			"Should process all 1000 messages, got processed=%d, failed=%d, retry=%d",
			result.data.processed,
			result.data.failed,
			result.data.retry_queued
		)
	)

	local end_mem = collectgarbage("count")
	local mem_growth = end_mem - start_mem

	-- Memory growth should be reasonable (< 500KB for 1000 messages)
	assert(mem_growth < 500, string.format("Memory growth too high: %.2f KB", mem_growth))

	-- Force GC to clean up
	collectgarbage()
end)

-- ============================================================================
-- RUN ALL TESTS
-- ============================================================================

print(
	"\n═══════════════════════════════════════════════════"
)
print("  CALYX FSM PRODUCTION HARDENING TEST SUITE")
print(
	"═══════════════════════════════════════════════════\n"
)

Tests:summary()

if Tests.failed > 0 then
	os.exit(1)
else
	print("\n🎉 All tests passed! Production-ready.\n")
	os.exit(0)
end
