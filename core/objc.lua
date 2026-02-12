-- ============================================================================
-- lua-fsm-objC.objc (FIXED - Proper upvalue ordering)
-- ============================================================================
-- core/objc.lua (REFACTORED - Closure Pattern)
local ABI = require("abi")
local Core = require("core")
local Utils = require("utils")

local ObjCFSM = {}

function ObjCFSM.create(opts)
	opts = opts or {}

	-- ============================================================
	-- PRIVATE STATE (Hidden in Closure - LLM Cannot Touch)
	-- ============================================================
	local current_state = opts.initial or ABI.STATES.IDLE
	local transition_map = Core.build_transition_map(opts.events or {})
	local fsm_name = opts.name or string.format("fsm_%x", math.floor(math.random() * 0xFFFFFF))
	local debug_mode = opts.debug or false
	local _ = opts.strict_mode -- Mark as used to silence warning

	-- Callback storage (private)
	local callbacks = {}
	if opts.callbacks then
		for k, v in pairs(opts.callbacks) do
			callbacks[k] = v
		end
	end

	-- ============================================================
	-- PUBLIC API (Define FIRST so it's available as upvalue)
	-- ============================================================
	local public_api = {}

	-- ============================================================
	-- PRIVATE HELPER FUNCTIONS
	-- ============================================================

	local function can_transition_internal(event_name)
		return Core.can_transition(transition_map, event_name, current_state)
	end

	local function execute_transition(event_name, data, options)
		local can, target = can_transition_internal(event_name)
		if not can then
			return ABI.error_result(
				ABI.ERRORS.INVALID_TRANSITION,
				string.format("Cannot transition from '%s' via '%s'", current_state, event_name),
				{ current = current_state, event = event_name }
			)
		end

		local ctx = Core.create_context(event_name, current_state, target, data, options)

		-- BEFORE callback
		if callbacks["onbefore" .. event_name] then
			local result = callbacks["onbefore" .. event_name](public_api, ctx)
			if result == false then
				return ABI.error_result(
					ABI.ERRORS.CANCELLED_BEFORE,
					string.format("Transition cancelled in onbefore%s", event_name),
					{ event = event_name, context = ctx }
				)
			end
		end

		-- LEAVE callback
		if callbacks["onleave" .. ctx.from] then
			local result = callbacks["onleave" .. ctx.from](public_api, ctx)
			if result == false then
				return ABI.error_result(
					ABI.ERRORS.CANCELLED_LEAVE,
					string.format("Transition cancelled in onleave%s", ctx.from),
					{ event = event_name, context = ctx }
				)
			end
		end

		-- Update state
		current_state = target
		public_api.current = current_state -- Update current field
		ABI.clock:advance() -- Advance clock on successful transition

		-- ENTER callback
		if callbacks["onenter" .. ctx.to] then
			callbacks["onenter" .. ctx.to](public_api, ctx)
		end

		-- AFTER callback
		if callbacks["onafter" .. event_name] then
			callbacks["onafter" .. event_name](public_api, ctx)
		end

		-- State change notification
		if callbacks.onstatechange then
			callbacks.onstatechange(public_api, ctx)
		end

		return ABI.success_result(ctx)
	end

	-- ============================================================
	-- WRAP CALLBACKS TO UPDATE CURRENT FIELD
	-- (Define AFTER public_api but BEFORE final API assembly)
	-- ============================================================

	-- Store original onstatechange
	local original_onstatechange = callbacks.onstatechange

	-- Wrap it
	callbacks.onstatechange = function(fsm, ctx)
		public_api.current = ctx.to
		if original_onstatechange then
			original_onstatechange(fsm, ctx)
		end
	end

	-- ============================================================
	-- BUILD PUBLIC API
	-- ============================================================

	-- Read-only state access (compatibility with both styles)
	public_api.current = current_state

	function public_api.get_state()
		return current_state
	end

	function public_api.get_name()
		return fsm_name
	end

	-- Predicate checks
	function public_api.can(event_name)
		return can_transition_internal(event_name)
	end

	function public_api.is(state_name)
		return current_state == state_name
	end

	-- ============================================================================
	-- lua-fsm-objC.mailbox (FIXED - Event method creation)
	-- ============================================================================

	-- ============================================================
	-- DYNAMIC EVENT METHODS + CAPABILITY LIST
	-- ============================================================
	local caps = {}

	for _, ev in ipairs(opts.events or {}) do
		local event_name = ev.name
		caps[#caps + 1] = event_name

		public_api[event_name] = function(params)
			params = params or {}
			if debug_mode then
				print("[CALL] " .. utils.format_objc_call(event_name, params))
			end
			return execute_transition(event_name, params.data, params.options)
		end
	end

	table.sort(caps)
	public_api.capabilities = caps

	-- Export constants (read-only)
	public_api.ASYNC = ABI.STATES.ASYNC
	public_api.NONE = ABI.STATES.NONE
	public_api.STATES = ABI.STATES

	-- ============================================================
	-- FREEZE PUBLIC API (Prevent Method Injection)
	-- ============================================================

	local frozen = {}
	local mt = {
		__index = public_api,
		__newindex = function(t, k, v)
			-- Allow setting 'current' field
			if k == "current" then
				rawset(t, k, v)
				return
			end
			error(string.format("Cannot modify FSM public API: attempted to set '%s'", tostring(k)), 2)
		end,
		__metatable = {
			protected = true,
			type = "CALYX_OBJC_FSM",
			version = ABI.VERSION,
		},
	}
	setmetatable(frozen, mt)

	-- Initialize current field
	frozen.current = current_state

	return frozen
end

return ObjCFSM
