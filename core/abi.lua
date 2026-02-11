-- ============================================================================
-- calyx/fsm/abi.lua
-- CALYX FSM ABI Constants
-- Shared state definitions, error types, and lifecycle markers
-- Lua 5.1.5 Compatible
-- PRODUCTION HARDENED: Deterministic clock + standardized Result format
-- ============================================================================

local ABI = {}

-- ============================================================================
-- DETERMINISTIC CLOCK
-- ============================================================================

ABI.clock = {
	tick = 0,
	real_clock = os.date, -- Injected for testing
}

function ABI.clock:advance()
	self.tick = self.tick + 1
	return self.tick
end

function ABI.clock:now()
	return self.tick
end

function ABI.clock:reset(start_tick)
	self.tick = start_tick or 0
end

function ABI.clock:real_timestamp(format)
	format = format or "%H:%M:%S"
	return self.real_clock(format)
end

-- ============================================================================
-- STATE CONSTANTS
-- ============================================================================

ABI.STATES = {
	-- Core state markers
	NONE = "none",
	ASYNC = "async",

	-- Transition phase suffixes
	SUFFIXES = {
		LEAVE_WAIT = "_LEAVE_WAIT",
		ENTER_WAIT = "_ENTER_WAIT",
	},

	-- Lifecycle states
	INIT = "init",
	IDLE = "idle",
	RUNNING = "running",
	PAUSED = "paused",
	STOPPED = "stopped",
	ERROR = "error",
	FINAL = "final",
}

-- ============================================================================
-- ERROR CATEGORIES
-- ============================================================================

ABI.ERRORS = {
	-- Transition errors
	INVALID_TRANSITION = "invalid_transition",
	TRANSITION_IN_PROGRESS = "transition_in_progress",
	CANCELLED_BEFORE = "cancelled_before",
	CANCELLED_LEAVE = "cancelled_leave",
	INVALID_STAGE = "invalid_stage",

	-- Context errors
	NO_CONTEXT = "no_context",
	CONTEXT_LOST = "context_lost",
	NO_ACTIVE_TRANSITION = "no_active_transition",

	-- Mailbox errors
	NO_MAILBOX = "no_mailbox",
	QUEUE_FULL = "queue_full",
	ALREADY_PROCESSING = "already_processing",

	-- Validation errors
	INVALID_EVENT_NAME = "invalid_event_name",
	EVENT_COLLISION = "event_collision",
	MISSING_EVENT = "missing_event",
	MISSING_TARGET = "missing_target",

	-- Resource errors
	NO_MEMORY = "no_memory",
	GC_FAILED = "gc_failed",
}

-- ============================================================================
-- EVENT VALIDATION PATTERNS
-- ============================================================================

ABI.PATTERNS = {
	-- Event name must start with letter/underscore, then letters/numbers/_.-
	EVENT_NAME = "^[%a_][%w_%.%-]*$",

	-- State name validation (similar constraints)
	STATE_NAME = "^[%a_][%w_%.%-]*$",

	-- Callback name pattern (onbefore*, onleave*, onenter*, onafter*)
	CALLBACK = "^on(before|leave|enter|after)[%a_][%w_%.%-]*$",
}

-- ============================================================================
-- RESERVED NAMES
-- ============================================================================

ABI.RESERVED = {
	-- Core methods
	"send",
	"resume",
	"current",
	"_context",
	"mailbox",
	"process_mailbox",
	"clear_mailbox",
	"force_gc_cleanup",
	"mailbox_stats",
	"set_mailbox_size",
	"can",
	"is",
	"asyncState",
	"events",
	"currentTransitioningEvent",
	"_complete",
	"name",

	-- Lifecycle callbacks
	"onbefore",
	"onleave",
	"onenter",
	"onafter",
	"onstatechange",

	-- Internal
	"__index",
	"__newindex",
	"__metatable",
}

-- ============================================================================
-- METADATA
-- ============================================================================

ABI.VERSION = "0.4.0"
ABI.NAME = "calyx-fsm"
ABI.SPEC = "CALYX Finite State Machine Specification v1"

-- ============================================================================
-- UTILITY: Safe string conversion for error messages
-- ============================================================================

function ABI.safe_tostring(value)
	local success, result = pcall(tostring, value)
	if success then
		return result
	end
	return "[UNPRINTABLE]"
end

-- ============================================================================
-- STANDARDIZED RESULT FORMAT
-- All operations return Result tables (never multi-return for errors)
-- ============================================================================

function ABI.error_result(error_code, message, details)
	return {
		ok = false,
		code = error_code,
		message = message or error_code,
		details = details or {},
		tick = ABI.clock:now(),
		-- trace omitted by default (add via debug mode)
	}
end

function ABI.success_result(data)
	return {
		ok = true,
		data = data or {},
		tick = ABI.clock:now(),
	}
end

-- ============================================================================
-- LEGACY COMPATIBILITY (DEPRECATED)
-- Old multi-return format - will be removed in 1.0
-- ============================================================================

function ABI.error_response(error_type, details)
	-- Log deprecation warning once
	if not ABI._warned_multi_return then
		print("[DEPRECATED] error_response uses multi-return. Use error_result instead.")
		ABI._warned_multi_return = true
	end

	return false, ABI.error_result(error_type, nil, details)
end

function ABI.success_response(data)
	return true, ABI.success_result(data)
end

return ABI
