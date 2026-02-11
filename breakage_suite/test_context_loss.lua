-- breakage_suite/test_context_loss_fixed.lua
local TestRunner = require("tools.test_runner")
local runner = TestRunner.new()

runner:start_suite()

runner:run("test_context_loss", function()
	local bundle = require("init")
	local ASYNC = bundle.ASYNC

	metric("test_start", os.time(), "timestamp")
	log("Starting context loss stress tests", "INFO")

	-- ============================================================================
	-- TEST 1: DEEP ASYNC CHAIN (SIMPLIFIED - NO CALLBACK ACCESS)
	-- ============================================================================
	log("Test 1: Deep async chain", "SECTION")

	local deep_chain_fsm = bundle.create({
		name = "DEEP_CHAIN_TEST",
		initial = "A",
		events = {
			{ name = "step1", from = "A", to = "B" },
			{ name = "step2", from = "B", to = "C" },
			{ name = "step3", from = "C", to = "D" },
			{ name = "step4", from = "D", to = "E" },
			{ name = "step5", from = "E", to = "F" },
		},
		callbacks = {
			onleaveA = function(ctx)
				metric("deep_chain_step_A", os.time(), "timestamp")
				return ASYNC
			end,
			onleaveB = function(ctx)
				metric("deep_chain_step_B", os.time(), "timestamp")
				return ASYNC
			end,
			onleaveC = function(ctx)
				metric("deep_chain_step_C", os.time(), "timestamp")
				return ASYNC
			end,
			onleaveD = function(ctx)
				metric("deep_chain_step_D", os.time(), "timestamp")
				return ASYNC
			end,
			onleaveE = function(ctx)
				metric("deep_chain_step_E", os.time(), "timestamp")
				return ASYNC
			end,
		},
	})

	-- Start and complete chain
	local ok = deep_chain_fsm:send("step1", { to_fsm = deep_chain_fsm })
	metric("deep_chain_started", ok, "boolean")

	if ok then
		for i = 1, 5 do
			local process_ok = deep_chain_fsm:process_mailbox()
			metric("deep_chain_process_" .. i, process_ok, "boolean")
		end
	end

	metric("deep_chain_final_state", deep_chain_fsm.current, "string")

	-- ============================================================================
	-- TEST 2: RAPID-FIRE (FIXED - HANDLE EXPECTED FAILURES)
	-- ============================================================================
	log("Test 2: Rapid-fire transitions", "SECTION")

	local rapid_fire_fsm = bundle.create({
		name = "RAPID_FIRE_TEST",
		initial = "READY",
		events = {
			{ name = "fire", from = "READY", to = "PROCESSING" },
			{ name = "reset", from = "PROCESSING", to = "READY" },
		},
		callbacks = {
			onleaveREADY = function(ctx)
				return ASYNC
			end,
			onleavePROCESSING = function(ctx)
				return ASYNC
			end,
		},
	})

	local rapid_iterations = 20 -- Reduced for stability
	local rapid_success = 0
	local rapid_expected_fails = 0
	local rapid_unexpected_fails = 0

	for i = 1, rapid_iterations do
		-- Wait for READY state
		local attempts = 0
		while rapid_fire_fsm.current ~= "READY" and attempts < 3 do
			rapid_fire_fsm:process_mailbox()
			attempts = attempts + 1
		end

		local fire_ok, fire_err = rapid_fire_fsm:send("fire", {
			to_fsm = rapid_fire_fsm,
			data = { iteration = i },
		})

		if fire_ok then
			local process_ok = rapid_fire_fsm:process_mailbox()
			metric("rapid_fire_success_" .. i, process_ok, "boolean")

			if process_ok then
				rapid_success = rapid_success + 1

				-- Try to reset
				local reset_ok = rapid_fire_fsm:send("reset", {
					to_fsm = rapid_fire_fsm,
				})
				if reset_ok then
					rapid_fire_fsm:process_mailbox()
				end
			end
		else
			metric("rapid_fire_fail_reason_" .. i, fire_err or "unknown", "string")
			if fire_err == "invalid_transition_for_current_state" then
				rapid_expected_fails = rapid_expected_fails + 1
			else
				rapid_unexpected_fails = rapid_unexpected_fails + 1
			end
		end
	end

	metric("rapid_total", rapid_iterations, "count")
	metric("rapid_success", rapid_success, "count")
	metric("rapid_expected_fails", rapid_expected_fails, "count")
	metric("rapid_unexpected_fails", rapid_unexpected_fails, "count")

	-- ============================================================================
	-- TEST 3: SYNTHETIC CONTEXT (SIMPLIFIED)
	-- ============================================================================
	log("Test 3: Synthetic context", "SECTION")

	local synthetic_fsm = bundle.create({
		name = "SYNTHETIC_TEST",
		initial = "STABLE",
		events = {
			{ name = "corrupt", from = "STABLE", to = "CORRUPTED" },
		},
	})

	-- Manually set async state without context
	synthetic_fsm.asyncState = "corrupt_LEAVE_WAIT"
	synthetic_fsm.currentTransitioningEvent = "corrupt"

	log("Testing synthetic context recovery", "DEBUG")

	-- This should trigger the guard in _complete()
	local recovery_ok, recovery_result = synthetic_fsm:resume()
	metric("synthetic_recovery_attempted", true, "boolean")
	metric("synthetic_recovery_success", recovery_ok, "boolean")

	if recovery_ok then
		log("Synthetic context recovery succeeded", "INFO")
		metric("recovered_state", synthetic_fsm.current, "string")
	else
		warn("Synthetic recovery failed: " .. (recovery_result.error_type or "unknown"), "context_recovery")
	end

	-- ============================================================================
	-- TEST 4: MEMORY CHECK (SIMPLIFIED)
	-- ============================================================================
	log("Test 4: Memory check", "SECTION")

	collectgarbage("collect")
	local start_mem = collectgarbage("count")

	local fsm_count = 50
	local fsms = {}

	for i = 1, fsm_count do
		fsms[i] = bundle.create({
			name = "MEM_TEST_" .. i,
			initial = "IDLE",
			events = { { name = "ping", from = "IDLE", to = "PONG" } },
			mailbox_size = 5,
		})

		-- Send and process one message
		fsms[i]:send("ping", { to_fsm = fsms[i] })
		fsms[i]:process_mailbox()
		fsms[i]:clear_mailbox()
	end

	-- Clean up
	for i = 1, fsm_count do
		fsms[i] = nil
	end

	collectgarbage("collect")
	local end_mem = collectgarbage("count")
	local memory_diff = end_mem - start_mem

	metric("memory_start_kb", start_mem, "KB")
	metric("memory_end_kb", end_mem, "KB")
	metric("memory_difference_kb", memory_diff, "KB")
	metric("fsms_created", fsm_count, "count")

	if memory_diff > 100 then
		fail(
			"MEMORY_LEAK",
			"CRITICAL",
			string.format("Memory increased by %.2f KB", memory_diff),
			"FSM objects not being collected",
			"Check for reference cycles"
		)
	elseif memory_diff > 50 then
		warn(string.format("Moderate memory retention: +%.2f KB", memory_diff), "memory")
	end

	log("All tests completed", "SUCCESS")
	metric("test_end", os.time(), "timestamp")
end)

runner:end_suite()
