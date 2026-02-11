-- tools/reportgen.lua
-- CALYX TEST REPORT GENERATOR
-- Professional JSON reporting with proper array handling

local ReportGen = {}
ReportGen.__index = ReportGen

-- ============================================================================
-- SIMPLE BUT ROBUST JSON ENCODER
-- ============================================================================

local json = {}

function json.encode(tbl)
	local function encode_value(val)
		local t = type(val)

		if t == "string" then
			-- Escape special characters
			return string.format(
				'"%s"',
				val:gsub('["\\\n\r\t]', {
					['"'] = '\\"',
					["\\"] = "\\\\",
					["\n"] = "\\n",
					["\r"] = "\\r",
					["\t"] = "\\t",
				})
			)
		elseif t == "number" then
			-- Handle special numeric cases
			if val ~= val then
				return '"NaN"'
			elseif val == math.huge then
				return '"Infinity"'
			elseif val == -math.huge then
				return '"-Infinity"'
			end
			return tostring(val)
		elseif t == "boolean" then
			return val and "true" or "false"
		elseif t == "table" then
			-- Check if it's an array (sequential integer keys starting at 1)
			local is_array = true
			local count = 0
			for k, _ in pairs(val) do
				if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
					is_array = false
					break
				end
				count = count + 1
			end

			if is_array and count == #val then
				-- Encode as array
				local items = {}
				for i = 1, #val do
					items[i] = encode_value(val[i])
				end
				return "[" .. table.concat(items, ",") .. "]"
			else
				-- Encode as object
				local items = {}
				for k, v in pairs(val) do
					table.insert(items, string.format('"%s":%s', tostring(k), encode_value(v)))
				end
				return "{" .. table.concat(items, ",") .. "}"
			end
		elseif val == nil then
			return "null"
		else
			return string.format('"%s"', tostring(val))
		end
	end

	return encode_value(tbl)
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function timestamp()
	return os.date("%Y-%m-%d %H:%M:%S")
end

local function ensure_directory(dir)
	-- Try shell command first
	local ok = os.execute("mkdir -p " .. dir .. " 2>/dev/null")
	if not ok then
		-- Try LuaFileSystem if available
		local lfs_ok, lfs = pcall(require, "lfs")
		if lfs_ok then
			lfs.mkdir(dir)
		else
			-- Last resort: just return and hope for the best
			return false
		end
	end
	return true
end

-- ============================================================================
-- REPORTGEN CLASS IMPLEMENTATION
-- ============================================================================

function ReportGen.new(report_dir)
	local dir = report_dir or "survival_reports"

	-- Create directory if needed
	ensure_directory(dir)

	return setmetatable({
		dir = dir,
		reports = {},
		current_test = nil,
	}, ReportGen)
end

function ReportGen:start_test(test_name)
	self.current_test = test_name
	self.reports[test_name] = {
		test = test_name,
		timestamp_start = timestamp(),
		failures = {},
		warnings = {},
		metrics = {},
		status = "running",
	}
	return self
end

function ReportGen:add_failure(id, severity, evidence, impact, resolution)
	if not self.current_test or not self.reports[self.current_test] then
		error("No active test. Call start_test() first.")
	end

	table.insert(self.reports[self.current_test].failures, {
		id = id or "UNKNOWN",
		severity = severity or "MEDIUM",
		evidence = evidence or "",
		impact = impact or "",
		resolution = resolution or "",
		timestamp = timestamp(),
	})
	return self
end

function ReportGen:add_warning(message, category)
	if not self.current_test or not self.reports[self.current_test] then
		error("No active test. Call start_test() first.")
	end

	table.insert(self.reports[self.current_test].warnings, {
		message = message or "",
		category = category or "general",
		timestamp = timestamp(),
	})
	return self
end

function ReportGen:add_metric(name, value, unit)
	if not self.current_test or not self.reports[self.current_test] then
		error("No active test. Call start_test() first.")
	end

	self.reports[self.current_test].metrics[name] = {
		value = value,
		unit = unit or "",
		timestamp = timestamp(),
	}
	return self
end

function ReportGen:end_test(status, summary)
	if not self.current_test or not self.reports[self.current_test] then
		error("No active test. Call start_test() first.")
	end

	local report = self.reports[self.current_test]
	report.timestamp_end = timestamp()
	report.status = status or "completed"
	report.summary = summary or ""
	report.pass = (#report.failures == 0)

	-- Calculate duration (simplified - could parse timestamps properly)
	report.duration_sec = 0 -- Placeholder for actual timing

	-- Write to file
	self:write_report(self.current_test)

	self.current_test = nil
	return report
end

function ReportGen:write_report(test_name)
	local report = self.reports[test_name]
	if not report then
		error("No report found for test: " .. test_name)
	end

	-- Ensure failures and warnings are properly formatted as arrays
	if not report.failures then
		report.failures = {}
	end
	if not report.warnings then
		report.warnings = {}
	end
	if not report.metrics then
		report.metrics = {}
	end

	local filename = string.format("%s/%s.report.json", self.dir, test_name)
	local file, err = io.open(filename, "w")
	if not file then
		print("[REPORTGEN ERROR] Failed to write report: " .. err)
		return false
	end

	file:write(json.encode(report))
	file:close()

	print(string.format("[REPORTGEN] Wrote report: %s", filename))
	return true
end

function ReportGen:capture_failure_catalog(test_name, failures, warnings, metrics)
	self:start_test(test_name)

	-- Add failures if provided
	if failures then
		for _, failure in ipairs(failures) do
			self:add_failure(failure.id, failure.severity, failure.evidence, failure.impact, failure.resolution)
		end
	end

	-- Add warnings if provided
	if warnings then
		for _, warning in ipairs(warnings) do
			self:add_warning(warning.message, warning.category)
		end
	end

	-- Add metrics if provided
	if metrics then
		for name, metric in pairs(metrics) do
			self:add_metric(name, metric.value, metric.unit)
		end
	end

	-- Determine status
	local status = "COMPLETED"
	local summary = ""

	if failures and #failures > 0 then
		status = "FAILED"
		summary = string.format("%d failures", #failures)
	else
		status = "PASSED"
		summary = "No failures"
	end

	if warnings and #warnings > 0 then
		summary = summary .. string.format(", %d warnings", #warnings)
	end

	return self:end_test(status, summary)
end

function ReportGen:generate_summary()
	local summary = {
		generated_at = timestamp(),
		total_tests = 0,
		passed = 0,
		failed = 0,
		total_failures = 0,
		total_warnings = 0,
		tests = {}, -- This will be an array
	}

	for test_name, report in pairs(self.reports) do
		if report.status ~= "running" then -- Skip incomplete tests
			summary.total_tests = summary.total_tests + 1

			if report.pass then
				summary.passed = summary.passed + 1
			else
				summary.failed = summary.failed + 1
			end

			summary.total_failures = summary.total_failures + #report.failures
			summary.total_warnings = summary.total_warnings + #report.warnings

			-- Add test to array
			table.insert(summary.tests, {
				name = test_name,
				status = report.status,
				pass = report.pass,
				failures = #report.failures,
				warnings = #report.warnings,
				timestamp = report.timestamp_end or report.timestamp_start,
			})
		end
	end

	-- Write summary to file
	local filename = string.format("%s/test_summary.json", self.dir)
	local file, err = io.open(filename, "w")
	if file then
		file:write(json.encode(summary))
		file:close()
		print(string.format("[REPORTGEN] Wrote summary: %s", filename))
	else
		print("[REPORTGEN ERROR] Failed to write summary: " .. err)
	end

	return summary
end

function ReportGen:print_console_report(test_name)
	local report = self.reports[test_name]
	if not report then
		print("No report found for test: " .. test_name)
		return
	end

	print(string.rep("=", 60))
	print(string.format("TEST REPORT: %s", test_name:upper()))
	print(string.rep("=", 60))
	print(string.format("Status: %s", report.status))
	print(string.format("Pass: %s", report.pass and "✅ YES" or "❌ NO"))
	print(string.format("Timestamp: %s", report.timestamp_end or report.timestamp_start))

	if #report.failures > 0 then
		print("\nFAILURES:")
		for i, failure in ipairs(report.failures) do
			print(string.format("  %d. [%s] %s", i, failure.severity, failure.id))
			print(string.format("     Evidence: %s", failure.evidence))
			if failure.impact and failure.impact ~= "" then
				print(string.format("     Impact: %s", failure.impact))
			end
			if failure.resolution and failure.resolution ~= "" then
				print(string.format("     Resolution: %s", failure.resolution))
			end
			print()
		end
	end

	if #report.warnings > 0 then
		print("WARNINGS:")
		for i, warning in ipairs(report.warnings) do
			print(string.format("  %d. [%s] %s", i, warning.category, warning.message))
		end
	end

	if next(report.metrics) then
		print("\nMETRICS:")
		for name, metric in pairs(report.metrics) do
			-- Handle all value types safely
			local value_str
			if type(metric.value) == "boolean" then
				value_str = metric.value and "true" or "false"
			elseif type(metric.value) == "number" then
				value_str = tostring(metric.value)
			elseif metric.value == nil then
				value_str = "nil"
			else
				value_str = tostring(metric.value)
			end

			print(string.format("  • %s: %s %s", name, value_str, metric.unit or ""))
		end
	end

	if report.summary and report.summary ~= "" then
		print("\nSUMMARY:")
		print("  " .. report.summary)
	end

	print(string.rep("=", 60))
end

-- Convenience function for quick reporting
function ReportGen.quick_report(test_name, pass, failures, warnings)
	local reporter = ReportGen.new()
	reporter:start_test(test_name)

	if failures then
		for _, failure in ipairs(failures) do
			reporter:add_failure(
				failure.id or "UNKNOWN",
				failure.severity or "MEDIUM",
				failure.evidence or "",
				failure.impact or "",
				failure.resolution or ""
			)
		end
	end

	if warnings then
		for _, warning in ipairs(warnings) do
			reporter:add_warning(warning.message or "", warning.category or "general")
		end
	end

	local status = pass and "PASSED" or "FAILED"
	local summary = string.format("Quick report - Pass: %s", tostring(pass))

	return reporter:end_test(status, summary)
end

-- Export JSON encoder for external use
ReportGen.json = json

return ReportGen
