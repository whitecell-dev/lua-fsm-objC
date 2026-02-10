-- failure_modes/workarounds/calyx_sil.lua
local SIL = {}

function SIL.validate(fsm)
	local errors = {}
	local state = fsm:semantic_state()

	if state.async ~= "none" and not state.context_valid then
		table.insert(errors, "ASYNC_WITHOUT_CONTEXT: FSM is waiting but has no data.")
	end

	if state.stuck then
		table.insert(errors, "STUCK_STATE: FSM logic cannot progress.")
	end

	return errors
end

return SIL
