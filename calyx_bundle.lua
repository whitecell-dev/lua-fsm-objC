local bundle = { modules = {}, loaded = {} }

local function load_module(name)
    if bundle.loaded[name] then return bundle.loaded[name] end
    local module = bundle.modules[name]
    if not module then error('MODULE_MISSING: ' .. name) end
    local loader = _G.loadstring or _G.load
    local fn, err = loader(module, name)
    if not fn then error('LOAD_FAILURE ['..name..']: ' .. err) end
    bundle.loaded[name] = fn()
    return bundle.loaded[name]
end

bundle.modules['data_handlers'] = "-- data_handlers.lua (ALBEO Layer)\
\
-- Assume the FSM library is available to access its ASYNC constant\
local machine = require(\"calyx_fsm_objc\")\
\
local handlers = {}\
\
-- Utility to simulate time-consuming operations\
local function simulate_work(duration_sec, message)\
	local start_time = os.time()\
	while os.time() < start_time + duration_sec do\
		-- Busy wait simulation (In a real system, this would be non-blocking I/O)\
	end\
	print(string.format(\"[ALBEO] Work Complete: %s (Duration: %d sec)\", message, duration_sec))\
end\
\
-- ------------------------------------------------------------------\
-- Handlers for the File Ingestion Pipeline\
-- ------------------------------------------------------------------\
\
-- onleaveIDLE handler\
function handlers.load_file(ctx)\
	print(string.format(\"[ALBEO] Loading file: %s\", ctx.data.file_path))\
	-- Simulate 2 seconds of loading time\
	simulate_work(2, \"File read complete\")\
\
	-- If we were truly async, we would start the I/O and return ASYNC immediately.\
	-- For this synchronous demonstration of the FSM structure:\
	return machine.ASYNC -- Tell the FSM to wait for an external transition call\
end\
\
-- onleaveLOADING handler\
function handlers.validate_data(ctx)\
	print(string.format(\"[ALBEO] Validating data for user: %s\", ctx.options.user_id))\
	-- Simulate 1 second of validation\
	simulate_work(1, \"Data validation passed\")\
	return machine.ASYNC\
end\
\
-- onleaveVALIDATING handler\
function handlers.transform_data(ctx)\
	print(string.format(\"[ALBEO] Transforming data with mode: %s\", ctx.data.transform_mode))\
	-- Simulate 3 seconds of heavy computation\
	simulate_work(3, \"Data transformation complete\")\
	return machine.ASYNC\
end\
\
-- onleaveTRANSFORMING handler\
function handlers.save_results(ctx)\
	print(string.format(\"[ALBEO] Saving results to DB: %s\", ctx.options.db_endpoint))\
	-- Simulate 1 second of saving\
	simulate_work(1, \"Database save acknowledged\")\
	return machine.ASYNC\
end\
\
-- onenterCLEANUP handler (Synchronous cleanup)\
function handlers.cleanup(ctx)\
	print(string.format(\"[ALBEO] FINAL: Clearing temp files for %s.\", ctx.data.file_path))\
	-- Cleanup returns nil (or anything not ASYNC), so the transition completes synchronously\
	return nil\
end\
\
return handlers\
"
bundle.modules['calyx_fsm_mailbox'] = "-- ============================================================================\
-- calyx_fsm_mailbox.lua\
-- CALYX FSM with Objective-C Style + Asynchronous Mailbox Queues\
-- Multiple FSMs communicate via message passing (Actor Model)\
-- ✅ FIXED: Context nil-safety guards at capture points\
-- ============================================================================\
\
local machine = {}\
machine.__index = machine\
\
local STATES = {\
	NONE = \"none\",\
	ASYNC = \"async\",\
	SUFFIXES = {\
		LEAVE_WAIT = \"_LEAVE_WAIT\",\
		ENTER_WAIT = \"_ENTER_WAIT\",\
	},\
}\
\
-- ============================================================================\
-- MAILBOX QUEUE SYSTEM\
-- ============================================================================\
\
local Mailbox = {}\
Mailbox.__index = Mailbox\
\
function Mailbox.new()\
	return setmetatable({\
		queue = {},\
		processing = false,\
	}, Mailbox)\
end\
\
function Mailbox:enqueue(message)\
	table.insert(self.queue, message)\
\
	-- Safely log FSM names even when to_fsm is a table object\
	local to_name = message.to_fsm\
	if type(to_name) == \"table\" and to_name.name then\
		to_name = to_name.name\
	elseif type(to_name) ~= \"string\" then\
		to_name = \"self\"\
	end\
\
	local from_name = message.from_fsm or \"external\"\
\
	print(\
		string.format(\
			\"[MAILBOX] Enqueued message: event=%s from=%s to=%s\",\
			tostring(message.event),\
			tostring(from_name),\
			tostring(to_name)\
		)\
	)\
end\
\
function Mailbox:dequeue()\
	if #self.queue > 0 then\
		return table.remove(self.queue, 1)\
	end\
	return nil\
end\
\
function Mailbox:has_messages()\
	return #self.queue > 0\
end\
\
function Mailbox:count()\
	return #self.queue\
end\
\
function Mailbox:clear()\
	self.queue = {}\
end\
\
-- ============================================================================\
-- UTILITIES\
-- ============================================================================\
\
local function timestamp()\
	return os.date(\"%H:%M:%S\")\
end\
\
local function success(data)\
	return true, {\
		ok = true,\
		data = data,\
		timestamp = timestamp(),\
	}\
end\
\
local function failure(error_type, details)\
	return false, {\
		ok = false,\
		error_type = error_type,\
		details = details,\
		timestamp = timestamp(),\
	}\
end\
\
local function log_trace(label, ctx, fsm_name)\
	local parts = {}\
	if fsm_name then\
		table.insert(parts, string.format(\"fsm=%s\", fsm_name))\
	end\
	table.insert(parts, string.format(\"event=%s\", ctx.event or \"?\"))\
	table.insert(parts, string.format(\"from=%s\", ctx.from or \"?\"))\
	table.insert(parts, string.format(\"to=%s\", ctx.to or \"?\"))\
\
	if ctx.data then\
		for k, v in pairs(ctx.data) do\
			table.insert(parts, string.format(\"data.%s=%s\", k, tostring(v)))\
		end\
	end\
\
	if ctx.options then\
		for k, v in pairs(ctx.options) do\
			table.insert(parts, string.format(\"options.%s=%s\", k, tostring(v)))\
		end\
	end\
\
	print(string.format(\"[TRACE %s] %s\", label, table.concat(parts, \" \")))\
end\
\
-- ============================================================================\
-- TRANSITION HANDLERS\
-- ============================================================================\
\
local function handle_initial(self, p)\
	local can, target = self:can(p.event)\
	if not can then\
		return failure(\"invalid_transition\", p.event)\
	end\
\
	local context = {\
		event = p.event,\
		from = self.current,\
		to = target,\
		data = p.data or {},\
		options = p.options or {},\
	}\
\
	self._context = context\
	self.currentTransitioningEvent = p.event\
	self.asyncState = p.event .. STATES.SUFFIXES.LEAVE_WAIT\
\
	log_trace(\"BEFORE\", context, self.name)\
\
	local before_cb = self[\"onbefore\" .. p.event]\
	if before_cb and before_cb(self, context) == false then\
		return failure(\"cancelled_before\", p.event)\
	end\
\
	local leave_cb = self[\"onleave\" .. self.current]\
	local leave_result = nil\
	if leave_cb then\
		leave_result = leave_cb(self, context)\
	end\
\
	if leave_result == false then\
		return failure(\"cancelled_leave\", p.event)\
	end\
\
	if leave_result ~= STATES.ASYNC then\
		return self:_complete(context)\
	end\
\
	return true\
end\
\
local function handle_leave_wait(self, ctx)\
	self.current = ctx.to\
	self.asyncState = ctx.event .. STATES.SUFFIXES.ENTER_WAIT\
\
	log_trace(\"ENTER\", ctx, self.name)\
\
	local enter_cb = self[\"onenter\" .. ctx.to] or self[\"on\" .. ctx.to]\
	local enter_result = nil\
	if enter_cb then\
		enter_result = enter_cb(self, ctx)\
	end\
\
	if enter_result ~= STATES.ASYNC then\
		return self:_complete(ctx)\
	end\
\
	return true\
end\
\
local function handle_enter_wait(self, ctx)\
	log_trace(\"AFTER\", ctx, self.name)\
\
	local after_cb = self[\"onafter\" .. ctx.event] or self[\"on\" .. ctx.event]\
	if after_cb then\
		after_cb(self, ctx)\
	end\
\
	if self.onstatechange then\
		self.onstatechange(self, ctx)\
	end\
\
	self.asyncState = STATES.NONE\
	self.currentTransitioningEvent = nil\
	self._context = nil\
\
	return success(ctx)\
end\
\
local HANDLERS = {\
	initial = handle_initial,\
	LEAVE_WAIT = handle_leave_wait,\
	ENTER_WAIT = handle_enter_wait,\
}\
\
-- ============================================================================\
-- CORE TRANSITION ENGINE\
-- ============================================================================\
\
function machine:_complete(ctx)\
	-- ✅ CRITICAL FIX: Ensure ctx is never nil at capture point\
	-- This prevents \"attempt to index local 'ctx' (a nil value)\" crashes\
	if not ctx then\
		-- Try to recover from self._context first\
		ctx = self._context\
	end\
	\
	if not ctx then\
		-- Last resort: create synthetic context\
		ctx = {\
			event = self.currentTransitioningEvent or \"unknown\",\
			from = self.current,\
			to = self.current,  -- Stay in same state\
			data = {},\
			options = {},\
			synthetic = true,\
			injected_at = \"_complete\",\
			timestamp = timestamp(),\
		}\
		self._context = ctx\
		print(string.format(\"[SEMANTIC GUARD] Injected synthetic context for %s at _complete\", self.name))\
	end\
	\
	local stage = \"initial\"\
	if self.asyncState and self.asyncState ~= STATES.NONE then\
		local suffix = self.asyncState:match(\"_(.+)$\")\
		if suffix then\
			stage = suffix\
		end\
	end\
	\
	local handler = HANDLERS[stage]\
	if not handler then\
		return failure(\"invalid_stage\", stage)\
	end\
	\
	return handler(self, ctx)\
end\
\
-- ============================================================================\
-- MAILBOX METHODS\
-- ============================================================================\
\
function machine:send(event, params)\
	params = params or {}\
	local message = {\
		event = event,\
		data = params.data or {},\
		options = params.options or {},\
		from_fsm = self.name,\
		to_fsm = params.to_fsm,\
		timestamp = timestamp(),\
	}\
\
	if params.to_fsm then\
		local target_fsm = params.to_fsm\
		if target_fsm.mailbox then\
			target_fsm.mailbox:enqueue(message)\
		else\
			print(string.format(\"[ERROR] Target FSM has no mailbox: %s\", target_fsm.name or \"unknown\"))\
		end\
	else\
		self.mailbox:enqueue(message)\
	end\
\
	return true\
end\
\
function machine:process_mailbox()\
	if not self.mailbox then\
		return failure(\"no_mailbox\", \"FSM has no mailbox\")\
	end\
	if self.mailbox.processing then\
		return failure(\"already_processing\", \"Mailbox is being processed\")\
	end\
\
	self.mailbox.processing = true\
	local processed = 0\
\
	print(string.format(\"\\n[%s] Processing mailbox for %s (%d messages)\", timestamp(), self.name, self.mailbox:count()))\
\
	while self.mailbox:has_messages() do\
		local message = self.mailbox:dequeue()\
		print(\
			string.format(\
				\"[%s] Processing message: %s from %s\",\
				timestamp(),\
				message.event,\
				message.from_fsm or \"external\"\
			)\
		)\
\
		if self[message.event] then\
			local ok, result = self[message.event](self, {\
				data = message.data,\
				options = message.options,\
			})\
			if not ok then\
				print(string.format(\"[ERROR] Failed to process message: %s\", result.error_type or \"unknown\"))\
			end\
		else\
			print(string.format(\"[ERROR] Unknown event: %s\", message.event))\
		end\
		processed = processed + 1\
	end\
\
	self.mailbox.processing = false\
	print(string.format(\"[%s] Mailbox processing complete: %d messages processed\\n\", timestamp(), processed))\
\
	return success({ processed = processed })\
end\
\
-- ============================================================================\
-- PUBLIC API\
-- ============================================================================\
\
function machine.create(opts)\
	assert(opts and opts.events, \"events required\")\
\
	local fsm = {\
		name = opts.name or \"unnamed_fsm\",\
		current = opts.initial or \"none\",\
		asyncState = STATES.NONE,\
		events = {},\
		currentTransitioningEvent = nil,\
		_context = nil,\
		mailbox = Mailbox.new(),\
	}\
\
	setmetatable(fsm, machine)\
\
	for _, ev in ipairs(opts.events) do\
		fsm.events[ev.name] = { map = {} }\
		local targets = type(ev.from) == \"table\" and ev.from or { ev.from }\
		for _, st in ipairs(targets) do\
			fsm.events[ev.name].map[st] = ev.to\
		end\
		\
		fsm[ev.name] = function(self, params)\
			params = params or {}\
			\
			-- Check for conflicting transition\
			if self.asyncState ~= STATES.NONE and not self.asyncState:find(ev.name) then\
				return failure(\"transition_in_progress\", self.currentTransitioningEvent)\
			end\
			\
			-- ✅ FIX: If resuming, guard against nil context\
			if self.asyncState ~= STATES.NONE and self.asyncState:find(ev.name) then\
				if not self._context then\
					print(string.format(\"[SEMANTIC ERROR] Context lost during resume of %s, clearing stale async state\", ev.name))\
					-- Clear stale async state and start fresh\
					self.asyncState = STATES.NONE\
					self.currentTransitioningEvent = nil\
					-- Fall through to start new transition\
				else\
					-- Valid resume path\
					return self:_complete(self._context)\
				end\
			end\
			\
			-- Start new transition\
			local p = {\
				event = ev.name,\
				data = params.data or {},\
				options = params.options or {},\
			}\
			\
			return handle_initial(self, p)\
		end\
	end\
\
	for k, v in pairs(opts.callbacks or {}) do\
		fsm[k] = v\
	end\
\
	return fsm\
end\
\
function machine:resume()\
	if self.asyncState == STATES.NONE then\
		return failure(\"no_active_transition\", \"resume\")\
	end\
	if not self._context then\
		return failure(\"no_context\", \"context lost\")\
	end\
	return self:_complete(self._context)\
end\
\
function machine:can(event)\
	local ev = self.events[event]\
	if not ev then\
		return false\
	end\
	local target = ev.map[self.current] or ev.map[\"*\"]\
	return target ~= nil, target\
end\
\
function machine:is(state)\
	return self.current == state\
end\
\
machine.NONE = STATES.NONE\
machine.ASYNC = STATES.ASYNC\
\
return machine"
bundle.modules['calyx_fsm_objc'] = "-- ============================================================================\
-- calyx_fsm_objc.lua\
-- CALYX FSM with Objective-C-style Named Parameters\
-- FIXED: Proper context persistence for async resume\
-- ============================================================================\
\
local machine = {}\
machine.__index = machine\
\
local STATES = {\
	NONE = \"none\",\
	ASYNC = \"async\",\
	SUFFIXES = {\
		LEAVE_WAIT = \"_LEAVE_WAIT\",\
		ENTER_WAIT = \"_ENTER_WAIT\",\
	},\
}\
\
-- ============== UTILITIES ==============\
\
local function timestamp()\
	return os.date(\"%Y-%m-%d %H:%M:%S\")\
end\
\
local function success(data)\
	return true, {\
		ok = true,\
		data = data,\
		timestamp = timestamp(),\
	}\
end\
\
local function failure(error_type, details)\
	return false, {\
		ok = false,\
		error_type = error_type,\
		details = details,\
		timestamp = timestamp(),\
	}\
end\
\
local function log_trace(label, ctx)\
	local parts = {}\
	table.insert(parts, string.format(\"event=%s\", ctx.event or \"?\"))\
	table.insert(parts, string.format(\"from=%s\", ctx.from or \"?\"))\
	table.insert(parts, string.format(\"to=%s\", ctx.to or \"?\"))\
\
	-- Log data fields\
	if ctx.data then\
		for k, v in pairs(ctx.data) do\
			table.insert(parts, string.format(\"data.%s=%s\", k, tostring(v)))\
		end\
	end\
\
	-- Log options fields\
	if ctx.options then\
		for k, v in pairs(ctx.options) do\
			table.insert(parts, string.format(\"options.%s=%s\", k, tostring(v)))\
		end\
	end\
\
	print(string.format(\"[TRACE %s] %s\", label, table.concat(parts, \" \")))\
end\
\
local function objc_call(method, params)\
	local parts = {}\
\
	if params.data then\
		for k, v in pairs(params.data) do\
			table.insert(parts, string.format(\"data.%s:%s\", k, tostring(v)))\
		end\
	end\
\
	if params.options then\
		for k, v in pairs(params.options) do\
			table.insert(parts, string.format(\"options.%s:%s\", k, tostring(v)))\
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
-- ============== TRANSITION HANDLERS ==============\
\
local function handle_initial(self, p)\
	local can, target = self:can(p.event)\
	if not can then\
		return failure(\"invalid_transition\", p.event)\
	end\
\
	-- Create full context with ALL parameters\
	local context = {\
		event = p.event,\
		from = self.current,\
		to = target,\
		data = p.data or {},\
		options = p.options or {},\
	}\
\
	-- CRITICAL: Store context for async resume\
	self._context = context\
	self.currentTransitioningEvent = p.event\
	self.asyncState = p.event .. STATES.SUFFIXES.LEAVE_WAIT\
\
	log_trace(\"BEFORE\", context)\
\
	-- Call before handler\
	local before_cb = self[\"onbefore\" .. p.event]\
	if before_cb and before_cb(context) == false then\
		return failure(\"cancelled_before\", p.event)\
	end\
\
	-- Call leave handler\
	local leave_cb = self[\"onleave\" .. self.current]\
	local leave_result = nil\
	if leave_cb then\
		leave_result = leave_cb(context)\
	end\
\
	if leave_result == false then\
		return failure(\"cancelled_leave\", p.event)\
	end\
\
	-- Check if async\
	if leave_result ~= STATES.ASYNC then\
		return self:_complete(context)\
	end\
\
	return true\
end\
\
local function handle_leave_wait(self, ctx)\
	self.current = ctx.to\
	self.asyncState = ctx.event .. STATES.SUFFIXES.ENTER_WAIT\
\
	log_trace(\"ENTER\", ctx)\
\
	-- Call enter handler\
	local enter_cb = self[\"onenter\" .. ctx.to] or self[\"on\" .. ctx.to]\
	local enter_result = nil\
	if enter_cb then\
		enter_result = enter_cb(ctx)\
	end\
\
	-- Check if async\
	if enter_result ~= STATES.ASYNC then\
		return self:_complete(ctx)\
	end\
\
	return true\
end\
\
local function handle_enter_wait(self, ctx)\
	log_trace(\"AFTER\", ctx)\
\
	-- Call after handlers\
	local after_cb = self[\"onafter\" .. ctx.event] or self[\"on\" .. ctx.event]\
	if after_cb then\
		after_cb(ctx)\
	end\
\
	if self.onstatechange then\
		self.onstatechange(ctx)\
	end\
\
	-- Cleanup\
	self.asyncState = STATES.NONE\
	self.currentTransitioningEvent = nil\
	self._context = nil\
\
	return success(ctx)\
end\
\
local HANDLERS = {\
	initial = handle_initial,\
	LEAVE_WAIT = handle_leave_wait,\
	ENTER_WAIT = handle_enter_wait,\
}\
\
-- ============== CORE TRANSITION ENGINE ==============\
\
function machine:_complete(ctx)\
	local stage = \"initial\"\
\
	if self.asyncState and self.asyncState ~= STATES.NONE then\
		local suffix = self.asyncState:match(\"_(.+)$\")\
		if suffix then\
			stage = suffix\
		end\
	end\
\
	local handler = HANDLERS[stage]\
	if not handler then\
		return failure(\"invalid_stage\", stage)\
	end\
\
	return handler(self, ctx)\
end\
\
-- ============== PUBLIC API ==============\
\
function machine.create(opts)\
	assert(opts and opts.events, \"events required\")\
\
	local fsm = {\
		current = opts.initial or \"none\",\
		asyncState = STATES.NONE,\
		events = {},\
		currentTransitioningEvent = nil,\
		_context = nil,\
	}\
\
	setmetatable(fsm, machine)\
\
	-- Build event methods\
	for _, ev in ipairs(opts.events) do\
		fsm.events[ev.name] = { map = {} }\
\
		-- Build transition map\
		local targets = type(ev.from) == \"table\" and ev.from or { ev.from }\
		for _, st in ipairs(targets) do\
			fsm.events[ev.name].map[st] = ev.to\
		end\
\
		-- Create event method (Objective-C style)\
		fsm[ev.name] = function(self, params)\
			params = params or {}\
\
			local call_str = objc_call(ev.name, params)\
			print(\"[CALL] \" .. call_str)\
\
			-- Check for conflicting transition\
			if self.asyncState ~= STATES.NONE and not self.asyncState:find(ev.name) then\
				return failure(\"transition_in_progress\", self.currentTransitioningEvent)\
			end\
\
			-- If in middle of THIS event, resume it\
			if self.asyncState ~= STATES.NONE and self.asyncState:find(ev.name) then\
				print(\"[RESUME] Continuing async transition for \" .. ev.name)\
				return self:_complete(self._context)\
			end\
\
			-- Otherwise, start new transition\
			local p = {\
				event = ev.name,\
				data = params.data or {},\
				options = params.options or {},\
			}\
\
			return handle_initial(self, p)\
		end\
	end\
\
	-- Add callbacks\
	for k, v in pairs(opts.callbacks or {}) do\
		fsm[k] = v\
	end\
\
	return fsm\
end\
\
-- CRITICAL FIX: Add explicit resume() method\
function machine:resume()\
	if self.asyncState == STATES.NONE then\
		return failure(\"no_active_transition\", \"resume\")\
	end\
\
	if not self._context then\
		return failure(\"no_context\", \"context lost\")\
	end\
\
	print(string.format(\"[RESUME] Continuing transition: %s (%s)\", self.currentTransitioningEvent, self.asyncState))\
\
	return self:_complete(self._context)\
end\
\
function machine:can(event)\
	local ev = self.events[event]\
	if not ev then\
		return false\
	end\
	local target = ev.map[self.current] or ev.map[\"*\"]\
	return target ~= nil, target\
end\
\
function machine:is(state)\
	return self.current == state\
end\
\
machine.NONE = STATES.NONE\
machine.ASYNC = STATES.ASYNC\
\
-- ============================================================================\
-- data_handlers.lua (ALBEO Layer)\
-- ============================================================================\
\
local handlers = {}\
\
local function simulate_work(duration_sec, message)\
	local start_time = os.time()\
	while os.time() < start_time + duration_sec do\
		-- Busy wait simulation\
	end\
	print(string.format(\"[ALBEO] Work Complete: %s (Duration: %d sec)\", message, duration_sec))\
end\
\
-- Handler: Load file (onleaveIDLE)\
function handlers.load_file(ctx)\
	print(string.format(\"[ALBEO] Loading file: %s\", ctx.data.file_path or \"unknown\"))\
	print(\
		string.format(\"[ALBEO] User ID: %s, Timeout: %s\", ctx.options.user_id or \"none\", ctx.options.timeout or \"none\")\
	)\
	simulate_work(2, \"File read complete\")\
	return machine.ASYNC\
end\
\
-- Handler: Validate data (onleaveLOADING)\
function handlers.validate_data(ctx)\
	print(string.format(\"[ALBEO] Validating data for user: %s\", ctx.options.user_id or \"unknown\"))\
	simulate_work(1, \"Data validation passed\")\
	return machine.ASYNC\
end\
\
-- Handler: Transform data (onleaveVALIDATING)\
function handlers.transform_data(ctx)\
	print(string.format(\"[ALBEO] Transforming data with mode: %s\", ctx.data.transform_mode or \"default\"))\
	simulate_work(3, \"Data transformation complete\")\
	return machine.ASYNC\
end\
\
-- Handler: Save results (onleaveTRANSFORMING)\
function handlers.save_results(ctx)\
	print(string.format(\"[ALBEO] Saving results to DB: %s\", ctx.options.db_endpoint or \"default\"))\
	simulate_work(1, \"Database save acknowledged\")\
	return machine.ASYNC\
end\
\
-- Handler: Cleanup (onenterCLEANUP)\
function handlers.cleanup(ctx)\
	print(string.format(\"[ALBEO] FINAL: Clearing temp files for %s\", ctx.data.file_path or \"unknown\"))\
	return nil -- Synchronous\
end\
\
-- ============================================================================\
-- DEMO (IMPO Layer)\
-- ============================================================================\
\
print(\"================================================================\")\
print(\"CALYX FSM Objective-C Style Demo\")\
print(\"================================================================\")\
\
-- Create pipeline\
local pipeline = machine.create({\
	initial = \"IDLE\",\
\
	events = {\
		{ name = \"startWithFile\", from = \"IDLE\", to = \"LOADING\" },\
		{ name = \"loaded\", from = \"LOADING\", to = \"VALIDATING\" },\
		{ name = \"validated\", from = \"VALIDATING\", to = \"TRANSFORMING\" },\
		{ name = \"completeWithMode\", from = \"TRANSFORMING\", to = \"SAVING\" },\
		{ name = \"savedToDB\", from = \"SAVING\", to = \"CLEANUP\" },\
	},\
\
	callbacks = {\
		onleaveIDLE = handlers.load_file,\
		onleaveLOADING = handlers.validate_data,\
		onleaveVALIDATING = handlers.transform_data,\
		onleaveTRANSFORMING = handlers.save_results,\
		onenterCLEANUP = handlers.cleanup,\
\
		onstatechange = function(ctx)\
			print(string.format(\"--> FSM TRANSITION: %s -> %s (Event: %s)\", ctx.from, ctx.to, ctx.event))\
		end,\
	},\
})\
\
print(string.format(\"\\nInitial State: %s\\n\", pipeline.current))\
\
-- Helper function to resume async transitions\
local function resume_async()\
	local start_time = os.date(\"%H:%M:%S\")\
	print(string.format(\"\\n[%s] Resuming async transition...\", start_time))\
\
	local ok, res = pipeline:resume()\
\
	local end_time = os.date(\"%H:%M:%S\")\
	if ok then\
		print(string.format(\"[%s] ✓ SUCCESS: New state = %s\\n\", end_time, pipeline.current))\
	else\
		print(string.format(\"[%s] ✗ FAILURE: %s\\n\", end_time, res.error_type))\
	end\
\
	return ok\
end\
\
-- ============================================================================\
-- EXECUTION SEQUENCE\
-- ============================================================================\
\
print(\"--- PHASE 1: START INGESTION (startWithFile) ---\")\
pipeline:startWithFile({\
	data = { file_path = \"financial_report_Q4.csv\" },\
	options = { user_id = 456, timeout = 30 },\
})\
print(string.format(\"Current State: %s, Async: %s\", pipeline.current, pipeline.asyncState))\
\
resume_async()\
\
print(\"--- PHASE 2: LOAD COMPLETE (loaded) ---\")\
pipeline:loaded() -- This will use STORED context from startWithFile!\
print(string.format(\"Current State: %s, Async: %s\", pipeline.current, pipeline.asyncState))\
\
resume_async()\
\
print(\"--- PHASE 3: VALIDATION COMPLETE (validated) ---\")\
pipeline:validated({\
	data = { transform_mode = \"normalization\" },\
})\
print(string.format(\"Current State: %s, Async: %s\", pipeline.current, pipeline.asyncState))\
\
resume_async()\
\
print(\"--- PHASE 4: TRANSFORMATION COMPLETE (completeWithMode) ---\")\
pipeline:completeWithMode({\
	options = { parallel = true },\
})\
print(string.format(\"Current State: %s, Async: %s\", pipeline.current, pipeline.asyncState))\
\
resume_async()\
\
print(\"--- PHASE 5: SAVE COMPLETE (savedToDB) ---\")\
pipeline:savedToDB({\
	options = { db_endpoint = \"prod-main-db\" },\
})\
print(string.format(\"Current State: %s, Async: %s\", pipeline.current, pipeline.asyncState))\
\
resume_async()\
\
print(\"================================================================\")\
print(string.format(\"FINAL STATE: %s\", pipeline.current))\
print(string.format(\"Async State: %s\", pipeline.asyncState))\
print(\"================================================================\")\
print(\"\\n✓ Demo Complete - All Transitions Successful\")\
\
return machine\
"

-- Survival Lab Registration
package.preload['data_handlers'] = function() return load_module('data_handlers') end
package.preload['calyx_fsm_mailbox'] = function() return load_module('calyx_fsm_mailbox') end
package.preload['calyx_fsm_objc'] = function() return load_module('calyx_fsm_objc') end

return bundle