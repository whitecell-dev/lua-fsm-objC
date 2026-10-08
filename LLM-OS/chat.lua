local CALYX = require("init")
local Ollama = require("LLM-OS.ollama")

local assistant = CALYX.create_mailbox_fsm({
	name = "DEEPSEEK_CHAT",
	initial = "listening",
	events = {
		{ name = "ask", from = "listening", to = "thinking" },
		{ name = "respond", from = "thinking", to = "listening" },
		{ name = "escalate", from = "*", to = "human" },
		{ name = "delegate", from = "*", to = "tool" },
	},
})

Ollama.attach(assistant)

print("\n============================================================")
print("🤖 CALYX + DeepSeek Interactive Chat")
print("============================================================")
print("Commands: 'exit' to quit, 'stats' for mailbox info, 'state' for current state")
print("Initial state: ", assistant:get_state())
print("============================================================")

while true do
	io.write("\n💬 You: ")
	local input = io.read()

	if input == "exit" then
		break
	end
	if input == "state" then
		print("📡 Current state:      ", assistant:get_state())
	elseif input == "stats" then
		print("📊 Mailbox:", 		-- KNOWN: `vim` does not exist in stock Lua/LuaJIT and there is no Vim shim
		-- or dependency in the repo, so entering "stats" raises "attempt to index a
		-- nil value (global 'vim')". (recon 7/B20) ALSO: io.read() returns nil on
		-- EOF and nil matches none of the verb checks below, so Ctrl-D falls into
		-- the else branch and loops forever calling iface.ask(nil). (recon 7/B21)
vim.inspect(assistant:mailbox_stats()))
	else
		-- DEBUG: print FSM capabilities
		print("🤖 CAPABILITIES: ", table.concat(assistant.capabilities or {}, ", "))

		local iface = Ollama.interface(assistant)
		local reply = iface.ask(input)
		print("🤖 Bot:        ", reply)
		print("📡 State:      ", assistant:get_state())
	end
end
