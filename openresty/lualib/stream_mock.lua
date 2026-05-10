local cjson = require("cjson")
local mock = require("mock_data")

local _M = {}

-- Function to stream mock data continuously
function _M.stream_data(duration_seconds, interval_ms)
	duration_seconds = duration_seconds or 60
	interval_ms = interval_ms or 1000
	local start_time = ngx.now()
	local iterations = 0

	-- Set headers for streaming
	ngx.header["Content-Type"] = "application/x-ndjson"
	ngx.header["X-Content-Type-Options"] = "nosniff"

	-- Send initial message
	local init_msg = cjson.encode({
		type = "stream_start",
		duration = duration_seconds,
		interval = interval_ms,
		timestamp = ngx.now(),
	})
	ngx.print(init_msg .. "\n")
	ngx.flush()

	while ngx.now() - start_time < duration_seconds do
		-- Generate random data safely
		local user_id = math.random(100, 105)

		-- Wrap in pcall to catch errors
		local ok, scenario = pcall(mock.run_mock_scenario, user_id, 3)

		if not ok then
			-- Send error message instead of crashing
			local error_msg = cjson.encode({
				type = "error",
				error = tostring(scenario),
				timestamp = ngx.now(),
			})
			ngx.print(error_msg .. "\n")
			ngx.flush()
		else
			-- Send successful data
			local output = cjson.encode({
				type = "mock_data",
				iteration = iterations,
				timestamp = ngx.now(),
				user_id = user_id,
				data = scenario,
			})
			ngx.print(output .. "\n")
			ngx.flush()
		end

		iterations = iterations + 1

		-- Wait for interval (non-blocking sleep)
		ngx.sleep(interval_ms / 1000)
	end

	-- Send end message
	local end_msg = cjson.encode({
		type = "stream_end",
		total_iterations = iterations,
		duration = duration_seconds,
		timestamp = ngx.now(),
	})
	ngx.print(end_msg .. "\n")
	ngx.flush()
end

return _M
