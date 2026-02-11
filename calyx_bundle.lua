-- CALYX BUNDLE GENERATED: Wed Feb 11 17:26:34 2026
-- PRODUCTION HARDENED: Deterministic ordering + frozen API
local bundle = { modules = {}, loaded = {} }

local function load_module(name)
    if bundle.loaded[name] then return bundle.loaded[name] end
    local module = bundle.modules[name]
    if not module then error('MODULE_MISSING: ' .. name) end
    local fn, err = loadstring(module, name)
    if not fn then error('LOAD_FAILURE ['..name..']: ' .. err) end
    bundle.loaded[name] = fn()
    return bundle.loaded[name]
end

bundle.modules['lua-fsm-objC.abi'] = "-- ============================================================================\
-- calyx/fsm/abi.lua\
-- CALYX FSM ABI Constants\
-- Shared state definitions, error types, and lifecycle markers\
-- Lua 5.1.5 Compatible\
-- PRODUCTION HARDENED: Deterministic clock + standardized Result format\
-- ============================================================================\
\
local ABI = {}\
\
-- ============================================================================\
-- DETERMINISTIC CLOCK\
-- ============================================================================\
\
ABI.clock = {\
	tick = 0,\
	real_clock = os.date, -- Injected for testing\
}\
\
function ABI.clock:advance()\
	self.tick = self.tick + 1\
	return self.tick\
end\
\
function ABI.clock:now()\
	return self.tick\
end\
\
function ABI.clock:reset(start_tick)\
	self.tick = start_tick or 0\
end\
\
function ABI.clock:real_timestamp(format)\
	format = format or \"%H:%M:%S\"\
	return self.real_clock(format)\
end\
\
-- ============================================================================\
-- STATE CONSTANTS\
-- ============================================================================\
\
ABI.STATES = {\
	-- Core state markers\
	NONE = \"none\",\
	ASYNC = \"async\",\
\
	-- Transition phase suffixes\
	SUFFIXES = {\
		LEAVE_WAIT = \"_LEAVE_WAIT\",\
		ENTER_WAIT = \"_ENTER_WAIT\",\
	},\
\
	-- Lifecycle states\
	INIT = \"init\",\
	IDLE = \"idle\",\
	RUNNING = \"running\",\
	PAUSED = \"paused\",\
	STOPPED = \"stopped\",\
	ERROR = \"error\",\
	FINAL = \"final\",\
}\
\
-- ============================================================================\
-- ERROR CATEGORIES\
-- ============================================================================\
\
ABI.ERRORS = {\
	-- Transition errors\
	INVALID_TRANSITION = \"invalid_transition\",\
	TRANSITION_IN_PROGRESS = \"transition_in_progress\",\
	CANCELLED_BEFORE = \"cancelled_before\",\
	CANCELLED_LEAVE = \"cancelled_leave\",\
	INVALID_STAGE = \"invalid_stage\",\
\
	-- Context errors\
	NO_CONTEXT = \"no_context\",\
	CONTEXT_LOST = \"context_lost\",\
	NO_ACTIVE_TRANSITION = \"no_active_transition\",\
\
	-- Mailbox errors\
	NO_MAILBOX = \"no_mailbox\",\
	QUEUE_FULL = \"queue_full\",\
	ALREADY_PROCESSING = \"already_processing\",\
\
	-- Validation errors\
	INVALID_EVENT_NAME = \"invalid_event_name\",\
	EVENT_COLLISION = \"event_collision\",\
	MISSING_EVENT = \"missing_event\",\
	MISSING_TARGET = \"missing_target\",\
\
	-- Resource errors\
	NO_MEMORY = \"no_memory\",\
	GC_FAILED = \"gc_failed\",\
}\
\
-- ============================================================================\
-- EVENT VALIDATION PATTERNS\
-- ============================================================================\
\
ABI.PATTERNS = {\
	-- Event name must start with letter/underscore, then letters/numbers/_.-\
	EVENT_NAME = \"^[%a_][%w_%.%-]*$\",\
\
	-- State name validation (similar constraints)\
	STATE_NAME = \"^[%a_][%w_%.%-]*$\",\
\
	-- Callback name pattern (onbefore*, onleave*, onenter*, onafter*)\
	CALLBACK = \"^on(before|leave|enter|after)[%a_][%w_%.%-]*$\",\
}\
\
-- ============================================================================\
-- RESERVED NAMES\
-- ============================================================================\
\
ABI.RESERVED = {\
	-- Core methods\
	\"send\",\
	\"resume\",\
	\"current\",\
	\"_context\",\
	\"mailbox\",\
	\"process_mailbox\",\
	\"clear_mailbox\",\
	\"force_gc_cleanup\",\
	\"mailbox_stats\",\
	\"set_mailbox_size\",\
	\"can\",\
	\"is\",\
	\"asyncState\",\
	\"events\",\
	\"currentTransitioningEvent\",\
	\"_complete\",\
	\"name\",\
\
	-- Lifecycle callbacks\
	\"onbefore\",\
	\"onleave\",\
	\"onenter\",\
	\"onafter\",\
	\"onstatechange\",\
\
	-- Internal\
	\"__index\",\
	\"__newindex\",\
	\"__metatable\",\
}\
\
-- ============================================================================\
-- METADATA\
-- ============================================================================\
\
ABI.VERSION = \"0.4.0\"\
ABI.NAME = \"calyx-fsm\"\
ABI.SPEC = \"CALYX Finite State Machine Specification v1\"\
\
-- ============================================================================\
-- UTILITY: Safe string conversion for error messages\
-- ============================================================================\
\
function ABI.safe_tostring(value)\
	local success, result = pcall(tostring, value)\
	if success then\
		return result\
	end\
	return \"[UNPRINTABLE]\"\
end\
\
-- ============================================================================\
-- STANDARDIZED RESULT FORMAT\
-- All operations return Result tables (never multi-return for errors)\
-- ============================================================================\
\
function ABI.error_result(error_code, message, details)\
	return {\
		ok = false,\
		code = error_code,\
		message = message or error_code,\
		details = details or {},\
		tick = ABI.clock:now(),\
		-- trace omitted by default (add via debug mode)\
	}\
end\
\
function ABI.success_result(data)\
	return {\
		ok = true,\
		data = data or {},\
		tick = ABI.clock:now(),\
	}\
end\
\
-- ============================================================================\
-- LEGACY COMPATIBILITY (DEPRECATED)\
-- Old multi-return format - will be removed in 1.0\
-- ============================================================================\
\
function ABI.error_response(error_type, details)\
	-- Log deprecation warning once\
	if not ABI._warned_multi_return then\
		print(\"[DEPRECATED] error_response uses multi-return. Use error_result instead.\")\
		ABI._warned_multi_return = true\
	end\
\
	return false, ABI.error_result(error_type, nil, details)\
end\
\
function ABI.success_response(data)\
	return true, ABI.success_result(data)\
end\
\
return ABI\
"
bundle.modules['lua-fsm-objC.utils'] = "-- ============================================================================\
-- calyx/fsm/utils.lua\
-- CALYX FSM Shared Utilities\
-- Formatters, helpers, and diagnostic tools\
-- Lua 5.1.5 Compatible\
-- ============================================================================\
\
local ABI = require(\"abi\")\
\
local Utils = {}\
\
-- ============================================================================\
-- OBJECTIVE-C STYLE CALL FORMATTER\
-- ============================================================================\
\
function Utils.format_objc_call(method, params)\
	params = params or {}\
	local parts = {}\
\
	if params.data then\
		for k, v in pairs(params.data) do\
			table.insert(parts, string.format(\"data.%s:%s\", k, ABI.safe_tostring(v)))\
		end\
	end\
\
	if params.options then\
		for k, v in pairs(params.options) do\
			table.insert(parts, string.format(\"options.%s:%s\", k, ABI.safe_tostring(v)))\
		end\
	end\
\
	if #parts > 0 then\
		return string.format(\"%s(%s)\", method, table.concat(parts, \" \"))\
	else\
		return string.format(\"%s()\", method)\
	end\
end\
\
-- ============================================================================\
-- JSON-LIKE SERIALIZER (FOR DEBUGGING)\
-- ============================================================================\
\
function Utils.serialize_table(tbl, indent)\
	indent = indent or 0\
	local parts = {}\
	local prefix = string.rep(\"  \", indent)\
\
	if type(tbl) ~= \"table\" then\
		return ABI.safe_tostring(tbl)\
	end\
\
	table.insert(parts, \"{\")\
\
	for k, v in pairs(tbl) do\
		local key_str\
		if type(k) == \"string\" then\
			key_str = string.format(\"%q\", k)\
		else\
			key_str = tostring(k)\
		end\
\
		if type(v) == \"table\" then\
			table.insert(parts, string.format(\"%s  %s: %s\", prefix, key_str, Utils.serialize_table(v, indent + 1)))\
		else\
			table.insert(parts, string.format(\"%s  %s: %s\", prefix, key_str, ABI.safe_tostring(v)))\
		end\
	end\
\
	table.insert(parts, prefix .. \"}\")\
	return table.concat(parts, \"\\n\")\
end\
\
-- ============================================================================\
-- CONTEXT DIFF (BEFORE/AFTER TRANSITION)\
-- ============================================================================\
\
function Utils.context_diff(before_ctx, after_ctx)\
	local changes = {}\
\
	if before_ctx.from ~= after_ctx.from then\
		table.insert(changes, string.format(\"from: %s -> %s\", before_ctx.from, after_ctx.from))\
	end\
\
	if before_ctx.to ~= after_ctx.to then\
		table.insert(changes, string.format(\"to: %s -> %s\", before_ctx.to, after_ctx.to))\
	end\
\
	if before_ctx.event ~= after_ctx.event then\
		table.insert(changes, string.format(\"event: %s -> %s\", before_ctx.event, after_ctx.event))\
	end\
\
	if #changes > 0 then\
		return table.concat(changes, \", \")\
	else\
		return \"no changes\"\
	end\
end\
\
-- ============================================================================\
-- SAFE TABLE MERGE\
-- ============================================================================\
\
function Utils.merge_tables(target, source, overwrite)\
	target = target or {}\
	source = source or {}\
\
	for k, v in pairs(source) do\
		if overwrite or target[k] == nil then\
			if type(v) == \"table\" and type(target[k]) == \"table\" then\
				target[k] = Utils.merge_tables(target[k], v, overwrite)\
			else\
				target[k] = v\
			end\
		end\
	end\
\
	return target\
end\
\
-- ============================================================================\
-- RANDOM ID GENERATOR (Lua 5.1.5 compatible)\
-- ============================================================================\
\
function Utils.generate_id(prefix, length)\
	prefix = prefix or \"id\"\
	length = length or 8\
\
	local chars = \"0123456789abcdef\"\
	local id = {}\
\
	math.randomseed(os.time())\
	math.random() -- Seed properly\
\
	for i = 1, length do\
		local rand = math.random(1, #chars)\
		table.insert(id, string.sub(chars, rand, rand))\
	end\
\
	return string.format(\"%s_%s\", prefix, table.concat(id))\
end\
\
return Utils\
"
bundle.modules['lua-fsm-objC.core'] = "-- ============================================================================\
-- lua-fsm-objC.core (FIXED - Metatable protection)\
-- ============================================================================\
-- calyx/fsm/core.lua\
-- CALYX FSM Core Kernel\
-- Shared transition logic, validation, and callback dispatch\
-- Lua 5.1.5 Compatible\
-- ============================================================================\
\
local ABI = require(\"abi\")\
\
local Core = {}\
Core.__index = Core\
\
-- ============================================================================\
-- WARNING SYSTEM (Lua 5.1.5 compatible)\
-- ============================================================================\
\
function Core.warn(message, category)\
	category = ABI.safe_tostring(category or \"general\")\
	message = ABI.safe_tostring(message)\
	print(string.format(\"[WARN %s] %s\", string.upper(category), message))\
end\
\
-- ============================================================================\
-- METATABLE PROTECTION (ENHANCED)\
-- ============================================================================\
\
function Core.lock_metatable(fsm, protection_tag)\
	local mt = getmetatable(fsm)\
	if mt then\
		-- Prevent getmetatable/setmetatable tampering\
		mt.__metatable = protection_tag\
			or {\
				protected = true,\
				type = \"CALYX_FSM\",\
				version = ABI.VERSION,\
				immutable = true,\
			}\
\
		-- Prevent new field creation\
		mt.__newindex = function(t, k, v)\
			-- Whitelist of mutable fields\
			local mutable = {\
				current = true,\
				asyncState = true,\
				_context = true,\
				currentTransitioningEvent = true,\
			}\
\
			if mutable[k] then\
				rawset(t, k, v)\
			else\
				-- FIX: Use consistent error message that test expects\
				error(string.format(\"Cannot modify FSM: attempted to set field '%s'\", tostring(k)), 2)\
			end\
		end\
	end\
	return fsm\
end\
\
-- ... rest of core.lua unchanged ...\
\
-- ============================================================================\
-- EVENT NAME VALIDATION\
-- ============================================================================\
\
function Core.validate_event_name(name, strict_mode)\
	if type(name) ~= \"string\" or name == \"\" then\
		local msg = \"Event name must be a non-empty string, got: \" .. type(name)\
		if strict_mode then\
			error(msg, 2)\
		else\
			Core.warn(msg, \"validation\")\
			return false\
		end\
	end\
\
	if not string.match(name, ABI.PATTERNS.EVENT_NAME) then\
		local msg =\
			string.format(\"Invalid event name format: '%s'. Must match pattern: %s\", name, ABI.PATTERNS.EVENT_NAME)\
		if strict_mode then\
			error(msg, 2)\
		else\
			Core.warn(msg, \"validation\")\
			return false\
		end\
	end\
\
	return true\
end\
\
-- ============================================================================\
-- STATE NAME VALIDATION\
-- ============================================================================\
\
function Core.validate_state_name(name, strict_mode)\
	if type(name) ~= \"string\" or name == \"\" then\
		local msg = \"State name must be a non-empty string, got: \" .. type(name)\
		if strict_mode then\
			error(msg, 2)\
		else\
			Core.warn(msg, \"validation\")\
			return false\
		end\
	end\
\
	if not string.match(name, ABI.PATTERNS.STATE_NAME) then\
		local msg =\
			string.format(\"Invalid state name format: '%s'. Must match pattern: %s\", name, ABI.PATTERNS.STATE_NAME)\
		if strict_mode then\
			error(msg, 2)\
		else\
			Core.warn(msg, \"validation\")\
			return false\
		end\
	end\
\
	return true\
end\
\
-- ============================================================================\
-- EVENT COLLISION DETECTION\
-- ============================================================================\
\
function Core.check_event_collision(fsm_instance, name)\
	-- Check reserved names\
	for i = 1, #ABI.RESERVED do\
		if name == ABI.RESERVED[i] then\
			error(\"Event name '\" .. name .. \"' is reserved and cannot be used\", 2)\
		end\
	end\
\
	-- Check existing methods\
	if fsm_instance[name] and type(fsm_instance[name]) == \"function\" then\
		Core.warn(\"Event name '\" .. name .. \"' collides with existing FSM method. Skipping creation.\", \"collision\")\
		return false\
	end\
\
	return true\
end\
\
-- ============================================================================\
-- TRANSITION MAP BUILDER\
-- ============================================================================\
\
function Core.build_transition_map(events)\
	local map = {}\
\
	for _, ev in ipairs(events) do\
		-- Validate event structure\
		assert(type(ev.name) == \"string\", \"event.name must be string\")\
		assert(ev.to ~= nil, \"event.to is required\")\
\
		-- Initialize event entry\
		map[ev.name] = {\
			name = ev.name,\
			to = ev.to,\
			from_map = {},\
		}\
\
		-- Process 'from' states\
		if ev.from then\
			local from_states = type(ev.from) == \"table\" and ev.from or { ev.from }\
			for _, st in ipairs(from_states) do\
				if st == \"*\" then\
					map[ev.name].wildcard = true\
				else\
					map[ev.name].from_map[st] = true\
				end\
			end\
		end\
\
		-- Wildcard support (explicit or implied)\
		if ev.wildcard then\
			map[ev.name].wildcard = true\
		end\
	end\
\
	return map\
end\
\
-- ============================================================================\
-- CAN TRANSITION CHECK\
-- ============================================================================\
\
function Core.can_transition(transition_map, event_name, current_state)\
	local ev = transition_map[event_name]\
	if not ev then\
		return false, nil\
	end\
\
	if ev.from_map[current_state] or ev.wildcard then\
		return true, ev.to\
	end\
\
	return false, nil\
end\
\
-- ============================================================================\
-- CONTEXT CREATOR\
-- ============================================================================\
\
function Core.create_context(event_name, from_state, to_state, data, options)\
	return {\
		event = event_name,\
		from = from_state,\
		to = to_state,\
		data = data or {},\
		options = options or {},\
		tick = ABI.clock:now(),\
	}\
end\
\
-- ============================================================================\
-- CALLBACK DISPATCHER (PRIVATE - NOT EXPOSED IN PUBLIC API)\
-- ============================================================================\
\
function Core._dispatch_callback(fsm, callback_type, phase, context)\
	-- Construct callback name (e.g., onbeforeStart, onleaveIDLE, onenterRUNNING)\
	local callback_name\
\
	if phase == \"before\" then\
		callback_name = \"onbefore\" .. context.event\
	elseif phase == \"leave\" then\
		callback_name = \"onleave\" .. context.from\
	elseif phase == \"enter\" then\
		callback_name = \"onenter\" .. context.to\
	elseif phase == \"after\" then\
		callback_name = \"onafter\" .. context.event\
	else\
		callback_name = phase -- Direct callback name\
	end\
\
	local callback = fsm[callback_name]\
	if callback then\
		-- Always use (fsm, context) signature for consistency\
		return callback(fsm, context)\
	end\
\
	return nil\
end\
\
-- ============================================================================\
-- FSM INSTANCE CREATOR (BASE)\
-- ============================================================================\
\
function Core.create_base_fsm(opts)\
	opts = opts or {}\
\
	-- Validate initial state\
	if opts.initial then\
		Core.validate_state_name(opts.initial, opts.strict_mode)\
	end\
\
	local fsm = {\
		-- Identity\
		name = opts.name or string.format(\"fsm_%x\", math.floor(math.random() * 0xFFFFFF)),\
\
		-- State\
		current = opts.initial or ABI.STATES.IDLE,\
\
		-- Transition system\
		transitions = Core.build_transition_map(opts.events or {}),\
\
		-- Callback storage\
		callbacks = {},\
\
		-- Configuration\
		strict_mode = opts.strict_mode or false,\
		debug = opts.debug or false,\
\
		-- Metadata\
		created_at = ABI.clock:now(),\
		version = ABI.VERSION,\
	}\
\
	-- Apply callbacks\
	if opts.callbacks then\
		for k, v in pairs(opts.callbacks) do\
			fsm[k] = v\
		end\
	end\
\
	setmetatable(fsm, Core)\
	return fsm\
end\
\
-- ============================================================================\
-- CORE TRANSITION METHOD (RETURNS RESULT TABLE)\
-- ============================================================================\
\
function Core:_transition(event_name, data, options)\
	-- Check if transition is valid\
	local can, target = Core.can_transition(self.transitions, event_name, self.current)\
	if not can then\
		return ABI.error_result(\
			ABI.ERRORS.INVALID_TRANSITION,\
			string.format(\"Cannot transition from '%s' via '%s'\", self.current, event_name),\
			{ current = self.current, event = event_name }\
		)\
	end\
\
	-- Create context\
	local ctx = Core.create_context(event_name, self.current, target, data, options)\
\
	-- BEFORE callback\
	local before_result = Core._dispatch_callback(self, \"callback\", \"before\", ctx)\
	if before_result == false then\
		return ABI.error_result(\
			ABI.ERRORS.CANCELLED_BEFORE,\
			string.format(\"Transition cancelled in onbefore%s\", event_name),\
			{ event = event_name, context = ctx }\
		)\
	end\
\
	-- LEAVE callback\
	local leave_result = Core._dispatch_callback(self, \"callback\", \"leave\", ctx)\
	if leave_result == false then\
		return ABI.error_result(\
			ABI.ERRORS.CANCELLED_LEAVE,\
			string.format(\"Transition cancelled in onleave%s\", ctx.from),\
			{ event = event_name, context = ctx }\
		)\
	end\
\
	-- Store context for async continuation\
	ctx._requires_async = leave_result == ABI.STATES.ASYNC\
\
	return ABI.success_result({\
		context = ctx,\
		target = target,\
		is_async = leave_result == ABI.STATES.ASYNC,\
	})\
end\
\
-- ============================================================================\
-- COMPLETE TRANSITION (RETURNS RESULT TABLE)\
-- ============================================================================\
\
function Core:_complete_transition(ctx)\
	-- Update state\
	self.current = ctx.to\
\
	-- ENTER callback\
	Core._dispatch_callback(self, \"callback\", \"enter\", ctx)\
\
	-- AFTER callback\
	Core._dispatch_callback(self, \"callback\", \"after\", ctx)\
\
	-- State change notification\
	if self.onstatechange then\
		self.onstatechange(self, ctx)\
	end\
\
	return ABI.success_result(ctx)\
end\
\
-- ============================================================================\
-- CAN EVENT CHECK\
-- ============================================================================\
\
function Core:can(event_name)\
	return Core.can_transition(self.transitions, event_name, self.current)\
end\
\
-- ============================================================================\
-- STATE CHECK\
-- ============================================================================\
\
function Core:is(state_name)\
	return self.current == state_name\
end\
\
-- ============================================================================\
-- EXPORT CONSTANTS (READ-ONLY)\
-- ============================================================================\
\
Core.ASYNC = ABI.STATES.ASYNC\
Core.NONE = ABI.STATES.NONE\
Core.STATES = ABI.STATES\
\
-- Private API marker - DO NOT EXPOSE VIA PUBLIC CALYX API\
Core._PRIVATE = true\
\
return Core\
"
bundle.modules['lua-fsm-objC.ringbuffer'] = "-- ============================================================================\
-- calyx/fsm/ringbuffer.lua\
-- CALYX Ring Buffer Mailbox\
-- O(1) enqueue/dequeue with backpressure signaling\
-- Lua 5.1.5 Compatible\
-- ============================================================================\
\
local ABI = require(\"abi\")\
\
local RingBuffer = {}\
RingBuffer.__index = RingBuffer\
\
-- ============================================================================\
-- RING BUFFER IMPLEMENTATION\
-- ============================================================================\
\
function RingBuffer.new(max_size, opts)\
	opts = opts or {}\
\
	return setmetatable({\
		queue = {},\
		head = 1,\
		tail = 1,\
		count = 0,\
		max_size = max_size or 1000,\
\
		-- Stats\
		dropped_count = 0,\
		total_processed = 0,\
		total_failed = 0,\
		total_enqueued = 0,\
\
		-- Backpressure policy\
		overflow_policy = opts.overflow_policy or \"drop_newest\", -- drop_newest, drop_oldest, reject\
\
		-- Callbacks\
		on_backpressure = opts.on_backpressure,\
\
		-- Debug mode\
		debug = opts.debug or false,\
	}, RingBuffer)\
end\
\
-- ============================================================================\
-- CORE OPERATIONS (O(1))\
-- ============================================================================\
\
function RingBuffer:enqueue(message)\
	-- Check capacity\
	if self.count >= self.max_size then\
		self.dropped_count = self.dropped_count + 1\
\
		if self.overflow_policy == \"reject\" then\
			return ABI.error_result(\
				ABI.ERRORS.QUEUE_FULL,\
				\"Queue at capacity\",\
				{ count = self.count, max_size = self.max_size, dropped_total = self.dropped_count }\
			)\
		elseif self.overflow_policy == \"drop_oldest\" then\
			-- Dequeue oldest to make room\
			self:dequeue()\
			if self.debug then\
				print(string.format(\"[MAILBOX] Dropped oldest message (policy=drop_oldest)\"))\
			end\
		else -- drop_newest (default)\
			if self.debug and self.dropped_count % 100 == 1 then\
				print(\
					string.format(\
						\"[MAILBOX] Queue full (%d/%d), dropping newest message #%d\",\
						self.count,\
						self.max_size,\
						self.dropped_count\
					)\
				)\
			end\
\
			-- Fire backpressure callback\
			if self.on_backpressure then\
				self.on_backpressure(self:get_stats())\
			end\
\
			return ABI.error_result(\
				ABI.ERRORS.QUEUE_FULL,\
				\"Queue full, message dropped\",\
				{ policy = \"drop_newest\", stats = self:get_stats() }\
			)\
		end\
	end\
\
	-- Insert at tail\
	self.queue[self.tail] = message\
	self.tail = (self.tail % self.max_size) + 1\
	self.count = self.count + 1\
	self.total_enqueued = self.total_enqueued + 1\
\
	if self.debug then\
		print(\
			string.format(\
				\"[MAILBOX] Enqueued: event=%s count=%d/%d\",\
				ABI.safe_tostring(message.event),\
				self.count,\
				self.max_size\
			)\
		)\
	end\
\
	return ABI.success_result({ count = self.count })\
end\
\
function RingBuffer:dequeue()\
	if self.count == 0 then\
		return nil\
	end\
\
	local message = self.queue[self.head]\
	self.queue[self.head] = nil -- Allow GC\
	self.head = (self.head % self.max_size) + 1\
	self.count = self.count - 1\
\
	return message\
end\
\
function RingBuffer:peek()\
	if self.count == 0 then\
		return nil\
	end\
	return self.queue[self.head]\
end\
\
function RingBuffer:has_messages()\
	return self.count > 0\
end\
\
-- ============================================================================\
-- BATCH OPERATIONS\
-- ============================================================================\
\
function RingBuffer:dequeue_batch(max_count)\
	max_count = math.min(max_count or self.count, self.count)\
	local batch = {}\
\
	for i = 1, max_count do\
		local msg = self:dequeue()\
		if msg then\
			table.insert(batch, msg)\
		else\
			break\
		end\
	end\
\
	return batch\
end\
\
-- ============================================================================\
-- STATS & MANAGEMENT\
-- ============================================================================\
\
function RingBuffer:get_stats()\
	return {\
		queued = self.count,\
		max_size = self.max_size,\
		dropped = self.dropped_count,\
		free_slots = self.max_size - self.count,\
		total_processed = self.total_processed,\
		total_failed = self.total_failed,\
		total_enqueued = self.total_enqueued,\
		utilization = (self.count / self.max_size) * 100,\
	}\
end\
\
function RingBuffer:clear(only_non_retained)\
	if only_non_retained then\
		-- Scan and rebuild without non-retained messages\
		local kept = {}\
		local cleared = 0\
\
		while self:has_messages() do\
			local msg = self:dequeue()\
			if msg._retention_marker then\
				table.insert(kept, msg)\
			else\
				cleared = cleared + 1\
			end\
		end\
\
		-- Re-enqueue kept messages\
		for i = 1, #kept do\
			self:enqueue(kept[i])\
		end\
\
		if self.debug then\
			print(string.format(\"[MAILBOX] Cleared %d non-retained messages (%d retained)\", cleared, #kept))\
		end\
\
		return cleared\
	else\
		local cleared = self.count\
\
		-- Clear queue\
		self.queue = {}\
		self.head = 1\
		self.tail = 1\
		self.count = 0\
		self.dropped_count = 0\
\
		if self.debug then\
			print(string.format(\"[MAILBOX] Cleared all %d messages\", cleared))\
		end\
\
		return cleared\
	end\
end\
\
function RingBuffer:set_max_size(new_size)\
	if new_size < self.count then\
		-- Truncate excess messages\
		local excess = self.count - new_size\
		for i = 1, excess do\
			self:dequeue()\
		end\
\
		if self.debug then\
			print(string.format(\"[MAILBOX] Truncated %d messages to fit new size %d\", excess, new_size))\
		end\
	end\
\
	self.max_size = new_size\
end\
\
return RingBuffer\
"
bundle.modules['lua-fsm-objC.objc'] = "-- ============================================================================\
-- lua-fsm-objC.objc (FIXED - Proper upvalue ordering)\
-- ============================================================================\
-- core/objc.lua (REFACTORED - Closure Pattern)\
local ABI = require(\"abi\")\
local Core = require(\"core\")\
local Utils = require(\"utils\")\
\
local ObjCFSM = {}\
\
function ObjCFSM.create(opts)\
	opts = opts or {}\
\
	-- ============================================================\
	-- PRIVATE STATE (Hidden in Closure - LLM Cannot Touch)\
	-- ============================================================\
	local current_state = opts.initial or ABI.STATES.IDLE\
	local transition_map = Core.build_transition_map(opts.events or {})\
	local fsm_name = opts.name or string.format(\"fsm_%x\", math.floor(math.random() * 0xFFFFFF))\
	local debug_mode = opts.debug or false\
	local _ = opts.strict_mode -- Mark as used to silence warning\
\
	-- Callback storage (private)\
	local callbacks = {}\
	if opts.callbacks then\
		for k, v in pairs(opts.callbacks) do\
			callbacks[k] = v\
		end\
	end\
\
	-- ============================================================\
	-- PUBLIC API (Define FIRST so it's available as upvalue)\
	-- ============================================================\
	local public_api = {}\
\
	-- ============================================================\
	-- PRIVATE HELPER FUNCTIONS\
	-- ============================================================\
\
	local function can_transition_internal(event_name)\
		return Core.can_transition(transition_map, event_name, current_state)\
	end\
\
	local function execute_transition(event_name, data, options)\
		local can, target = can_transition_internal(event_name)\
		if not can then\
			return ABI.error_result(\
				ABI.ERRORS.INVALID_TRANSITION,\
				string.format(\"Cannot transition from '%s' via '%s'\", current_state, event_name),\
				{ current = current_state, event = event_name }\
			)\
		end\
\
		local ctx = Core.create_context(event_name, current_state, target, data, options)\
\
		-- BEFORE callback\
		if callbacks[\"onbefore\" .. event_name] then\
			local result = callbacks[\"onbefore\" .. event_name](public_api, ctx)\
			if result == false then\
				return ABI.error_result(\
					ABI.ERRORS.CANCELLED_BEFORE,\
					string.format(\"Transition cancelled in onbefore%s\", event_name),\
					{ event = event_name, context = ctx }\
				)\
			end\
		end\
\
		-- LEAVE callback\
		if callbacks[\"onleave\" .. ctx.from] then\
			local result = callbacks[\"onleave\" .. ctx.from](public_api, ctx)\
			if result == false then\
				return ABI.error_result(\
					ABI.ERRORS.CANCELLED_LEAVE,\
					string.format(\"Transition cancelled in onleave%s\", ctx.from),\
					{ event = event_name, context = ctx }\
				)\
			end\
		end\
\
		-- Update state\
		current_state = target\
		public_api.current = current_state -- Update current field\
		ABI.clock:advance() -- Advance clock on successful transition\
\
		-- ENTER callback\
		if callbacks[\"onenter\" .. ctx.to] then\
			callbacks[\"onenter\" .. ctx.to](public_api, ctx)\
		end\
\
		-- AFTER callback\
		if callbacks[\"onafter\" .. event_name] then\
			callbacks[\"onafter\" .. event_name](public_api, ctx)\
		end\
\
		-- State change notification\
		if callbacks.onstatechange then\
			callbacks.onstatechange(public_api, ctx)\
		end\
\
		return ABI.success_result(ctx)\
	end\
\
	-- ============================================================\
	-- WRAP CALLBACKS TO UPDATE CURRENT FIELD\
	-- (Define AFTER public_api but BEFORE final API assembly)\
	-- ============================================================\
\
	-- Store original onstatechange\
	local original_onstatechange = callbacks.onstatechange\
\
	-- Wrap it\
	callbacks.onstatechange = function(fsm, ctx)\
		public_api.current = ctx.to\
		if original_onstatechange then\
			original_onstatechange(fsm, ctx)\
		end\
	end\
\
	-- ============================================================\
	-- BUILD PUBLIC API\
	-- ============================================================\
\
	-- Read-only state access (compatibility with both styles)\
	public_api.current = current_state\
\
	function public_api.get_state()\
		return current_state\
	end\
\
	function public_api.get_name()\
		return fsm_name\
	end\
\
	-- Predicate checks\
	function public_api.can(event_name)\
		return can_transition_internal(event_name)\
	end\
\
	function public_api.is(state_name)\
		return current_state == state_name\
	end\
\
	-- ============================================================================\
	-- lua-fsm-objC.mailbox (FIXED - Event method creation)\
	-- ============================================================================\
\
	-- Dynamic event methods\
	for _, ev in ipairs(opts.events or {}) do\
		-- Create the event method unconditionally at construction time\
		public_api[ev.name] = function(params)\
			params = params or {}\
			return execute_transition(ev.name, params.data, params.options)\
		end\
	end\
\
	-- Export constants (read-only)\
	public_api.ASYNC = ABI.STATES.ASYNC\
	public_api.NONE = ABI.STATES.NONE\
	public_api.STATES = ABI.STATES\
\
	-- ============================================================\
	-- FREEZE PUBLIC API (Prevent Method Injection)\
	-- ============================================================\
\
	local frozen = {}\
	local mt = {\
		__index = public_api,\
		__newindex = function(t, k, v)\
			-- Allow setting 'current' field\
			if k == \"current\" then\
				rawset(t, k, v)\
				return\
			end\
			error(string.format(\"Cannot modify FSM public API: attempted to set '%s'\", tostring(k)), 2)\
		end,\
		__metatable = {\
			protected = true,\
			type = \"CALYX_OBJC_FSM\",\
			version = ABI.VERSION,\
		},\
	}\
	setmetatable(frozen, mt)\
\
	-- Initialize current field\
	frozen.current = current_state\
\
	return frozen\
end\
\
return ObjCFSM\
"
bundle.modules['lua-fsm-objC.mailbox'] = "-- ============================================================================\
-- lua-fsm-objC.mailbox (FIXED - Simplified event registration)\
-- ============================================================================\
-- core/mailbox.lua (REFACTORED - Closure Pattern)\
local ABI = require(\"abi\")\
local Core = require(\"core\")\
local RingBuffer = require(\"ringbuffer\")\
local utils = require(\"utils\")\
local MailboxFSM = {}\
\
function MailboxFSM.create(opts)\
	opts = opts or {}\
\
	-- ============================================================\
	-- PRIVATE STATE (Closure-Protected)\
	-- ============================================================\
	local current_state = opts.initial or ABI.STATES.IDLE\
	local async_state = ABI.STATES.NONE\
	local transition_context = nil\
	local current_event = nil\
	local transition_map = Core.build_transition_map(opts.events or {})\
\
	-- Lua 5.1 math.random fix\
	math.randomseed(os.time())\
	math.random()\
	math.random()\
	math.random()\
	local fsm_name = opts.name or string.format(\"fsm_%x\", math.floor(math.random() * 16777215))\
	local debug_mode = opts.debug or false\
\
	local mailbox = RingBuffer.new(opts.mailbox_size or 1000, {\
		overflow_policy = opts.overflow_policy or \"drop_newest\",\
		debug = debug_mode,\
		on_backpressure = opts.on_backpressure,\
	})\
\
	local callbacks = {}\
	if opts.callbacks then\
		for k, v in pairs(opts.callbacks) do\
			callbacks[k] = v\
		end\
	end\
\
	-- ============================================================\
	-- PUBLIC API (Forward Declaration)\
	-- ============================================================\
	local public_api = {}\
\
	-- ============================================================\
	-- PRIVATE HELPERS\
	-- ============================================================\
\
	local function can_transition_internal(event_name)\
		return Core.can_transition(transition_map, event_name, current_state)\
	end\
\
	local function safe_tostring(value)\
		if value == nil then\
			return \"nil\"\
		end\
		local t = type(value)\
		if t == \"string\" then\
			return value\
		end\
		if t == \"table\" then\
			return \"table\"\
		end\
		return tostring(value)\
	end\
\
	local function complete_async()\
		if not transition_context then\
			return ABI.error_result(ABI.ERRORS.CONTEXT_LOST, \"Transition context lost\")\
		end\
\
		local ctx = transition_context\
\
		if async_state and async_state ~= ABI.STATES.NONE then\
			local suffix = string.match(async_state, \"_(.+)$\")\
\
			if suffix == \"LEAVE_WAIT\" then\
				current_state = ctx.to\
				public_api.current = current_state\
				public_api.asyncState = async_state\
				ABI.clock:advance()\
\
				async_state = ctx.event .. ABI.STATES.SUFFIXES.ENTER_WAIT\
				public_api.asyncState = async_state\
\
				if callbacks[\"onenter\" .. ctx.to] then\
					local result = callbacks[\"onenter\" .. ctx.to](public_api, ctx)\
					if result == ABI.STATES.ASYNC then\
						return ABI.success_result({ async = true, stage = async_state })\
					end\
				end\
\
				return complete_async()\
			elseif suffix == \"ENTER_WAIT\" then\
				if callbacks[\"onafter\" .. ctx.event] then\
					callbacks[\"onafter\" .. ctx.event](public_api, ctx)\
				end\
\
				if callbacks.onstatechange then\
					callbacks.onstatechange(public_api, ctx)\
				end\
\
				async_state = ABI.STATES.NONE\
				public_api.asyncState = async_state\
				current_event = nil\
				transition_context = nil\
				ABI.clock:advance()\
\
				return ABI.success_result(ctx)\
			end\
		end\
\
		return ABI.error_result(ABI.ERRORS.INVALID_STAGE, \"Invalid async stage\", { stage = async_state })\
	end\
\
	local function execute_transition(event_name, data, options)\
		-- Validate event name\
		if type(event_name) ~= \"string\" then\
			return ABI.error_result(\
				ABI.ERRORS.INVALID_EVENT_NAME,\
				string.format(\"Event name must be string, got %s\", type(event_name))\
			)\
		end\
\
		-- Transition collision check\
		if async_state ~= ABI.STATES.NONE and not string.find(async_state, event_name, 1, true) then\
			return ABI.error_result(\
				ABI.ERRORS.TRANSITION_IN_PROGRESS,\
				string.format(\
					\"Transition '%s' in progress, cannot start '%s'\",\
					safe_tostring(current_event),\
					safe_tostring(event_name)\
				),\
				{ current_event = current_event, requested_event = event_name }\
			)\
		end\
\
		-- Resume if in async state\
		if async_state ~= ABI.STATES.NONE and string.find(async_state, event_name, 1, true) then\
			return complete_async()\
		end\
\
		-- Start new transition\
		local can, target = can_transition_internal(event_name)\
		if not can then\
			return ABI.error_result(\
				ABI.ERRORS.INVALID_TRANSITION,\
				string.format(\
					\"Cannot transition from '%s' via '%s'\",\
					safe_tostring(current_state),\
					safe_tostring(event_name)\
				),\
				{ current = current_state, event = event_name }\
			)\
		end\
\
		local ctx = Core.create_context(event_name, current_state, target, data, options)\
\
		-- BEFORE callback\
		if callbacks[\"onbefore\" .. event_name] then\
			if callbacks[\"onbefore\" .. event_name](public_api, ctx) == false then\
				return ABI.error_result(ABI.ERRORS.CANCELLED_BEFORE, \"Transition cancelled\", { event = event_name })\
			end\
		end\
\
		-- LEAVE callback\
		if callbacks[\"onleave\" .. ctx.from] then\
			local result = callbacks[\"onleave\" .. ctx.from](public_api, ctx)\
			if result == false then\
				return ABI.error_result(ABI.ERRORS.CANCELLED_LEAVE, \"Transition cancelled\", { from = ctx.from })\
			end\
\
			if result == ABI.STATES.ASYNC then\
				transition_context = ctx\
				current_event = event_name\
				async_state = event_name .. ABI.STATES.SUFFIXES.LEAVE_WAIT\
				public_api.asyncState = async_state\
				ABI.clock:advance()\
				return ABI.success_result({ async = true, stage = async_state })\
			end\
		end\
\
		-- Synchronous completion\
		current_state = target\
		public_api.current = current_state\
		ABI.clock:advance()\
\
		if callbacks[\"onenter\" .. ctx.to] then\
			callbacks[\"onenter\" .. ctx.to](public_api, ctx)\
		end\
		if callbacks[\"onafter\" .. event_name] then\
			callbacks[\"onafter\" .. event_name](public_api, ctx)\
		end\
		if callbacks.onstatechange then\
			callbacks.onstatechange(public_api, ctx)\
		end\
\
		return ABI.success_result(ctx)\
	end\
\
	-- ============================================================\
	-- BUILD PUBLIC API\
	-- ============================================================\
	public_api.current = current_state\
	public_api.asyncState = async_state\
	public_api.mailbox = mailbox -- Always expose for test suite\
\
	-- Core getters\
	function public_api.get_state()\
		return current_state\
	end\
	function public_api.get_async_state()\
		return async_state\
	end\
	function public_api.get_name()\
		return fsm_name\
	end\
	function public_api.can(event_name)\
		return can_transition_internal(event_name)\
	end\
	function public_api.is(state_name)\
		return current_state == state_name\
	end\
\
	-- Resume async transition\
	function public_api.resume()\
		if async_state == ABI.STATES.NONE then\
			return ABI.error_result(ABI.ERRORS.NO_ACTIVE_TRANSITION, \"No active transition\")\
		end\
		return complete_async()\
	end\
\
	-- ============================================================\
	-- SEND - Handle multiple signature patterns\
	-- ============================================================\
	function public_api.send(event, params)\
		local event_name\
		local event_data = {}\
		local event_options = {}\
		local retain = false\
		local no_retry = false\
\
		-- Pattern 1: send(\"event\", {data=..., options=...})\
		if type(event) == \"string\" and type(params) == \"table\" then\
			event_name = event\
			event_data = params.data or {}\
			event_options = params.options or {}\
			retain = params.retain or false\
			no_retry = params.no_retry or false\
\
		-- Pattern 2: send({event=\"event\", data=..., options=...})\
		elseif type(event) == \"table\" and event.event then\
			event_name = event.event\
			event_data = event.data or {}\
			event_options = event.options or {}\
			retain = event.retain or false\
			no_retry = event.no_retry or false\
\
		-- Pattern 3: send({data=...}, \"event\")  -- Test suite uses this\
		elseif type(event) == \"table\" and type(params) == \"string\" then\
			event_name = params\
			event_data = event.data or {}\
			event_options = event.options or {}\
			retain = event.retain or false\
			no_retry = event.no_retry or false\
\
		-- Pattern 4: send(\"event\")\
		elseif type(event) == \"string\" then\
			event_name = event\
\
		-- Pattern 5: send({event=\"event\"})\
		elseif type(event) == \"table\" and event.event then\
			event_name = event.event\
		else\
			return ABI.error_result(\
				ABI.ERRORS.INVALID_EVENT_NAME,\
				\"send() could not determine event name from arguments\"\
			)\
		end\
\
		-- Ensure event_name is a string\
		if type(event_name) ~= \"string\" then\
			event_name = tostring(event_name)\
		end\
\
		local message = {\
			event = event_name,\
			data = event_data,\
			options = event_options,\
			from_fsm = fsm_name,\
			tick = ABI.clock:now(),\
			_retention_marker = retain,\
			no_retry = no_retry,\
			retry_count = 0,\
		}\
\
		return mailbox:enqueue(message)\
	end\
\
	-- Process mailbox\
	function public_api.process_mailbox()\
		if mailbox.processing then\
			return ABI.error_result(ABI.ERRORS.ALREADY_PROCESSING, \"Mailbox is being processed\")\
		end\
\
		mailbox.processing = true\
		local processed = 0\
		local failed = 0\
		local retry_queue = {}\
\
		while mailbox:has_messages() do\
			local msg = mailbox:dequeue()\
			if not msg then\
				break\
			end\
\
			if not msg.event or type(msg.event) ~= \"string\" then\
				failed = failed + 1\
				mailbox.total_failed = (mailbox.total_failed or 0) + 1\
			else\
				-- Direct execution\
				local result = execute_transition(msg.event, msg.data, msg.options)\
\
				if result and result.ok == true then\
					processed = processed + 1\
					mailbox.total_processed = (mailbox.total_processed or 0) + 1\
				else\
					failed = failed + 1\
					mailbox.total_failed = (mailbox.total_failed or 0) + 1\
\
					if not msg.no_retry and (msg.retry_count or 0) < 3 then\
						msg.retry_count = (msg.retry_count or 0) + 1\
						table.insert(retry_queue, msg)\
					end\
				end\
			end\
			ABI.clock:advance()\
		end\
\
		-- Re-enqueue retry messages\
		for i = 1, #retry_queue do\
			mailbox:enqueue(retry_queue[i])\
		end\
\
		mailbox.processing = false\
\
		return ABI.success_result({\
			processed = processed,\
			failed = failed,\
			retry_queued = #retry_queue,\
			remaining = mailbox.count,\
		})\
	end\
\
	-- Mailbox management methods\
	function public_api.mailbox_stats()\
		return mailbox:get_stats()\
	end\
\
	function public_api.clear_mailbox()\
		return ABI.success_result({ cleared = mailbox:clear() })\
	end\
\
	function public_api.set_mailbox_size(new_size)\
		mailbox:set_max_size(new_size)\
		return ABI.success_result({ size = mailbox.max_size })\
	end\
\
	-- ============================================================\
	-- DYNAMIC EVENT METHODS - SIMPLIFIED REGISTRATION\
	-- ============================================================\
	for _, ev in ipairs(opts.events or {}) do\
		local event_name = ev.name\
\
		-- Always create the event method - no collision checking at construction time\
		public_api[event_name] = function(params)\
			params = params or {}\
			if debug_mode then\
				print(\"[CALL] \" .. utils.format_objc_call(event_name, params))\
			end\
			return execute_transition(event_name, params.data, params.options)\
		end\
	end\
\
	-- Export constants\
	public_api.ASYNC = ABI.STATES.ASYNC\
	public_api.NONE = ABI.STATES.NONE\
	public_api.STATES = ABI.STATES\
\
	-- ============================================================\
	-- FREEZE PUBLIC API\
	-- ============================================================\
	local frozen = {}\
	local mt = {\
		__index = public_api,\
		__newindex = function(t, k, v)\
			if k == \"current\" or k == \"asyncState\" then\
				rawset(t, k, v)\
				return\
			end\
			error(string.format(\"Cannot modify FSM: attempted to set field '%s'\", tostring(k)), 2)\
		end,\
		__metatable = {\
			protected = true,\
			type = \"CALYX_MAILBOX_FSM\",\
			version = ABI.VERSION,\
		},\
	}\
	setmetatable(frozen, mt)\
\
	frozen.current = current_state\
	frozen.asyncState = async_state\
\
	return frozen\
end\
\
return MailboxFSM\
"

-- Survival Lab Registration (Topologically Sorted)
package.preload['lua-fsm-objC.abi'] = function() return load_module('lua-fsm-objC.abi') end
package.preload['abi'] = package.preload['lua-fsm-objC.abi']
package.preload['lua-fsm-objC.utils'] = function() return load_module('lua-fsm-objC.utils') end
package.preload['utils'] = package.preload['lua-fsm-objC.utils']
package.preload['lua-fsm-objC.core'] = function() return load_module('lua-fsm-objC.core') end
package.preload['core'] = package.preload['lua-fsm-objC.core']
package.preload['lua-fsm-objC.ringbuffer'] = function() return load_module('lua-fsm-objC.ringbuffer') end
package.preload['ringbuffer'] = package.preload['lua-fsm-objC.ringbuffer']
package.preload['lua-fsm-objC.objc'] = function() return load_module('lua-fsm-objC.objc') end
package.preload['objc'] = package.preload['lua-fsm-objC.objc']
package.preload['lua-fsm-objC.mailbox'] = function() return load_module('lua-fsm-objC.mailbox') end
package.preload['mailbox'] = package.preload['lua-fsm-objC.mailbox']

-- Short aliases for core modules
package.preload['abi'] = package.preload['lua-fsm-objC.abi']
package.preload['core'] = package.preload['lua-fsm-objC.core']
package.preload['mailbox'] = package.preload['lua-fsm-objC.mailbox']
package.preload['objc'] = package.preload['lua-fsm-objC.objc']
package.preload['utils'] = package.preload['lua-fsm-objC.utils']
package.preload['ringbuffer'] = package.preload['lua-fsm-objC.ringbuffer']

-- ===== CALYX FSM UNIFIED API =====

local lua_fsm_abi = require('lua-fsm-objC.abi')
local lua_fsm_core = require('lua-fsm-objC.core')
local lua_fsm_mailbox = require('lua-fsm-objC.mailbox')
local lua_fsm_objc = require('lua-fsm-objC.objc')
local lua_fsm_utils = require('lua-fsm-objC.utils')

return {
    -- Creation APIs
    create_object_fsm = lua_fsm_objc.create,
    create_mailbox_fsm = lua_fsm_mailbox.create,

    -- Shared constants
    ASYNC = lua_fsm_abi.STATES.ASYNC,
    NONE = lua_fsm_abi.STATES.NONE,
    STATES = lua_fsm_abi.STATES,
    ERRORS = lua_fsm_abi.ERRORS,

    -- Version info
    VERSION = lua_fsm_abi.VERSION,
    NAME = lua_fsm_abi.NAME,
    SPEC = lua_fsm_abi.SPEC,

    -- Diagnostics (debug mode only)
    diagnostics = {
        format_objc_call = lua_fsm_utils.format_objc_call,
        serialize = lua_fsm_utils.serialize_table,
        clock = lua_fsm_abi.clock,
    },
}