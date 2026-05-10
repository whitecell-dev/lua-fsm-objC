-- redis_host.lua
-- Redis Host Adapter - In-memory, ultra-fast FSM persistence
-- WITH EFFECT CONTRACT INTEGRATION

local redis = require("redis")
local cjson = require("cjson")
local create_session_fsm = require("session_fsm")
local EffectContract = require("effect_contract") -- NEW

local RedisHost = {}
RedisHost.__index = RedisHost

function RedisHost.new(host, port, agent_type)
	local self = setmetatable({}, RedisHost)
	self.client = redis.connect(host or "127.0.0.1", port or 6379)
	self.agent_type = agent_type or "user_agent" -- NEW: capability scope
	self.fsms = {}
	self.stats = {
		total_events = 0,
		successful_auth = 0,
		failed_auth = 0,
		logouts = 0,
		rejected_effects = 0, -- NEW: track rejected effects
	}

	-- NEW: Register effect handlers for Redis
	self.effect_handlers = {
		log = function(effect)
			print(string.format("[%s] %s", effect.level, effect.message))
			return { ok = true }
		end,

		metric = function(effect)
			-- Store metrics in Redis sorted sets
			local key = "metric:" .. effect.name .. ":" .. effect.type
			self.client:zadd(key, effect.value, os.time())
			if effect.labels then
				for k, v in pairs(effect.labels) do
					self.client:hset(key .. ":labels", k, v)
				end
			end
			return { ok = true }
		end,

		trace = function(effect)
			-- Store trace spans in Redis
			local trace_entry = cjson.encode({
				name = effect.name,
				operation = effect.operation,
				parent_id = effect.parent_id,
				attributes = effect.attributes,
				timestamp = os.time(),
			})
			self.client:lpush("trace:" .. effect.name, trace_entry)
			self.client:ltrim("trace:" .. effect.name, 0, 999)
			return { ok = true }
		end,

		audit = function(effect)
			local audit_entry = cjson.encode({
				user_id = effect.actor,
				action = effect.action,
				resource = effect.resource,
				status = effect.status,
				details = effect.details,
				timestamp = os.time(),
			})
			self.client:lpush("audit:log", audit_entry)
			self.client:ltrim("audit:log", 0, 9999)
			return { ok = true }
		end,

		cache_set = function(effect)
			local value_json = cjson.encode(effect.value)
			if effect.ttl then
				self.client:setex(effect.key, effect.ttl, value_json)
			else
				self.client:set(effect.key, value_json)
			end
			if effect.namespace then
				self.client:sadd("namespace:" .. effect.namespace, effect.key)
			end
			return { ok = true }
		end,

		cache_get = function(effect)
			local value = self.client:get(effect.key)
			if value then
				return { ok = true, data = cjson.decode(value) }
			end
			return { ok = true, data = nil }
		end,

		cache_delete = function(effect)
			self.client:del(effect.key)
			if effect.namespace then
				self.client:srem("namespace:" .. effect.namespace, effect.key)
			end
			return { ok = true }
		end,

		db_query = function(effect)
			-- Redis doesn't do SQL, reject with clear error
			return { ok = false, error = "Redis cannot execute SQL queries" }
		end,

		http_request = function(effect)
			-- Redis can't do HTTP directly, but could queue
			local request = cjson.encode(effect)
			self.client:lpush("http:queue", request)
			return { ok = true, queued = true }
		end,

		websocket_send = function(effect)
			-- Queue for websocket worker
			local message = cjson.encode(effect)
			self.client:lpush("websocket:" .. effect.connection_id, message)
			return { ok = true }
		end,

		email = function(effect)
			-- Queue email in Redis list for external worker
			local email_json = cjson.encode(effect)
			self.client:lpush("email:queue", email_json)
			print(string.format("[REDIS] Queued email to: %s", effect.to))
			return { ok = true, queued = true }
		end,

		notification = function(effect)
			-- Queue push notification
			local notif_json = cjson.encode(effect)
			self.client:lpush("notification:queue", notif_json)
			return { ok = true }
		end,

		sleep = function(effect)
			-- Redis can't sleep, but we can log and continue
			print(string.format("[REDIS] Sleep requested: %ds (ignored)", effect.duration))
			return { ok = true }
		end,

		exit = function(effect)
			-- Redis can't exit, log and continue
			print(string.format("[REDIS] Exit requested with code %d (ignored)", effect.code))
			return { ok = true }
		end,
	}

	return self
end

-- Get or create FSM for a user (unchanged)
function RedisHost:get_or_create_fsm(user_id)
	if self.fsms[user_id] then
		return self.fsms[user_id].fsm, self.fsms[user_id].data
	end

	local state = self.client:get("user:" .. user_id .. ":state") or "logged_out"
	local data_blob = self.client:get("user:" .. user_id .. ":data")

	local fsm = create_session_fsm({ state = state })

	local user_data = {}
	if data_blob then
		local ok, decoded = pcall(cjson.decode, data_blob)
		if ok then
			user_data = decoded
		end
	end

	self.fsms[user_id] = {
		fsm = fsm,
		data = user_data,
		created_at = os.time(),
		last_event = nil,
	}

	return fsm, user_data
end

-- Save FSM state to Redis (unchanged)
function RedisHost:save_state(user_id)
	local entry = self.fsms[user_id]
	if not entry then
		return
	end

	local state = entry.fsm:get_state()
	local data_blob = cjson.encode(entry.data)

	self.client:set("user:" .. user_id .. ":state", state)
	self.client:set("user:" .. user_id .. ":data", data_blob)
	self.client:zadd("users:all", os.time(), user_id)
end

-- NEW: Execute a single effect with Redis handler
function RedisHost:execute_effect(effect)
	local handler = self.effect_handlers[effect.type]
	if not handler then
		return { ok = false, error = string.format("No handler for effect type: %s", effect.type) }
	end
	return handler(effect)
end

-- Handle event (UPDATED with effect contract)
function RedisHost:handle_event(user_id, event_name, event_data)
	local event_str = tostring(event_name)
	self.stats.total_events = self.stats.total_events + 1

	print(string.format("\n--- REDIS HOST: Event '%s' for User %d ---", event_str, user_id))

	local fsm, user_data = self:get_or_create_fsm(user_id)

	print("  [HOST] Current state: " .. fsm:get_state())
	print("  [HOST] Current data: " .. cjson.encode(user_data))

	-- Send event
	local send_result = fsm:send(event_str, { data = event_data or {} })
	if not send_result or not send_result.ok then
		print("  [HOST] Send failed:", send_result and send_result.message)
		return { ok = false, error = "Send failed" }
	end

	fsm:process_mailbox()
	local new_state = fsm:get_state()
	print("  [HOST] After transition: " .. new_state)

	-- State-specific logic (generates effects)
	local effects = {}
	local updated_data = user_data

	if new_state == "authenticating" then
		local user_id_from_event = event_data and event_data.user_id

		if user_id_from_event and user_id_from_event ~= 999 then
			updated_data = { user_id = user_id_from_event, login_time = os.time() }
			self.fsms[user_id].data = updated_data

			fsm:send("auth_success", { data = {} })
			fsm:process_mailbox()

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
			self.fsms[user_id].data = updated_data

			fsm:send("auth_failure", { data = {} })
			fsm:process_mailbox()

			effects = {
				{ type = "log", level = "warn", message = "Login failed: " .. tostring(user_id_from_event) },
				{ type = "audit", action = "login", actor = user_id_from_event, status = "failed" },
			}
		end
	elseif new_state == "logged_out" then
		local old_user_id = user_data and user_data.user_id or "unknown"
		updated_data = {}
		self.fsms[user_id].data = updated_data

		effects = {
			{ type = "log", level = "info", message = "User logged out" },
			{ type = "audit", action = "logout", actor = old_user_id, status = "success" },
			{ type = "cache_delete", key = "user:" .. old_user_id .. ":session" },
		}
	end

	-- ========================================================================
	-- EFFECT CONTRACT VALIDATION (NEW)
	-- ========================================================================

	-- Phase 1: Validate ALL effects against contract and capabilities
	local validated_effects = {}
	for i, effect in ipairs(effects) do
		local ok, err, cleaned = EffectContract.validate_for_agent(self.agent_type, effect)
		if not ok then
			print(string.format("  [HOST] REJECTED effect[%d]: %s", i, err))
			self.stats.rejected_effects = self.stats.rejected_effects + 1

			-- Write rejection to audit
			self:write_audit(user_id, "rejected_effect", "failed", {
				error = err,
				effect_type = effect.type,
				agent_type = self.agent_type,
			})

			-- Return error - no effects executed
			return {
				ok = false,
				error = string.format("Effect validation failed: %s", err),
				state = new_state,
				data = updated_data,
				rejected_effect = effect,
			}
		end
		validated_effects[i] = cleaned
	end

	-- Phase 2: Execute ALL validated effects (all-or-nothing)
	print("  [HOST] Executing Effects:")
	for _, effect in ipairs(validated_effects) do
		local result = self:execute_effect(effect)
		if result.ok then
			if effect.type == "log" then
				print(string.format("    LOG [%s]: %s", effect.level, effect.message))
			elseif effect.type == "audit" then
				print(
					string.format("    AUDIT: %s user=%s status=%s", effect.action, effect.actor, effect.status or "")
				)
			elseif effect.type == "cache_set" then
				print(string.format("    CACHE SET: %s (ttl=%s)", effect.key, effect.ttl or "forever"))
			elseif effect.type == "cache_delete" then
				print(string.format("    CACHE DEL: %s", effect.key))
			end
		else
			print(string.format("    [EFFECT FAILED] %s: %s", effect.type, result.error))
			-- Log failure but don't roll back (Redis has no transaction)
		end
	end

	-- Save to Redis
	self:save_state(user_id)

	print("  [HOST] Final state: " .. fsm:get_state())
	print("  [HOST] Final data: " .. cjson.encode(updated_data))

	return {
		ok = true,
		state = fsm:get_state(),
		data = updated_data,
		effects = validated_effects,
		stats = { rejected = self.stats.rejected_effects },
	}
end

-- Write to audit log (updated to use effect contract format)
function RedisHost:write_audit(user_id, action, status, details)
	local audit_effect = {
		type = "audit",
		action = action,
		actor = user_id,
		status = status,
		details = details,
		timestamp = os.time(),
	}
	self:execute_effect(audit_effect)
end

-- Get stats from Redis (updated)
function RedisHost:get_stats()
	local user_count = self.client:zcard("users:all")
	local audit_count = self.client:llen("audit:log")

	return {
		runtime = self.stats,
		redis = {
			total_users = user_count,
			audit_entries = audit_count,
			active_in_memory = self:count_active_fsms(),
		},
		contract = {
			agent_type = self.agent_type,
			rejected_effects = self.stats.rejected_effects,
		},
	}
end

function RedisHost:count_active_fsms()
	local count = 0
	for _ in pairs(self.fsms) do
		count = count + 1
	end
	return count
end

function RedisHost:cleanup_old_sessions(max_age_seconds)
	local cutoff = os.time() - (max_age_seconds or 86400)
	local old_users = self.client:zrangebyscore("users:all", 0, cutoff)

	for _, user_id in ipairs(old_users) do
		self.client:del("user:" .. user_id .. ":state")
		self.client:del("user:" .. user_id .. ":data")
		self.client:zrem("users:all", user_id)
		self.fsms[tonumber(user_id)] = nil
	end

	return #old_users
end

function RedisHost:close()
	self.client:quit()
end

return RedisHost
