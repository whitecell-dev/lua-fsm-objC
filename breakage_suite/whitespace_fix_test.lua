-- breakage_suite/whitespace_fix_test.lua
package.path = package.path .. ";../core/?.lua"
local machine = require("calyx_fsm_mailbox")

-- Monkey-patch _complete to add debugging
local original_complete = machine._complete
machine._complete = function(self, ctx)
	print("[DEBUG] _complete called")
	print("  asyncState: '" .. self.asyncState .. "'")
	print("  Length:", #self.asyncState)

	-- Check for invisible chars
	if self.asyncState then
		print("  Char codes:")
		for i = 1, #self.asyncState do
			local byte = string.byte(self.asyncState, i)
			print("    " .. i .. ": " .. byte .. " ('" .. string.char(byte) .. "')")
		end
	end

	return original_complete(self, ctx)
end

-- Now run the failing test
local producer = machine.create({
	name = "TEST",
	initial = "IDLE",
	events = { { name = "send_batch", from = "IDLE", to = "IDLE" } },
	callbacks = {
		onleaveIDLE = function(fsm, ctx)
			print("onleaveIDLE called")
			return nil -- Synchronous
		end,
	},
})

print("=== FIRST CALL ===")
local ok, res = producer:send_batch({ data = { count = 1 } })
print("Result:", ok, res and res.error_type or "success")

print("\n=== Check asyncState directly ===")
if producer.asyncState then
	local clean = producer.asyncState:gsub("%s+", "")
	print("Original: '" .. producer.asyncState .. "'")
	print("Cleaned: '" .. clean .. "'")
	print("Equal?", producer.asyncState == clean)
end
