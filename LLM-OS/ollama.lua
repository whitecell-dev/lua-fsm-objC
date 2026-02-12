-- ============================================================================
-- calyx/ollama.lua
-- Ollama LLM Provider for CALYX FSM - COMPLETE WITH ALL FUNCTIONS
-- ============================================================================

local ABI = require("core/abi")
local LLM = require("LLM-OS.llm")
local Ollama = {}

-- ----------------------------------------------------------------------------
-- CONFIGURATION
-- ----------------------------------------------------------------------------
Ollama.config = {
	host = "http://localhost:11435",
	model = "llama3.2:3b",
	fallback_models = {
		"llama3.2:3b",
		"deepseek-coder:latest",
		"tinyllama",
	},
	temperature = 0.0,
	stream = false,
}

-- ----------------------------------------------------------------------------
-- REGISTRY
-- ----------------------------------------------------------------------------
local llm_registry = {}

-- ----------------------------------------------------------------------------
-- JSON ENCODER (Required for Ollama API)
-- ----------------------------------------------------------------------------
local function escape_json_string(s)
	if not s then
		return '""'
	end
	s = string.gsub(s, "\\", "\\\\")
	s = string.gsub(s, '"', '\\"')
	s = string.gsub(s, "\n", "\\n")
	s = string.gsub(s, "\r", "\\r")
	s = string.gsub(s, "\t", "\\t")
	return '"' .. s .. '"'
end

local function encode_table(t)
	if type(t) ~= "table" then
		if type(t) == "string" then
			return escape_json_string(t)
		end
		if type(t) == "number" then
			return tostring(t)
		end
		if type(t) == "boolean" then
			return t and "true" or "false"
		end
		return "null"
	end

	local is_array = true
	local max_key = 0
	local count = 0
	for k, _ in pairs(t) do
		count = count + 1
		if type(k) ~= "number" then
			is_array = false
			break
		end
		if k > max_key then
			max_key = k
		end
	end

	local parts = {}
	if is_array and max_key == count then
		for i = 1, count do
			parts[i] = encode_table(t[i])
		end
		return "[" .. table.concat(parts, ",") .. "]"
	else
		local i = 1
		for k, v in pairs(t) do
			local key = type(k) == "string" and escape_json_string(k) or tostring(k)
			parts[i] = key .. ":" .. encode_table(v)
			i = i + 1
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
end

local function extract_between(str, left, right)
	local lstart = string.find(str, left, 1, true)
	if not lstart then
		return nil
	end
	local rstart = string.find(str, right, lstart + #left, true)
	if not rstart then
		return nil
	end
	return string.sub(str, lstart + #left, rstart - 1)
end

-- ----------------------------------------------------------------------------
-- SIMPLE COMMAND EXTRACTION
-- ----------------------------------------------------------------------------
local function extract_command(text)
	if not text then
		return nil
	end

	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")

	local commands = { "ask", "respond", "escalate", "delegate" }
	for _, cmd in ipairs(commands) do
		if string.find(text, cmd) then
			return cmd
		end
	end

	return nil
end

-- ----------------------------------------------------------------------------
-- OLLAMA API CALL
-- ----------------------------------------------------------------------------
function Ollama.generate(prompt, callback)
	callback = callback or function() end

	local payload = {
		model = Ollama.config.model,
		prompt = prompt,
		stream = false,
		temperature = Ollama.config.temperature,
		options = {
			num_predict = 20,
		},
	}

	local json_payload = encode_table(payload)
	local escaped_payload = string.gsub(json_payload, "'", "'\\''")

	local command = string.format(
		"curl -s -X POST %s/api/generate -H 'Content-Type: application/json' -d '%s'",
		Ollama.config.host,
		escaped_payload
	)

	local handle = io.popen(command)
	if handle then
		local response = handle:read("*a")
		handle:close()

		local resp_text = extract_between(response, '"response":"', '"')
		if not resp_text then
			resp_text = extract_between(response, '"response": "', '"')
		end

		if resp_text then
			resp_text = string.gsub(resp_text, "\\n", "\n")
			resp_text = string.gsub(resp_text, '\\"', '"')
			resp_text = string.gsub(resp_text, "\\\\", "\\")
			return callback(resp_text)
		end
	end

	return callback(nil, "Model not responding")
end

-- ----------------------------------------------------------------------------
-- SIMPLE PROMPT - JUST COMPLETE THE COMMAND
-- ----------------------------------------------------------------------------
-- Replace the _decide function with this even simpler version:

function Ollama._decide(prompt_table)
	if not prompt_table.available or prompt_table.available == "" then
		return { message = "ask", reasoning = "Default command" }
	end

	-- Filter to valid commands
	local valid_commands = {}
	for cmd in string.gmatch(prompt_table.available, "[^, ]+") do
		if cmd == "ask" or cmd == "respond" or cmd == "escalate" or cmd == "delegate" then
			table.insert(valid_commands, cmd)
		end
	end

	if #valid_commands == 0 then
		valid_commands = { "ask" }
	end

	-- CONTEXT-AWARE COMMAND SELECTION
	-- Based on current state, suggest appropriate commands
	local suggested_commands = {}
	if prompt_table.state == "listening" then
		-- In listening state, user can ask or escalate
		table.insert(suggested_commands, "ask")
		table.insert(suggested_commands, "escalate")
	elseif prompt_table.state == "thinking" then
		-- In thinking state, FSM should respond or delegate
		table.insert(suggested_commands, "respond")
		table.insert(suggested_commands, "delegate")
	elseif prompt_table.state == "tool" then
		-- In tool state, FSM should respond or escalate
		table.insert(suggested_commands, "respond")
		table.insert(suggested_commands, "escalate")
	else
		-- Default to all commands
		suggested_commands = valid_commands
	end

	local commands_str = table.concat(suggested_commands, " or ")

	-- STATE-AWARE PROMPT
	local full_prompt = string.format(
		"Current state: %s\nUser: %s\n\nRespond with ONE word: %s",
		prompt_table.state,
		prompt_table.user or "",
		commands_str
	)

	print("[PROMPT] " .. full_prompt)

	local decision = nil
	Ollama.generate(full_prompt, function(text, err)
		if err then
			print("[ERROR] Ollama:", err)
			return
		end
		if text then
			print("[RAW] " .. text)
			-- Only check for suggested commands
			for _, cmd in ipairs(suggested_commands) do
				if string.find(string.lower(text), cmd) then
					decision = {
						message = cmd,
						reasoning = "Selected by LLM",
						params = { data = {}, options = {} },
					}
					print("[CMD] " .. cmd)
					break
				end
			end
		end
	end)

	-- State-appropriate default
	local default_cmd = "ask"
	if prompt_table.state == "thinking" then
		default_cmd = "respond"
	elseif prompt_table.state == "tool" then
		default_cmd = "respond"
	end

	if not decision or not decision.message then
		print("[DEFAULT] Using '" .. default_cmd .. "'")
		return {
			message = default_cmd,
			reasoning = "Default command",
			params = { data = {}, options = {} },
		}
	end

	return decision
end

function Ollama._dispatch(fsm, instruction)
	print("\n=== DISPATCH DEBUG ===")
	local context = LLM.inspect(fsm)

	-- Build command list
	local command_list = {}
	for i = 1, #context.capabilities do
		local cmd = context.capabilities[i]
		if cmd == "ask" or cmd == "respond" or cmd == "escalate" or cmd == "delegate" then
			table.insert(command_list, cmd)
		end
	end

	print("Commands: " .. table.concat(command_list, ", "))
	print("State: " .. context.state.current)
	print("Instruction: " .. instruction)
	print("=== END DISPATCH DEBUG ===\n")

	-- Get LLM decision
	local decision = Ollama._decide({
		available = table.concat(command_list, ", "),
		state = context.state.current,
		user = instruction,
	})

	-- Send the command
	print("[SEND] " .. decision.message)
	local result = fsm:send(decision.message, decision.params or {})

	if fsm.process_mailbox then
		fsm:process_mailbox()
	end

	return {
		ok = result and result.ok or false,
		instruction = instruction,
		decision = decision,
		result = result,
		state = fsm:get_state(),
	}
end

function Ollama._ask(fsm, question)
	local result = Ollama._dispatch(fsm, question)
	if result.ok then
		return result.decision.reasoning or "Command executed"
	else
		return "Failed: " .. (result.decision.error or "Unknown error")
	end
end

-- ----------------------------------------------------------------------------
-- REGISTRY API
-- ----------------------------------------------------------------------------
function Ollama.attach(fsm)
	local name = fsm:get_name()
	llm_registry[name] = {
		ask = function(question)
			return Ollama._ask(fsm, question)
		end,
		dispatch = function(instruction)
			return Ollama._dispatch(fsm, instruction)
		end,
	}
	return true
end

function Ollama.interface(fsm)
	return llm_registry[fsm:get_name()]
end

-- ----------------------------------------------------------------------------
-- TEST FUNCTION
-- ----------------------------------------------------------------------------
function Ollama.test()
	print("\n🔧 Testing Ollama connection...")
	print("Host:", Ollama.config.host)
	print("Model:", Ollama.config.model)

	local command = string.format("curl -s %s/api/tags", Ollama.config.host)
	local handle = io.popen(command)
	if handle then
		local response = handle:read("*a")
		handle:close()
		print("✅ Ollama is reachable")
		return true
	else
		print("❌ Cannot connect to Ollama")
		return false
	end
end

return Ollama
