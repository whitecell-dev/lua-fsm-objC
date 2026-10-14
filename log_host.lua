-- log_host.lua
-- APPEND-ONLY LOG HOST ADAPTER - durable record, not an executor.
--
-- Every effect appends one JSON record (NDJSON) to a single global log file.
-- Records are never modified or deleted. Current state is a fold of the log;
-- there is no separate state table. Deleting the checkpoint sidecar only
-- costs a rescan: the log is authoritative, the checkpoint is a hint.
--
-- RECORD-ONLY, EXECUTE-NOTHING, by design: the sqlite/redis/nginx hosts
-- already execute effects (and carry the known non-atomic-execution hole,
-- sqlite_host.lua:535). This host is the durable witness. It composes as a
-- standalone recorder; delegating to an executor host is out of scope.
--
-- CONCURRENCY: single-writer assumption, same posture as the other hosts'
-- in-memory fsm caches. One log file per writer process. No locking.
-- Pure Lua 5.1, no C dependencies: JSON via tools/json.lua (no cjson).
--
-- Record schema (v=1):
-- {v, seq, tick, ts, user_id, event, from, to, effect, agent, ok, note}
-- seq is a host-wide monotonic counter; a gap on fold is counted as
-- corruption evidence, never fatal. Corrupt lines are skipped and counted.

local create_session_fsm = require("session_fsm")
local EffectContract = require("effect_contract")
local Json = require("tools.json")

local LogHost = {}
LogHost.__index = LogHost

local RECORD_VERSION = 1

-- KNOWN: STUB AUTH, same as every other host in this repo. Any user_id except
-- 999 passes. sqlite_host.lua:18-20 documents the identical stub.
-- Constructor-injected so a caller can replace it without forking the file.
local function default_authenticate(user_id)
	return user_id and user_id ~= 999
end

function LogHost.new(opts)
	opts = opts or {}
	local self = setmetatable({}, LogHost)

	self.config = {
		agent_type = opts.agent_type or "user_agent",
		authenticate = opts.authenticate or default_authenticate,
	}
	self.path = opts.path or "calyx.log"

	self.fsms = {}
	self.next_seq = 1
	-- Idempotency set for corruption evidence. The log and the checkpoint
	-- file are append-only, so line index i always names the same line;
	-- repeated folds over the same bad line count it once.
	self._seen_bad = {}
	self.stats = {
		total_events = 0,
		successful_auth = 0,
		failed_auth = 0,
		logouts = 0,
		rejected_effects = 0,
		records_appended = 0,
		corrupt_records = 0,
	}

	-- Recover the seq counter from the existing log so a restart never
	-- reuses sequence numbers. A missing file is a fresh log, not an error
	-- (same posture as CREATE TABLE IF NOT EXISTS in sqlite_host.lua).
	local max_seq = self:_scan_max_seq()
	if max_seq and max_seq >= self.next_seq then
		self.next_seq = max_seq + 1
	end

	return self
end

function LogHost:checkpoint_path()
	return self.path .. ".checkpoint"
end

-- Count a corruption observation once per stable key. Returns true the
-- first time a key is seen.
function LogHost:_count_once(key)
	if self._seen_bad[key] then
		return false
	end
	self._seen_bad[key] = true
	self.stats.corrupt_records = self.stats.corrupt_records + 1
	return true
end

-- ============================================================================
-- LOW-LEVEL APPEND (open/append/close per record: crash-safe, always flushed)
-- ============================================================================

function LogHost:_append_record(rec)
	rec.v = RECORD_VERSION
	rec.seq = self.next_seq
	rec.ts = os.time()
	local line = Json.encode(rec)
	local fh, err = io.open(self.path, "a")
	if not fh then
		return false, err
	end
	fh:write(line, "\n")
	fh:flush()
	fh:close()
	self.next_seq = self.next_seq + 1
	self.stats.records_appended = self.stats.records_appended + 1
	return true, nil
end

function LogHost:_read_lines(path)
	local fh = io.open(path, "r")
	if not fh then
		return nil
	end
	local lines = {}
	for line in fh:lines() do
		lines[#lines + 1] = line
	end
	fh:close()
	return lines
end

-- Highest seq present in the log, or nil when the log is missing/empty.
-- Corrupt lines are counted here too: recovery must not hide evidence.
function LogHost:_scan_max_seq()
	local lines = self:_read_lines(self.path)
	if not lines then
		return nil
	end
	local max_seq = nil
	for idx, line in ipairs(lines) do
		if line:match("%S") then
			local rec = Json.decode(line)
			if type(rec) == "table" and type(rec.seq) == "number" then
				if not max_seq or rec.seq > max_seq then
					max_seq = rec.seq
				end
			else
				self:_count_once("line:" .. idx)
			end
		end
	end
	return max_seq
end

-- ============================================================================
-- FOLD: state is derived by replaying the log, optionally from a checkpoint
-- ============================================================================

function LogHost:_read_checkpoints()
	local states = {}
	local lines = self:_read_lines(self:checkpoint_path())
	if not lines then
		return states
	end
	for idx, line in ipairs(lines) do
		if line:match("%S") then
			local cp = Json.decode(line)
			if type(cp) == "table" and cp.user_id ~= nil and type(cp.seq) == "number" and type(cp.state) == "string" then
				local key = tostring(cp.user_id)
				if not states[key] or cp.seq > states[key].seq then
					states[key] = { seq = cp.seq, state = cp.state }
				end
			else
				self:_count_once("cp:" .. idx)
			end
		end
	end
	return states
end

-- Fold the log for one user. Returns (state, last_seq).
-- Corrupt lines and seq gaps are counted, never fatal.
function LogHost:fold_user(user_id)
	local key = tostring(user_id)
	local checkpoints = self:_read_checkpoints()
	local start_seq = 0
	local state = "logged_out"
	if checkpoints[key] then
		start_seq = checkpoints[key].seq
		state = checkpoints[key].state
	end

	local lines = self:_read_lines(self.path)
	if not lines then
		return state, start_seq
	end
	local expected = start_seq + 1
	for idx, line in ipairs(lines) do
		if line:match("%S") then
			local rec = Json.decode(line)
			if type(rec) ~= "table" then
				self:_count_once("line:" .. idx)
			elseif tostring(rec.user_id) == key then
				if type(rec.seq) ~= "number" or rec.v ~= RECORD_VERSION then
					self:_count_once("line:" .. idx)
				elseif rec.seq >= expected then
					if rec.seq > expected then
						-- Gap: evidence of lost/duplicated writes. Count it.
						self:_count_once("gap:" .. key .. ":" .. expected .. "-" .. rec.seq)
					end
					if type(rec.to) == "string" and rec.to ~= "" then
						state = rec.to
					end
					expected = rec.seq + 1
				end
				-- rec.seq < expected: already checkpointed, skip silently.
			end
			-- Other users' records (or witness records): not ours, never corruption.
		end
	end
	return state, expected - 1
end

-- ============================================================================
-- CANONICAL HOST SURFACE (see sqlite_host.lua for the template)
-- ============================================================================

function LogHost:get_or_create_fsm(user_id)
	if self.fsms[user_id] then
		return self.fsms[user_id].fsm, self.fsms[user_id].data
	end

	local state = self:fold_user(user_id)
	local fsm = create_session_fsm({ state = state })

	self.fsms[user_id] = {
		fsm = fsm,
		data = {},
		created_at = os.time(),
		last_event = nil,
	}

	return fsm, {}
end

-- Checkpoint, not state storage: records the (user, seq, state) triple so
-- the next fold can skip replayed prefix. Losing this file is harmless.
function LogHost:save_state(user_id)
	local entry = self.fsms[user_id]
	if not entry then
		return
	end
	local _, last_seq = self:fold_user(user_id)
	local cp = {
		v = RECORD_VERSION,
		user_id = user_id,
		seq = last_seq,
		state = entry.fsm:get_state(),
		ts = os.time(),
	}
	local fh, err = io.open(self:checkpoint_path(), "a")
	if not fh then
		return nil, err
	end
	fh:write(Json.encode(cp), "\n")
	fh:flush()
	fh:close()
	return true
end

-- Record one validated effect. This IS the execution for this host:
-- durable witness, no side effects beyond the log.
function LogHost:execute_effect(effect)
	local ok, err, cleaned = EffectContract.validate_for_agent(self.config.agent_type, effect)
	if not ok then
		self.stats.rejected_effects = self.stats.rejected_effects + 1
		return { ok = false, error = err }
	end
	local append_ok, append_err = self:_append_record({
		user_id = cleaned.actor or cleaned.user_id or "?",
		event = nil,
		from = nil,
		to = nil,
		effect = cleaned,
		agent = self.config.agent_type,
		ok = true,
		note = "recorded",
	})
	if not append_ok then
		return { ok = false, error = "log append failed: " .. tostring(append_err) }
	end
	return { ok = true, seq = self.next_seq - 1 }
end

-- State-specific business logic. Mirrors sqlite_host.lua:395-466 so the
-- session machine behaves identically; only the persistence differs.
function LogHost:handle_state_logic(fsm, user_id, user_data, event_data, new_state)
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

-- Handle an event for a user. Same shape as sqlite_host.lua:469-581:
-- send, process, state logic, all-or-nothing validation, record, checkpoint.
function LogHost:handle_event(user_id, event_name, event_data)
	local event_str = tostring(event_name)
	self.stats.total_events = self.stats.total_events + 1

	local fsm, user_data = self:get_or_create_fsm(user_id)

	local send_result = fsm:send(event_str, { data = event_data or {} })
	if not send_result or not send_result.ok then
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

	local updated_data, final_state, effects =
		self:handle_state_logic(fsm, user_id, user_data, event_data, new_state)

	if self.fsms[user_id] then
		self.fsms[user_id].last_event = os.time()
	end

	-- Phase 1: validate ALL effects (all-or-nothing, like the other hosts).
	local validated_effects = {}
	for i, effect in ipairs(effects) do
		local ok, err, cleaned = EffectContract.validate_for_agent(self.config.agent_type, effect)
		if not ok then
			self.stats.rejected_effects = self.stats.rejected_effects + 1
			self:_append_record({
				user_id = user_id,
				event = event_str,
				from = new_state,
				to = final_state,
				effect = { type = effect.type or "?" },
				agent = self.config.agent_type,
				ok = false,
				note = "rejected_effect: " .. tostring(err),
			})
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

	-- Phase 2: record. Each record carries the transition it witnessed, so
	-- the fold can replay state without any other store.
	local recorded = {}
	for _, effect in ipairs(validated_effects) do
		local append_ok, append_err = self:_append_record({
			user_id = user_id,
			event = event_str,
			from = new_state,
			to = final_state,
			effect = effect,
			agent = self.config.agent_type,
			ok = true,
			note = "recorded",
		})
		if not append_ok then
			return {
				ok = false,
				error = "log append failed: " .. tostring(append_err),
				state = new_state,
				data = updated_data,
				effects = recorded,
			}
		end
		recorded[#recorded + 1] = effect
	end

	self:save_state(user_id)

	return {
		ok = true,
		state = final_state,
		data = updated_data,
		effects = recorded,
		stats = { rejected = self.stats.rejected_effects },
	}
end

function LogHost:get_stats()
	local users = 0
	for _ in pairs(self.fsms) do
		users = users + 1
	end
	return {
		runtime = {
			total_events = self.stats.total_events,
			successful_auth = self.stats.successful_auth,
			failed_auth = self.stats.failed_auth,
			logouts = self.stats.logouts,
			rejected_effects = self.stats.rejected_effects,
		},
		log = {
			path = self.path,
			records_appended = self.stats.records_appended,
			corrupt_records = self.stats.corrupt_records,
			next_seq = self.next_seq,
			active_in_memory = users,
		},
	}
end

function LogHost:cleanup_old_sessions(max_age)
	max_age = max_age or 3600
	local cutoff = os.time() - max_age
	local removed = {}
	for user_id, entry in pairs(self.fsms) do
		if entry.last_event and entry.last_event < cutoff then
			self:save_state(user_id)
			self.fsms[user_id] = nil
			removed[#removed + 1] = user_id
		end
	end
	return removed
end

-- Replay the whole log from scratch, independent of checkpoints and the
-- mem-cache. Used by tests to prove the checkpoint is only a hint: fold
-- with and without the sidecar must agree.
function LogHost:replay_all()
	local states = {}
	local lines = self:_read_lines(self.path)
	if not lines then
		return states
	end
	for idx, line in ipairs(lines) do
		if line:match("%S") then
			local rec = Json.decode(line)
			if type(rec) == "table" and rec.v == RECORD_VERSION and rec.user_id ~= nil then
				if type(rec.to) == "string" and rec.to ~= "" then
					states[tostring(rec.user_id)] = rec.to
				end
			else
				self:_count_once("line:" .. idx)
			end
		end
	end
	return states
end

function LogHost:close()
	-- Nothing to flush: every append opens, writes, flushes, closes.
	-- Checkpoint the live sessions so the next open folds faster.
	for user_id, _ in pairs(self.fsms) do
		self:save_state(user_id)
	end
	self.fsms = {}
	return true
end

return LogHost
