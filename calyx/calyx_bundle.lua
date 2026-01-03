-- ======================================================================
-- CALYX LUA BUNDLE - LLM OPTIMIZED FORMAT
-- ======================================================================

local CALYX_METADATA = {
  "format_version":"calyx-lua-1.0",
  "generated_at":"2026-01-03T08:25:30Z",
  "external_deps":[],
  "total_modules":4,
  "layers":{
    "UTILITY":4
  }
}

-- ======================================================================
-- MODULE MAP (name → path, layer)
-- ======================================================================
local MODULE_MAP = {
    ["demo"] = {
        path = "demo.lua",
        layer = "UTILITY",
        exports = ["resume_async_transition"],
    },
    ["calyx_fsm_objc"] = {
        path = "calyx_fsm_objc.lua",
        layer = "UTILITY",
        exports = ["timestamp","success","failure","log_trace","objc_call","handle_initial","handle_leave_wait","handle_enter_wait","simulate_work","resume_async"],
    },
    ["data_handlers"] = {
        path = "data_handlers.lua",
        layer = "UTILITY",
        exports = ["simulate_work"],
    },
    ["calyx_fsm_mailbox"] = {
        path = "calyx_fsm_mailbox.lua",
        layer = "UTILITY",
        exports = ["timestamp","success","failure","log_trace","handle_initial","handle_leave_wait","handle_enter_wait"],
    },
}

-- ======================================================================
-- DEPENDENCY GRAPH (module → [dependencies])
-- ======================================================================
local DEPENDENCY_GRAPH = {
    ["demo"] = ["calyx_fsm_objc","data_handlers"],
    ["calyx_fsm_objc"] = [],
    ["data_handlers"] = ["calyx_fsm_objc"],
    ["calyx_fsm_mailbox"] = [],
}

-- ======================================================================
-- MODULE CONTENTS (PRESERVED EXACTLY)
-- ======================================================================
local MODULE_CONTENTS = {
    -- ------------------------------------------------------------
    -- MODULE: demo
    -- LAYER: UTILITY
    -- PATH: demo.lua
    -- ------------------------------------------------------------
    ["demo"] = [[
-- demo.lua (IMPO Layer / Orchestrator)

local machine = require("calyx_fsm_objc")
local handlers = require("data_handlers")

-- Define the Async Pipeline FSM
local pipeline = machine.create({
	initial = "IDLE",

	events = {
		-- Event 1: startWithFile:forUser:
		{ name = "startWithFile", from = "IDLE", to = "LOADING" },
		-- Event 2: loaded
		{ name = "loaded", from = "LOADING", to = "VALIDATING" },
		-- Event 3: validated
		{ name = "validated", from = "VALIDATING", to = "TRANSFORMING" },
		-- Event 4: completeWithMode:
		{ name = "completeWithMode", from = "TRANSFORMING", to = "SAVING" },
		-- Event 5: savedToDB:
		{ name = "savedToDB", from = "SAVING", to = "CLEANUP" },
	},

	callbacks = {
		-- Delegate to ALBEO handlers
		onleaveIDLE = handlers.load_file,
		onleaveLOADING = handlers.validate_data,
		onleaveVALIDATING = handlers.transform_data,
		onleaveTRANSFORMING = handlers.save_results,
		onenterCLEANUP = handlers.cleanup,

		-- Global trace (shows Objective-C style context)
		onstatechange = function(ctx)
			print(string.format("--> FSM TRANSITION: %s -> %s (Event: %s)", ctx.from, ctx.to, ctx.event))
		end,
	},
})

print("================================================================")
print(string.format("CALYX Pipeline Initialized. State: %s", pipeline.current))
print("================================================================")

-- Helper function to simulate time passing and resuming the FSM
local function resume_async_transition(event_name)
	local start_time = os.date("%H:%M:%S")
	print(string.format("[%s] Resuming transition...", start_time))
	local ok, res = pipeline[event_name](pipeline, {}) -- Pass empty params to resume
	local end_time = os.date("%H:%M:%S")
	if ok then
		print(string.format("[%s] SUCCESS: Transition completed. New state: %s", end_time, pipeline.current))
	else
		print(string.format("[%s] FAILURE: %s", end_time, res.error_type))
	end
end

-- Phase 1: Start Ingestion (IDLE -> LOADING)
print("\n--- PHASE 1: START (Event: startWithFile:forUser:) ---")
-- Objective-C style call: Event is named, parameters are named (data/options table keys)
pipeline:startWithFile({
	data = { file_path = "financial_report_Q4.csv" },
	options = { user_id = 456, timeout = 30 },
})
-- FSM is now paused in "startWithFile_LEAVE_WAIT"

-- Phase 2: Resume Loading (LOADING -> VALIDATING)
print("\n--- PHASE 2: RESUME LOADING (Event: loaded) ---")
resume_async_transition("loaded")
-- FSM is now paused in "loaded_ENTER_WAIT" (if onenterLOADING was ASYNC) or "loaded_LEAVE_WAIT" (if onleaveVALIDATING is next)

-- Phase 3: Resume Validation (VALIDATING -> TRANSFORMING)
print("\n--- PHASE 3: RESUME VALIDATION (Event: validated) ---")
resume_async_transition("validated")
-- FSM is paused in "validated_LEAVE_WAIT"

-- Phase 4: Resume Transformation (TRANSFORMING -> SAVING)
print("\n--- PHASE 4: RESUME TRANSFORMATION (Event: completeWithMode:) ---")
pipeline:completeWithMode({
	data = { transform_mode = "normalization" },
	options = { parallel = true },
})
resume_async_transition("completeWithMode")
-- FSM is paused in "completeWithMode_LEAVE_WAIT"

-- Phase 5: Resume Saving (SAVING -> CLEANUP)
print("\n--- PHASE 5: RESUME SAVING (Event: savedToDB:) ---")
pipeline:savedToDB({
	options = { db_endpoint = "prod-main-db" },
})
resume_async_transition("savedToDB")
-- FSM completes synchronously via onenterCLEANUP and clears context

print("\n================================================================")
print(string.format("FINAL STATE: %s (Async State: %s)", pipeline.current, pipeline.asyncState))
print("================================================================")

]],

    -- ------------------------------------------------------------
    -- MODULE: calyx_fsm_objc
    -- LAYER: UTILITY
    -- PATH: calyx_fsm_objc.lua
    -- ------------------------------------------------------------
    ["calyx_fsm_objc"] = [[
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

]],

    -- ------------------------------------------------------------
    -- MODULE: data_handlers
    -- LAYER: UTILITY
    -- PATH: data_handlers.lua
    -- ------------------------------------------------------------
    ["data_handlers"] = [[
-- data_handlers.lua (ALBEO Layer)

-- Assume the FSM library is available to access its ASYNC constant
local machine = require("calyx_fsm_objc")

local handlers = {}

-- Utility to simulate time-consuming operations
local function simulate_work(duration_sec, message)
	local start_time = os.time()
	while os.time() < start_time + duration_sec do
		-- Busy wait simulation (In a real system, this would be non-blocking I/O)
	end
	print(string.format("[ALBEO] Work Complete: %s (Duration: %d sec)", message, duration_sec))
end

-- ------------------------------------------------------------------
-- Handlers for the File Ingestion Pipeline
-- ------------------------------------------------------------------

-- onleaveIDLE handler
function handlers.load_file(ctx)
	print(string.format("[ALBEO] Loading file: %s", ctx.data.file_path))
	-- Simulate 2 seconds of loading time
	simulate_work(2, "File read complete")

	-- If we were truly async, we would start the I/O and return ASYNC immediately.
	-- For this synchronous demonstration of the FSM structure:
	return machine.ASYNC -- Tell the FSM to wait for an external transition call
end

-- onleaveLOADING handler
function handlers.validate_data(ctx)
	print(string.format("[ALBEO] Validating data for user: %s", ctx.options.user_id))
	-- Simulate 1 second of validation
	simulate_work(1, "Data validation passed")
	return machine.ASYNC
end

-- onleaveVALIDATING handler
function handlers.transform_data(ctx)
	print(string.format("[ALBEO] Transforming data with mode: %s", ctx.data.transform_mode))
	-- Simulate 3 seconds of heavy computation
	simulate_work(3, "Data transformation complete")
	return machine.ASYNC
end

-- onleaveTRANSFORMING handler
function handlers.save_results(ctx)
	print(string.format("[ALBEO] Saving results to DB: %s", ctx.options.db_endpoint))
	-- Simulate 1 second of saving
	simulate_work(1, "Database save acknowledged")
	return machine.ASYNC
end

-- onenterCLEANUP handler (Synchronous cleanup)
function handlers.cleanup(ctx)
	print(string.format("[ALBEO] FINAL: Clearing temp files for %s.", ctx.data.file_path))
	-- Cleanup returns nil (or anything not ASYNC), so the transition completes synchronously
	return nil
end

return handlers

]],

    -- ------------------------------------------------------------
    -- MODULE: calyx_fsm_mailbox
    -- LAYER: UTILITY
    -- PATH: calyx_fsm_mailbox.lua
    -- ------------------------------------------------------------
    ["calyx_fsm_mailbox"] = [[
-- ============================================================================
-- calyx_fsm_mailbox.lua
-- CALYX FSM with Objective-C Style + Asynchronous Mailbox Queues
-- Multiple FSMs communicate via message passing (Actor Model)
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

-- ============================================================================
-- MAILBOX QUEUE SYSTEM
-- ============================================================================

local Mailbox = {}
Mailbox.__index = Mailbox

function Mailbox.new()
	return setmetatable({
		queue = {},
		processing = false,
	}, Mailbox)
end

function Mailbox:enqueue(message)
	table.insert(self.queue, message)

	-- ✅ FIXED: Safely log FSM names even when to_fsm is a table object
	local to_name = message.to_fsm
	if type(to_name) == "table" and to_name.name then
		to_name = to_name.name
	elseif type(to_name) ~= "string" then
		to_name = "self"
	end

	local from_name = message.from_fsm or "external"

	print(
		string.format(
			"[MAILBOX] Enqueued message: event=%s from=%s to=%s",
			tostring(message.event),
			tostring(from_name),
			tostring(to_name)
		)
	)
end

function Mailbox:dequeue()
	if #self.queue > 0 then
		return table.remove(self.queue, 1)
	end
	return nil
end

function Mailbox:has_messages()
	return #self.queue > 0
end

function Mailbox:count()
	return #self.queue
end

function Mailbox:clear()
	self.queue = {}
end

-- ============================================================================
-- UTILITIES
-- ============================================================================

local function timestamp()
	return os.date("%H:%M:%S")
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

local function log_trace(label, ctx, fsm_name)
	local parts = {}
	if fsm_name then
		table.insert(parts, string.format("fsm=%s", fsm_name))
	end
	table.insert(parts, string.format("event=%s", ctx.event or "?"))
	table.insert(parts, string.format("from=%s", ctx.from or "?"))
	table.insert(parts, string.format("to=%s", ctx.to or "?"))

	if ctx.data then
		for k, v in pairs(ctx.data) do
			table.insert(parts, string.format("data.%s=%s", k, tostring(v)))
		end
	end

	if ctx.options then
		for k, v in pairs(ctx.options) do
			table.insert(parts, string.format("options.%s=%s", k, tostring(v)))
		end
	end

	print(string.format("[TRACE %s] %s", label, table.concat(parts, " ")))
end

-- ============================================================================
-- TRANSITION HANDLERS
-- ============================================================================

local function handle_initial(self, p)
	local can, target = self:can(p.event)
	if not can then
		return failure("invalid_transition", p.event)
	end

	local context = {
		event = p.event,
		from = self.current,
		to = target,
		data = p.data or {},
		options = p.options or {},
	}

	self._context = context
	self.currentTransitioningEvent = p.event
	self.asyncState = p.event .. STATES.SUFFIXES.LEAVE_WAIT

	log_trace("BEFORE", context, self.name)

	local before_cb = self["onbefore" .. p.event]
	if before_cb and before_cb(self, context) == false then
		return failure("cancelled_before", p.event)
	end

	local leave_cb = self["onleave" .. self.current]
	local leave_result = nil
	if leave_cb then
		leave_result = leave_cb(self, context)
	end

	if leave_result == false then
		return failure("cancelled_leave", p.event)
	end

	if leave_result ~= STATES.ASYNC then
		return self:_complete(context)
	end

	return true
end

local function handle_leave_wait(self, ctx)
	self.current = ctx.to
	self.asyncState = ctx.event .. STATES.SUFFIXES.ENTER_WAIT

	log_trace("ENTER", ctx, self.name)

	local enter_cb = self["onenter" .. ctx.to] or self["on" .. ctx.to]
	local enter_result = nil
	if enter_cb then
		enter_result = enter_cb(self, ctx)
	end

	if enter_result ~= STATES.ASYNC then
		return self:_complete(ctx)
	end

	return true
end

local function handle_enter_wait(self, ctx)
	log_trace("AFTER", ctx, self.name)

	local after_cb = self["onafter" .. ctx.event] or self["on" .. ctx.event]
	if after_cb then
		after_cb(self, ctx)
	end

	if self.onstatechange then
		self.onstatechange(self, ctx)
	end

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

-- ============================================================================
-- CORE TRANSITION ENGINE
-- ============================================================================

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

-- ============================================================================
-- MAILBOX METHODS
-- ============================================================================

function machine:send(event, params)
	params = params or {}
	local message = {
		event = event,
		data = params.data or {},
		options = params.options or {},
		from_fsm = self.name,
		to_fsm = params.to_fsm,
		timestamp = timestamp(),
	}

	if params.to_fsm then
		local target_fsm = params.to_fsm
		if target_fsm.mailbox then
			target_fsm.mailbox:enqueue(message)
		else
			print(string.format("[ERROR] Target FSM has no mailbox: %s", target_fsm.name or "unknown"))
		end
	else
		self.mailbox:enqueue(message)
	end

	return true
end

function machine:process_mailbox()
	if not self.mailbox then
		return failure("no_mailbox", "FSM has no mailbox")
	end
	if self.mailbox.processing then
		return failure("already_processing", "Mailbox is being processed")
	end

	self.mailbox.processing = true
	local processed = 0

	print(string.format("\n[%s] Processing mailbox for %s (%d messages)", timestamp(), self.name, self.mailbox:count()))

	while self.mailbox:has_messages() do
		local message = self.mailbox:dequeue()
		print(
			string.format(
				"[%s] Processing message: %s from %s",
				timestamp(),
				message.event,
				message.from_fsm or "external"
			)
		)

		if self[message.event] then
			local ok, result = self[message.event](self, {
				data = message.data,
				options = message.options,
			})
			if not ok then
				print(string.format("[ERROR] Failed to process message: %s", result.error_type or "unknown"))
			end
		else
			print(string.format("[ERROR] Unknown event: %s", message.event))
		end
		processed = processed + 1
	end

	self.mailbox.processing = false
	print(string.format("[%s] Mailbox processing complete: %d messages processed\n", timestamp(), processed))

	return success({ processed = processed })
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function machine.create(opts)
	assert(opts and opts.events, "events required")

	local fsm = {
		name = opts.name or "unnamed_fsm",
		current = opts.initial or "none",
		asyncState = STATES.NONE,
		events = {},
		currentTransitioningEvent = nil,
		_context = nil,
		mailbox = Mailbox.new(),
	}

	setmetatable(fsm, machine)

	for _, ev in ipairs(opts.events) do
		fsm.events[ev.name] = { map = {} }
		local targets = type(ev.from) == "table" and ev.from or { ev.from }
		for _, st in ipairs(targets) do
			fsm.events[ev.name].map[st] = ev.to
		end
		fsm[ev.name] = function(self, params)
			params = params or {}
			if self.asyncState ~= STATES.NONE and not self.asyncState:find(ev.name) then
				return failure("transition_in_progress", self.currentTransitioningEvent)
			end
			if self.asyncState ~= STATES.NONE and self.asyncState:find(ev.name) then
				return self:_complete(self._context)
			end
			local p = {
				event = ev.name,
				data = params.data or {},
				options = params.options or {},
			}
			return handle_initial(self, p)
		end
	end

	for k, v in pairs(opts.callbacks or {}) do
		fsm[k] = v
	end

	return fsm
end

function machine:resume()
	if self.asyncState == STATES.NONE then
		return failure("no_active_transition", "resume")
	end
	if not self._context then
		return failure("no_context", "context lost")
	end
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
-- DEMO: TWO FSMs COMMUNICATING VIA MAILBOX
-- ============================================================================

print("================================================================")
print("CALYX FSM MAILBOX DEMO: Producer-Consumer Pattern")
print("================================================================\n")

-- ============================================================================
-- PRODUCER FSM (Data Generator)
-- ============================================================================

local producer = machine.create({
	name = "PRODUCER",
	initial = "IDLE",

	events = {
		{ name = "start", from = "IDLE", to = "GENERATING" },
		{ name = "generated", from = "GENERATING", to = "SENDING" },
		{ name = "sent", from = "SENDING", to = "WAITING" },
		{ name = "acknowledged", from = "WAITING", to = "IDLE" },
	},

	callbacks = {
		onleaveIDLE = function(fsm, ctx)
			print(string.format("[PRODUCER] Starting data generation for: %s", ctx.data.dataset_name or "unknown"))
			return nil -- Synchronous
		end,

		onleaveGENERATING = function(fsm, ctx)
			print("[PRODUCER] Generating data...")
			-- Simulate work
			local start = os.time()
			while os.time() < start + 1 do
			end
			print("[PRODUCER] Data generation complete")
			return nil
		end,

		onleaveSENDING = function(fsm, ctx)
			print("[PRODUCER] Sending data to CONSUMER...")

			-- Send message to consumer
			if ctx.options.consumer_fsm then
				fsm:send("receive", {
					to_fsm = ctx.options.consumer_fsm,
					data = {
						dataset = ctx.data.dataset_name,
						records = 1000,
						format = "csv",
					},
				})
			end

			return nil
		end,

		onstatechange = function(fsm, ctx)
			print(string.format("[PRODUCER] State: %s -> %s", ctx.from, ctx.to))
		end,
	},
})

-- ============================================================================
-- CONSUMER FSM (Data Processor)
-- ============================================================================

local consumer = machine.create({
	name = "CONSUMER",
	initial = "IDLE",

	events = {
		{ name = "receive", from = "IDLE", to = "VALIDATING" },
		{ name = "validated", from = "VALIDATING", to = "PROCESSING" },
		{ name = "processed", from = "PROCESSING", to = "ACKNOWLEDGING" },
		{ name = "acknowledged", from = "ACKNOWLEDGING", to = "IDLE" },
	},

	callbacks = {
		onleaveIDLE = function(fsm, ctx)
			print(
				string.format(
					"[CONSUMER] Received dataset: %s (%s records)",
					ctx.data.dataset or "unknown",
					ctx.data.records or "?"
				)
			)
			return nil
		end,

		onleaveVALIDATING = function(fsm, ctx)
			print("[CONSUMER] Validating data...")
			local start = os.time()
			while os.time() < start + 1 do
			end
			print("[CONSUMER] Validation complete")
			return nil
		end,

		onleavePROCESSING = function(fsm, ctx)
			print("[CONSUMER] Processing data...")
			local start = os.time()
			while os.time() < start + 2 do
			end
			print("[CONSUMER] Processing complete")
			return nil
		end,

		onleaveACKNOWLEDGING = function(fsm, ctx)
			print("[CONSUMER] Sending acknowledgment to PRODUCER...")

			-- Send ACK back to producer
			if ctx.options.producer_fsm then
				fsm:send("acknowledged", {
					to_fsm = ctx.options.producer_fsm,
					data = {
						status = "success",
						processed_records = ctx.data.records,
					},
				})
			end

			return nil
		end,

		onstatechange = function(fsm, ctx)
			print(string.format("[CONSUMER] State: %s -> %s", ctx.from, ctx.to))
		end,
	},
})

-- ============================================================================
-- EXECUTION: PRODUCER SENDS TO CONSUMER
-- ============================================================================

print("=== PHASE 1: Producer generates and sends data ===\n")

-- Start producer
producer:start({
	data = { dataset_name = "financial_report_Q4.csv" },
	options = { consumer_fsm = consumer },
})

producer:generated()
producer:sent({ options = { consumer_fsm = consumer } })
producer:sent({ options = { consumer_fsm = consumer } })

print("\n=== PHASE 2: Consumer processes mailbox ===\n")

-- Process consumer mailbox
consumer:process_mailbox()

-- Continue consumer workflow
consumer:validated()
consumer:processed()
consumer:acknowledged({ options = { producer_fsm = producer } })

print("\n=== PHASE 3: Producer processes acknowledgment ===\n")

-- Process producer mailbox (receives ACK)
producer:process_mailbox()

print("\n=== FINAL STATE ===")
print(string.format("PRODUCER: %s (mailbox: %d messages)", producer.current, producer.mailbox:count()))
print(string.format("CONSUMER: %s (mailbox: %d messages)", consumer.current, consumer.mailbox:count()))

-- ============================================================================
-- DEMO 2: CIRCULAR COMMUNICATION (PING-PONG)
-- ============================================================================

print("\n\n================================================================")
print("DEMO 2: PING-PONG FSM COMMUNICATION")
print("================================================================\n")

local ping_fsm = machine.create({
	name = "PING",
	initial = "READY",

	events = {
		{ name = "ping", from = "READY", to = "WAITING" },
		{ name = "pong", from = "WAITING", to = "READY" },
	},

	callbacks = {
		onleaveREADY = function(fsm, ctx)
			print(string.format("[PING] Sending ping #%d", ctx.data.count or 1))

			if ctx.options.pong_fsm and ctx.data.count <= 3 then
				fsm:send("pong", {
					to_fsm = ctx.options.pong_fsm,
					data = { count = ctx.data.count },
				})
			end
			return nil
		end,

		onleaveWAITING = function(fsm, ctx)
			print(string.format("[PING] Received pong #%d", ctx.data.count or 1))

			-- Send next ping
			if ctx.options.pong_fsm and ctx.data.count < 3 then
				fsm:send("ping", {
					to_fsm = fsm, -- Send to self
					data = { count = (ctx.data.count or 1) + 1 },
				})
			end
			return nil
		end,
	},
})

local pong_fsm = machine.create({
	name = "PONG",
	initial = "READY",

	events = {
		{ name = "pong", from = "READY", to = "WAITING" },
		{ name = "ping", from = "WAITING", to = "READY" },
	},

	callbacks = {
		onleaveREADY = function(fsm, ctx)
			print(string.format("[PONG] Received ping #%d", ctx.data.count or 1))

			-- Send pong back
			if ctx.options.ping_fsm then
				fsm:send("pong", {
					to_fsm = ctx.options.ping_fsm,
					data = { count = ctx.data.count },
				})
			end
			return nil
		end,

		onleaveWAITING = function(fsm, ctx)
			print(string.format("[PONG] Sent pong #%d", ctx.data.count or 1))
			return nil
		end,
	},
})

print("=== Starting Ping-Pong Exchange ===\n")

-- Start the ping-pong
ping_fsm:ping({
	data = { count = 1 },
	options = { pong_fsm = pong_fsm },
})

-- Process mailboxes in rounds
for round = 1, 3 do
	print(string.format("\n--- Round %d ---", round))
	pong_fsm:process_mailbox()
	ping_fsm:process_mailbox()

	-- Continue transitions
	if pong_fsm:can("ping") then
		pong_fsm:ping({ options = { ping_fsm = ping_fsm } })
	end
	if ping_fsm:can("pong") then
		ping_fsm:pong({
			data = { count = round },
			options = { pong_fsm = pong_fsm },
		})
	end
end

print("\n=== Ping-Pong Complete ===")
print(string.format("PING FSM: %s (mailbox: %d)", ping_fsm.current, ping_fsm.mailbox:count()))
print(string.format("PONG FSM: %s (mailbox: %d)", pong_fsm.current, pong_fsm.mailbox:count()))

print("\n================================================================")
print("DEMO COMPLETE")
print("================================================================")

return machine

]],

}

-- ======================================================================
-- PUBLIC API (what to expose)
-- ======================================================================

local function get_module(name)
    -- Retrieve module source by name
    return MODULE_CONTENTS[name] or ""
end

local function list_modules(layer)
    -- List modules, optionally filtered by layer
    local result = {}
    for name, meta in pairs(MODULE_MAP) do
        if not layer or meta.layer == layer then
            table.insert(result, name)
        end
    end
    return result
end

local function get_dependencies(name)
    -- Get module dependencies
    return DEPENDENCY_GRAPH[name] or {}
end

local function get_layer_stats()
    -- Get statistics by layer
    return CALYX_METADATA.layers
end

local function get_external_deps()
    -- Get external dependencies
    return CALYX_METADATA.external_deps
end

-- ======================================================================
-- RUNTIME SHIM (for execution)
-- ======================================================================
local function _calyx_import_shim()
    -- Register modules in package.loaded
    -- Only create packages that exist in our bundle
    local packages = {}
    for name, _ in pairs(MODULE_CONTENTS) do
        local first_dot = name:find(".")
        if first_dot then
            local pkg = name:sub(1, first_dot - 1)
            packages[pkg] = true
        end
    end

    for pkg, _ in pairs(packages) do
        -- Create package table
        local pkg_name = pkg
        local pkg_table = {}
        package.loaded[pkg_name] = pkg_table

        -- Add submodules that belong to this package
        for full_name, content in pairs(MODULE_CONTENTS) do
            if full_name:find("^" .. pkg .. ".") then
                local sub_name = full_name:sub(#pkg + 2)
                local sub_full = pkg .. "." .. sub_name

                -- Execute the module code in its own environment
                local env = {
                    module = { exports = {} },
                    require = require,
                    _G = _G,
                    ... = ...
                }
                setmetatable(env, { __index = _G })
                local fn, err = load(content, sub_full, "t", env)
                if fn then
                    local result = fn()
                    if env.module.exports and next(env.module.exports) then
                        package.loaded[sub_full] = env.module.exports
                        pkg_table[sub_name] = env.module.exports
                    elseif result then
                        package.loaded[sub_full] = result
                        pkg_table[sub_name] = result
                    else
                        package.loaded[sub_full] = env
                        pkg_table[sub_name] = env
                    end
                else
                    error("Failed to load " .. sub_full .. ": " .. err)
                end
            end
        end
    end
end

-- Auto-register on load
_calyx_import_shim()

-- ======================================================================
-- MAIN ENTRY POINT (if run as script)
-- ======================================================================
if arg and arg[0] and debug.getinfo(1, "S").what == "main" then
    print("CALYX Lua Bundle Loaded")
    print(string.format("Modules: %d", #list_modules()))
    print(string.format("Layers: %s", json.encode(get_layer_stats())))
    print("")
    print("Available commands:")
    print("  - get_module(name)")
    print("  - list_modules(layer)")
    print("  - get_dependencies(name)")
    print("  - get_layer_stats()")
    print("  - get_external_deps()")
end

-- ======================================================================
-- EXPORTS
-- ======================================================================
return {
    get_module = get_module,
    list_modules = list_modules,
    get_dependencies = get_dependencies,
    get_layer_stats = get_layer_stats,
    get_external_deps = get_external_deps,
    metadata = CALYX_METADATA,
    module_map = MODULE_MAP,
    dependency_graph = DEPENDENCY_GRAPH,
    module_contents = MODULE_CONTENTS,
}
