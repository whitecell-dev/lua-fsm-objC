-- sqlite_host.lua
-- SQLITE HOST ADAPTER - Manages FSM lifecycle and persistence
-- WITH EFFECT CONTRACT INTEGRATION

local lsqlite3 = require("lsqlite3")
local cjson = require("cjson")
local create_session_fsm = require("session_fsm")
local EffectContract = require("effect_contract") -- NEW

local SQLiteHost = {}
SQLiteHost.__index = SQLiteHost

-- Configuration (can be overridden)
local DEFAULT_CONFIG = {
	authenticate = function(user_id)
		return user_id and user_id ~= 999
	end,
	agent_type = "user_agent", -- NEW: capability scope
}

function SQLiteHost.new(db_path, config)
	local self = setmetatable({}, SQLiteHost)

	self.config = {}
	for k, v in pairs(DEFAULT_CONFIG) do
		self.config[k] = config and config[k] or v
	end

	self.db = lsqlite3.open(db_path)
	self:setup_database()

	self.fsms = {}
	self.stats = {
		total_events = 0,
		successful_auth = 0,
		failed_auth = 0,
		logouts = 0,
		rejected_effects = 0, -- NEW
	}

	-- NEW: Register effect handlers for SQLite
	self.effect_handlers = {
		log = function(effect)
			print(string.format("[%s] %s", effect.level, effect.message))
			return { ok = true }
		end,

		metric = function(effect)
			local stmt = self.db:prepare([[
                INSERT INTO metrics (name, value, type, labels, created_at)
                VALUES (?, ?, ?, ?, strftime('%s', 'now'))
            ]])
			stmt:bind_values(
				effect.name,
				effect.value,
				effect.type,
				effect.labels and cjson.encode(effect.labels) or nil
			)
			stmt:step()
			stmt:finalize()
			return { ok = true }
		end,

		trace = function(effect)
			local stmt = self.db:prepare([[
                INSERT INTO traces (name, operation, parent_id, attributes, created_at)
                VALUES (?, ?, ?, ?, strftime('%s', 'now'))
            ]])
			stmt:bind_values(
				effect.name,
				effect.operation,
				effect.parent_id,
				effect.attributes and cjson.encode(effect.attributes) or nil
			)
			stmt:step()
			stmt:finalize()
			return { ok = true }
		end,

		audit = function(effect)
			local stmt = self.db:prepare([[
                INSERT INTO audit_log (user_id, action, status, details, created_at)
                VALUES (?, ?, ?, ?, strftime('%s', 'now'))
            ]])
			stmt:bind_values(
				effect.actor,
				effect.action,
				effect.status or "",
				effect.details and cjson.encode(effect.details) or nil
			)
			stmt:step()
			stmt:finalize()
			return { ok = true }
		end,

		cache_set = function(effect)
			-- SQLite can act as a simple cache table
			local stmt = self.db:prepare([[
                INSERT OR REPLACE INTO cache (key, value, ttl, updated_at)
                VALUES (?, ?, ?, strftime('%s', 'now'))
            ]])
			local ttl = effect.ttl or 86400 -- Default 24 hours
			stmt:bind_values(effect.key, cjson.encode(effect.value), os.time() + ttl)
			stmt:step()
			stmt:finalize()
			return { ok = true }
		end,

		cache_get = function(effect)
			local stmt = self.db:prepare([[
                SELECT value FROM cache WHERE key = ? AND (ttl IS NULL OR ttl > strftime('%s', 'now'))
            ]])
			stmt:bind_values(effect.key)
			local value = nil
			if stmt:step() == lsqlite3.ROW then
				value = cjson.decode(stmt:get_value(0))
			end
			stmt:finalize()
			return { ok = true, data = value }
		end,

		cache_delete = function(effect)
			local stmt = self.db:prepare("DELETE FROM cache WHERE key = ?")
			stmt:bind_values(effect.key)
			stmt:step()
			stmt:finalize()
			return { ok = true }
		end,

		db_query = function(effect)
			-- SQLite CAN execute queries (carefully)
			local result = self.db:exec(effect.query)
			return { ok = true, data = result }
		end,

		http_request = function(effect)
			-- SQLite can't do HTTP, queue it
			local stmt = self.db:prepare([[
                INSERT INTO http_queue (url, method, body, headers, created_at)
                VALUES (?, ?, ?, ?, strftime('%s', 'now'))
            ]])
			stmt:bind_values(
				effect.url,
				effect.method,
				effect.body and cjson.encode(effect.body) or nil,
				effect.headers and cjson.encode(effect.headers) or nil
			)
			stmt:step()
			stmt:finalize()
			return { ok = true, queued = true }
		end,

		websocket_send = function(effect)
			-- Queue for websocket worker
			local stmt = self.db:prepare([[
                INSERT INTO websocket_queue (connection_id, message, binary, created_at)
                VALUES (?, ?, ?, strftime('%s', 'now'))
            ]])
			stmt:bind_values(effect.connection_id, cjson.encode(effect.message), effect.binary and 1 or 0)
			stmt:step()
			stmt:finalize()
			return { ok = true }
		end,

		email = function(effect)
			-- Store email in queue table
			local stmt = self.db:prepare([[
                INSERT INTO email_queue (to_addr, subject, body, cc, bcc, created_at)
                VALUES (?, ?, ?, ?, ?, strftime('%s', 'now'))
            ]])
			stmt:bind_values(effect.to, effect.subject, effect.body or "", effect.cc or "", effect.bcc or "")
			stmt:step()
			stmt:finalize()
			print(string.format("[SQLITE] Queued email to: %s", effect.to))
			return { ok = true, queued = true }
		end,

		notification = function(effect)
			local stmt = self.db:prepare([[
                INSERT INTO notifications (user_id, title, body, data, sound, badge, created_at)
                VALUES (?, ?, ?, ?, ?, ?, strftime('%s', 'now'))
            ]])
			stmt:bind_values(
				effect.user_id,
				effect.title,
				effect.body,
				effect.data and cjson.encode(effect.data) or nil,
				effect.sound or "",
				effect.badge or 0
			)
			stmt:step()
			stmt:finalize()
			return { ok = true }
		end,

		sleep = function(effect)
			-- SQLite can't sleep, log it
			print(string.format("[SQLITE] Sleep requested: %ds (simulated)", effect.duration))
			return { ok = true }
		end,

		exit = function(effect)
			print(string.format("[SQLITE] Exit requested with code %d (ignored)", effect.code))
			return { ok = true }
		end,
	}

	return self
end

-- Create database schema with effect tables (UPDATED)
function SQLiteHost:setup_database()
	self.db:exec([[
        CREATE TABLE IF NOT EXISTS actor_states (
            user_id INTEGER PRIMARY KEY,
            state TEXT NOT NULL,
            data TEXT NOT NULL,
            updated_at INTEGER
        );
        
        CREATE TABLE IF NOT EXISTS audit_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER,
            action TEXT NOT NULL,
            status TEXT,
            details TEXT,
            created_at INTEGER
        );
        
        -- NEW: Effect contract tables
        CREATE TABLE IF NOT EXISTS metrics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            value REAL NOT NULL,
            type TEXT NOT NULL,
            labels TEXT,
            created_at INTEGER
        );
        
        CREATE TABLE IF NOT EXISTS traces (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            operation TEXT NOT NULL,
            parent_id TEXT,
            attributes TEXT,
            created_at INTEGER
        );
        
        CREATE TABLE IF NOT EXISTS cache (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            ttl INTEGER,
            updated_at INTEGER
        );
        
        CREATE TABLE IF NOT EXISTS http_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url TEXT NOT NULL,
            method TEXT NOT NULL,
            body TEXT,
            headers TEXT,
            created_at INTEGER,
            processed_at INTEGER
        );
        
        CREATE TABLE IF NOT EXISTS email_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            to_addr TEXT NOT NULL,
            subject TEXT NOT NULL,
            body TEXT,
            cc TEXT,
            bcc TEXT,
            created_at INTEGER,
            sent_at INTEGER
        );
        
        CREATE TABLE IF NOT EXISTS notifications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            data TEXT,
            sound TEXT,
            badge INTEGER,
            created_at INTEGER,
            delivered_at INTEGER
        );
        
        CREATE TABLE IF NOT EXISTS websocket_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            connection_id TEXT NOT NULL,
            message TEXT NOT NULL,
            binary INTEGER DEFAULT 0,
            created_at INTEGER,
            sent_at INTEGER
        );
    ]])

	-- Create indexes
	self.db:exec("CREATE INDEX IF NOT EXISTS idx_cache_ttl ON cache(ttl)")
	self.db:exec("CREATE INDEX IF NOT EXISTS idx_http_queue_processed ON http_queue(processed_at)")
	self.db:exec("CREATE INDEX IF NOT EXISTS idx_email_queue_sent ON email_queue(sent_at)")
end

-- Get or create an FSM for a user (unchanged)
function SQLiteHost:get_or_create_fsm(user_id)
	if self.fsms[user_id] then
		return self.fsms[user_id].fsm, self.fsms[user_id].data
	end

	local stmt = self.db:prepare("SELECT state, data FROM actor_states WHERE user_id = ?")
	if not stmt then
		local fsm = create_session_fsm({ state = "logged_out" })
		self.fsms[user_id] = {
			fsm = fsm,
			data = {},
			created_at = os.time(),
			last_event = nil,
		}
		return fsm, {}
	end

	stmt:bind_values(user_id)
	local state, data_blob

	if stmt:step() == lsqlite3.ROW then
		state = stmt:get_value(0)
		data_blob = stmt:get_value(1)
	end
	stmt:finalize()

	local fsm = create_session_fsm({ state = state or "logged_out" })

	local user_data = {}
	if data_blob and data_blob ~= "" then
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

-- Save FSM state (unchanged)
function SQLiteHost:save_state(user_id)
	local entry = self.fsms[user_id]
	if not entry then
		return
	end

	local new_data_blob = cjson.encode(entry.data)
	local current_state = entry.fsm:get_state()
	local current_time = os.time()

	local stmt = self.db:prepare([[
        INSERT OR REPLACE INTO actor_states (user_id, state, data, updated_at) 
        VALUES (?, ?, ?, ?)
    ]])
	if stmt then
		stmt:bind_values(user_id, current_state, new_data_blob, current_time)
		stmt:step()
		stmt:finalize()
	end
end

-- NEW: Execute a single effect with SQLite handler
function SQLiteHost:execute_effect(effect)
	local handler = self.effect_handlers[effect.type]
	if not handler then
		return { ok = false, error = string.format("No handler for effect type: %s", effect.type) }
	end
	return handler(effect)
end

-- Handle state-specific business logic (UPDATED to use effect contract)
function SQLiteHost:handle_state_logic(fsm, user_id, user_data, event_data, new_state)
	local updated_data = user_data
	local final_state = new_state
	local effects = {}

	if new_state == "authenticating" then
		local user_id_from_event = event_data and event_data.user_id
		local is_authenticated = self.config.authenticate(user_id_from_event)

		if is_authenticated then
			updated_data = {
				user_id = user_id_from_event,
				login_time = os.time(),
			}
			self.fsms[user_id].data = updated_data

			local send_result = fsm:send("auth_success", { data = {} })
			if send_result and send_result.ok then
				fsm:process_mailbox()
				final_state = fsm:get_state()
			end

			self.stats.successful_auth = self.stats.successful_auth + 1

			-- UPDATED: Use effect contract format
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

			local send_result = fsm:send("auth_failure", { data = {} })
			if send_result and send_result.ok then
				fsm:process_mailbox()
				final_state = fsm:get_state()
			end

			self.stats.failed_auth = self.stats.failed_auth + 1

			effects = {
				{ type = "log", level = "warn", message = "Login failed: " .. tostring(user_id_from_event) },
				{ type = "audit", action = "login", actor = user_id_from_event, status = "failed" },
			}
		end
	elseif new_state == "authenticated" then
		effects = {
			{ type = "log", level = "debug", message = "User session active" },
		}
	elseif new_state == "logged_out" then
		local old_user_id = user_data and user_data.user_id or "unknown"
		updated_data = {}
		self.fsms[user_id].data = updated_data

		self.stats.logouts = self.stats.logouts + 1

		effects = {
			{ type = "log", level = "info", message = "User logged out" },
			{ type = "audit", action = "logout", actor = old_user_id, status = "success" },
			{ type = "cache_delete", key = "user:" .. old_user_id .. ":session" },
		}
	end

	return updated_data, final_state, effects
end

-- Handle an event for a user (UPDATED with effect contract validation)
function SQLiteHost:handle_event(user_id, event_name, event_data)
	local event_str = tostring(event_name)
	self.stats.total_events = self.stats.total_events + 1

	print(string.format("\n--- HOST: Handling Event '%s' for User %d ---", event_str, user_id))

	local fsm, user_data = self:get_or_create_fsm(user_id)

	print("  [HOST] Current state: " .. fsm:get_state())
	print("  [HOST] Current data: " .. cjson.encode(user_data))

	local send_result = fsm:send(event_str, { data = event_data or {} })
	if not send_result or not send_result.ok then
		print("  [HOST] Send failed:", send_result and send_result.message or "unknown")
		return {
			ok = false,
			error = send_result and send_result.message or "Send failed",
			state = fsm:get_state(),
			data = user_data,
			effects = {},
		}
	end

	fsm:process_mailbox()
	local new_state = fsm:get_state()
	print("  [HOST] After transition: " .. new_state)

	local updated_data, final_state, effects = self:handle_state_logic(fsm, user_id, user_data, event_data, new_state)

	if self.fsms[user_id] then
		self.fsms[user_id].last_event = os.time()
	end

	-- ========================================================================
	-- EFFECT CONTRACT VALIDATION (NEW)
	-- ========================================================================

	-- Phase 1: Validate ALL effects against contract and capabilities
	local validated_effects = {}
	for i, effect in ipairs(effects) do
		local ok, err, cleaned = EffectContract.validate_for_agent(self.config.agent_type, effect)
		if not ok then
			print(string.format("  [HOST] REJECTED effect[%d]: %s", i, err))
			self.stats.rejected_effects = self.stats.rejected_effects + 1

			-- Write rejection to audit
			self:write_audit(user_id, "rejected_effect", "failed", {
				error = err,
				effect_type = effect.type,
				agent_type = self.config.agent_type,
			})

			-- Return error - no effects executed (all-or-nothing)
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
	if #validated_effects > 0 then
		print("  [HOST] Effects:")
		for _, effect in ipairs(validated_effects) do
			local result = self:execute_effect(effect)
			if result.ok then
				if effect.type == "log" then
					print(string.format("    LOG [%s]: %s", effect.level, effect.message))
				elseif effect.type == "audit" then
					print(
						string.format(
							"    AUDIT: %s user=%s status=%s",
							effect.action,
							effect.actor,
							effect.status or ""
						)
					)
				elseif effect.type == "cache_set" then
					print(string.format("    CACHE SET: %s (ttl=%s)", effect.key, effect.ttl or "forever"))
				elseif effect.type == "cache_delete" then
					print(string.format("    CACHE DEL: %s", effect.key))
				end
			else
				print(string.format("    [EFFECT FAILED] %s: %s", effect.type, result.error))
				-- In SQLite, we could rollback if using transactions
			end
		end
	end

	self:save_state(user_id)

	print("  [HOST] Final state: " .. final_state)
	print("  [HOST] Final data: " .. cjson.encode(updated_data))

	return {
		ok = true,
		state = final_state,
		data = updated_data,
		effects = validated_effects,
		stats = { rejected = self.stats.rejected_effects },
	}
end

-- Write to audit log (updated to use effect contract)
function SQLiteHost:write_audit(user_id, action, status, details)
	local audit_effect = {
		type = "audit",
		action = action,
		actor = user_id,
		status = status,
		details = details,
	}
	self:execute_effect(audit_effect)
end

-- Get statistics (updated)
function SQLiteHost:get_stats()
	local db_stats = { total_users = 0, audit_entries = 0 }

	local stmt = self.db:prepare("SELECT COUNT(*) FROM actor_states")
	if stmt then
		if stmt:step() == lsqlite3.ROW then
			db_stats.total_users = stmt:get_value(0) or 0
		end
		stmt:finalize()
	end

	local stmt2 = self.db:prepare("SELECT COUNT(*) FROM audit_log")
	if stmt2 then
		if stmt2:step() == lsqlite3.ROW then
			db_stats.audit_entries = stmt2:get_value(0) or 0
		end
		stmt2:finalize()
	end

	local active_count = 0
	for _ in pairs(self.fsms) do
		active_count = active_count + 1
	end

	return {
		runtime = self.stats,
		database = db_stats,
		memory_cache = { active_fsms = active_count },
		contract = {
			agent_type = self.config.agent_type,
			rejected_effects = self.stats.rejected_effects,
		},
	}
end

function SQLiteHost:cleanup_old_sessions(max_age_seconds)
	local cutoff = os.time() - (max_age_seconds or 86400)

	local to_remove = {}
	for user_id, entry in pairs(self.fsms) do
		if entry.last_event and entry.last_event < cutoff then
			table.insert(to_remove, user_id)
		end
	end

	for _, user_id in ipairs(to_remove) do
		self:save_state(user_id)
		self.fsms[user_id] = nil
	end

	-- Clean up old cache entries
	local stmt = self.db:prepare("DELETE FROM cache WHERE ttl < strftime('%s', 'now')")
	if stmt then
		stmt:step()
		stmt:finalize()
	end

	return #to_remove
end

function SQLiteHost:close()
	for user_id, _ in pairs(self.fsms) do
		self:save_state(user_id)
	end
	self.db:close()
end

return SQLiteHost
