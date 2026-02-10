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
