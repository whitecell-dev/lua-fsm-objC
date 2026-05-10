-- nginx_host.lua
-- NGINX/OPENRESTY HOST ADAPTER with Effect Contract

local cjson = require("cjson")

-- Fix: Use correct paths for your setup
local create_session_fsm = require("calyx.session_fsm")
local EffectContract = require("effect_contract")

-- Shared dictionaries
local state_dict = ngx.shared.fsm_state
local data_dict = ngx.shared.fsm_data
local audit_dict = ngx.shared.audit_log
local cache_dict = ngx.shared.contract_cache

-- Agent type (can be passed via header or query param)
local function get_agent_type()
	local agent = ngx.var.http_X_Agent_Type or ngx.var.arg_agent_type
	if agent and EffectContract.capabilities[agent] then
		return agent
	end
	return "user_agent"
end

-- Write to audit log
local function write_audit(actor, action, status, details)
	local audit_effect = {
		type = "audit",
		action = action,
		actor = tostring(actor),
		status = status or "",
		details = details,
	}

	local ok, err = EffectContract.validate(audit_effect)
	if not ok then
		ngx.log(ngx.ERR, "Audit validation failed: ", err)
		return
	end

	local audit_entry = cjson.encode({
		user_id = tostring(actor),
		action = action,
		status = status or "",
		details = details,
		timestamp = ngx.now(),
		worker = ngx.worker.pid(),
	})

	local idx = audit_dict:incr("audit_counter", 1, 1) or 1
	local slot = ((idx - 1) % 1000) + 1
	audit_dict:set("audit:" .. slot, audit_entry)

	ngx.log(ngx.INFO, string.format("AUDIT: %s user=%s status=%s", action, tostring(actor), status or ""))
end

-- Effect handlers
local effect_handlers = {
	log = function(effect)
		ngx.log(ngx.INFO, string.format("[%s] %s", effect.level, effect.message))
		return { ok = true }
	end,

	metric = function(effect)
		local key = "metric:" .. effect.name .. ":" .. effect.type
		cache_dict:set(key, effect.value)
		return { ok = true }
	end,

	trace = function(effect)
		local trace_entry = cjson.encode({
			name = effect.name,
			operation = effect.operation,
			parent_id = effect.parent_id,
			attributes = effect.attributes,
			timestamp = ngx.now(),
		})
		cache_dict:lpush("trace:" .. effect.name, trace_entry)
		cache_dict:ltrim("trace:" .. effect.name, 0, 99)
		return { ok = true }
	end,

	audit = function(effect)
		write_audit(effect.actor, effect.action, effect.status, effect.details)
		return { ok = true }
	end,

	cache_set = function(effect)
		local value_json = cjson.encode(effect.value)
		if effect.ttl then
			cache_dict:set(effect.key, value_json, effect.ttl)
		else
			cache_dict:set(effect.key, value_json)
		end
		return { ok = true }
	end,

	cache_get = function(effect)
		local value = cache_dict:get(effect.key)
		if value then
			return { ok = true, data = cjson.decode(value) }
		end
		return { ok = true, data = nil }
	end,

	cache_delete = function(effect)
		cache_dict:delete(effect.key)
		return { ok = true }
	end,

	db_query = function(effect)
		ngx.log(ngx.WARN, "SQL query rejected in nginx: ", effect.query)
		return { ok = false, error = "Nginx cannot execute SQL queries" }
	end,

	http_request = function(effect)
		-- Simplified - just log for now
		ngx.log(ngx.INFO, "HTTP request to: ", effect.url)
		return { ok = true, data = { status = "queued" } }
	end,

	websocket_send = function(effect)
		ngx.log(ngx.INFO, "WebSocket send to: ", effect.connection_id)
		return { ok = true }
	end,

	email = function(effect)
		ngx.log(ngx.INFO, "Email queued to: ", effect.to)
		return { ok = true, queued = true }
	end,

	notification = function(effect)
		ngx.log(ngx.INFO, "Notification queued for user: ", effect.user_id)
		return { ok = true }
	end,

	sleep = function(effect)
		ngx.log(ngx.WARN, "Sleep requested: ", effect.duration, "s (ignored)")
		return { ok = true }
	end,

	exit = function(effect)
		ngx.log(ngx.INFO, "Exit requested with code: ", effect.code)
		if effect.code == 0 then
			return { ok = true }
		else
			ngx.status = effect.code
			ngx.say(effect.message or "Exit")
			return ngx.exit(effect.code)
		end
	end,
}

local function execute_effect(effect)
	local handler = effect_handlers[effect.type]
	if not handler then
		return { ok = false, error = string.format("No handler for effect type: %s", effect.type) }
	end
	return handler(effect)
end

local function get_or_create_fsm(user_id)
	local user_id_str = tostring(user_id)

	local state = state_dict:get(user_id_str .. ":state") or "logged_out"
	local data_blob = data_dict:get(user_id_str .. ":data")

	local fsm = create_session_fsm({ state = state })

	local user_data = {}
	if data_blob then
		local ok, decoded = pcall(cjson.decode, data_blob)
		if ok then
			user_data = decoded
		end
	end

	return fsm, user_data, user_id_str
end

local function save_state(user_id_str, fsm, user_data)
	state_dict:set(user_id_str .. ":state", fsm:get_state())
	data_dict:set(user_id_str .. ":data", cjson.encode(user_data))
end

-- Main request handler
local function handle_request()
	local args = ngx.req.get_uri_args()
	local user_id = args.user_id or ngx.var.cookie_user_id
	local event = args.event or "login_attempt"

	if not user_id then
		ngx.status = 400
		ngx.say(cjson.encode({ error = "Missing user_id parameter" }))
		return ngx.exit(400)
	end

	ngx.req.read_body()
	local body_data = ngx.req.get_body_data()
	local event_data = {}
	if body_data then
		local ok, decoded = pcall(cjson.decode, body_data)
		if ok then
			event_data = decoded
		end
	end

	event_data.user_id = tonumber(user_id)
	event_data.ip = ngx.var.remote_addr
	event_data.timestamp = ngx.now()

	local agent_type = get_agent_type()
	ngx.log(ngx.INFO, string.format("FSM: Event '%s' for User %s", event, user_id))

	local fsm, user_data, user_id_str = get_or_create_fsm(user_id)

	local send_result = fsm:send(event, { data = event_data })
	if not send_result or not send_result.ok then
		ngx.status = 500
		ngx.say(cjson.encode({ error = "FSM send failed", message = send_result and send_result.message }))
		return ngx.exit(500)
	end

	fsm:process_mailbox()
	local new_state = fsm:get_state()

	-- Generate effects based on state
	local effects = {}
	local updated_data = user_data

	if new_state == "authenticating" then
		local user_id_from_event = event_data and event_data.user_id

		if user_id_from_event == 123 or user_id_from_event == 456 then
			updated_data = { user_id = user_id_from_event, login_time = os.time() }

			fsm:send("auth_success", { data = {} })
			fsm:process_mailbox()
			new_state = fsm:get_state()

			effects = {
				{ type = "log", level = "info", message = "Login success: " .. user_id_from_event },
				{ type = "audit", action = "login", actor = user_id_from_event, status = "success" },
				{
					type = "cache_set",
					key = "user:" .. user_id_from_event .. ":session",
					value = updated_data,
					ttl = 3600,
				},
			}
		else
			updated_data = {}

			fsm:send("auth_failure", { data = {} })
			fsm:process_mailbox()
			new_state = fsm:get_state()

			effects = {
				{ type = "log", level = "warn", message = "Login failed: " .. tostring(user_id_from_event) },
				{ type = "audit", action = "login", actor = user_id_from_event, status = "failed" },
			}
		end
	elseif new_state == "logged_out" then
		local old_user_id = user_data and user_data.user_id or "unknown"
		updated_data = {}

		effects = {
			{ type = "log", level = "info", message = "User logged out" },
			{ type = "audit", action = "logout", actor = old_user_id, status = "success" },
			{ type = "cache_delete", key = "user:" .. old_user_id .. ":session" },
		}
	end

	-- Validate all effects first
	local validated_effects = {}
	for i, effect in ipairs(effects) do
		local ok, err, cleaned = EffectContract.validate_for_agent(agent_type, effect)
		if not ok then
			ngx.log(ngx.ERR, string.format("REJECTED effect[%d]: %s", i, err))
			write_audit(user_id, "rejected_effect", "failed", {
				error = err,
				effect_type = effect.type,
				agent_type = agent_type,
			})

			ngx.status = 400
			ngx.say(cjson.encode({
				error = "Effect validation failed",
				details = err,
				rejected_effect = effect.type,
			}))
			return ngx.exit(400)
		end
		validated_effects[i] = cleaned
	end

	-- Execute all validated effects
	for _, effect in ipairs(validated_effects) do
		execute_effect(effect)
	end

	save_state(user_id_str, fsm, updated_data)

	local response = {
		ok = true,
		state = new_state,
		data = updated_data,
		effects_executed = #validated_effects,
		agent_type = agent_type,
	}

	ngx.status = 200
	ngx.header["Content-Type"] = "application/json"
	ngx.say(cjson.encode(response))
end

handle_request()
