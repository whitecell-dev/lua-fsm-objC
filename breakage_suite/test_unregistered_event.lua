-- breakage_suite/test_unregistered_event.lua
	-- FIX: dispatchers call callback(fsm, ctx) -- TWO args
	-- (core/objc.lua:57-98, core/mailbox.lua:164-200). These were declared
	-- as function(ctx), so `ctx` actually received the FSM table and any
	-- ctx.data access raised "attempt to index field 'data' (a nil value)".
local TestRunner = require("tools.test_runner")
local runner = TestRunner.new()

runner:start_suite()

runner:run("test_unregistered_event", function()
	local bundle = require("init")
	local ASYNC = bundle.ASYNC

	metric("test_start", os.time(), "timestamp")
	log("Starting unregistered event tests", "INFO")

	-- ============================================================================
	-- TEST 1: CALLING NON-EXISTENT METHOD ON FSM INSTANCE
	-- ============================================================================
	log("Test 1: Calling non-existent method", "SECTION")

	local simple_fsm = bundle.create({
		name = "SIMPLE_FSM",
		initial = "IDLE",
		events = {
			{ name = "start", from = "IDLE", to = "RUNNING" },
			{ name = "stop", from = "RUNNING", to = "IDLE" },
		},
		callbacks = {
			onleaveIDLE = function(fsm, ctx)
				metric("simple_start_callback", true, "boolean")
				return ASYNC
			end,
		},
	})

	-- Attempt to call a method that doesn't exist
	local method_exists, method_err = pcall(function()
		return simple_fsm:nonExistentMethod({ to_fsm = simple_fsm })
	end)

	metric("non_existent_method_call_attempted", true, "boolean")
	metric("non_existent_method_result", method_exists, "boolean")

	if not method_exists then
		metric("non_existent_method_error", method_err, "string")
		log(string.format("Expected error for non-existent method: %s", method_err), "INFO")

		-- Verify it's a "method not found" type error
		if string.find(method_err, "attempt to call method") or string.find(method_err, "nil value") then
			metric("non_existent_method_error_type", "method_not_found", "string")
		else
			fail(
				"UNEXPECTED_ERROR_TYPE",
				"MAJOR",
				"Non-existent method error has unexpected format",
				string.format("Error: %s", method_err),
				"Check Lua error handling for missing methods"
			)
		end
	else
		fail(
			"METHOD_SHOULD_NOT_EXIST",
			"CRITICAL",
			"Non-existent method call succeeded unexpectedly",
			"FSM instance should not have arbitrary methods",
			"Review metatable or __index implementation"
		)
	end

	-- ============================================================================
	-- TEST 2: CALLING VALID EVENT NAME NOT IN CONFIGURATION
	-- ============================================================================
	log("Test 2: Valid event name not in config", "SECTION")

	-- Try to call an event that exists as a method but isn't configured
	local unregistered_event_ok, unregistered_err = pcall(function()
		return simple_fsm:reset({ to_fsm = simple_fsm })
	end)

	metric("unregistered_event_call_attempted", true, "boolean")
	metric("unregistered_event_result", unregistered_event_ok, "boolean")

	if not unregistered_event_ok then
		metric("unregistered_event_error", unregistered_err, "string")
		log(string.format("Expected error for unregistered event: %s", unregistered_err), "INFO")

		-- Verify error type
		if
			string.find(unregistered_err, "reset")
			and (
				string.find(unregistered_err, "not found")
				or string.find(unregistered_err, "undefined")
				or string.find(unregistered_err, "invalid")
			)
		then
			metric("unregistered_event_error_type", "event_not_found", "string")
		else
			fail(
				"UNEXPECTED_UNREGISTERED_ERROR",
				"MAJOR",
				"Unregistered event error has unexpected format",
				string.format("Error: %s", unregistered_err),
				"Ensure unregistered events are properly rejected"
			)
		end
	else
		-- If it succeeded, check if FSM state changed (it shouldn't have)
		if simple_fsm.current ~= "IDLE" then
			fail(
				"UNREGISTERED_EVENT_CHANGED_STATE",
				"CRITICAL",
				"Unregistered event changed FSM state",
				string.format("State changed from IDLE to %s", simple_fsm.current),
				"Review event dispatch logic"
			)
		else
			warn(
				"Unregistered event call succeeded but didn't change state - " .. "may indicate silent failure",
				"event_handling"
			)
			metric("unregistered_event_silent_success", true, "boolean")
		end
	end

	-- ============================================================================
	-- TEST 3: DYNAMIC METHOD INJECTION ATTEMPT
	-- ============================================================================
	log("Test 3: Dynamic method injection", "SECTION")

	-- Attempt to add a new method to the FSM instance
	local injection_ok, injection_result = pcall(function()
		simple_fsm.newMethod = function(self, ctx)
			return "injected"
		end
		return simple_fsm:newMethod({ to_fsm = simple_fsm })
	end)

	metric("method_injection_attempted", true, "boolean")
	metric("method_injection_result", injection_ok, "boolean")

	if injection_ok then
		if injection_result == "injected" then
			warn("Method injection succeeded - FSM instances are mutable", "security")
			metric("method_injection_success", true, "boolean")

			-- Clean up
			simple_fsm.newMethod = nil
		else
			metric("method_injection_unexpected_result", injection_result, "string")
		end
	else
		metric("method_injection_error", injection_result, "string")
		log(string.format("Method injection failed as expected: %s", injection_result), "INFO")
	end

	-- ============================================================================
	-- TEST 4: METAMETHOD TAMPERING
	-- ============================================================================
	log("Test 4: Metamethod tampering", "SECTION")

	-- Attempt to modify the FSM's metatable
	local metatable_ok, metatable_result = pcall(function()
		local mt = getmetatable(simple_fsm)
		if mt then
			mt.__index.tampered = function()
				return "tampered"
			end
			return simple_fsm:tampered()
		end
		return "no_metatable"
	end)

	metric("metatable_tampering_attempted", true, "boolean")
	metric("metatable_tampering_result", metatable_ok, "boolean")

	if metatable_ok and metatable_result == "tampered" then
		warn("Metatable tampering succeeded - FSM instances are not protected", "security")
		metric("metatable_tampering_success", true, "boolean")

		-- Clean up
		local mt = getmetatable(simple_fsm)
		if mt and mt.__index then
			mt.__index.tampered = nil
		end
	else
		log("Metatable tampering failed or was blocked", "INFO")
		metric("metatable_tampering_blocked", true, "boolean")
	end

	-- ============================================================================
	-- TEST 5: EVENT NAME COLLISION WITH INTERNAL METHODS
	-- ============================================================================
	log("Test 5: Event name collision with internal methods", "SECTION")

-- Create FSM with event names that collide with internal methods.
-- FIX: needs kind="mailbox" -- this FSM is driven through :send()/:resume()/
-- :process_mailbox() at :219-230, none of which exist on the default objc FSM.
--
-- NOTE ON WHAT THIS SECTION NOW MEASURES: reserved names are REJECTED at
-- construction by Core.validate_fsm_config (core/core.lua), the enforcer of
-- ABI.RESERVED. Declaring events named send/resume/current is therefore an
-- error, and the mailbox FSM's own methods can no longer be overwritten by
-- the dynamic event-method loop. (Phase-1 validation; previously measured
-- as COLLISION_SEND_FAILED.)
local collision_ok, collision_err = pcall(bundle.create, {
	kind = "mailbox",
	name = "COLLISION_FSM",
		initial = "START",
		events = {
			{ name = "send", from = "START", to = "MIDDLE" }, -- Collides with send()
			{ name = "resume", from = "MIDDLE", to = "END" }, -- Collides with resume()
			{ name = "current", from = "END", to = "START" }, -- Collides with current property
		},
		callbacks = {
			onleaveSTART = function(fsm, ctx)
				metric("collision_send_callback", true, "boolean")
				return ASYNC
			end,
			onleaveMIDDLE = function(fsm, ctx)
				metric("collision_resume_callback", true, "boolean")
				return ASYNC
			end,
		},
	})

	metric("collision_rejected", not collision_ok, "boolean")

	if collision_ok then
		fail(
			"COLLISION_NOT_REJECTED",
			"CRITICAL",
			"Reserved event names were accepted at construction",
			"FSM with events send/resume/current was created without error",
			"Review Core.validate_fsm_config reserved-name enforcement"
		)
	else
		metric("collision_error", collision_err, "string")
		log(string.format("Reserved names rejected as expected: %s", collision_err), "INFO")
		if not string.find(collision_err, "reserved", 1, true) then
			fail(
				"COLLISION_WRONG_ERROR",
				"MAJOR",
				"Reserved-name rejection has unexpected format",
				string.format("Error: %s", collision_err),
				"Error should name the reserved event"
			)
		end
	end

	-- A healthy mailbox FSM keeps its own methods: no event could have
	-- overwritten them, since reserved names never get that far.
	local healthy_fsm = bundle.create({
		kind = "mailbox",
		name = "HEALTHY_FSM",
		initial = "START",
		events = {
			{ name = "go", from = "START", to = "MIDDLE" },
			{ name = "finish", from = "MIDDLE", to = "END" },
		},
	})

	local send_ok = type(healthy_fsm.send) == "function"
		and type(healthy_fsm.resume) == "function"
		and type(healthy_fsm.process_mailbox) == "function"
	metric("collision_send_event", send_ok, "boolean")

	if send_ok then
		local send_res = healthy_fsm:send("go")
		local process_ok = send_res.ok and healthy_fsm:process_mailbox()
		metric("collision_send_processed", process_ok and process_ok.ok == true, "boolean")

		-- NOTE: assert via get_state(), the closure source of truth. The
		-- `.current` field on the frozen proxy is stale after transitions
		-- (pre-existing shadowing bug, out of scope for Phase-1 validation).
		if process_ok and process_ok.ok == true and healthy_fsm:get_state() == "MIDDLE" then
			log("Healthy FSM methods intact and roundtrip works", "INFO")
			metric("collision_resume_event", true, "boolean")
		else
			fail(
				"COLLISION_SEND_FAILED",
				"MAJOR",
				"Healthy mailbox FSM failed a basic send/process roundtrip",
				string.format("State: %s", tostring(healthy_fsm:get_state())),
				"Review event method generation vs internal methods"
			)
		end
	else
		fail(
			"COLLISION_SEND_REJECTED",
			"MINOR",
			"Healthy FSM is missing send/resume/process_mailbox methods",
			"Methods should always exist on mailbox FSMs",
			"Verify if collision protection is desired"
		)
	end

	-- ============================================================================
	-- TEST 6: NIL OR EMPTY EVENT NAMES
	-- ============================================================================
	log("Test 6: Nil or empty event names", "SECTION")

	-- Empty event names are rejected at construction by
	-- Core.validate_fsm_config (event-name pattern check).
	local empty_ok, empty_err = pcall(bundle.create, {
		name = "EMPTY_FSM",
		initial = "IDLE",
		events = {
			{ name = "", from = "IDLE", to = "ACTIVE" }, -- Empty string
			{ name = "valid", from = "ACTIVE", to = "DONE" },
		},
	})

	metric("empty_event_call_attempted", true, "boolean")
	metric("empty_event_result", empty_ok, "boolean")

	if not empty_ok then
		metric("empty_event_error", empty_err, "string")
		log(string.format("Empty event rejected as expected: %s", empty_err), "INFO")
	else
		warn("Empty string event name was accepted", "validation")
		metric("empty_event_accepted", true, "boolean")
	end

	-- ============================================================================
	-- TEST 7: EVENT NAME WITH SPECIAL CHARACTERS
	-- ============================================================================
	log("Test 7: Special characters in event names", "SECTION")

	local special_fsm = bundle.create({
		name = "SPECIAL_FSM",
		initial = "START",
		events = {
			{ name = "event-with-dashes", from = "START", to = "MIDDLE" },
			{ name = "event_with_underscores", from = "MIDDLE", to = "END" },
			{ name = "event.with.dots", from = "END", to = "START" },
			{ name = "event123numbers", from = "START", to = "END" },
		},
	})

	local special_events = {
		"event-with-dashes",
		"event_with_underscores",
		"event.with.dots",
		"event123numbers",
	}

	for _, event_name in ipairs(special_events) do
		local special_ok, special_err = pcall(function()
			return special_fsm[event_name]({ to_fsm = special_fsm })
		end)

		metric("special_event_" .. event_name:gsub("[^%w]", "_"), special_ok, "boolean")

		if not special_ok then
			metric("special_event_error_" .. event_name:gsub("[^%w]", "_"), special_err, "string")
			log(string.format("Special event '%s' rejected: %s", event_name, special_err), "INFO")
		else
			log(string.format("Special event '%s' accepted", event_name), "INFO")
		end
	end

	log("All unregistered event tests completed", "SUCCESS")
	metric("test_end", os.time(), "timestamp")
end)

runner:end_suite()
