local cjson = require("cjson")
local EffectContract = require("effect_contract")

local _M = {}

-- Shared dictionaries with safe access
local function get_dict(name)
	local dict = ngx.shared[name]
	if not dict then
		ngx.log(ngx.WARN, "Shared dict ", name, " not found, using fallback")
		return nil
	end
	return dict
end

local state_dict = get_dict("fsm_state")
local data_dict = get_dict("fsm_data")
local audit_dict = get_dict("audit_log")
local cache_dict = get_dict("contract_cache")

-- Mock data templates
local mock_users = {
	{ id = 100, name = "Alice Johnson", role = "admin", email = "alice@example.com" },
	{ id = 101, name = "Bob Smith", role = "user", email = "bob@example.com" },
	{ id = 102, name = "Carol Davis", role = "user", email = "carol@example.com" },
	{ id = 103, name = "David Brown", role = "moderator", email = "david@example.com" },
	{ id = 104, name = "Eva Wilson", role = "user", email = "eva@example.com" },
	{ id = 105, name = "Frank Miller", role = "admin", email = "frank@example.com" },
	{ id = 999, name = "Attacker", role = "blocked", email = "attacker@example.com" },
}

local metric_names = { "user_logins", "api_calls", "response_time_ms", "error_rate", "cache_hits" }
local trace_ops = { "authentication", "data_fetch", "email_send", "cache_lookup" }
local subjects = { "Welcome!", "Your report", "System update", "Security alert" }

-- Generate random number between min and max
local function random(min, max)
	return math.random(min, max)
end

-- Execute an effect (internal) with safe dict access
local function execute_effect(effect)
	if effect.type == "log" then
		ngx.log(ngx.INFO, string.format("[MOCK] %s: %s", effect.level, effect.message))
		return { ok = true }
	elseif effect.type == "metric" then
		if cache_dict then
			local key = "metric:" .. effect.name .. ":" .. effect.type
			cache_dict:set(key, effect.value)
		end
		return { ok = true }
	elseif effect.type == "trace" then
		if cache_dict then
			local trace_entry = cjson.encode({
				name = effect.name,
				operation = effect.operation,
				attributes = effect.attributes,
				timestamp = ngx.now(),
			})
			-- Store traces as a list using incrementing keys (no ltrim in OpenResty)
			local trace_key = "trace:" .. effect.name
			local count = cache_dict:get(trace_key .. ":count") or 0
			count = count + 1
			cache_dict:set(trace_key .. ":" .. count, trace_entry)
			cache_dict:set(trace_key .. ":count", count)

			-- Keep only last 100 traces (manual cleanup)
			if count > 100 then
				local old_key = trace_key .. ":" .. (count - 100)
				cache_dict:delete(old_key)
			end
		end
		return { ok = true }
	elseif effect.type == "audit" then
		if audit_dict then
			local audit_entry = cjson.encode({
				user_id = effect.actor,
				action = effect.action,
				status = effect.status,
				timestamp = ngx.now(),
			})
			local idx = audit_dict:incr("audit_counter", 1, 1) or 1
			local slot = ((idx - 1) % 1000) + 1
			audit_dict:set("audit:" .. slot, audit_entry)
		end
		return { ok = true }
	elseif effect.type == "email" then
		ngx.log(ngx.INFO, string.format("[MOCK] Email queued to: %s", effect.to))
		return { ok = true, queued = true }
	elseif effect.type == "cache_set" then
		if cache_dict then
			cache_dict:set(effect.key, cjson.encode(effect.value))
		end
		return { ok = true }
	else
		return { ok = true }
	end
end

-- Generate mock session data for a user
function _M.generate_user_session(user_id)
	local user = nil
	for _, u in ipairs(mock_users) do
		if u.id == user_id then
			user = u
			break
		end
	end

	if not user then
		return { error = "User not found" }
	end

	-- Create session data
	local session_data = {
		user_id = user.id,
		name = user.name,
		role = user.role,
		email = user.email,
		login_time = os.time(),
		session_id = string.format("sess_%x", math.random(0xFFFFFF)),
	}

	-- Store in shared dicts (if available)
	if state_dict then
		state_dict:set(user.id .. ":state", "authenticated")
	end
	if data_dict then
		data_dict:set(user.id .. ":data", cjson.encode(session_data))
	end
	if cache_dict then
		cache_dict:set("user:" .. user.id .. ":session", cjson.encode(session_data), 3600)
	end

	-- Audit login
	local audit_effect = {
		type = "audit",
		action = "login",
		actor = user.id,
		status = "success",
	}
	execute_effect(audit_effect)

	return session_data
end

-- Generate random metrics
function _M.generate_random_metrics(count)
	count = count or 10
	local generated = 0

	for i = 1, count do
		local effect = {
			type = "metric",
			name = metric_names[random(1, #metric_names)],
			value = random(1, 1000),
			type = "counter",
			labels = { source = "realtime", environment = "production" },
		}
		local ok, err = EffectContract.validate(effect)
		if ok then
			execute_effect(effect)
			generated = generated + 1
		end
	end

	return { generated = generated, total_requested = count }
end

-- Generate random traces
function _M.generate_random_traces(count)
	count = count or 10
	local generated = 0

	for i = 1, count do
		local effect = {
			type = "trace",
			name = "op_" .. tostring(ngx.now()),
			operation = trace_ops[random(1, #trace_ops)],
			attributes = { duration_ms = random(10, 500), user_id = random(100, 105) },
		}
		local ok, err = EffectContract.validate(effect)
		if ok then
			execute_effect(effect)
			generated = generated + 1
		end
	end

	return { generated = generated, total_requested = count }
end

-- Generate mock emails
function _M.generate_random_emails(count)
	count = count or 5
	local generated = 0
	local domains = { "example.com", "test.com", "calyx.io" }

	for i = 1, count do
		local effect = {
			type = "email",
			to = "user" .. random(100, 105) .. "@" .. domains[random(1, #domains)],
			subject = subjects[random(1, #subjects)],
			body = "This is auto-generated mock email content.",
		}
		local ok, err = EffectContract.validate(effect)
		if ok then
			execute_effect(effect)
			generated = generated + 1
		end
	end

	return { generated = generated, total_requested = count }
end

-- Run complete mock scenario
function _M.run_mock_scenario(user_id, count)
	user_id = user_id or random(100, 105)
	count = count or 5

	-- Generate user session
	local session = _M.generate_user_session(user_id)
	if session.error then
		return { error = session.error }
	end

	-- Generate metrics
	local metrics = _M.generate_random_metrics(count)

	-- Generate traces
	local traces = _M.generate_random_traces(count)

	-- Generate emails
	local emails = _M.generate_random_emails(math.floor(count / 2))

	return {
		status = "ok",
		user = session,
		metrics = metrics,
		traces = traces,
		emails = emails,
		timestamp = ngx.now(),
	}
end

-- Get system stats (safe version)
function _M.get_stats()
	local function safe_len(dict)
		if not dict then
			return 0
		end
		local ok, keys = pcall(dict.get_keys, dict, 0)
		if not ok then
			return 0
		end
		return #keys
	end

	return {
		state_keys = safe_len(state_dict),
		data_keys = safe_len(data_dict),
		audit_entries = safe_len(audit_dict),
		cache_keys = safe_len(cache_dict),
	}
end

return _M
