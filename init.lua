-- ============================================================================
-- init.lua
-- CALYX BOOTLOADER
-- Deterministic environment hardening + bundle validation
-- PRODUCTION HARDENED: Frozen API + unified create()
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. LOAD HARDENED RUNTIME
-- ---------------------------------------------------------------------------
local hardened = require("hardened")

-- ---------------------------------------------------------------------------
-- 2. ENABLE SEMANTIC FIREWALL
-- Prevents accidental global leakage after this point.
-- ---------------------------------------------------------------------------
hardened.enable_strict_mode()

-- ---------------------------------------------------------------------------
-- 3. DEFINE BUNDLE ABI (SHAPE CONTRACT)
-- Updated to match the unified CALYX FSM API
-- ---------------------------------------------------------------------------
local BUNDLE_SCHEMA = {
	-- Creation APIs
	create_object_fsm = "function",
	create_mailbox_fsm = "function",

	-- Shared constants
	ASYNC = "string",
	NONE = "string",
	STATES = "table",
	ERRORS = "table",

	-- Version info
	VERSION = "string",
	NAME = "string",
	SPEC = "string",

	-- Diagnostics (optional, but should exist)
	diagnostics = "table",
}

-- ---------------------------------------------------------------------------
-- 4. LOAD BUNDLE VIA MODULE SYSTEM
-- `require` guarantees single execution and completed initialization.
-- ---------------------------------------------------------------------------
local ok, bundle = pcall(require, "calyx_bundle")

if not ok then
	error("[FATAL] Failed to load calyx_bundle: " .. tostring(bundle))
end

-- ---------------------------------------------------------------------------
-- 5. VALIDATE BUNDLE SHAPE (ABI CHECK)
-- This is the "no more lies" moment.
-- ---------------------------------------------------------------------------
local ok_shape, shape_err = pcall(function()
	hardened.validate_shape(bundle, BUNDLE_SCHEMA, "calyx_bundle")
end)

if not ok_shape then
	error("[FATAL] Bundle API mismatch: " .. tostring(shape_err))
end

-- ---------------------------------------------------------------------------
-- 6. CREATE UNIFIED API WITH ROUTING
-- ---------------------------------------------------------------------------

-- Unified create() function with mode selection
local function create(opts)
	opts = opts or {}

	local kind = opts.kind or opts.mode

	if not kind then
		-- Default to objc (sync) in permissive mode, error in strict mode
		if opts.strict_mode then
			error("[FATAL] opts.kind or opts.mode required in strict mode. Use 'objc' or 'mailbox'")
		end
		kind = "objc"
	end

	if kind == "mailbox" then
		return bundle.create_mailbox_fsm(opts)
	elseif kind == "objc" then
		return bundle.create_object_fsm(opts)
	else
		error(string.format("[FATAL] Unknown FSM kind '%s'. Use 'objc' or 'mailbox'", kind))
	end
end

-- ---------------------------------------------------------------------------
-- 7. BUILD FROZEN PUBLIC API
-- ---------------------------------------------------------------------------

local api = {
	-- Unified entrypoint
	create = create,

	-- Explicit constructors
	create_object_fsm = bundle.create_object_fsm,
	create_mailbox_fsm = bundle.create_mailbox_fsm,

	-- Shared constants
	ASYNC = bundle.ASYNC,
	NONE = bundle.NONE,
	STATES = bundle.STATES,
	ERRORS = bundle.ERRORS,

	-- Version info
	VERSION = bundle.VERSION,
	NAME = bundle.NAME,
	SPEC = bundle.SPEC,

	-- Diagnostics (debug mode only)
	diagnostics = bundle.diagnostics,
}

-- ---------------------------------------------------------------------------
-- 8. FREEZE API SURFACE (IMMUTABLE PUBLIC INTERFACE)
-- ---------------------------------------------------------------------------

local frozen_api = {}
local api_metatable = {
	__index = api,
	__newindex = function(t, k, v)
		error(string.format("Cannot modify frozen CALYX API: attempted to set '%s'", tostring(k)), 2)
	end,
	__metatable = {
		protected = true,
		type = "CALYX_API",
		version = bundle.VERSION,
		frozen = true,
		immutable = true,
	},
}

setmetatable(frozen_api, api_metatable)

-- ---------------------------------------------------------------------------
-- 9. BOOT DIAGNOSTICS
-- ---------------------------------------------------------------------------

print(string.format("[LAB_INIT] Hardened environment verified. Bundle ABI locked."))
print(string.format("[LAB_INIT] CALYX FSM %s loaded", bundle.VERSION or "unknown"))
print(string.format("[LAB_INIT] API frozen (immutable)"))
print(string.format("[LAB_INIT] Available: create(opts), create_object_fsm(opts), create_mailbox_fsm(opts)"))
print(string.format("[LAB_INIT] Modes: opts.kind='objc' (sync) or 'mailbox' (async+queue)"))

-- ---------------------------------------------------------------------------
-- 10. RETURN FROZEN API
-- ---------------------------------------------------------------------------

return frozen_api
