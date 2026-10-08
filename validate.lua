-- ============================================================================
-- validate.lua
-- CALYX Schema Validation & ABI Shape Enforcement
-- Lua 5.1.5 Compatible
-- ============================================================================
--
-- KNOWN: NO CALLERS (recon 7/B13). Nothing in the repo requires this module.
-- Do not assume the running system validates configs through it -- it does
-- not. bundle.create() (init.lua:70) goes straight to core/objc.lua:11 /
-- core/mailbox.lua:11 with no schema validation at all, which is why
-- breakage_suite/test_invalid_fsm_schema.lua fails 10 of 24 cases.
--
-- Not wired up because doing so would start rejecting FSM configs that
-- currently load = a behavior/feature change.
--
-- KNOWN: `hardened` is required below but never used in this file.
-- ============================================================================

local hardened = require("hardened") -- KNOWN: unused in this module (recon 7/B12)
local ABI = require("core.abi")

-- KNOWN: this used to call `Core.warn(...)`, but `Core` is never declared in
-- this file, so the unreferenced-initial-state branch was a guaranteed
-- nil-global call. Mirrors Core.warn's output format (core/core.lua:19)
-- exactly so log output is unchanged. (recon 7/B11)
local function warn(message, category)
	print(string.format("[WARN %s] %s", string.upper(category or "general"), message))
end

local Validate = {}

-- ============================================================================
-- TYPE VALIDATION
-- ============================================================================

function Validate.is_string(value)
	return type(value) == "string"
end

function Validate.is_table(value)
	return type(value) == "table"
end

function Validate.is_function(value)
	return type(value) == "function"
end

function Validate.is_boolean(value)
	return type(value) == "boolean"
end

function Validate.is_number(value)
	return type(value) == "number"
end

function Validate.is_nil(value)
	return value == nil
end

-- ============================================================================
-- SHAPE VALIDATION (Schema Enforcement)
-- ============================================================================

function Validate.validate_shape(obj, schema, context)
	context = context or "object"

	if not Validate.is_table(obj) then
		error(string.format("[SHAPE] %s: expected table, got %s", context, type(obj)))
	end

	if not Validate.is_table(schema) then
		error("[SHAPE] Schema must be a table")
	end

	for key, expected_type in pairs(schema) do
		local value = obj[key]
		local actual_type = type(value)

		-- Handle union types (e.g., "string|nil")
		if type(expected_type) == "string" and string.find(expected_type, "|") then
			local types = {}
			for t in string.gmatch(expected_type, "[%a_]+") do
				table.insert(types, t)
			end

			local match = false
			for i = 1, #types do
				if actual_type == types[i] then
					match = true
					break
				end
			end

			if not match then
				error(string.format("[SHAPE] %s.%s: expected %s, got %s", context, key, expected_type, actual_type))
			end

		-- Handle single type
		elseif actual_type ~= expected_type then
			error(string.format("[SHAPE] %s.%s: expected %s, got %s", context, key, expected_type, actual_type))
		end
	end

	return true
end

-- ============================================================================
-- FSM SCHEMA VALIDATION
-- ============================================================================

function Validate.validate_fsm_config(config)
	local schema = {
		name = "string|nil",
		initial = "string|nil",
		events = "table",
		callbacks = "table|nil",
		strict_mode = "boolean|nil",
		mailbox_size = "number|nil",
	}

	Validate.validate_shape(config, schema, "FSM.config")

	-- Validate events array
	for i, ev in ipairs(config.events) do
		local event_schema = {
			name = "string",
			to = "string",
			from = "string|table|nil",
			wildcard = "boolean|nil",
		}

		Validate.validate_shape(ev, event_schema, string.format("FSM.event[%d]", i))

		-- Validate event name format
		if not string.match(ev.name, ABI.PATTERNS.EVENT_NAME) then
			error(
				string.format("[SCHEMA] Event[%d] name '%s' must match pattern %s", i, ev.name, ABI.PATTERNS.EVENT_NAME)
			)
		end

		-- Validate state names in 'from' array
		if type(ev.from) == "table" then
			for j, state in ipairs(ev.from) do
				if type(state) == "string" and state ~= "*" then
					if not string.match(state, ABI.PATTERNS.STATE_NAME) then
						error(
							string.format(
								"[SCHEMA] Event[%d].from[%d] state '%s' must match pattern %s",
								i,
								j,
								state,
								ABI.PATTERNS.STATE_NAME
							)
						)
					end
				end
			end
		elseif type(ev.from) == "string" and ev.from ~= "*" then
			if not string.match(ev.from, ABI.PATTERNS.STATE_NAME) then
				error(
					string.format(
						"[SCHEMA] Event[%d].from state '%s' must match pattern %s",
						i,
						ev.from,
						ABI.PATTERNS.STATE_NAME
					)
				)
			end
		end
	end

	-- Validate initial state
	if config.initial then
		local found = false
		for _, ev in ipairs(config.events) do
			if
				ev.from == config.initial
				or (type(ev.from) == "table" and table.concat(ev.from, ","):find(config.initial))
			then
				found = true
				break
			end
			if ev.to == config.initial then
				found = true
				break
			end
		end

		if
			not found
			and config.initial ~= ABI.STATES.IDLE
			and config.initial ~= ABI.STATES.NONE
			and config.initial ~= "none"
		then
			warn("Initial state '" .. config.initial .. "' not referenced in any event", "validation")
		end
	end

	return true
end

-- ============================================================================
-- BUNDLE ABI VALIDATION
-- ============================================================================

function Validate.validate_bundle_abi(bundle)
	local required_exports = {
		create_object_fsm = "function",
		create_mailbox_fsm = "function",
		ASYNC = "string",
		STATES = "table",
	}

	Validate.validate_shape(bundle, required_exports, "CALYX.Bundle")

	-- Validate STATES structure
	local required_states = {
		NONE = "string",
		ASYNC = "string",
	}

	Validate.validate_shape(bundle.STATES, required_states, "CALYX.Bundle.STATES")

	return true
end

-- ============================================================================
-- CONTEXT VALIDATION
-- ============================================================================

function Validate.validate_context(ctx)
	local schema = {
		event = "string",
		from = "string",
		to = "string",
		data = "table|nil",
		options = "table|nil",
		timestamp = "string|nil",
	}

	return Validate.validate_shape(ctx, schema, "FSM.context")
end

-- ============================================================================
-- SAFE TABLE COPY
-- ============================================================================

function Validate.safe_copy(tbl)
	if type(tbl) ~= "table" then
		return tbl
	end

	local copy = {}
	for k, v in pairs(tbl) do
		if type(v) == "table" then
			copy[k] = Validate.safe_copy(v)
		else
			copy[k] = v
		end
	end

	return copy
end

-- ============================================================================
-- EXPORT
-- ============================================================================

return Validate
