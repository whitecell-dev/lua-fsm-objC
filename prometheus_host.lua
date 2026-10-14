-- prometheus_host.lua
-- PROMETHEUS METRIC HOST ADAPTER - metric effects accumulated and exposed
-- in Prometheus exposition format. Everything else is rejected.
--
-- WHY THIS HOST EXISTS: the `metric` effect type is unsatisfiable through
-- EffectContract.validate (effect_contract.lua:57-64): the discriminator
-- must be "metric" to reach the schema, but the validator then demands the
-- kind be counter/gauge/histogram. So validate_for_agent can NEVER pass a
-- metric. This host does not call it for metrics. Instead it gates
-- authorization with check_capability (schema-independent,
-- effect_contract.lua:506-519) and validates its own intake fields with
-- validate_metric_intake below -- the interim authority until the contract
-- kind-field rename lands (an RFC, out of scope here).
--
-- Intake (host-local, NOT the contract schema):
-- {type="metric", name=<non-empty string>, value=<number>,
--  kind=<"counter"|"gauge"|"histogram"> or absent (= "counter"),
--  labels=<table of string->scalar> or absent}
-- The raw discriminator is preserved as a label (`calyx_type`) so the
-- run_demo.lua double-`type` table (effect_contract KIND string in `type`)
-- is absorbed instead of dropped: kind resolves from `kind`, else from
-- `type` when it names a valid kind, else defaults to "counter".
--
-- TRANSPORT: this host runs no listener (no luasocket, no new dependency).
-- Primary: OpenResty content_by_lua_block calls host:render() for /metrics
-- (lua_package_path already resolves repo-root modules, nginx.conf:38).
-- Fallback: write_textfile(path) for the node-exporter textfile collector.
-- Accumulation is in-memory; save_state/close persist a snapshot file when
-- snapshot_path is configured. Losing the snapshot loses history, never
-- correctness.
--
-- Pure Lua 5.1, no C dependencies. JSON snapshot via tools/json.lua.
-- Non-metric effects are REJECTED ({ok=false}), never no-ops: a silent
-- swallow would recreate the mock_data.lua:101 catch-all lie.

local create_session_fsm = require("session_fsm")
local EffectContract = require("effect_contract")
local Json = require("tools.json")

local PrometheusHost = {}
PrometheusHost.__index = PrometheusHost

local VALID_KINDS = { counter = true, gauge = true, histogram = true }
local HISTOGRAM_BOUND = 1000 -- oldest observations dropped past this; counted

-- KNOWN: STUB AUTH, same as every other host in this repo (sqlite_host.lua:18).
local function default_authenticate(user_id)
	return user_id and user_id ~= 999
end

function PrometheusHost.new(opts)
	opts = opts or {}
	local self = setmetatable({}, PrometheusHost)

	self.config = {
		agent_type = opts.agent_type or "admin_agent",
		authenticate = opts.authenticate or default_authenticate,
	}
	self.snapshot_path = opts.snapshot_path -- nil = in-memory only
	self.histogram_bound = opts.histogram_bound or HISTOGRAM_BOUND

	self.fsms = {}
	self.metrics = {} -- key -> {name, kind, value|observations, labels, updated_ts, dropped}
	self.stats = {
		total_events = 0,
		successful_auth = 0,
		failed_auth = 0,
		logouts = 0,
		rejected_effects = 0,
		observations = 0,
		dropped_observations = 0,
	}

	if self.snapshot_path then
		self:_load_snapshot()
	end

	return self
end

-- ============================================================================
-- METRIC INTAKE (interim authority; see header)
-- @return ok, err, cleaned {name, value, kind, labels}
-- ============================================================================

function PrometheusHost:validate_metric_intake(agent_type, effect)
	if type(effect) ~= "table" then
		return false, "effect must be a table"
	end
	if effect.type ~= "metric" and not VALID_KINDS[effect.type] then
		return false,
			string.format(
				"prometheus host accepts only metric effects, got type '%s'",
				tostring(effect.type)
			)
	end

	local has_cap, cap_err = EffectContract.check_capability(agent_type, "metric")
	if not has_cap then
		return false, cap_err
	end

	if type(effect.name) ~= "string" or effect.name == "" then
		return false, "metric missing non-empty string 'name'"
	end
	if type(effect.value) ~= "number" then
		return false, "metric 'value' must be number"
	end

	-- Kind resolution: explicit `kind` wins; else the discriminator when it
	-- names a valid kind (absorbs the run_demo.lua double-`type` table);
	-- else the documented default.
	local kind = effect.kind or "counter"
	if effect.kind == nil and VALID_KINDS[effect.type] then
		kind = effect.type
	end
	if not VALID_KINDS[kind] then
		return false, string.format("invalid metric kind: %s", tostring(kind))
	end

	local labels = {}
	if effect.labels ~= nil then
		if type(effect.labels) ~= "table" then
			return false, "metric 'labels' must be table"
		end
		for k, v in pairs(effect.labels) do
			if type(v) ~= "string" and type(v) ~= "number" and type(v) ~= "boolean" then
				return false, string.format("metric label '%s' must be scalar", tostring(k))
			end
			labels[tostring(k)] = v
		end
	end
	-- Preserve the wire discriminator for forensics.
	labels.calyx_type = tostring(effect.type)

	return true, nil, { name = effect.name, value = effect.value, kind = kind, labels = labels }
end

local function metric_key(name, labels)
	local parts = { name }
	local keys = {}
	for k, _ in pairs(labels) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	for _, k in ipairs(keys) do
		parts[#parts + 1] = k .. "=" .. tostring(labels[k])
	end
	return table.concat(parts, "\0")
end

function PrometheusHost:_accumulate(cleaned)
	local key = metric_key(cleaned.name, cleaned.labels)
	local entry = self.metrics[key]
	if not entry then
		entry = {
			name = cleaned.name,
			kind = cleaned.kind,
			labels = cleaned.labels,
			updated_ts = os.time(),
			dropped = 0,
		}
		if cleaned.kind == "histogram" then
			entry.observations = {}
		else
			entry.value = 0
		end
		self.metrics[key] = entry
	end
	if entry.kind ~= cleaned.kind then
		return false,
			string.format(
				"metric '%s' kind conflict: registered as %s, got %s",
				cleaned.name,
				entry.kind,
				cleaned.kind
			)
	end
	if cleaned.kind == "counter" then
		entry.value = entry.value + cleaned.value
	elseif cleaned.kind == "gauge" then
		entry.value = cleaned.value
	else
		entry.observations[#entry.observations + 1] = cleaned.value
		while #entry.observations > self.histogram_bound do
			table.remove(entry.observations, 1)
			entry.dropped = entry.dropped + 1
			self.stats.dropped_observations = self.stats.dropped_observations + 1
		end
	end
	entry.updated_ts = os.time()
	self.stats.observations = self.stats.observations + 1
	return true, nil
end

-- ============================================================================
-- EXPOSITION
-- ============================================================================

local function escape_label(v)
	return tostring(v):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n")
end

local function escape_name(name)
	return tostring(name):gsub("[^%w_:]", "_")
end

function PrometheusHost:render()
	local keys = {}
	for k, _ in pairs(self.metrics) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	local lines = {}
	for _, k in ipairs(keys) do
		local e = self.metrics[k]
		local name = escape_name(e.name)
		local label_parts = {}
		local lkeys = {}
		for lk, _ in pairs(e.labels) do
			lkeys[#lkeys + 1] = lk
		end
		table.sort(lkeys)
		for _, lk in ipairs(lkeys) do
			label_parts[#label_parts + 1] = string.format('%s="%s"', lk, escape_label(e.labels[lk]))
		end
		local lstr = #label_parts > 0 and ("{" .. table.concat(label_parts, ",") .. "}") or ""
		if e.kind == "histogram" then
			local sum, count = 0, #e.observations
			for _, v in ipairs(e.observations) do
				sum = sum + v
			end
			-- Summary-style exposition (no buckets configured): _count + _sum.
			lines[#lines + 1] = string.format("# HELP %s observations summary", name)
			lines[#lines + 1] = string.format("# TYPE %s summary", name)
			lines[#lines + 1] = string.format("%s_count%s %d", name, lstr, count)
			lines[#lines + 1] = string.format("%s_sum%s %s", name, lstr, tostring(sum))
		else
			local ptype = e.kind == "counter" and "counter" or "gauge"
			lines[#lines + 1] = string.format("# HELP %s calyx %s", name, e.kind)
			lines[#lines + 1] = string.format("# TYPE %s %s", name, ptype)
			lines[#lines + 1] = string.format("%s%s %s", name, lstr, tostring(e.value))
		end
	end
	return table.concat(lines, "\n") .. "\n"
end

-- Node-exporter textfile fallback: render to a .prom file.
function PrometheusHost:write_textfile(path)
	path = path or (self.snapshot_path and self.snapshot_path .. ".prom")
	if not path then
		return { ok = false, error = "no textfile path configured" }
	end
	local fh, err = io.open(path, "w")
	if not fh then
		return { ok = false, error = "textfile write failed: " .. tostring(err) }
	end
	fh:write(self:render())
	fh:flush()
	fh:close()
	return { ok = true, path = path }
end

-- ============================================================================
-- SNAPSHOT (restart continuity; loss is harmless)
-- ============================================================================

function PrometheusHost:save_state(user_id)
	-- user_id accepted for interface parity but unused: metric state is
	-- global, so there is nothing per-user to persist.
	if not self.snapshot_path then
		return true
	end
	local snap = { v = 1, ts = os.time(), metrics = {} }
	for k, e in pairs(self.metrics) do
		snap.metrics[#snap.metrics + 1] = {
			key = k,
			name = e.name,
			kind = e.kind,
			value = e.value,
			observations = e.observations,
			labels = e.labels,
			dropped = e.dropped,
		}
	end
	local fh, err = io.open(self.snapshot_path, "w")
	if not fh then
		return nil, err
	end
	fh:write(Json.encode(snap))
	fh:flush()
	fh:close()
	return true
end

function PrometheusHost:_load_snapshot()
	local fh = io.open(self.snapshot_path, "r")
	if not fh then
		return -- missing snapshot is a fresh start, not an error
	end
	local body = fh:read("*a")
	fh:close()
	local snap = Json.decode(body)
	if type(snap) ~= "table" or type(snap.metrics) ~= "table" then
		return -- corrupt snapshot: start empty, never crash the host
	end
	for _, m in ipairs(snap.metrics) do
		if type(m) == "table" and type(m.name) == "string" and VALID_KINDS[m.kind] then
			self.metrics[m.key or metric_key(m.name, m.labels or {})] = {
				name = m.name,
				kind = m.kind,
				value = m.value or 0,
				observations = m.observations or (m.kind == "histogram" and {} or nil),
				labels = m.labels or {},
				updated_ts = os.time(),
				dropped = m.dropped or 0,
			}
		end
	end
end

-- ============================================================================
-- CANONICAL HOST SURFACE (see sqlite_host.lua for the template)
-- ============================================================================

function PrometheusHost:get_or_create_fsm(user_id)
	if self.fsms[user_id] then
		return self.fsms[user_id].fsm, self.fsms[user_id].data
	end
	-- Metric state is global; per-user FSMs hydrate at the default state.
	-- There is no per-user store to fold (unlike log_host.lua).
	local fsm = create_session_fsm({ state = "logged_out" })
	self.fsms[user_id] = {
		fsm = fsm,
		data = {},
		created_at = os.time(),
		last_event = nil,
	}
	return fsm, {}
end

-- Record-only dispatch: metric effects accumulate; everything else is
-- REJECTED (never a silent no-op).
function PrometheusHost:execute_effect(effect)
	if type(effect) ~= "table" or (effect.type ~= "metric" and not VALID_KINDS[effect.type]) then
		self.stats.rejected_effects = self.stats.rejected_effects + 1
		return {
			ok = false,
			error = string.format(
				"prometheus host accepts only metric effects, got type '%s'",
				tostring(effect and effect.type)
			),
		}
	end
	local ok, err, cleaned = self:validate_metric_intake(self.config.agent_type, effect)
	if not ok then
		self.stats.rejected_effects = self.stats.rejected_effects + 1
		return { ok = false, error = err }
	end
	local acc_ok, acc_err = self:_accumulate(cleaned)
	if not acc_ok then
		self.stats.rejected_effects = self.stats.rejected_effects + 1
		return { ok = false, error = acc_err }
	end
	return { ok = true, name = cleaned.name, kind = cleaned.kind }
end

-- Metric-native state logic: this host's effects ARE metrics (login
-- attempt/success/failure/logout counters), so the batch always passes the
-- intake gate. Same session-machine behavior as sqlite_host.lua:395-466.
function PrometheusHost:handle_state_logic(fsm, user_id, user_data, event_data, new_state)
	local updated_data = user_data
	local final_state = new_state
	local effects = {}

	local function metric(name, extra_labels)
		local labels = { user_id = tostring(user_id) }
		if extra_labels then
			for k, v in pairs(extra_labels) do
				labels[k] = v
			end
		end
		return { type = "metric", kind = "counter", name = name, value = 1, labels = labels }
	end

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
				metric("calyx_login_attempts_total", { result = "success" }),
				metric("calyx_auth_success_total"),
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
				metric("calyx_login_attempts_total", { result = "failure" }),
				metric("calyx_auth_failure_total"),
			}
		end
	elseif new_state == "authenticated" then
		effects = {
			metric("calyx_session_active_total"),
		}
	elseif new_state == "logged_out" then
		updated_data = {}
		self.fsms[user_id].data = updated_data

		self.stats.logouts = self.stats.logouts + 1

		effects = {
			metric("calyx_logouts_total"),
		}
	end

	return updated_data, final_state, effects
end

-- Same shape as sqlite_host.lua:469-581. Validation gate is the metric
-- intake (validate_for_agent cannot pass metrics by construction).
function PrometheusHost:handle_event(user_id, event_name, event_data)
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

	-- All-or-nothing intake gate.
	local validated_effects = {}
	for _, effect in ipairs(effects) do
		local ok, err, cleaned = self:validate_metric_intake(self.config.agent_type, effect)
		if not ok then
			self.stats.rejected_effects = self.stats.rejected_effects + 1
			return {
				ok = false,
				error = string.format("Effect validation failed: %s", err),
				state = new_state,
				data = updated_data,
				rejected_effect = effect,
			}
		end
		validated_effects[#validated_effects + 1] = cleaned
	end

	for _, cleaned in ipairs(validated_effects) do
		local acc_ok, acc_err = self:_accumulate(cleaned)
		if not acc_ok then
			self.stats.rejected_effects = self.stats.rejected_effects + 1
			return {
				ok = false,
				error = tostring(acc_err),
				state = new_state,
				data = updated_data,
				effects = {},
			}
		end
	end

	self:save_state(user_id)

	return {
		ok = true,
		state = final_state,
		data = updated_data,
		effects = validated_effects,
		stats = { rejected = self.stats.rejected_effects },
	}
end

function PrometheusHost:get_stats()
	local users = 0
	for _ in pairs(self.fsms) do
		users = users + 1
	end
	local series = 0
	for _ in pairs(self.metrics) do
		series = series + 1
	end
	return {
		runtime = {
			total_events = self.stats.total_events,
			successful_auth = self.stats.successful_auth,
			failed_auth = self.stats.failed_auth,
			logouts = self.stats.logouts,
			rejected_effects = self.stats.rejected_effects,
		},
		prometheus = {
			series = series,
			observations = self.stats.observations,
			dropped_observations = self.stats.dropped_observations,
			active_in_memory = users,
		},
	}
end

function PrometheusHost:cleanup_old_sessions(max_age)
	max_age = max_age or 3600
	local cutoff = os.time() - max_age
	local removed = {}
	for user_id, entry in pairs(self.fsms) do
		if entry.last_event and entry.last_event < cutoff then
			self.fsms[user_id] = nil
			removed[#removed + 1] = user_id
		end
	end
	return removed
end

function PrometheusHost:close()
	self:save_state(nil)
	self.fsms = {}
	return true
end

return PrometheusHost
