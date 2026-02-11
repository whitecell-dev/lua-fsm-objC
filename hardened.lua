-- ============================================================================
-- hardened.lua
-- Runtime Hardening Layer for Lua FSM Systems
-- Provides semantic firewall against common Lua footguns
-- ============================================================================
--
-- PURPOSE: Make Lua's dynamic runtime predictable and safe for:
-- - Long-lived FSM event loops
-- - Message-passing actor systems
-- - Asynchronous coroutine workflows
-- - Multi-module bundle orchestration
--
-- USAGE:
--   local hardened = require("hardened")
--   hardened.enable_strict_mode()
--   local count = hardened.safe_len(queue)
--   if hardened.float_eq(start + duration, os.clock()) then ... end
--
-- ============================================================================

local M = {}

-- ============================================================================
-- 1. STRICT MODE: GLOBAL VARIABLE PROTECTION
-- ============================================================================

local _strict_enabled = false
local _allowed_globals = {
	-- Standard Lua globals that should be allowed
	_G = true,
	_VERSION = true,
	assert = true,
	collectgarbage = true,
	dofile = true,
	error = true,
	getmetatable = true,
	ipairs = true,
	load = true,
	loadfile = true,
	next = true,
	pairs = true,
	pcall = true,
	print = true,
	rawequal = true,
	rawget = true,
	rawset = true,
	require = true,
	select = true,
	setmetatable = true,
	tonumber = true,
	tostring = true,
	type = true,
	xpcall = true,
	-- Standard libraries
	coroutine = true,
	debug = true,
	io = true,
	math = true,
	os = true,
	package = true,
	string = true,
	table = true,
	utf8 = true,
}

function M.enable_strict_mode()
	if _strict_enabled then
		return
	end

	_strict_enabled = true

	local mt = getmetatable(_G)
	if mt == nil then
		mt = {}
		setmetatable(_G, mt)
	end

	mt.__declared = {}

	-- Mark existing globals as declared
	for k, _ in pairs(_G) do
		mt.__declared[k] = true
	end

	-- Allow standard globals
	for k, _ in pairs(_allowed_globals) do
		mt.__declared[k] = true
	end

	mt.__newindex = function(t, name, value)
		if not mt.__declared[name] then
			local info = debug.getinfo(2, "Sl")
			error(
				string.format(
					"[HARDENED] Attempt to create global variable '%s' at %s:%d",
					name,
					info.short_src,
					info.currentline
				),
				2
			)
		end
		rawset(t, name, value)
	end

	mt.__index = function(_, name)
		if not mt.__declared[name] and not _allowed_globals[name] then
			local info = debug.getinfo(2, "Sl")
			error(
				string.format(
					"[HARDENED] Attempt to read undefined global '%s' at %s:%d",
					name,
					info.short_src,
					info.currentline
				),
				2
			)
		end
		return nil
	end

	print("[HARDENED] Strict mode enabled - global variable protection active")
end

function M.disable_strict_mode()
	if not _strict_enabled then
		return
	end

	local mt = getmetatable(_G)
	if mt then
		mt.__newindex = nil
		mt.__index = nil
	end

	_strict_enabled = false
	print("[HARDENED] Strict mode disabled")
end

function M.declare_global(name)
	local mt = getmetatable(_G)
	if mt and mt.__declared then
		mt.__declared[name] = true
	end
end

-- ============================================================================
-- 2. SAFE TABLE LENGTH
-- ============================================================================

function M.safe_len(t)
	if type(t) ~= "table" then
		return #t
	end

	-- Count using ipairs (stops at first nil)
	local count = 0
	for _ in ipairs(t) do
		count = count + 1
	end
	return count
end

function M.true_len(t)
	if type(t) ~= "table" then
		return #t
	end

	-- Count ALL non-nil entries (including holes)
	local count = 0
	for _ in pairs(t) do
		count = count + 1
	end
	return count
end

-- ============================================================================
-- 3. FLOAT COMPARISON WITH EPSILON
-- ============================================================================

function M.float_eq(a, b, epsilon)
	epsilon = epsilon or 1e-9
	return math.abs(a - b) < epsilon
end

function M.float_lt(a, b, epsilon)
	epsilon = epsilon or 1e-9
	return a < b - epsilon
end

function M.float_le(a, b, epsilon)
	epsilon = epsilon or 1e-9
	return a <= b + epsilon
end

-- ============================================================================
-- 4. DEEP COPY
-- ============================================================================

function M.deep_copy(obj, seen)
	-- Handle non-tables and nil
	if type(obj) ~= "table" then
		return obj
	end

	-- Handle circular references
	seen = seen or {}
	if seen[obj] then
		return seen[obj]
	end

	-- Create new table with same metatable
	local copy = {}
	seen[obj] = copy

	for k, v in pairs(obj) do
		copy[M.deep_copy(k, seen)] = M.deep_copy(v, seen)
	end

	return setmetatable(copy, getmetatable(obj))
end

function M.shallow_copy(obj)
	if type(obj) ~= "table" then
		return obj
	end

	local copy = {}
	for k, v in pairs(obj) do
		copy[k] = v
	end

	return setmetatable(copy, getmetatable(obj))
end

-- ============================================================================
-- 5. ORDERED TABLE ITERATION
-- ============================================================================

function M.ordered_pairs(t, order_fn)
	-- Collect keys
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = k
	end

	-- Sort keys
	table.sort(keys, order_fn)

	-- Return iterator
	local i = 0
	return function()
		i = i + 1
		local k = keys[i]
		if k ~= nil then
			return k, t[k]
		end
	end
end

function M.sorted_keys(t)
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return keys
end

-- ============================================================================
-- 6. RESOURCE MANAGEMENT
-- ============================================================================

function M.with_resource(create, use, cleanup)
	local resource, create_err = create()

	if not resource then
		error(string.format("[HARDENED] Resource creation failed: %s", tostring(create_err)))
	end

	local ok, use_err = pcall(use, resource)

	-- Always cleanup, even if use failed
	local cleanup_ok, cleanup_err = pcall(cleanup, resource)

	if not cleanup_ok then
		print(string.format("[HARDENED] Cleanup failed: %s", tostring(cleanup_err)))
	end

	-- Propagate use error if it occurred
	if not ok then
		error(string.format("[HARDENED] Resource use failed: %s", tostring(use_err)))
	end

	return resource
end

function M.auto_close(obj)
	if type(obj) ~= "table" then
		return obj
	end

	local mt = getmetatable(obj) or {}

	mt.__gc = function(self)
		if self.close then
			pcall(self.close, self)
		elseif self.destroy then
			pcall(self.destroy, self)
		end
	end

	return setmetatable(obj, mt)
end

-- ============================================================================
-- 7. STRING UTILITIES (MEMORY SAFE)
-- ============================================================================

function M.safe_concat(parts, sep)
	-- Use table.concat instead of .. for large strings
	if type(parts) ~= "table" then
		return tostring(parts)
	end

	return table.concat(parts, sep or "")
end

function M.string_builder()
	local parts = {}

	return {
		append = function(s)
			parts[#parts + 1] = tostring(s)
		end,
		build = function()
			local result = table.concat(parts)
			parts = {} -- Clear for reuse
			return result
		end,
		clear = function()
			parts = {}
		end,
	}
end

-- ============================================================================
-- 8. TABLE INSPECTION
-- ============================================================================

function M.table_keys(t)
	local keys = {}
	for k, _ in pairs(t) do
		keys[#keys + 1] = k
	end
	return keys
end

function M.table_values(t)
	local values = {}
	for _, v in pairs(t) do
		values[#values + 1] = v
	end
	return values
end

function M.table_is_empty(t)
	return next(t) == nil
end

function M.table_has_key(t, key)
	return t[key] ~= nil
end

-- ============================================================================
-- 9. FUNCTION GUARDS
-- ============================================================================

function M.assert_type(value, expected_type, name)
	local actual_type = type(value)
	if actual_type ~= expected_type then
		error(
			string.format(
				"[HARDENED] Type assertion failed: %s expected %s, got %s",
				name or "value",
				expected_type,
				actual_type
			)
		)
	end
	return value
end

function M.assert_not_nil(value, name)
	if value == nil then
		error(string.format("[HARDENED] Nil assertion failed: %s is nil", name or "value"))
	end
	return value
end

function M.assert_table(value, name)
	return M.assert_type(value, "table", name)
end

function M.assert_string(value, name)
	return M.assert_type(value, "string", name)
end

function M.assert_number(value, name)
	return M.assert_type(value, "number", name)
end

function M.assert_function(value, name)
	return M.assert_type(value, "function", name)
end

-- ============================================================================
-- 10. MEMOIZATION
-- ============================================================================

function M.memoize(fn)
	local cache = {}

	return function(...)
		local key = table.concat({ ... }, "\0")

		if cache[key] ~= nil then
			return cache[key]
		end

		local result = fn(...)
		cache[key] = result
		return result
	end
end

function M.memoize_with_clear(fn)
	local cache = {}

	local wrapped = function(...)
		local key = table.concat({ ... }, "\0")

		if cache[key] ~= nil then
			return cache[key]
		end

		local result = fn(...)
		cache[key] = result
		return result
	end

	wrapped.clear = function()
		cache = {}
	end

	return wrapped
end

-- ============================================================================
-- 11. COROUTINE SAFETY
-- ============================================================================

function M.safe_coroutine(fn)
	local co = coroutine.create(function(...)
		local ok, result = pcall(fn, ...)
		if not ok then
			print(string.format("[HARDENED] Coroutine error: %s", tostring(result)))
			error(result)
		end
		return result
	end)

	return co
end

function M.resume_safe(co, ...)
	local ok, result = coroutine.resume(co, ...)

	if not ok then
		print(string.format("[HARDENED] Coroutine resume failed: %s", tostring(result)))
		return false, result
	end

	return true, result
end

-- ============================================================================
-- 12. ARRAY UTILITIES (SAFE FOR FSM QUEUES)
-- ============================================================================

function M.array_push(arr, value)
	arr[#arr + 1] = value
	return arr
end

function M.array_pop(arr)
	if #arr == 0 then
		return nil
	end
	local value = arr[#arr]
	arr[#arr] = nil
	return value
end

function M.array_shift(arr)
	if #arr == 0 then
		return nil
	end
	return table.remove(arr, 1)
end

function M.array_unshift(arr, value)
	table.insert(arr, 1, value)
	return arr
end

function M.array_clear(arr)
	for i = 1, #arr do
		arr[i] = nil
	end
	return arr
end

function M.array_has_holes(arr)
	local max_index = 0
	local count = 0

	for k, _ in pairs(arr) do
		if type(k) == "number" then
			count = count + 1
			if k > max_index then
				max_index = k
			end
		end
	end

	return max_index ~= count
end

-- ============================================================================
-- 13. DEBUG UTILITIES
-- ============================================================================

function M.dump(obj, name, indent)
	name = name or "value"
	indent = indent or 0
	local prefix = string.rep("  ", indent)

	if type(obj) ~= "table" then
		print(string.format("%s%s = %s (%s)", prefix, name, tostring(obj), type(obj)))
		return
	end

	print(string.format("%s%s = {", prefix, name))
	for k, v in pairs(obj) do
		if type(v) == "table" then
			M.dump(v, tostring(k), indent + 1)
		else
			print(string.format("%s  %s = %s (%s)", prefix, tostring(k), tostring(v), type(v)))
		end
	end
	print(string.format("%s}", prefix))
end

function M.trace(message)
	local info = debug.getinfo(2, "Sl")
	print(string.format("[TRACE] %s:%d: %s", info.short_src, info.currentline, message))
end

-- ============================================================================
-- 14. VALIDATION
-- ============================================================================

function M.validate_shape(obj, schema, path)
	path = path or "obj"

	for key, expected_type in pairs(schema) do
		local actual_value = obj[key]
		local actual_type = type(actual_value)

		-- Handle Optional Fields (e.g., "?string")
		local is_optional = false
		if expected_type:sub(1, 1) == "?" then
			expected_type = expected_type:sub(2)
			is_optional = true
		end

		-- Skip validation for optional fields that are nil
		if is_optional and actual_value == nil then
			-- Continue to next iteration
		else
			if actual_value == nil then
				error(string.format("[HARDENED] Missing required field %s.%s (expected %s)", path, key, expected_type))
			end
			-- Validate the type
			if actual_type ~= expected_type then
				error(
					string.format(
						"[HARDENED] Shape validation failed at %s.%s: expected %s, got %s",
						path,
						key,
						expected_type,
						actual_type
					)
				)
			end
		end
	end

	return true
end

-- ============================================================================
-- 15. PERFORMANCE MONITORING
-- ============================================================================

function M.timed(fn, name)
	name = name or "function"

	return function(...)
		local start = os.clock()
		local results = { fn(...) }
		local elapsed = os.clock() - start

		print(string.format("[HARDENED] %s took %.6f seconds", name, elapsed))

		return table.unpack(results)
	end
end

function M.profile(fn, iterations)
	iterations = iterations or 1000

	local start = os.clock()
	for i = 1, iterations do
		fn()
	end
	local elapsed = os.clock() - start

	print(
		string.format(
			"[HARDENED] Profile: %d iterations in %.6f seconds (%.9f per iteration)",
			iterations,
			elapsed,
			elapsed / iterations
		)
	)

	return elapsed
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

return M
