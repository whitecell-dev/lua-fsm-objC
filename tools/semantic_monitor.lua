-- KNOWN: UNREFERENCED, and semantically stale. :13 reads `#fsm.mailbox`, but
-- core/core.lua has no `mailbox` field at all and objc FSMs expose no mailbox,
-- so this raises "attempt to get length of a nil value" on any current FSM.
-- It also rawset()s state the live frozen proxy (core/objc.lua:180,
-- core/mailbox.lua:405) is designed to block. (recon 7/B34)
-- NOT FIXED: reimplementing it against the closure API is a feature change.

local Monitor = {}

function Monitor.watch(fsm)
	local proxy = {}
	local internal = fsm

	setmetatable(proxy, {
		__index = internal,
		__newindex = function(_, key, value)
			if key == "current" then
				print(string.format("[SEMANTIC] State Shift: %s -> %s", internal.current, value))
				-- ASSERTION: Never return to IDLE while a mailbox is full
				if value == "IDLE" and #internal.mailbox > 0 then
					print("[WARNING] Semantic Violation: Entering IDLE with pending messages!")
				end
			end
			rawset(internal, key, value)
		end,
	})
	return proxy
end

return Monitor
