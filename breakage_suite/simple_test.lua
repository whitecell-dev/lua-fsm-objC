-- Survival Lab Validation Script
-- Purpose: Compare Pure vs. Patched behavior of the FSM Transition Engine

local function run_fsm_test(machine_module)
	-- Create a minimal FSM that uses async-style transitions
	local machine = machine_module.create({
		name = "VALIDATOR",
		initial = "START",
		events = {
			{ name = "proceed", from = "START", to = "END" },
		},
		callbacks = {
			onleaveSTART = function(self, ctx)
				print("  [CALLBACK] Leaving START...")
				return "async" -- Force the logic into the LEAVE_WAIT stage
			end,
			onenterEND = function(self, ctx)
				print("  [CALLBACK] Entering END!")
			end,
		},
	})

	print("  Attempting transition: START -> END")
	local success = machine:proceed()
	print("  Transition call returned:", success)
	print("  Final State:", machine.current)
end

-- 1. TEST AGAINST PURE BUNDLE
print("--- TESTING PURE BUNDLE (EXPECTED FAILURE/HANG) ---")
require("init")
local pure_fsm = require("calyx_fsm_mailbox")

-- Wrap in pcall to prevent the whole script from dying if the pure bundle crashes
local ok, err = pcall(function()
	run_fsm_test(pure_fsm)
end)
if not ok then
	print("  [OBSERVED FAILURE]: " .. tostring(err))
end

-- 2. RESET LABORATORY ENVIRONMENT
-- We must clear the registry so the patch can re-bind to a fresh module
package.loaded["calyx_fsm_mailbox"] = nil
package.loaded["failure_modes.workarounds.fix_invalid_stage"] = nil

-- 3. TEST AGAINST PATCHED BUNDLE
print("\n--- TESTING PATCHED BUNDLE (EXPECTED SUCCESS) ---")
local patched_fsm = require("failure_modes.workarounds.fix_invalid_stage")

local ok_patch, err_patch = pcall(function()
	run_fsm_test(patched_fsm)
end)
if not ok_patch then
	print("  [PATCH FAILURE]: " .. tostring(err_patch))
else
	print("  [PATCH SUCCESS]: Validation test completed.")
end

print("\n================================================================")
print("EVIDENCE GATHERING COMPLETE")
print("================================================================")
