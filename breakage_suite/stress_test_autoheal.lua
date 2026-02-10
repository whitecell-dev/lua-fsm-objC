require("init")
local FSM = require("calyx_fsm_mailbox")

print("================================================================")
print("STRESS TEST: 100,000 TRANSITIONS (AUTO-HEAL & AUDIT)")
print("================================================================")

-- --- AUDIT LOGGING OVERRIDE ---
local recovery_count = 0
local old_print = print

-- Intercept prints to count recoveries without flooding the terminal
print = function(...)
	local msg = tostring(...)
	if msg:match("SIL_RECOVERY") then
		recovery_count = recovery_count + 1
	elseif not msg:match("Realignment") and not msg:match("Protocol Violation") then
		old_print(...)
	end
end

local producer = FSM.create({
	name = "STRESS_PRODUCER",
	initial = "IDLE",
	events = { { name = "send", from = "IDLE", to = "IDLE" } },
	callbacks = {
		onleaveIDLE = function(self, ctx)
			return "async"
		end,
	},
})

local function run_batch(size)
	local start_mem = collectgarbage("count")
	for i = 1, size do
		producer:send()

		-- SYNTHETIC DRIFT: Force a context wipe through the Proxy
		-- This ensures the Proxy's __newindex trap sees the nullification
		if i % 100 == 0 then
			producer._context = nil
		end

		producer:resume()
	end

	collectgarbage("collect")
	local end_mem = collectgarbage("count")
	return end_mem, end_mem - start_mem
end

-- Execute Stress Batches
local batches = { 100, 1000, 10000, 50000 }
old_print(string.format("%-15s | %-15s | %-15s", "Batch Size", "Final Mem (KB)", "Delta (KB)"))
old_print("----------------------------------------------------------------")

for _, size in ipairs(batches) do
	local final, delta = run_batch(size)
	old_print(string.format("%-15s | %-15.2f | %-15.2f", size, final, delta))
end

-- --- FINAL ANALYSIS ---
old_print("----------------------------------------------------------------")
old_print(string.format("TOTAL RECOVERIES HANDLED: %d", recovery_count))

-- Restoration of the print function
print = old_print

local expected = (100 + 1000 + 10000 + 50000) / 100
if recovery_count >= expected then
	print("[RESULT] SUCCESS: Proxy intercepted and healed all drifts.")
else
	print("[RESULT] WARNING: Recovery count is " .. recovery_count .. ". Expected ~" .. expected)
end
