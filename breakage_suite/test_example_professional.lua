-- breakage_suite/test_example_professional.lua
-- EXAMPLE: Professional VM-grade test using TestRunner

local TestRunner = require("tools.test_runner")
local runner = TestRunner.new()

runner:start_suite()

runner:run("test_fsm_basic", function()
	-- Test code with injected reporting API
	local bundle = require("init")

	metric("test_start_time", os.time(), "timestamp")

	-- Create FSM
	local fsm = bundle.create({
		name = "PROFESSIONAL_TEST",
		initial = "IDLE",
		events = {
			{ name = "activate", from = "IDLE", to = "ACTIVE" },
			{ name = "deactivate", from = "ACTIVE", to = "IDLE" },
		},
	})

	if not fsm then
		fail(
			"FSM_CREATION_FAILED",
			"CRITICAL",
			"Failed to create FSM",
			"All further tests invalid",
			"Check bundle.create() implementation"
		)
		return
	end

	metric("fsm_created", true, "boolean")
	metric("initial_state", fsm.current, "string")

	-- Test transitions
	local can_activate = fsm:can("activate")
	metric("can_activate", can_activate, "boolean")

	if not can_activate then
		fail(
			"CANNOT_ACTIVATE",
			"MAJOR",
			"FSM cannot transition from IDLE to ACTIVE",
			"State machine broken",
			"Check event definition"
		)
	end

	-- Test mailbox
	if not fsm.mailbox then
		warn("Missing mailbox on FSM", "configuration")
	else
		local ok = fsm:send("activate", { to_fsm = fsm })
		metric("mailbox_send_success", ok, "boolean")

		if ok then
			local queue_size = fsm.mailbox:count()
			metric("queue_size_after_send", queue_size, "messages")

			if queue_size ~= 1 then
				warn(string.format("Expected 1 message, got %d", queue_size), "mailbox")
			end
		end
	end

	-- Performance metric
	local start = os.clock()
	for i = 1, 1000 do
		fsm:can("activate")
	end
	local duration = os.clock() - start
	metric("can_check_1000_iterations_ms", duration * 1000, "ms")

	-- Cleanup
	if fsm.clear_mailbox then
		fsm:clear_mailbox()
	end

	log("Test completed successfully", "INFO")
end)

runner:end_suite()
