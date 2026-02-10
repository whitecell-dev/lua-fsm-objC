-- breakage_suite/debug_handlers_test.lua
package.path = package.path .. ";../core/?.lua"
local machine = require("calyx_fsm_mailbox")

print("=== Checking HANDLERS table ===")

-- Try to access HANDLERS (might not be accessible)
local success, handlers = pcall(function()
	return HANDLERS
end)
print("HANDLERS accessible?", success)
if success then
	print("HANDLERS.LEAVE_WAIT exists?", handlers.LEAVE_WAIT ~= nil)
	print("HANDLERS keys:")
	for k, v in pairs(handlers) do
		print("  " .. k .. ": " .. tostring(v))
	end
end

-- Check if _complete can see HANDLERS
local original_complete = machine._complete
machine._complete = function(self, ctx)
	print("\n[DEBUG] Inside _complete override")
	print("  self.asyncState:", self.asyncState)

	-- Try to access HANDLERS here
	local success, handlers = pcall(function()
		return HANDLERS
	end)
	print("  HANDLERS accessible inside _complete?", success)
	if success then
		print("  HANDLERS.LEAVE_WAIT:", handlers.LEAVE_WAIT)
	end

	-- Calculate stage
	local stage = "initial"
	if self.asyncState and self.asyncState ~= "none" then
		local suffix = self.asyncState:match("_(.+)$")
		if suffix then
			stage = suffix
			print("  Calculated stage:", stage)
			print("  HANDLERS[stage] exists?", handlers and handlers[stage] ~= nil)
		end
	end

	return original_complete(self, ctx)
end

-- Run test
local fsm = machine.create({
	name = "TEST",
	initial = "IDLE",
	events = { { name = "test", from = "IDLE", to = "IDLE" } },
})

fsm:test({})
