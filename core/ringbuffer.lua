-- ============================================================================
-- calyx/fsm/ringbuffer.lua
-- CALYX Ring Buffer Mailbox
-- O(1) enqueue/dequeue with backpressure signaling
-- Lua 5.1.5 Compatible
-- ============================================================================

local ABI = require("abi")

local RingBuffer = {}
RingBuffer.__index = RingBuffer

-- ============================================================================
-- RING BUFFER IMPLEMENTATION
-- ============================================================================

function RingBuffer.new(max_size, opts)
	opts = opts or {}

	return setmetatable({
		queue = {},
		head = 1,
		tail = 1,
		count = 0,
		max_size = max_size or 1000,

		-- Stats
		dropped_count = 0,
		total_processed = 0,
		total_failed = 0,
		total_enqueued = 0,

		-- Backpressure policy
		overflow_policy = opts.overflow_policy or "drop_newest", -- drop_newest, drop_oldest, reject

		-- Callbacks
		on_backpressure = opts.on_backpressure,

		-- Debug mode
		debug = opts.debug or false,
	}, RingBuffer)
end

-- ============================================================================
-- CORE OPERATIONS (O(1))
-- ============================================================================

function RingBuffer:enqueue(message)
	-- Check capacity
	if self.count >= self.max_size then
		self.dropped_count = self.dropped_count + 1

		if self.overflow_policy == "reject" then
			return ABI.error_result(
				ABI.ERRORS.QUEUE_FULL,
				"Queue at capacity",
				{ count = self.count, max_size = self.max_size, dropped_total = self.dropped_count }
			)
		elseif self.overflow_policy == "drop_oldest" then
			-- Dequeue oldest to make room
			self:dequeue()
			if self.debug then
				print(string.format("[MAILBOX] Dropped oldest message (policy=drop_oldest)"))
			end
		else -- drop_newest (default)
			if self.debug and self.dropped_count % 100 == 1 then
				print(
					string.format(
						"[MAILBOX] Queue full (%d/%d), dropping newest message #%d",
						self.count,
						self.max_size,
						self.dropped_count
					)
				)
			end

			-- Fire backpressure callback
			if self.on_backpressure then
				self.on_backpressure(self:get_stats())
			end

			return ABI.error_result(
				ABI.ERRORS.QUEUE_FULL,
				"Queue full, message dropped",
				{ policy = "drop_newest", stats = self:get_stats() }
			)
		end
	end

	-- Insert at tail
	self.queue[self.tail] = message
	self.tail = (self.tail % self.max_size) + 1
	self.count = self.count + 1
	self.total_enqueued = self.total_enqueued + 1

	if self.debug then
		print(
			string.format(
				"[MAILBOX] Enqueued: event=%s count=%d/%d",
				ABI.safe_tostring(message.event),
				self.count,
				self.max_size
			)
		)
	end

	return ABI.success_result({ count = self.count })
end

function RingBuffer:dequeue()
	if self.count == 0 then
		return nil
	end

	local message = self.queue[self.head]
	self.queue[self.head] = nil -- Allow GC
	self.head = (self.head % self.max_size) + 1
	self.count = self.count - 1

	return message
end

function RingBuffer:peek()
	if self.count == 0 then
		return nil
	end
	return self.queue[self.head]
end

function RingBuffer:has_messages()
	return self.count > 0
end

-- ============================================================================
-- BATCH OPERATIONS
-- ============================================================================

function RingBuffer:dequeue_batch(max_count)
	max_count = math.min(max_count or self.count, self.count)
	local batch = {}

	for i = 1, max_count do
		local msg = self:dequeue()
		if msg then
			table.insert(batch, msg)
		else
			break
		end
	end

	return batch
end

-- ============================================================================
-- STATS & MANAGEMENT
-- ============================================================================

function RingBuffer:get_stats()
	return {
		queued = self.count,
		max_size = self.max_size,
		dropped = self.dropped_count,
		free_slots = self.max_size - self.count,
		total_processed = self.total_processed,
		total_failed = self.total_failed,
		total_enqueued = self.total_enqueued,
		utilization = (self.count / self.max_size) * 100,
	}
end

function RingBuffer:clear(only_non_retained)
	if only_non_retained then
		-- Scan and rebuild without non-retained messages
		local kept = {}
		local cleared = 0

		while self:has_messages() do
			local msg = self:dequeue()
			if msg._retention_marker then
				table.insert(kept, msg)
			else
				cleared = cleared + 1
			end
		end

		-- Re-enqueue kept messages
		for i = 1, #kept do
			self:enqueue(kept[i])
		end

		if self.debug then
			print(string.format("[MAILBOX] Cleared %d non-retained messages (%d retained)", cleared, #kept))
		end

		return cleared
	else
		local cleared = self.count

		-- Clear queue
		self.queue = {}
		self.head = 1
		self.tail = 1
		self.count = 0
		self.dropped_count = 0

		if self.debug then
			print(string.format("[MAILBOX] Cleared all %d messages", cleared))
		end

		return cleared
	end
end

function RingBuffer:set_max_size(new_size)
	if new_size < self.count then
		-- Truncate excess messages
		local excess = self.count - new_size
		for i = 1, excess do
			self:dequeue()
		end

		if self.debug then
			print(string.format("[MAILBOX] Truncated %d messages to fit new size %d", excess, new_size))
		end
	end

	self.max_size = new_size
end

return RingBuffer
