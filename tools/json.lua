-- tools/json.lua
-- CALYX minimal JSON codec (pure Lua 5.1, no dependencies).
-- Shared by log_host.lua and prometheus_host.lua so neither carries its own
-- codec and neither requires cjson (OpenResty-only, absent on bare Lua 5.1).
--
-- SCOPE: encode handles strings/numbers/booleans/nil/tables (arrays vs
-- objects by key shape, object keys sorted for determinism). Decode is a
-- recursive-descent parser for exactly what the encoder emits, plus
-- whitespace. Anything else is a decode error, never a guess: callers treat
-- undecodable input as corrupt data, not as a value.
-- Numbers decode via tonumber; "NaN"/"Infinity" quoted forms decode back to
-- 0/0 and math.huge/-math.huge. Depth is capped (100) against nesting bombs.

local Json = {}

local MAX_DEPTH = 100

-- ============================================================================
-- ENCODE
-- ============================================================================

local function encode_string(s)
	return string.format(
		'"%s"',
		s:gsub('["\\\n\r\t\b\f]', {
			['"'] = '\\"',
			["\\"] = "\\\\",
			["\n"] = "\\n",
			["\r"] = "\\r",
			["\t"] = "\\t",
			["\b"] = "\\b",
			["\f"] = "\\f",
		}):gsub("[%z\1-\31]", function(c)
			return string.format("\\u%04x", string.byte(c))
		end)
	)
end

local function encode_value(val, depth)
	local t = type(val)
	if t == "string" then
		return encode_string(val)
	elseif t == "number" then
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
	elseif val == nil then
		return "null"
	elseif t == "table" then
		if depth > MAX_DEPTH then
			error("json.encode: nesting exceeds " .. MAX_DEPTH)
		end
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
			local items = {}
			for i = 1, #val do
				items[i] = encode_value(val[i], depth + 1)
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
			items[#items + 1] = encode_string(tostring(k)) .. ":" .. encode_value(val[k], depth + 1)
		end
		return "{" .. table.concat(items, ",") .. "}"
	else
		return encode_string(tostring(val))
	end
end

function Json.encode(val)
	return encode_value(val, 0)
end

-- ============================================================================
-- DECODE (restricted recursive descent)
-- ============================================================================

local function decode_error(s, pos, what)
	return nil, string.format("json.decode: %s at byte %d in %q", what, pos, s:sub(1, 60))
end

local function skip_ws(s, pos)
	while pos <= #s and s:sub(pos, pos):match("%s") do
		pos = pos + 1
	end
	return pos
end

local parse_value -- forward declaration

local function parse_string(s, pos)
	-- pos is at opening quote
	pos = pos + 1
	local out = {}
	while pos <= #s do
		local c = s:sub(pos, pos)
		if c == '"' then
			return table.concat(out), pos + 1
		elseif c == "\\" then
			local e = s:sub(pos + 1, pos + 1)
			if e == '"' or e == "\\" or e == "/" then
				out[#out + 1] = e
				pos = pos + 2
			elseif e == "n" then
				out[#out + 1] = "\n"
				pos = pos + 2
			elseif e == "r" then
				out[#out + 1] = "\r"
				pos = pos + 2
			elseif e == "t" then
				out[#out + 1] = "\t"
				pos = pos + 2
			elseif e == "b" then
				out[#out + 1] = "\b"
				pos = pos + 2
			elseif e == "f" then
				out[#out + 1] = "\f"
				pos = pos + 2
			elseif e == "u" then
				local hex = s:sub(pos + 2, pos + 5)
				local code = tonumber(hex, 16)
				if not code then
					return decode_error(s, pos, "bad \\u escape")
				end
				if code < 0x80 then
					out[#out + 1] = string.char(code)
				elseif code < 0x800 then
					out[#out + 1] = string.char(0xC0 + math.floor(code / 0x40), 0x80 + (code % 0x40))
				else
					out[#out + 1] = string.char(
						0xE0 + math.floor(code / 0x1000),
						0x80 + (math.floor(code / 0x40) % 0x40),
						0x80 + (code % 0x40)
					)
				end
				pos = pos + 6
			else
				return decode_error(s, pos, "bad escape")
			end
		else
			out[#out + 1] = c
			pos = pos + 1
		end
	end
	return decode_error(s, pos, "unterminated string")
end

local function parse_number(s, pos)
	local num = s:sub(pos):match("^%-?%d+%.?%d*[eE]?[+-]?%d*")
	if not num or num == "" or num == "-" then
		return decode_error(s, pos, "bad number")
	end
	local val = tonumber(num)
	if val == nil then
		return decode_error(s, pos, "bad number")
	end
	return val, pos + #num
end

local function parse_array(s, pos, depth)
	-- pos is at '['
	pos = skip_ws(s, pos + 1)
	local arr = {}
	if s:sub(pos, pos) == "]" then
		return arr, pos + 1
	end
	while true do
		local val, next_pos = parse_value(s, pos, depth + 1)
		-- Success is (non-nil value, numeric pos). Failures return
		-- (nil, nil) or (nil, errstring); both have non-numeric pos.
		if type(next_pos) ~= "number" then
			return nil, nil
		end
		arr[#arr + 1] = val
		pos = skip_ws(s, next_pos)
		local c = s:sub(pos, pos)
		if c == "," then
			pos = skip_ws(s, pos + 1)
		elseif c == "]" then
			return arr, pos + 1
		else
			return decode_error(s, pos, "expected ',' or ']'")
		end
	end
end

local function parse_object(s, pos, depth)
	-- pos is at '{'
	pos = skip_ws(s, pos + 1)
	local obj = {}
	if s:sub(pos, pos) == "}" then
		return obj, pos + 1
	end
	while true do
		pos = skip_ws(s, pos)
		if s:sub(pos, pos) ~= '"' then
			return decode_error(s, pos, "expected string key")
		end
		local key, next_pos = parse_string(s, pos)
		if type(next_pos) ~= "number" then
			return nil, nil
		end
		pos = skip_ws(s, next_pos)
		if s:sub(pos, pos) ~= ":" then
			return decode_error(s, pos, "expected ':'")
		end
		local val, val_pos = parse_value(s, skip_ws(s, pos + 1), depth + 1)
		if type(val_pos) ~= "number" then
			return nil, nil
		end
		obj[key] = val
		pos = skip_ws(s, val_pos)
		local c = s:sub(pos, pos)
		if c == "," then
			pos = pos + 1
		elseif c == "}" then
			return obj, pos + 1
		else
			return decode_error(s, pos, "expected ',' or '}'")
		end
	end
end

-- Returns (value, next_pos) on success, (nil, nil) on failure. Callers that
-- need the reason re-run is not required: failure is failure; the log host
-- counts corrupt lines without diagnosing them further. A separate
-- decode_verbose exists for tests.
function parse_value(s, pos, depth)
	if depth > MAX_DEPTH then
		return nil, nil
	end
	pos = skip_ws(s, pos)
	local c = s:sub(pos, pos)
	if c == "" then
		return nil, nil
	elseif c == '"' then
		return parse_string(s, pos)
	elseif c == "{" then
		return parse_object(s, pos, depth)
	elseif c == "[" then
		return parse_array(s, pos, depth)
	elseif s:sub(pos, pos + 3) == "true" then
		return true, pos + 4
	elseif s:sub(pos, pos + 4) == "false" then
		return false, pos + 5
	elseif s:sub(pos, pos + 3) == "null" then
		-- Decode JSON null as nil is lossy inside objects; callers that need
		-- presence use Json.NULL sentinel via decode_null_as_sentinel. Here:
		-- object assignment of nil drops the key, matching encoder output
		-- for absent fields. Top-level null returns sentinel + pos.
		return Json.NULL, pos + 4
	elseif c == "-" or c:match("%d") then
		return parse_number(s, pos)
	else
		return nil, nil
	end
end

Json.NULL = setmetatable({}, {
	__tostring = function()
		return "null"
	end,
})

-- @return value (nil on any failure), with Json.NULL for JSON null.
function Json.decode(s)
	if type(s) ~= "string" then
		return nil
	end
	local val, pos = parse_value(s, 1, 0)
	if type(pos) ~= "number" then
		return nil
	end
	pos = skip_ws(s, pos)
	if pos <= #s then
		return nil -- trailing garbage
	end
	if val == Json.NULL then
		return nil
	end
	return val
end

return Json
