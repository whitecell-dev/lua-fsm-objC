-- ============================================================================
-- lua-fsm-objC.stringbuffer (FIXED - Pure Data Structure)
-- ============================================================================
-- A passive, deterministic string buffer that composes with Calyx
-- - Mutations return Result tables
-- - Reads return raw values
-- - No clock coupling
-- - No debug logging in core
-- - Bundle-safe (no closure fragility)
-- ============================================================================

local ABI = require("abi")

local StringBuffer = {}
StringBuffer.__index = StringBuffer

-- Private storage key (immutable, bundle-safe)
local PRIVATE = {}

function StringBuffer.new(capacity, opts)
	opts = opts or {}

	-- Validate
	if type(capacity) ~= "number" or capacity <= 0 then
		error("StringBuffer.new: capacity must be positive number", 2)
	end

	-- Create instance
	local self = setmetatable({}, StringBuffer)

	-- Private data (stored in object, not closures)
	self[PRIVATE] = {
		chunks = {}, -- table of string chunks
		total_bytes = 0, -- total bytes stored
		capacity = capacity, -- max bytes allowed
		overflow_policy = opts.overflow_policy or "reject", -- reject, drop_oldest, drop_newest
	}

	-- Freeze the API
	local mt = getmetatable(self)
	mt.__newindex = function(t, k, v)
		if k == PRIVATE then
			rawset(t, k, v)
			return
		end
		error(string.format("StringBuffer is frozen: cannot set field '%s'", tostring(k)), 2)
	end
	mt.__metatable = { protected = true, type = "CALYX_STRING_BUFFER" }

	return self
end

-- ============================================================================
-- MUTATIONS (return Result tables)
-- ============================================================================

--- Append a string to the buffer
--- @param str string
--- @return table Result with {ok, data}
function StringBuffer:append(str)
	local private = self[PRIVATE]

	if type(str) ~= "string" then
		return ABI.error_result(ABI.ERRORS.INVALID_ARGUMENT, "append() requires a string", { got = type(str) })
	end

	local chunk_len = #str
	if chunk_len == 0 then
		return ABI.success_result({
			bytes_added = 0,
			total_bytes = private.total_bytes,
		})
	end

	local new_total = private.total_bytes + chunk_len

	-- Capacity check based on policy
	if new_total > private.capacity then
		if private.overflow_policy == "reject" then
			return ABI.error_result(
				ABI.ERRORS.BUFFER_FULL,
				string.format("Buffer full: %d/%d bytes", private.total_bytes, private.capacity),
				{
					total_bytes = private.total_bytes,
					capacity = private.capacity,
					requested = chunk_len,
				}
			)
		elseif private.overflow_policy == "drop_oldest" then
			-- Drop oldest chunks until we have room
			while private.total_bytes + chunk_len > private.capacity and #private.chunks > 0 do
				local oldest = table.remove(private.chunks, 1)
				private.total_bytes = private.total_bytes - #oldest
			end

			if private.total_bytes + chunk_len > private.capacity then
				return ABI.error_result(ABI.ERRORS.BUFFER_FULL, "Buffer still full after dropping oldest")
			end
		elseif private.overflow_policy == "drop_newest" then
			-- Silently drop, return error
			return ABI.error_result(ABI.ERRORS.BUFFER_FULL, "Buffer full, data dropped", { policy = "drop_newest" })
		end
	end

	-- Add the chunk
	table.insert(private.chunks, str)
	private.total_bytes = private.total_bytes + chunk_len

	return ABI.success_result({
		bytes_added = chunk_len,
		total_bytes = private.total_bytes,
		capacity = private.capacity,
		utilization = (private.total_bytes / private.capacity) * 100,
	})
end

--- Alias for append
function StringBuffer:push(str)
	return self:append(str)
end

--- Clear all data from the buffer
--- @return table Result with cleared_bytes count
function StringBuffer:clear()
	local private = self[PRIVATE]
	local cleared = private.total_bytes

	private.chunks = {}
	private.total_bytes = 0

	return ABI.success_result({
		cleared_bytes = cleared,
		total_bytes = 0,
	})
end

--- Reset (alias for clear)
function StringBuffer:reset()
	return self:clear()
end

--- Pop N bytes from the buffer (destructive read)
--- @param n number|nil Bytes to read (nil = all)
--- @return table Result with {data, bytes_read, remaining}
function StringBuffer:pop(n)
	local private = self[PRIVATE]

	if private.total_bytes == 0 then
		return ABI.success_result({
			data = "",
			bytes_read = 0,
			remaining = 0,
		})
	end

	-- If n is nil or >= total, return everything
	if not n or n >= private.total_bytes then
		local data = table.concat(private.chunks)
		local bytes_read = private.total_bytes

		-- Clear buffer
		private.chunks = {}
		private.total_bytes = 0

		return ABI.success_result({
			data = data,
			bytes_read = bytes_read,
			remaining = 0,
		})
	end

	-- Read exactly n bytes
	local result_parts = {}
	local bytes_read = 0
	local remaining_chunks = {}

	while bytes_read < n and #private.chunks > 0 do
		local chunk = table.remove(private.chunks, 1)

		if bytes_read + #chunk <= n then
			-- Take whole chunk
			table.insert(result_parts, chunk)
			bytes_read = bytes_read + #chunk
			private.total_bytes = private.total_bytes - #chunk
		else
			-- Take part of chunk
			local needed = n - bytes_read
			local take = string.sub(chunk, 1, needed)
			local keep = string.sub(chunk, needed + 1)

			table.insert(result_parts, take)
			bytes_read = bytes_read + needed
			private.total_bytes = private.total_bytes - needed

			-- Put remainder back
			if keep ~= "" then
				table.insert(remaining_chunks, 1, keep)
			end
			break
		end
	end

	-- Restore unread chunks
	for i = #remaining_chunks, 1, -1 do
		table.insert(private.chunks, 1, remaining_chunks[i])
	end

	return ABI.success_result({
		data = table.concat(result_parts),
		bytes_read = bytes_read,
		remaining = private.total_bytes,
	})
end

-- ============================================================================
-- READS (return raw values)
-- ============================================================================

--- Get current buffer content (non-destructive)
--- @return string
function StringBuffer:tostring()
	local private = self[PRIVATE]
	return table.concat(private.chunks)
end

--- Get current buffer size in bytes
--- @return number
function StringBuffer:size()
	local private = self[PRIVATE]
	return private.total_bytes
end

--- Get buffer capacity in bytes
--- @return number
function StringBuffer:capacity()
	local private = self[PRIVATE]
	return private.capacity
end

--- Check if buffer is full
--- @return boolean
function StringBuffer:is_full()
	local private = self[PRIVATE]
	return private.total_bytes >= private.capacity
end

--- Peek at N bytes without consuming
--- @param n number|nil Bytes to peek (nil = all)
--- @return string
function StringBuffer:peek(n)
	local private = self[PRIVATE]

	if private.total_bytes == 0 then
		return ""
	end

	if not n or n >= private.total_bytes then
		return table.concat(private.chunks)
	end

	-- Build exactly n bytes
	local parts = {}
	local bytes = 0

	for _, chunk in ipairs(private.chunks) do
		if bytes + #chunk <= n then
			table.insert(parts, chunk)
			bytes = bytes + #chunk
		else
			local needed = n - bytes
			table.insert(parts, string.sub(chunk, 1, needed))
			break
		end
	end

	return table.concat(parts)
end

--- Get buffer statistics (pure data, no side effects)
--- @return table
function StringBuffer:stats()
	local private = self[PRIVATE]

	return {
		total_bytes = private.total_bytes,
		capacity = private.capacity,
		utilization = (private.total_bytes / private.capacity) * 100,
		chunks = #private.chunks,
		overflow_policy = private.overflow_policy,
		free_bytes = private.capacity - private.total_bytes,
	}
end

return StringBuffer
