-- ============================================================================
-- calyx/llm.lua - FIXED inspect function to see through frozen proxy
-- ============================================================================

local ABI = require("core.abi")
local CALYX = require("init")

local LLM = {}

function LLM.inspect(fsm, opts)
	opts = opts or {}

	print("[LLM_INSPECT] Inspecting FSM:", fsm:get_name())

	-- Build capability map
	local capabilities = {}

	-- METHOD 0: Preferred in hardened/frozen mode
	if fsm.capabilities and type(fsm.capabilities) == "table" then
		print("[LLM_INSPECT] Found fsm.capabilities (" .. #fsm.capabilities .. ")")
		for i = 1, #fsm.capabilities do
			capabilities[#capabilities + 1] = fsm.capabilities[i]
			print("[LLM_INSPECT]   Cap:", fsm.capabilities[i])
		end
	end
	-- METHOD 1: Try to access the original public_api via the metatable's __index
	local mt = getmetatable(fsm)
	if mt and type(mt.__index) == "table" then
		print("[LLM_INSPECT] Found __index table with methods:")
		for k, v in pairs(mt.__index) do
			if type(v) == "function" then
				-- Filter out reserved/internal methods
				local is_reserved = false
				for i = 1, #ABI.RESERVED do
					if k == ABI.RESERVED[i] then
						is_reserved = true
						break
					end
				end
				if not is_reserved then
					table.insert(capabilities, k)
					print("[LLM_INSPECT]   Found method: " .. k)
				end
			end
		end
	end

	-- METHOD 2: If we have a direct reference to public_api (for mailbox FSM)
	if fsm._public_api and type(fsm._public_api) == "table" then
		print("[LLM_INSPECT] Found _public_api table:")
		for k, v in pairs(fsm._public_api) do
			if type(v) == "function" then
				local is_reserved = false
				for i = 1, #ABI.RESERVED do
					if k == ABI.RESERVED[i] then
						is_reserved = true
						break
					end
				end
				if not is_reserved then
					table.insert(capabilities, k)
					print("[LLM_INSPECT]   Found method: " .. k)
				end
			end
		end
	end

	-- METHOD 3: Try to get transitions from the FSM
	if fsm.transitions then
		print("[LLM_INSPECT] Checking transitions:")
		for event_name, _ in pairs(fsm.transitions) do
			local already_have = false
			for i = 1, #capabilities do
				if capabilities[i] == event_name then
					already_have = true
					break
				end
			end
			if not already_have then
				table.insert(capabilities, event_name)
				print("[LLM_INSPECT]   Found transition: " .. event_name)
			end
		end
	end

	-- Sort capabilities
	table.sort(capabilities)

	print("[LLM_INSPECT] Total capabilities found: " .. #capabilities)

	-- Current state context
	local context = {
		identity = {
			name = fsm:get_name(),
			type = getmetatable(fsm) and getmetatable(fsm).type or "CALYX_FSM",
		},
		state = {
			current = fsm:get_state(),
			async = fsm.get_async_state and fsm:get_async_state() or "none",
		},
		capabilities = capabilities,
		mailbox = fsm.mailbox_stats and fsm:mailbox_stats() or nil,
		timestamp = ABI.clock:real_timestamp("%H:%M:%S"),
		tick = ABI.clock:now(),
	}

	return context
end

return LLM
