-- ============================================================================
-- calyx/fsm/utils.lua
-- CALYX FSM Shared Utilities
-- Formatters, helpers, and diagnostic tools
-- Lua 5.1.5 Compatible
-- ============================================================================

local ABI = require("abi")

local Utils = {}

-- ============================================================================
-- OBJECTIVE-C STYLE CALL FORMATTER
-- ============================================================================

function Utils.format_objc_call(method, params)
	params = params or {}
	local parts = {}

	if params.data then
		for k, v in pairs(params.data) do
			table.insert(parts, string.format("data.%s:%s", k, ABI.safe_tostring(v)))
		end
	end

	if params.options then
		for k, v in pairs(params.options) do
			table.insert(parts, string.format("options.%s:%s", k, ABI.safe_tostring(v)))
		end
	end

	if #parts > 0 then
		return string.format("%s(%s)", method, table.concat(parts, " "))
	else
		return string.format("%s()", method)
	end
end

-- ============================================================================
-- JSON-LIKE SERIALIZER (FOR DEBUGGING)
-- ============================================================================

function Utils.serialize_table(tbl, indent)
	indent = indent or 0
	local parts = {}
	local prefix = string.rep("  ", indent)

	if type(tbl) ~= "table" then
		return ABI.safe_tostring(tbl)
	end

	table.insert(parts, "{")

	for k, v in pairs(tbl) do
		local key_str
		if type(k) == "string" then
			key_str = string.format("%q", k)
		else
			key_str = tostring(k)
		end

		if type(v) == "table" then
			table.insert(parts, string.format("%s  %s: %s", prefix, key_str, Utils.serialize_table(v, indent + 1)))
		else
			table.insert(parts, string.format("%s  %s: %s", prefix, key_str, ABI.safe_tostring(v)))
		end
	end

	table.insert(parts, prefix .. "}")
	return table.concat(parts, "\n")
end

-- ============================================================================
-- CONTEXT DIFF (BEFORE/AFTER TRANSITION)
-- ============================================================================

function Utils.context_diff(before_ctx, after_ctx)
	local changes = {}

	if before_ctx.from ~= after_ctx.from then
		table.insert(changes, string.format("from: %s -> %s", before_ctx.from, after_ctx.from))
	end

	if before_ctx.to ~= after_ctx.to then
		table.insert(changes, string.format("to: %s -> %s", before_ctx.to, after_ctx.to))
	end

	if before_ctx.event ~= after_ctx.event then
		table.insert(changes, string.format("event: %s -> %s", before_ctx.event, after_ctx.event))
	end

	if #changes > 0 then
		return table.concat(changes, ", ")
	else
		return "no changes"
	end
end

-- ============================================================================
-- SAFE TABLE MERGE
-- ============================================================================

function Utils.merge_tables(target, source, overwrite)
	target = target or {}
	source = source or {}

	for k, v in pairs(source) do
		if overwrite or target[k] == nil then
			if type(v) == "table" and type(target[k]) == "table" then
				target[k] = Utils.merge_tables(target[k], v, overwrite)
			else
				target[k] = v
			end
		end
	end

	return target
end

-- ============================================================================
-- RANDOM ID GENERATOR (Lua 5.1.5 compatible)
-- ============================================================================

function Utils.generate_id(prefix, length)
	prefix = prefix or "id"
	length = length or 8

	local chars = "0123456789abcdef"
	local id = {}

	math.randomseed(os.time())
	math.random() -- Seed properly

	for i = 1, length do
		local rand = math.random(1, #chars)
		table.insert(id, string.sub(chars, rand, rand))
	end

	return string.format("%s_%s", prefix, table.concat(id))
end

return Utils
