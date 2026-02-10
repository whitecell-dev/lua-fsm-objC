require("init")
local fsm_lib = require("failure_modes.workarounds.fix_invalid_stage")

local test_fsm = fsm_lib.create({
	name = "PROTOCOL_TESTER",
	initial = "IDLE",
	events = { { name = "activate", from = "IDLE", to = "ACTIVE" } },
	callbacks = {
		onleaveIDLE = function()
			print("  [SYSTEM] Requesting Async...")
			return "async"
		end,
	},
})

print("\n--- TRIGGERING PROTOCOL EVENT ---")
test_fsm:activate()

print("\n--- SEMANTIC AUDIT ---")
print("Final State: " .. test_fsm.current)
print("Async Status: " .. (test_fsm.asyncState or "none"))

if test_fsm.current == "ACTIVE" then
	print("\n[VERDICT] PROTOCOL SUCCESS: Semantic Proxy bridged the async gap.")
else
	print("\n[VERDICT] PROTOCOL FAILURE: State still trapped.")
end
