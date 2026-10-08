-- KNOWN: UNREFERENCED AND UNCALLABLE. SIL.validate (:6) calls
-- `fsm:semantic_state()`, which does not exist on any FSM in this repo -- there
-- is no such method on core/objc.lua or core/mailbox.lua, and no `state.stuck`
-- / `state.context_valid` / `state.async` shape behind it. (recon 7/B33)
-- NOT FIXED: inventing that introspection API is a feature change.

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
