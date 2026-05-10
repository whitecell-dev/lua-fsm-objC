-- session_fsm.lua
-- PURE FSM FACTORY - Returns unmodified Calyx FSM instances

local calyx = require("init")

-- Factory function that creates a fresh FSM instance
-- @param initial_state: table with optional 'state' field
-- @return: unmodified Calyx FSM instance
local function create_session_fsm(initial_state)
	-- Extract initial state (default to "logged_out")
	local state = initial_state and initial_state.state or "logged_out"

	-- Create FSM using Calyx's create_mailbox_fsm
	-- This returns a FROZEN, IMMUTABLE instance
	local fsm = calyx.create_mailbox_fsm({
		-- Unique name for this FSM instance
		name = "USER_SESSION_" .. tostring(math.random(10000)),

		-- Starting state
		initial = state,

		-- Define all possible transitions
		events = {
			{ name = "login_attempt", from = "logged_out", to = "authenticating" },
			{ name = "auth_success", from = "authenticating", to = "authenticated" },
			{ name = "auth_failure", from = "authenticating", to = "logged_out" },
			{ name = "logout", from = "authenticated", to = "logged_out" },
		},
	})

	-- ⚠️ CRITICAL: Return the FSM WITHOUT ANY MODIFICATIONS
	-- Do NOT add fields (fsm.custom_data = ...)
	-- Do NOT wrap methods (fsm.send = ...)
	-- The FSM must remain PURE and UNMODIFIED
	return fsm
end

return create_session_fsm
