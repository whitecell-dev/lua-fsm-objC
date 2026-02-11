-- breakage_suite/test_reporting_demo.lua
-- DEMO: Test the reporting system with the FSM

local bundle = require("init")
local ReportGen = require("tools.reportgen")

print("[BREAKAGE_SUITE] Starting reporting system demo test...")

local report = ReportGen.new("survival_reports")
report:start_test("test_reporting_demo")

-- Test 1: Basic FSM creation
local fsm1 = bundle.create({
	name = "REPORT_TEST",
	initial = "IDLE",
	events = {
		{ name = "start", from = "IDLE", to = "RUNNING" },
		{ name = "stop", from = "RUNNING", to = "STOPPED" },
	},
})

if fsm1 then
	report:add_metric("fsm_creation", "success", "status")
	report:add_metric("initial_state", fsm1.current, "state")
else
	report:add_failure(
		"FSM_CREATION_FAILED",
		"CRITICAL",
		"Failed to create basic FSM",
		"All tests will fail",
		"Check bundle.create() implementation"
	)
end

-- Test 2: Mailbox functionality
if fsm1 and fsm1.mailbox then
	local ok = fsm1:send("start", { to_fsm = fsm1 })
	report:add_metric("mailbox_send", ok and "success" or "failed", "status")
	report:add_metric("mailbox_queue_size", fsm1.mailbox:count(), "messages")
else
	report:add_failure(
		"MAILBOX_MISSING",
		"MAJOR",
		"FSM created without mailbox",
		"Message passing disabled",
		"Ensure mailbox is initialized in create()"
	)
end

-- Test 3: State transitions
if fsm1 then
	local can_start = fsm1:can("start")
	report:add_metric("can_start_transition", can_start, "boolean")

	if can_start then
		local ok, result = fsm1:start({ data = { test = true } })
		report:add_metric("transition_result", ok and "success" or "failed", "status")
		if ok then
			report:add_metric("new_state", fsm1.current, "state")
		else
			report:add_warning("Transition returned error: " .. (result.error_type or "unknown"), "transition")
		end
	end
end

-- Test 4: Memory check (simulated)
collectgarbage()
local start_mem = collectgarbage("count")
local big_table = {}
for i = 1, 1000 do
	big_table[i] = string.rep("x", 100)
end
collectgarbage()
local end_mem = collectgarbage("count")
local memory_growth = end_mem - start_mem

report:add_metric("memory_growth", string.format("%.2f", memory_growth), "KB")
report:add_metric("test_iterations", 1000, "iterations")

if memory_growth > 500 then
	report:add_warning(string.format("Large memory growth: %.2f KB", memory_growth), "memory")
end

-- Clean up
if fsm1 and fsm1.clear_mailbox then
	fsm1:clear_mailbox()
end

-- End test with summary
local test_report = report:end_test("COMPLETED", "Basic FSM functionality test")

-- Print console version
print("\n" .. string.rep("=", 60))
print("DEMO: Console Report Output")
print(string.rep("=", 60))
report:print_console_report("test_reporting_demo")

-- Generate overall summary
local summary = report:generate_summary()

print("\n" .. string.rep("=", 60))
print("TEST SUMMARY")
print(string.rep("=", 60))
print(string.format("Total Tests: %d", summary.total_tests))
print(string.format("Passed: %d", summary.passed))
print(string.format("Failed: %d", summary.failed))
print(string.format("Total Failures: %d", summary.total_failures))
print(string.format("Total Warnings: %d", summary.total_warnings))

print("\n[BREAKAGE_SUITE] Reporting demo complete")
print("Check 'survival_reports/' directory for JSON reports")
