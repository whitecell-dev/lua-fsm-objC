-- ============================================================================
-- tools/export_fsm.lua
-- CALYX machine visualization: spec normalization + JSON/PlantUML export
-- plus a structured transition-trace formatter.
-- Lua 5.1.5 Compatible. Pure module: NO requires, no FSM construction here.
--
-- DESIGN: the export input is the SAME config table the caller passes to
-- create() (see session_fsm.lua). The diagram is therefore generated from
-- the real machine definition, never from a separately maintained drawing.
-- Live FSM instances hide their transition map in a closure, so exporting
-- from an instance is impossible by design -- pass the config instead.
-- (Phase-2 visualization; rFSM rfsm2json/rfsm2plantuml equivalent.)
-- ============================================================================

local Export = {}

-- ============================================================================
-- SPEC NORMALIZATION (deterministic: everything sorted)
-- ============================================================================

local function to_string_list(value)
	if value == nil then
		return { "*" }
	end
	if type(value) == "table" then
		local out = {}
		for _, v in ipairs(value) do
			out[#out + 1] = tostring(v)
		end
		table.sort(out)
		return out
	end
	return { tostring(value) }
end

-- Normalize a create() config into a canonical spec.
-- @param config: {name=string|nil, initial=string|nil, events={{name,from,to}}}
-- @return: {name=string, initial=string, states={sorted}, events={sorted by name}}
function Export.to_spec(config)
	if type(config) ~= "table" then
		error("export config must be a table", 2)
	end
	if type(config.events) ~= "table" then
		error("export config.events must be a table", 2)
	end

	-- Default matches ObjCFSM/MailboxFSM.create (core/objc.lua, core/mailbox.lua).
	-- All state identities are strings (numeric states stringified).
	local spec = {
		name = config.name or "unnamed",
		initial = tostring(config.initial or "idle"),
		states = {},
		events = {},
	}

	local state_set = { [spec.initial] = true }

	for _, ev in ipairs(config.events) do
		if type(ev) ~= "table" or type(ev.name) ~= "string" or ev.to == nil then
			error("export event must have string name and non-nil to", 2)
		end
		local from_list = to_string_list(ev.from)
		local to_name = tostring(ev.to)
		state_set[to_name] = true
		for _, s in ipairs(from_list) do
			if s ~= "*" then
				state_set[s] = true
			end
		end
		spec.events[#spec.events + 1] = {
			name = ev.name,
			from = from_list,
			to = to_name,
			wildcard = from_list[1] == "*" and #from_list == 1,
		}
	end

	for s, _ in pairs(state_set) do
		spec.states[#spec.states + 1] = s
	end
	table.sort(spec.states)
	table.sort(spec.events, function(a, b)
		return a.name < b.name
	end)

	return spec
end

-- ============================================================================
-- DETERMINISTIC JSON ENCODER (sorted object keys; self-contained so this
-- module stays dependency-free -- tools/reportgen.lua has its own local copy)
-- ============================================================================

local function escape_string(s)
	return (string.gsub(s, '[%z\1-\31\\"]', function(c)
		if c == '"' then
			return '\\"'
		elseif c == "\\" then
			return "\\\\"
		elseif c == "\n" then
			return "\\n"
		elseif c == "\r" then
			return "\\r"
		elseif c == "\t" then
			return "\\t"
		end
		return string.format("\\u%04x", string.byte(c))
	end))
end

local function encode_value(val)
	local t = type(val)
	if t == "string" then
		return '"' .. escape_string(val) .. '"'
	elseif t == "number" then
		if val ~= val or val == math.huge or val == -math.huge then
			return "null"
		end
		return tostring(val)
	elseif t == "boolean" then
		return val and "true" or "false"
	elseif t == "table" then
		local is_array = true
		for k, _ in pairs(val) do
			if type(k) ~= "number" then
				is_array = false
				break
			end
		end
		if is_array then
			local items = {}
			for i = 1, #val do
				items[#items + 1] = encode_value(val[i])
			end
			return "[" .. table.concat(items, ",") .. "]"
		end
		local keys = {}
		for k, _ in pairs(val) do
			keys[#keys + 1] = k
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		local items = {}
		for _, k in ipairs(keys) do
			items[#items + 1] = '"' .. escape_string(tostring(k)) .. '":' .. encode_value(val[k])
		end
		return "{" .. table.concat(items, ",") .. "}"
	elseif val == nil then
		return "null"
	end
	return '"' .. escape_string(tostring(val)) .. '"'
end

-- Encode a spec (or any plain-data table) as deterministic JSON.
function Export.to_json(spec)
	return encode_value(spec)
end

-- ============================================================================
-- PLANTUML EXPORT (states always aliased: s1..sN in sorted order, so dots,
-- dashes and leading digits in state names can never break the diagram)
-- ============================================================================

function Export.to_plantuml(spec, title)
	if type(spec) ~= "table" or type(spec.states) ~= "table" or type(spec.events) ~= "table" then
		error("to_plantuml expects a spec from to_spec()", 2)
	end

	local alias = {}
	for i, s in ipairs(spec.states) do
		alias[s] = "s" .. tostring(i)
	end

	local lines = {
		"@startuml",
		"title " .. (title or spec.name or "FSM"),
	}

	for _, s in ipairs(spec.states) do
		lines[#lines + 1] = string.format('state "%s" as %s', s, alias[s])
	end

	lines[#lines + 1] = string.format("[*] --> %s", alias[spec.initial] or "s1")

	for _, ev in ipairs(spec.events) do
		if ev.wildcard then
			for _, s in ipairs(spec.states) do
				lines[#lines + 1] = string.format("%s --> %s : %s", alias[s], alias[ev.to], ev.name)
			end
		else
			for _, s in ipairs(ev.from) do
				if alias[s] then
					lines[#lines + 1] = string.format("%s --> %s : %s", alias[s], alias[ev.to], ev.name)
				end
			end
		end
	end

	lines[#lines + 1] = "@enduml"
	return table.concat(lines, "\n")
end

-- ============================================================================
-- STRUCTURED TRANSITION-TRACE FORMATTER (tick, source, destination, event,
-- result -- the rFSM rfsm.pp equivalent for CALYX observers)
-- ============================================================================

-- @param entry: {tick=number|nil, from=string, to=string, event=string,
--                ok=boolean, code=string|nil}
function Export.format_trace(entry)
	if type(entry) ~= "table" then
		error("format_trace expects a table", 2)
	end
	local result = entry.ok and "ok" or ("FAIL(" .. tostring(entry.code or "unknown") .. ")")
	return string.format(
		"[%s] %s --%s--> %s %s",
		tostring(entry.tick or "?"),
		tostring(entry.from or "?"),
		tostring(entry.event or "?"),
		tostring(entry.to or "?"),
		result
	)
end

-- ============================================================================
-- FILE HELPER (caller-owned paths only; never writes into survival_reports/)
-- ============================================================================

function Export.write_file(path, content)
	local f, err = io.open(path, "w")
	if not f then
		return false, err
	end
	f:write(content)
	f:close()
	return true
end

return Export
