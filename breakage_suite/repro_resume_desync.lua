require("init")
local FSM = require("calyx_fsm_mailbox")

print("[SIL_TEST] Initializing Semantic Drift Test...")

local fsm = FSM.create({
	name = "DRIFT_TESTER",
	initial = "IDLE",
	events = { { name = "stutter", from = "IDLE", to = "IDLE" } },
	callbacks = {
		onleaveIDLE = function(self, ctx)
			print("[SIL_TEST] onleaveIDLE fired. Returning 'async'...")
			return "async"
		end,
	},
})

-- EMERGENCY INJECTION (If the Proxy missed it)
if not fsm.semantic_state then
	local internal = debug.getmetatable(fsm) and debug.getmetatable(fsm).__index or fsm
	internal.semantic_state = function(self)
		return {
			current = self.current,
			async = self.asyncState,
			context_valid = self._context ~= nil,
		}
	end
end

-- [STEP 1] Triggering event...
fsm:stutter()

-- [STEP 2] Verify state
local state = fsm:semantic_state()
print(
	string.format(
		"[METRIC] Current: %s, Async: %s, Context Valid: %s",
		state.current,
		state.async,
		tostring(state.context_valid)
	)
)

-- [STEP 3] Simulate the Drift
print("\n[STEP 3] Wiping Context...")
local raw = debug.getmetatable(fsm).__index
raw._context = nil

-- [STEP 4] The Guarded Resume
print("[STEP 4] Attempting Resume...")
assert(fsm._context ~= nil, "[GUARD] Cannot resume: No context set")
fsm:resume()
