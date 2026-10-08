-- ============================================================================
-- core/core.lua
-- CALYX FSM Core Kernel
-- Shared transition logic, validation, and callback dispatch
-- Lua 5.1.5 Compatible
-- ============================================================================
--
-- READ THIS BEFORE TRUSTING ANYTHING BELOW
--
-- This module is SPLIT. Only four functions are actually live on the shipped
-- path (both FSMs in core/objc.lua and core/mailbox.lua call exactly these):
--
--   LIVE  Core.build_transition_map  (:147)  Core.can_transition   (:187)
--   LIVE  Core.create_context        (:204)  Core.warn             (:19)
--
-- Everything else below -- lock_metatable, check_event_collision,
-- validate_event_name, validate_state_name, _dispatch_callback,
-- create_base_fsm, :_transition, :_complete_transition, :can, :is, and the
-- ASYNC/NONE/STATES re-exports -- is DEAD CODE. core/objc.lua and
-- core/mailbox.lua are closure-based and re-implement transition execution
-- and freezing themselves. Nothing calls the versions here.
--
-- Two consequences that used to read as guarantees but are not enforced:
--
--   1. NO event/state name validation runs on any shipped path. ABI.PATTERNS
--      (:102-109) is only consulted by Core.validate_event_name, which is
--      never called. The ONLY live checks are the two asserts in
--      build_transition_map (:152-153). See breakage_suite/
--      test_invalid_fsm_schema.lua, which fails 10/24 cases against this.
--
--   2. ABI.RESERVED (core/abi.lua:115-146) is NOT enforced. The only enforcer
--      is Core.check_event_collision, which is dead. So an event literally
--      named "send" will silently overwrite the mailbox FSM's own send()
--      (defined core/mailbox.lua:240, reassigned in the event loop at :382).
--
-- KNOWN: dead validators + unenforced reserved names (recon 7/D1,D2); kept,
-- not deleted, so the intended design stays readable. Not fixed here because
-- wiring them in changes FSM construction behavior = a feature change.
--
-- The frozen-proxy guards that DO run are core/objc.lua:180-187 and
-- core/mailbox.lua:405-411 -- not lock_metatable below.
-- ============================================================================

local ABI = require("abi")

local Core = {}
Core.__index = Core

-- ============================================================================
-- WARNING SYSTEM (Lua 5.1.5 compatible)
-- LIVE (called by hardening/validation paths) but see note: no FSM code path
-- calls it today -- core/objc.lua and core/mailbox.lua return Result tables
-- instead of printing.
-- ============================================================================

function Core.warn(message, category)
	category = ABI.safe_tostring(category or "general")
	message = ABI.safe_tostring(message)
	print(string.format("[WARN %s] %s", string.upper(category), message))
end

-- ============================================================================
-- METATABLE PROTECTION (ENHANCED)
-- DEAD CODE -- never called on any shipped path.
-- The freeze that actually runs is core/objc.lua:178-194 and
-- core/mailbox.lua:403-418. test_hardened.lua:283 passes because of THOSE,
-- not because of this function.
-- ============================================================================

-- KNOWN: dead (recon 1.5/8.7). Kept for the intended design; not wired
-- because the closure FSMs already freeze themselves and doing both would
-- change the error text callers depend on.

function Core.lock_metatable(fsm, protection_tag)
	local mt = getmetatable(fsm)
	if mt then
		-- Prevent getmetatable/setmetatable tampering
		mt.__metatable = protection_tag
			or {
				protected = true,
				type = "CALYX_FSM",
				version = ABI.VERSION,
				immutable = true,
			}

		-- Prevent new field creation
		mt.__newindex = function(t, k, v)
			-- Whitelist of mutable fields
			local mutable = {
				current = true,
				asyncState = true,
				_context = true,
				currentTransitioningEvent = true,
			}

			if mutable[k] then
				rawset(t, k, v)
			else
				-- FIX: Use consistent error message that test expects
				error(string.format("Cannot modify FSM: attempted to set field '%s'", tostring(k)), 2)
			end
		end
	end
	return fsm
end

-- ============================================================================
-- EVENT NAME VALIDATION
-- DEAD CODE -- never called. ABI.PATTERNS.EVENT_NAME is therefore
-- NOT enforced on any shipped path (recon 7/D2).
-- ============================================================================

function Core.validate_event_name(name, strict_mode)
	if type(name) ~= "string" or name == "" then
		local msg = "Event name must be a non-empty string, got: " .. type(name)
		if strict_mode then
			error(msg, 2)
		else
			Core.warn(msg, "validation")
			return false
		end
	end

	if not string.match(name, ABI.PATTERNS.EVENT_NAME) then
		local msg =
			string.format("Invalid event name format: '%s'. Must match pattern: %s", name, ABI.PATTERNS.EVENT_NAME)
		if strict_mode then
			error(msg, 2)
		else
			Core.warn(msg, "validation")
			return false
		end
	end

	return true
end

-- ============================================================================
-- STATE NAME VALIDATION
-- DEAD CODE -- only caller is create_base_fsm (:248), itself dead.
-- ============================================================================

function Core.validate_state_name(name, strict_mode)
	if type(name) ~= "string" or name == "" then
		local msg = "State name must be a non-empty string, got: " .. type(name)
		if strict_mode then
			error(msg, 2)
		else
			Core.warn(msg, "validation")
			return false
		end
	end

	if not string.match(name, ABI.PATTERNS.STATE_NAME) then
		local msg =
			string.format("Invalid state name format: '%s'. Must match pattern: %s", name, ABI.PATTERNS.STATE_NAME)
		if strict_mode then
			error(msg, 2)
		else
			Core.warn(msg, "validation")
			return false
		end
	end

	return true
end

-- ============================================================================
-- EVENT COLLISION DETECTION
-- DEAD CODE -- never called.
--
-- This is the ONLY place ABI.RESERVED is enforced. Because it is dead,
-- reserved event names are silently accepted and can clobber FSM methods
-- (e.g. an event named "send" overwrites core/mailbox.lua:240).
-- KNOWN: unenforced reserved names (recon 7/D1); not wired because doing so
-- would make previously-accepted FSM configs start failing = feature change.
-- ============================================================================

function Core.check_event_collision(fsm_instance, name)
	-- Check reserved names
	for i = 1, #ABI.RESERVED do
		if name == ABI.RESERVED[i] then
			error("Event name '" .. name .. "' is reserved and cannot be used", 2)
		end
	end

	-- Check existing methods
	if fsm_instance[name] and type(fsm_instance[name]) == "function" then
		Core.warn("Event name '" .. name .. "' collides with existing FSM method. Skipping creation.", "collision")
		return false
	end

	return true
end

-- ============================================================================
-- TRANSITION MAP BUILDER
-- ============================================================================

function Core.build_transition_map(events)
	local map = {}

	for _, ev in ipairs(events) do
		-- Validate event structure
		assert(type(ev.name) == "string", "event.name must be string")
		assert(ev.to ~= nil, "event.to is required")

		-- Initialize event entry
		map[ev.name] = {
			name = ev.name,
			to = ev.to,
			from_map = {},
		}

		-- Process 'from' states
		if ev.from then
			local from_states = type(ev.from) == "table" and ev.from or { ev.from }
			for _, st in ipairs(from_states) do
				if st == "*" then
					map[ev.name].wildcard = true
				else
					map[ev.name].from_map[st] = true
				end
			end
		end

		-- Wildcard support (explicit or implied)
		if ev.wildcard then
			map[ev.name].wildcard = true
		end
	end

	return map
end

-- ============================================================================
-- CAN TRANSITION CHECK
-- ============================================================================

function Core.can_transition(transition_map, event_name, current_state)
	local ev = transition_map[event_name]
	if not ev then
		return false, nil
	end

	if ev.from_map[current_state] or ev.wildcard then
		return true, ev.to
	end

	return false, nil
end

-- ============================================================================
-- CONTEXT CREATOR
-- ============================================================================

function Core.create_context(event_name, from_state, to_state, data, options)
	return {
		event = event_name,
		from = from_state,
		to = to_state,
		data = data or {},
		options = options or {},
		tick = ABI.clock:now(),
	}
end

-- ============================================================================
-- CALLBACK DISPATCHER (PRIVATE - NOT EXPOSED IN PUBLIC API)
-- DEAD CODE -- only caller is :_transition (:308), itself dead.
-- The live dispatch is inline in core/objc.lua:57-98 and
-- core/mailbox.lua:164-200 / :90-105.
-- ============================================================================

function Core._dispatch_callback(fsm, callback_type, phase, context)
	-- Construct callback name (e.g., onbeforeStart, onleaveIDLE, onenterRUNNING)
	local callback_name

	if phase == "before" then
		callback_name = "onbefore" .. context.event
	elseif phase == "leave" then
		callback_name = "onleave" .. context.from
	elseif phase == "enter" then
		callback_name = "onenter" .. context.to
	elseif phase == "after" then
		callback_name = "onafter" .. context.event
	else
		callback_name = phase -- Direct callback name
	end

	local callback = fsm[callback_name]
	if callback then
		-- Always use (fsm, context) signature for consistency
		return callback(fsm, context)
	end

	return nil
end

-- ============================================================================
-- FSM INSTANCE CREATOR (BASE)
-- DEAD CODE -- never called. Superseded by the closure-based
-- ObjCFSM.create (core/objc.lua:11) and MailboxFSM.create (core/mailbox.lua:11).
-- ============================================================================

function Core.create_base_fsm(opts)
	opts = opts or {}

	-- Validate initial state
	if opts.initial then
		Core.validate_state_name(opts.initial, opts.strict_mode)
	end

	local fsm = {
		-- Identity
		name = opts.name or string.format("fsm_%x", math.floor(math.random() * 0xFFFFFF)),

		-- State
		current = opts.initial or ABI.STATES.IDLE,

		-- Transition system
		transitions = Core.build_transition_map(opts.events or {}),

		-- Callback storage
		callbacks = {},

		-- Configuration
		strict_mode = opts.strict_mode or false,
		debug = opts.debug or false,

		-- Metadata
		created_at = ABI.clock:now(),
		version = ABI.VERSION,
	}

	-- Apply callbacks
	if opts.callbacks then
		for k, v in pairs(opts.callbacks) do
			fsm[k] = v
		end
	end

	setmetatable(fsm, Core)
	return fsm
end

-- ============================================================================
-- CORE TRANSITION METHOD (RETURNS RESULT TABLE)
-- DEAD CODE -- never called. See core/objc.lua:44 and core/mailbox.lua:120.
-- ============================================================================

function Core:_transition(event_name, data, options)
	-- Check if transition is valid
	local can, target = Core.can_transition(self.transitions, event_name, self.current)
	if not can then
		return ABI.error_result(
			ABI.ERRORS.INVALID_TRANSITION,
			string.format("Cannot transition from '%s' via '%s'", self.current, event_name),
			{ current = self.current, event = event_name }
		)
	end

	-- Create context
	local ctx = Core.create_context(event_name, self.current, target, data, options)

	-- BEFORE callback
	local before_result = Core._dispatch_callback(self, "callback", "before", ctx)
	if before_result == false then
		return ABI.error_result(
			ABI.ERRORS.CANCELLED_BEFORE,
			string.format("Transition cancelled in onbefore%s", event_name),
			{ event = event_name, context = ctx }
		)
	end

	-- LEAVE callback
	local leave_result = Core._dispatch_callback(self, "callback", "leave", ctx)
	if leave_result == false then
		return ABI.error_result(
			ABI.ERRORS.CANCELLED_LEAVE,
			string.format("Transition cancelled in onleave%s", ctx.from),
			{ event = event_name, context = ctx }
		)
	end

	-- Store context for async continuation
	ctx._requires_async = leave_result == ABI.STATES.ASYNC

	return ABI.success_result({
		context = ctx,
		target = target,
		is_async = leave_result == ABI.STATES.ASYNC,
	})
end

-- ============================================================================
-- COMPLETE TRANSITION (RETURNS RESULT TABLE)
-- DEAD CODE -- never called.
-- ============================================================================

function Core:_complete_transition(ctx)
	-- Update state
	self.current = ctx.to

	-- ENTER callback
	Core._dispatch_callback(self, "callback", "enter", ctx)

	-- AFTER callback
	Core._dispatch_callback(self, "callback", "after", ctx)

	-- State change notification
	if self.onstatechange then
		self.onstatechange(self, ctx)
	end

	return ABI.success_result(ctx)
end

-- ============================================================================
-- CAN EVENT CHECK
-- DEAD CODE -- this metatable method is never installed. The closure FSMs
-- define their own can() (core/objc.lua:135, core/mailbox.lua:222).
-- ============================================================================

function Core:can(event_name)
	return Core.can_transition(self.transitions, event_name, self.current)
end

-- ============================================================================
-- STATE CHECK
-- DEAD CODE -- same as above; see core/objc.lua:139.
-- ============================================================================

function Core:is(state_name)
	return self.current == state_name
end

-- ============================================================================
-- EXPORT CONSTANTS (READ-ONLY)
-- DEAD CODE -- calyx_bundle.lua:1969 re-exports ABI.STATES directly, not
-- these. Kept so `local Core = require("core")` still yields the constants.
-- ============================================================================

Core.ASYNC = ABI.STATES.ASYNC
Core.NONE = ABI.STATES.NONE
Core.STATES = ABI.STATES

-- Private API marker - DO NOT EXPOSE VIA PUBLIC CALYX API
Core._PRIVATE = true

return Core
