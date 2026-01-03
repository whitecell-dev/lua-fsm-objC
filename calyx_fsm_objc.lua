-- ============================================================================
-- calyx_fsm_objc.lua
-- CALYX FSM with Objective-C-style Named Parameters
-- FIXED: Proper context persistence for async resume
-- ============================================================================

local machine = {}
machine.__index = machine

local STATES = {
	NONE = "none",
	ASYNC = "async",
	SUFFIXES = {
		LEAVE_WAIT = "_LEAVE_WAIT",
		ENTER_WAIT = "_ENTER_WAIT",
	},
}

-- ============== UTILITIES ==============

local function timestamp()
	return os.date("%Y-%m-%d %H:%M:%S")
end

local function success(data)
	return true, {
		ok = true,
		data = data,
		timestamp = timestamp(),
	}
end

local function failure(error_type, details)
	return false, {
		ok = false,
		error_type = error_type,
		details = details,
		timestamp = timestamp(),
	}
end

local function log_trace(label, ctx)
	local parts = {}
	table.insert(parts, string.format("event=%s", ctx.event or "?"))
	table.insert(parts, string.format("from=%s", ctx.from or "?"))
	table.insert(parts, string.format("to=%s", ctx.to or "?"))

	-- Log data fields
	if ctx.data then
		for k, v in pairs(ctx.data) do
			table.insert(parts, string.format("data.%s=%s", k, tostring(v)))
		end
	end

	-- Log options fields
	if ctx.options then
		for k, v in pairs(ctx.options) do
			table.insert(parts, string.format("options.%s=%s", k, tostring(v)))
		end
	end

	print(string.format("[TRACE %s] %s", label, table.concat(parts, " ")))
end

local function objc_call(method, params)
	local parts = {}

	if params.data then
		for k, v in pairs(params.data) do
			table.insert(parts, string.format("data.%s:%s", k, tostring(v)))
		end
	end

	if params.options then
		for k, v in pairs(params.options) do
			table.insert(parts, string.format("options.%s:%s", k, tostring(v)))
		end
	end

	if #parts > 0 then
		return string.format("%s(%s)", method, table.concat(parts, " "))
	else
		return string.format("%s()", method)
	end
end

-- ============== TRANSITION HANDLERS ==============

local function handle_initial(self, p)
	local can, target = self:can(p.event)
	if not can then
		return failure("invalid_transition", p.event)
	end

	-- Create full context with ALL parameters
	local context = {
		event = p.event,
		from = self.current,
		to = target,
		data = p.data or {},
		options = p.options or {},
	}

	-- CRITICAL: Store context for async resume
	self._context = context
	self.currentTransitioningEvent = p.event
	self.asyncState = p.event .. STATES.SUFFIXES.LEAVE_WAIT

	log_trace("BEFORE", context)

	-- Call before handler
	local before_cb = self["onbefore" .. p.event]
	if before_cb and before_cb(context) == false then
		return failure("cancelled_before", p.event)
	end

	-- Call leave handler
	local leave_cb = self["onleave" .. self.current]
	local leave_result = nil
	if leave_cb then
		leave_result = leave_cb(context)
	end

	if leave_result == false then
		return failure("cancelled_leave", p.event)
	end

	-- Check if async
	if leave_result ~= STATES.ASYNC then
		return self:_complete(context)
	end

	return true
end

local function handle_leave_wait(self, ctx)
	self.current = ctx.to
	self.asyncState = ctx.event .. STATES.SUFFIXES.ENTER_WAIT

	log_trace("ENTER", ctx)

	-- Call enter handler
	local enter_cb = self["onenter" .. ctx.to] or self["on" .. ctx.to]
	local enter_result = nil
	if enter_cb then
		enter_result = enter_cb(ctx)
	end

	-- Check if async
	if enter_result ~= STATES.ASYNC then
		return self:_complete(ctx)
	end

	return true
end

local function handle_enter_wait(self, ctx)
	log_trace("AFTER", ctx)

	-- Call after handlers
	local after_cb = self["onafter" .. ctx.event] or self["on" .. ctx.event]
	if after_cb then
		after_cb(ctx)
	end

	if self.onstatechange then
		self.onstatechange(ctx)
	end

	-- Cleanup
	self.asyncState = STATES.NONE
	self.currentTransitioningEvent = nil
	self._context = nil

	return success(ctx)
end

local HANDLERS = {
	initial = handle_initial,
	LEAVE_WAIT = handle_leave_wait,
	ENTER_WAIT = handle_enter_wait,
}

-- ============== CORE TRANSITION ENGINE ==============

function machine:_complete(ctx)
	local stage = "initial"

	if self.asyncState and self.asyncState ~= STATES.NONE then
		local suffix = self.asyncState:match("_(.+)$")
		if suffix then
			stage = suffix
		end
	end

	local handler = HANDLERS[stage]
	if not handler then
		return failure("invalid_stage", stage)
	end

	return handler(self, ctx)
end

-- ============== PUBLIC API ==============

function machine.create(opts)
	assert(opts and opts.events, "events required")

	local fsm = {
		current = opts.initial or "none",
		asyncState = STATES.NONE,
		events = {},
		currentTransitioningEvent = nil,
		_context = nil,
	}

	setmetatable(fsm, machine)

	-- Build event methods
	for _, ev in ipairs(opts.events) do
		fsm.events[ev.name] = { map = {} }

		-- Build transition map
		local targets = type(ev.from) == "table" and ev.from or { ev.from }
		for _, st in ipairs(targets) do
			fsm.events[ev.name].map[st] = ev.to
		end

		-- Create event method (Objective-C style)
		fsm[ev.name] = function(self, params)
			params = params or {}

			local call_str = objc_call(ev.name, params)
			print("[CALL] " .. call_str)

			-- Check for conflicting transition
			if self.asyncState ~= STATES.NONE and not self.asyncState:find(ev.name) then
				return failure("transition_in_progress", self.currentTransitioningEvent)
			end

			-- If in middle of THIS event, resume it
			if self.asyncState ~= STATES.NONE and self.asyncState:find(ev.name) then
				print("[RESUME] Continuing async transition for " .. ev.name)
				return self:_complete(self._context)
			end

			-- Otherwise, start new transition
			local p = {
				event = ev.name,
				data = params.data or {},
				options = params.options or {},
			}

			return handle_initial(self, p)
		end
	end

	-- Add callbacks
	for k, v in pairs(opts.callbacks or {}) do
		fsm[k] = v
	end

	return fsm
end

-- CRITICAL FIX: Add explicit resume() method
function machine:resume()
	if self.asyncState == STATES.NONE then
		return failure("no_active_transition", "resume")
	end

	if not self._context then
		return failure("no_context", "context lost")
	end

	print(string.format("[RESUME] Continuing transition: %s (%s)", self.currentTransitioningEvent, self.asyncState))

	return self:_complete(self._context)
end

function machine:can(event)
	local ev = self.events[event]
	if not ev then
		return false
	end
	local target = ev.map[self.current] or ev.map["*"]
	return target ~= nil, target
end

function machine:is(state)
	return self.current == state
end

machine.NONE = STATES.NONE
machine.ASYNC = STATES.ASYNC

-- ============================================================================
-- data_handlers.lua (ALBEO Layer)
-- ============================================================================

local handlers = {}

local function simulate_work(duration_sec, message)
	local start_time = os.time()
	while os.time() < start_time + duration_sec do
		-- Busy wait simulation
	end
	print(string.format("[ALBEO] Work Complete: %s (Duration: %d sec)", message, duration_sec))
end

-- Handler: Load file (onleaveIDLE)
function handlers.load_file(ctx)
	print(string.format("[ALBEO] Loading file: %s", ctx.data.file_path or "unknown"))
	print(
		string.format("[ALBEO] User ID: %s, Timeout: %s", ctx.options.user_id or "none", ctx.options.timeout or "none")
	)
	simulate_work(2, "File read complete")
	return machine.ASYNC
end

-- Handler: Validate data (onleaveLOADING)
function handlers.validate_data(ctx)
	print(string.format("[ALBEO] Validating data for user: %s", ctx.options.user_id or "unknown"))
	simulate_work(1, "Data validation passed")
	return machine.ASYNC
end

-- Handler: Transform data (onleaveVALIDATING)
function handlers.transform_data(ctx)
	print(string.format("[ALBEO] Transforming data with mode: %s", ctx.data.transform_mode or "default"))
	simulate_work(3, "Data transformation complete")
	return machine.ASYNC
end

-- Handler: Save results (onleaveTRANSFORMING)
function handlers.save_results(ctx)
	print(string.format("[ALBEO] Saving results to DB: %s", ctx.options.db_endpoint or "default"))
	simulate_work(1, "Database save acknowledged")
	return machine.ASYNC
end

-- Handler: Cleanup (onenterCLEANUP)
function handlers.cleanup(ctx)
	print(string.format("[ALBEO] FINAL: Clearing temp files for %s", ctx.data.file_path or "unknown"))
	return nil -- Synchronous
end

-- ============================================================================
-- DEMO (IMPO Layer)
-- ============================================================================

print("================================================================")
print("CALYX FSM Objective-C Style Demo")
print("================================================================")

-- Create pipeline
local pipeline = machine.create({
	initial = "IDLE",

	events = {
		{ name = "startWithFile", from = "IDLE", to = "LOADING" },
		{ name = "loaded", from = "LOADING", to = "VALIDATING" },
		{ name = "validated", from = "VALIDATING", to = "TRANSFORMING" },
		{ name = "completeWithMode", from = "TRANSFORMING", to = "SAVING" },
		{ name = "savedToDB", from = "SAVING", to = "CLEANUP" },
	},

	callbacks = {
		onleaveIDLE = handlers.load_file,
		onleaveLOADING = handlers.validate_data,
		onleaveVALIDATING = handlers.transform_data,
		onleaveTRANSFORMING = handlers.save_results,
		onenterCLEANUP = handlers.cleanup,

		onstatechange = function(ctx)
			print(string.format("--> FSM TRANSITION: %s -> %s (Event: %s)", ctx.from, ctx.to, ctx.event))
		end,
	},
})

print(string.format("\nInitial State: %s\n", pipeline.current))

-- Helper function to resume async transitions
local function resume_async()
	local start_time = os.date("%H:%M:%S")
	print(string.format("\n[%s] Resuming async transition...", start_time))

	local ok, res = pipeline:resume()

	local end_time = os.date("%H:%M:%S")
	if ok then
		print(string.format("[%s] ✓ SUCCESS: New state = %s\n", end_time, pipeline.current))
	else
		print(string.format("[%s] ✗ FAILURE: %s\n", end_time, res.error_type))
	end

	return ok
end

-- ============================================================================
-- EXECUTION SEQUENCE
-- ============================================================================

print("--- PHASE 1: START INGESTION (startWithFile) ---")
pipeline:startWithFile({
	data = { file_path = "financial_report_Q4.csv" },
	options = { user_id = 456, timeout = 30 },
})
print(string.format("Current State: %s, Async: %s", pipeline.current, pipeline.asyncState))

resume_async()

print("--- PHASE 2: LOAD COMPLETE (loaded) ---")
pipeline:loaded() -- This will use STORED context from startWithFile!
print(string.format("Current State: %s, Async: %s", pipeline.current, pipeline.asyncState))

resume_async()

print("--- PHASE 3: VALIDATION COMPLETE (validated) ---")
pipeline:validated({
	data = { transform_mode = "normalization" },
})
print(string.format("Current State: %s, Async: %s", pipeline.current, pipeline.asyncState))

resume_async()

print("--- PHASE 4: TRANSFORMATION COMPLETE (completeWithMode) ---")
pipeline:completeWithMode({
	options = { parallel = true },
})
print(string.format("Current State: %s, Async: %s", pipeline.current, pipeline.asyncState))

resume_async()

print("--- PHASE 5: SAVE COMPLETE (savedToDB) ---")
pipeline:savedToDB({
	options = { db_endpoint = "prod-main-db" },
})
print(string.format("Current State: %s, Async: %s", pipeline.current, pipeline.asyncState))

resume_async()

print("================================================================")
print(string.format("FINAL STATE: %s", pipeline.current))
print(string.format("Async State: %s", pipeline.asyncState))
print("================================================================")
print("\n✓ Demo Complete - All Transitions Successful")

return machine
