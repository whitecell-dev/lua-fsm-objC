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
		print("📊 Mailbox:", vim.inspect(assistant:mailbox_stats()))
	else
		-- DEBUG: print FSM capabilities
		print("🤖 CAPABILITIES: ", table.concat(assistant.capabilities or {}, ", "))

		local iface = Ollama.interface(assistant)
		local reply = iface.ask(input)
		print("🤖 Bot:        ", reply)
		print("📡 State:      ", assistant:get_state())
	end
end
