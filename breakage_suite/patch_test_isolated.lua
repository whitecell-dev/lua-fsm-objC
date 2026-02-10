require("init") -- Boot the bundle
local patched_module = require("failure_modes.workarounds.fix_invalid_stage") -- Inject the patch

print("\n=== ISOLATED PATCH TEST ===")
local machine = patched_module.create({
	name = "PATCH_TESTER",
	initial = "START",
	events = { { name = "go", from = "START", to = "END" } },
	callbacks = {
		onleaveSTART = function()
			print("  [ACTION] Returning 'async' from START")
			return "async"
		end,
	},
})

machine:go()
print("Final State:", machine.current)
