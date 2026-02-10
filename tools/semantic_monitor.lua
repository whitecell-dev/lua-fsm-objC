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
