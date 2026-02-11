-- tools/test_runner.lua
-- CALYX PROFESSIONAL TEST RUNNER
-- VM-grade test execution with automatic reporting

local ReportGen = require("tools.reportgen")

local TestRunner = {}
TestRunner.__index = TestRunner

function TestRunner.new(report_dir)
	return setmetatable({
		reporter = ReportGen.new(report_dir or "survival_reports"),
		suite_start_time = nil,
		test_results = {},
		current_test = nil,
	}, TestRunner)
end

function TestRunner:start_suite()
	self.suite_start_time = os.time()
	print(string.rep("=", 70))
	print("CALYX SURVIVAL SUITE")
	print("Professional VM-Grade Testing Framework")
	print(string.rep("=", 70))
	print(string.format("Started: %s", os.date("%Y-%m-%d %H:%M:%S")))
	print("Report directory: survival_reports/")
	print(string.rep("-", 70))
end

function TestRunner:run(test_name, test_fn)
	print(string.format("\n🏃 RUNNING: %s", test_name))
	print(string.rep("-", 50))

	local start_time = os.time()
	self.current_test = test_name

	-- Create test environment with reporting API
	local test_env = {
		-- Reporting API (injected into test)
		fail = function(id, severity, evidence, impact, resolution)
			return self.reporter:add_failure(id, severity, evidence, impact, resolution)
		end,

		warn = function(message, category)
			return self.reporter:add_warning(message, category or "general")
		end,

		metric = function(name, value, unit)
			return self.reporter:add_metric(name, value, unit or "")
		end,

		-- Utility functions
		log = function(message, level)
			level = level or "INFO"
			print(string.format("[%s] %s", level, message))
		end,

		trace = function(message)
			local info = debug.getinfo(2, "Sl")
			print(string.format("[TRACE] %s:%d %s", info.short_src, info.currentline, message))
		end,

		-- Test control
		skip = function(reason)
			error("TEST_SKIPPED: " .. (reason or "No reason given"))
		end,

		-- Access to globals (safely)
		_G = _G,
		require = require,
	}

	-- Set up the test environment
	setmetatable(test_env, {
		__index = function(t, k)
			-- Allow access to standard Lua libraries
			if package.loaded[k] then
				return package.loaded[k]
			end
			return _G[k]
		end,
	})

	-- Run test with protection
	self.reporter:start_test(test_name)
	local ok, test_error = pcall(setfenv(test_fn, test_env))
	local duration = os.time() - start_time

	-- Handle test result
	local status, summary
	if not ok then
		if test_error:match("TEST_SKIPPED:") then
			status = "SKIPPED"
			summary = test_error:match("TEST_SKIPPED: (.+)$") or "Test skipped"
			self.reporter:add_warning(summary, "skip")
		else
			status = "CRASHED"
			summary = "Unhandled error: " .. test_error
			self.reporter:add_failure(
				"TEST_CRASH",
				"CRITICAL",
				test_error,
				"Test cannot complete",
				"Add error handling to test function"
			)
		end
	else
		status = "COMPLETED"
		summary = string.format("Duration: %d seconds", duration)
	end

	-- Finalize test report
	local result = self.reporter:end_test(status, summary)
	table.insert(self.test_results, result)

	-- Print immediate result
	local status_icon = "?"
	if status == "COMPLETED" then
		status_icon = result.pass and "✅" or "❌"
	elseif status == "SKIPPED" then
		status_icon = "⏭️"
	else
		status_icon = "💥"
	end

	print(string.format("\n%s %s: %s", status_icon, test_name, status))

	if #result.failures > 0 then
		print(string.format("   Failures: %d", #result.failures))
		for i, f in ipairs(result.failures) do
			print(string.format("   %d. [%s] %s", i, f.severity, f.id))
		end
	end

	if #result.warnings > 0 then
		print(string.format("   Warnings: %d", #result.warnings))
	end

	print(string.format("   Duration: %ds", duration))
	print(string.rep("-", 50))

	self.current_test = nil
	return result
end

function TestRunner:end_suite()
	local suite_duration = os.time() - (self.suite_start_time or os.time())

	print(string.rep("=", 70))
	print("TEST SUITE COMPLETE")
	print(string.rep("=", 70))

	-- Generate summary
	local total = #self.test_results
	local passed = 0
	local failed = 0
	local skipped = 0
	local crashed = 0
	local total_failures = 0
	local total_warnings = 0

	for _, result in ipairs(self.test_results) do
		if result.status == "SKIPPED" then
			skipped = skipped + 1
		elseif result.status == "CRASHED" then
			crashed = crashed + 1
			failed = failed + 1
		elseif result.pass then
			passed = passed + 1
		else
			failed = failed + 1
		end

		total_failures = total_failures + #result.failures
		total_warnings = total_warnings + #result.warnings
	end

	-- Print summary
	print(string.format("Total Tests:  %d", total))
	print(string.format("Passed:       %d (%.1f%%)", passed, total > 0 and (passed / total) * 100 or 0))
	print(string.format("Failed:       %d (%.1f%%)", failed, total > 0 and (failed / total) * 100 or 0))
	print(string.format("Skipped:      %d", skipped))
	print(string.format("Crashed:      %d", crashed))
	print(string.format("Total Failures: %d", total_failures))
	print(string.format("Total Warnings: %d", total_warnings))
	print(string.format("Suite Duration: %d seconds", suite_duration))

	-- Generate final summary report
	local summary = self.reporter:generate_summary()

	print(string.rep("=", 70))
	print("Reports written to: survival_reports/")
	print("Summary: survival_reports/test_summary.json")
	print(string.rep("=", 70))

	return {
		total = total,
		passed = passed,
		failed = failed,
		skipped = skipped,
		crashed = crashed,
		total_failures = total_failures,
		total_warnings = total_warnings,
		duration = suite_duration,
		summary = summary,
	}
end

-- Convenience function for simple test runs
function TestRunner.run_single(test_name, test_fn)
	local runner = TestRunner.new()
	runner:start_suite()
	local result = runner:run(test_name, test_fn)
	runner:end_suite()
	return result
end

return TestRunner
