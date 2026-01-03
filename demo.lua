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
