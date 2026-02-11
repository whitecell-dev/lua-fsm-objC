-- tools/summarize_reports.lua
-- Summarize all reports in the survival_reports directory

local function read_json_file(filename)
	local file = io.open(filename, "r")
	if not file then
		return nil
	end
	local content = file:read("*a")
	file:close()

	-- Simple JSON parser (for demo - in reality use a proper JSON library)
	-- This just extracts basic info without full parsing
	return content
end

local function extract_test_info(json_str)
	-- Extract test name
	local test_name = json_str:match('"test"%s*:%s*"([^"]+)"')

	-- Extract pass status
	local pass = json_str:match('"pass"%s*:%s*(true)')
	pass = pass or json_str:match('"pass"%s*:%s*(false)')

	-- Count failures
	local failures = 0
	for _ in json_str:gmatch('"id"%s*:') do
		failures = failures + 1
	end

	return {
		name = test_name or "unknown",
		pass = pass == "true",
		failures = failures,
	}
end

print("CALYX TEST REPORT SUMMARY")
print(string.rep("=", 60))

local dir = "survival_reports"
local total = 0
local passed = 0
local total_failures = 0

for file in io.popen("ls " .. dir .. "/*.json 2>/dev/null"):lines() do
	local content = read_json_file(file)
	if content then
		local info = extract_test_info(content)
		total = total + 1

		local status = info.pass and "✅ PASS" or "❌ FAIL"
		print(string.format("%-30s %s (Failures: %d)", info.name, status, info.failures))

		if info.pass then
			passed = passed + 1
		end
		total_failures = total_failures + info.failures
	end
end

print(string.rep("=", 60))
print(string.format("TOTAL TESTS: %d", total))
print(string.format("PASSED: %d (%.1f%%)", passed, total > 0 and (passed / total) * 100 or 0))
print(string.format("FAILED: %d", total - passed))
print(string.format("TOTAL FAILURES: %d", total_failures))
print(string.rep("=", 60))
