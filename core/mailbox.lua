-- ============================================================================
-- lua-fsm-objC.mailbox (FIXED - Simplified event registration)
-- ============================================================================
-- core/mailbox.lua (REFACTORED - Closure Pattern)
local ABI = require("abi")
local Core = require("core")
local RingBuffer = require("ringbuffer")
local utils = require("utils")
local MailboxFSM = {}

function MailboxFSM.create(opts)
	opts = opts or {}

	-- ============================================================
	-- PRIVATE STATE (Closure-Protected)
	-- ============================================================
	local current_state = opts.initial or ABI.STATES.IDLE
	local async_state = ABI.STATES.NONE
	local transition_context = nil
	local current_event = nil
	local transition_map = Core.build_transition_map(opts.events or {})

	-- Lua 5.1 math.random fix
	math.randomseed(os.time())
	math.random()
	math.random()
	math.random()
	local fsm_name = opts.name or string.format("fsm_%x", math.floor(math.random() * 16777215))
	local debug_mode = opts.debug or false

	local mailbox = RingBuffer.new(opts.mailbox_size or 1000, {
		overflow_policy = opts.overflow_policy or "drop_newest",
		debug = debug_mode,
		on_backpressure = opts.on_backpressure,
	})

	local callbacks = {}
	if opts.callbacks then
		for k, v in pairs(opts.callbacks) do
			callbacks[k] = v
		end
	end

	-- ============================================================
	-- PUBLIC API (Forward Declaration)
	-- ============================================================
	local public_api = {}

	-- ============================================================
	-- PRIVATE HELPERS
	-- ============================================================

	local function can_transition_internal(event_name)
		return Core.can_transition(transition_map, event_name, current_state)
	end

	local function safe_tostring(value)
		if value == nil then
			return "nil"
		end
		local t = type(value)
		if t == "string" then
			return value
		end
		if t == "table" then
			return "table"
		end
		return tostring(value)
	end

	local function complete_async()
		if not transition_context then
			return ABI.error_result(ABI.ERRORS.CONTEXT_LOST, "Transition context lost")
		end

		local ctx = transition_context

		if async_state and async_state ~= ABI.STATES.NONE then
			local suffix = string.match(async_state, "_(.+)$")

			if suffix == "LEAVE_WAIT" then
				current_state = ctx.to
				public_api.current = current_state
				public_api.asyncState = async_state
				ABI.clock:advance()

				async_state = ctx.event .. ABI.STATES.SUFFIXES.ENTER_WAIT
				public_api.asyncState = async_state

				if callbacks["onenter" .. ctx.to] then
					local result = callbacks["onenter" .. ctx.to](public_api, ctx)
					if result == ABI.STATES.ASYNC then
						return ABI.success_result({ async = true, stage = async_state })
					end
				end

				return complete_async()
			elseif suffix == "ENTER_WAIT" then
				if callbacks["onafter" .. ctx.event] then
					callbacks["onafter" .. ctx.event](public_api, ctx)
				end

				if callbacks.onstatechange then
					callbacks.onstatechange(public_api, ctx)
				end

				async_state = ABI.STATES.NONE
				public_api.asyncState = async_state
				current_event = nil
				transition_context = nil
				ABI.clock:advance()

				return ABI.success_result(ctx)
			end
		end

		return ABI.error_result(ABI.ERRORS.INVALID_STAGE, "Invalid async stage", { stage = async_state })
	end

	local function execute_transition(event_name, data, options)
		-- Validate event name
		if type(event_name) ~= "string" then
			return ABI.error_result(
				ABI.ERRORS.INVALID_EVENT_NAME,
				string.format("Event name must be string, got %s", type(event_name))
			)
		end

		-- Transition collision check
		if async_state ~= ABI.STATES.NONE and not string.find(async_state, event_name, 1, true) then
			return ABI.error_result(
				ABI.ERRORS.TRANSITION_IN_PROGRESS,
				string.format(
					"Transition '%s' in progress, cannot start '%s'",
					safe_tostring(current_event),
					safe_tostring(event_name)
				),
				{ current_event = current_event, requested_event = event_name }
			)
		end

		-- Resume if in async state
		if async_state ~= ABI.STATES.NONE and string.find(async_state, event_name, 1, true) then
			return complete_async()
		end

		-- Start new transition
		local can, target = can_transition_internal(event_name)
		if not can then
			return ABI.error_result(
				ABI.ERRORS.INVALID_TRANSITION,
				string.format(
					"Cannot transition from '%s' via '%s'",
					safe_tostring(current_state),
					safe_tostring(event_name)
				),
				{ current = current_state, event = event_name }
			)
		end

		local ctx = Core.create_context(event_name, current_state, target, data, options)

		-- BEFORE callback
		if callbacks["onbefore" .. event_name] then
			if callbacks["onbefore" .. event_name](public_api, ctx) == false then
				return ABI.error_result(ABI.ERRORS.CANCELLED_BEFORE, "Transition cancelled", { event = event_name })
			end
		end

		-- LEAVE callback
		if callbacks["onleave" .. ctx.from] then
			local result = callbacks["onleave" .. ctx.from](public_api, ctx)
			if result == false then
				return ABI.error_result(ABI.ERRORS.CANCELLED_LEAVE, "Transition cancelled", { from = ctx.from })
			end

			if result == ABI.STATES.ASYNC then
				transition_context = ctx
				current_event = event_name
				async_state = event_name .. ABI.STATES.SUFFIXES.LEAVE_WAIT
				public_api.asyncState = async_state
				ABI.clock:advance()
				return ABI.success_result({ async = true, stage = async_state })
			end
		end

		-- Synchronous completion
		current_state = target
		public_api.current = current_state
		ABI.clock:advance()

		if callbacks["onenter" .. ctx.to] then
			callbacks["onenter" .. ctx.to](public_api, ctx)
		end
		if callbacks["onafter" .. event_name] then
			callbacks["onafter" .. event_name](public_api, ctx)
		end
		if callbacks.onstatechange then
			callbacks.onstatechange(public_api, ctx)
		end

		return ABI.success_result(ctx)
	end

	-- ============================================================
	-- BUILD PUBLIC API
	-- ============================================================
	public_api.current = current_state
	public_api.asyncState = async_state
	public_api.mailbox = mailbox -- Always expose for test suite

	-- Core getters
	function public_api.get_state()
		return current_state
	end
	function public_api.get_async_state()
		return async_state
	end
	function public_api.get_name()
		return fsm_name
	end
	function public_api.can(event_name)
		return can_transition_internal(event_name)
	end
	function public_api.is(state_name)
		return current_state == state_name
	end

	-- Resume async transition
	function public_api.resume()
		if async_state == ABI.STATES.NONE then
			return ABI.error_result(ABI.ERRORS.NO_ACTIVE_TRANSITION, "No active transition")
		end
		return complete_async()
	end

	-- ============================================================
	-- SEND - Handle multiple signature patterns
	-- ============================================================
	function public_api.send(event, params)
		local event_name
		local event_data = {}
		local event_options = {}
		local retain = false
		local no_retry = false

		-- Pattern 1: send("event", {data=..., options=...})
		if type(event) == "string" and type(params) == "table" then
			event_name = event
			event_data = params.data or {}
			event_options = params.options or {}
			retain = params.retain or false
			no_retry = params.no_retry or false

		-- Pattern 2: send({event="event", data=..., options=...})
		elseif type(event) == "table" and event.event then
			event_name = event.event
			event_data = event.data or {}
			event_options = event.options or {}
			retain = event.retain or false
			no_retry = event.no_retry or false

		-- Pattern 3: send({data=...}, "event")  -- Test suite uses this
		elseif type(event) == "table" and type(params) == "string" then
			event_name = params
			event_data = event.data or {}
			event_options = event.options or {}
			retain = event.retain or false
			no_retry = event.no_retry or false

		-- Pattern 4: send("event")
		elseif type(event) == "string" then
			event_name = event

		-- Pattern 5: send({event="event"})
		elseif type(event) == "table" and event.event then
			event_name = event.event
		else
			return ABI.error_result(
				ABI.ERRORS.INVALID_EVENT_NAME,
				"send() could not determine event name from arguments"
			)
		end

		-- Ensure event_name is a string
		if type(event_name) ~= "string" then
			event_name = tostring(event_name)
		end

		local message = {
			event = event_name,
			data = event_data,
			options = event_options,
			from_fsm = fsm_name,
			tick = ABI.clock:now(),
			_retention_marker = retain,
			no_retry = no_retry,
			retry_count = 0,
		}

		return mailbox:enqueue(message)
	end

	-- Process mailbox
	function public_api.process_mailbox()
		if mailbox.processing then
			return ABI.error_result(ABI.ERRORS.ALREADY_PROCESSING, "Mailbox is being processed")
		end

		mailbox.processing = true
		local processed = 0
		local failed = 0
		local retry_queue = {}

		while mailbox:has_messages() do
			local msg = mailbox:dequeue()
			if not msg then
				break
			end

			if not msg.event or type(msg.event) ~= "string" then
				failed = failed + 1
				mailbox.total_failed = (mailbox.total_failed or 0) + 1
			else
				-- Direct execution
				local result = execute_transition(msg.event, msg.data, msg.options)

				if result and result.ok == true then
					processed = processed + 1
					mailbox.total_processed = (mailbox.total_processed or 0) + 1
				else
					failed = failed + 1
					mailbox.total_failed = (mailbox.total_failed or 0) + 1

					if not msg.no_retry and (msg.retry_count or 0) < 3 then
						msg.retry_count = (msg.retry_count or 0) + 1
						table.insert(retry_queue, msg)
					end
				end
			end
			ABI.clock:advance()
		end

		-- Re-enqueue retry messages
		for i = 1, #retry_queue do
			mailbox:enqueue(retry_queue[i])
		end

		mailbox.processing = false

		return ABI.success_result({
			processed = processed,
			failed = failed,
			retry_queued = #retry_queue,
			remaining = mailbox.count,
		})
	end

	-- Mailbox management methods
	function public_api.mailbox_stats()
		return mailbox:get_stats()
	end

	function public_api.clear_mailbox()
		return ABI.success_result({ cleared = mailbox:clear() })
	end

	function public_api.set_mailbox_size(new_size)
		mailbox:set_max_size(new_size)
		return ABI.success_result({ size = mailbox.max_size })
	end

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

	-- Export constants
	public_api.ASYNC = ABI.STATES.ASYNC
	public_api.NONE = ABI.STATES.NONE
	public_api.STATES = ABI.STATES

	-- ============================================================
	-- FREEZE PUBLIC API
	-- ============================================================
	local frozen = {}
	local mt = {
		__index = public_api,
		__newindex = function(t, k, v)
			if k == "current" or k == "asyncState" then
				rawset(t, k, v)
				return
			end
			error(string.format("Cannot modify FSM: attempted to set field '%s'", tostring(k)), 2)
		end,
		__metatable = {
			protected = true,
			type = "CALYX_MAILBOX_FSM",
			version = ABI.VERSION,
		},
	}
	setmetatable(frozen, mt)

	frozen.current = current_state
	frozen.asyncState = async_state

	return frozen
end

return MailboxFSM
