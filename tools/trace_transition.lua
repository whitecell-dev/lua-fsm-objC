-- KNOWN: THIS FILE CANNOT LOAD. Line 2 requires "calyx_fsm_mailbox", a module
-- deleted in commit 9470a9c (2026-02-11); nothing on disk provides it. It also
-- reads machine.asyncState / machine.currentTransitioningEvent (:24-25), which
-- live only on the closure FSMs' public surface. Unreferenced by anything.
-- (recon 7/B32) NOT FIXED: restoring the old module API is a feature change.

require("init")
local machine_module = require("calyx_fsm_mailbox")

print("--- DIAGNOSTIC: TRANSITION NERVE CENTER ---")

local machine = machine_module.create({
	name = "DIAGNOSTIC",
	initial = "START",
	events = { { name = "go", from = "START", to = "END" } },
	callbacks = {
		onleaveSTART = function()
			print("  [STEP] Returning 'async' from callback")
			return "async"
		end,
	},
})

print("Executing machine:go()...")
local ret = machine:go()

print("\nPOST-MORTEM:")
print("Return Value of go():", ret)
print("Current State:", machine.current)
print("Async State (internal):", machine.asyncState or "NIL")
print("Transition Event (internal):", machine.currentTransitioningEvent or "NIL")

if machine.current == "START" and ret == true then
	print("\n[VERDICT]: THE 'ASYNC' SIGNAL IS BEING IGNORED.")
	print("ACTION: The transition logic needs to be patched, not just the completion logic.")
end
