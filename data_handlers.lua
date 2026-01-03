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
