-- effect_contract.lua
-- CALYX EFFECT CONTRACT - Execution ABI v1.0
-- Defines the complete algebra of what effects can be expressed
-- Every host adapter MUST implement this contract exactly

local EffectContract = {}

-- ============================================================================
-- VERSIONING
-- ============================================================================
EffectContract.version = "1.0.0"
EffectContract.name = "CALYX Effect Contract"
EffectContract.description = "Formal execution ABI between FSM logic and host infrastructure"

-- ============================================================================
-- CAPABILITY ALGEBRA
-- ============================================================================
-- Defines the complete set of possible actions in the system
-- Agents can only request these effect types
-- Hosts must implement handlers for these effect types

EffectContract.schemas = {
	-- ------------------------------------------------------------------------
	-- OBSERVABILITY EFFECTS
	-- ------------------------------------------------------------------------

	log = {
		type = "log",
		description = "Emit a structured log message",
		required = { "level", "message" },
		optional = { "context", "timestamp" },
		levels = { "debug", "info", "warn", "error", "fatal" },
		validate = function(e)
			if not e.level or not e.message then
				return false, "missing level or message"
			end
			local valid_levels = { debug = true, info = true, warn = true, error = true, fatal = true }
			if not valid_levels[e.level] then
				return false, string.format("invalid log level: %s (must be debug/info/warn/error/fatal)", e.level)
			end
			if type(e.message) ~= "string" or #e.message == 0 then
				return false, "message must be non-empty string"
			end
			return true
		end,
	},

	metric = {
		type = "metric",
		description = "Emit a telemetry metric (counter, gauge, histogram)",
		required = { "name", "value", "type" },
		optional = { "labels", "timestamp" },
		metric_types = { "counter", "gauge", "histogram" },
		validate = function(e)
			if not e.name or not e.value then
				return false, "missing name or value"
			end
			if type(e.value) ~= "number" then
				return false, "value must be number"
			end
			local valid_types = { counter = true, gauge = true, histogram = true }
			if not valid_types[e.type] then
				return false, string.format("invalid metric type: %s", e.type)
			end
			if e.labels and type(e.labels) ~= "table" then
				return false, "labels must be table"
			end
			return true
		end,
	},

	trace = {
		type = "trace",
		description = "Emit a distributed tracing span",
		required = { "name", "operation" },
		optional = { "parent_id", "attributes", "start_time", "end_time" },
		validate = function(e)
			if not e.name or not e.operation then
				return false, "missing name or operation"
			end
			if e.parent_id and type(e.parent_id) ~= "string" then
				return false, "parent_id must be string"
			end
			if e.attributes and type(e.attributes) ~= "table" then
				return false, "attributes must be table"
			end
			return true
		end,
	},

	audit = {
		type = "audit",
		description = "Record an immutable audit log entry",
		required = { "action", "actor" },
		optional = { "resource", "status", "details", "timestamp" },
		validate = function(e)
			if not e.action or not e.actor then
				return false, "missing action or actor"
			end
			if type(e.action) ~= "string" or #e.action == 0 then
				return false, "action must be non-empty string"
			end
			if type(e.actor) ~= "string" and type(e.actor) ~= "number" then
				return false, "actor must be string or number"
			end
			return true
		end,
	},

	-- ------------------------------------------------------------------------
	-- STORAGE EFFECTS
	-- ------------------------------------------------------------------------

	cache_set = {
		type = "cache_set",
		description = "Store a value in cache with optional TTL",
		required = { "key", "value" },
		optional = { "ttl", "namespace" },
		validate = function(e)
			if not e.key or e.value == nil then
				return false, "missing key or value"
			end
			if type(e.key) ~= "string" then
				return false, "key must be string"
			end
			if e.ttl and type(e.ttl) ~= "number" then
				return false, "ttl must be number (seconds)"
			end
			if e.ttl and e.ttl <= 0 then
				return false, "ttl must be positive"
			end
			return true
		end,
	},

	cache_get = {
		type = "cache_get",
		description = "Retrieve a value from cache",
		required = { "key" },
		optional = { "namespace" },
		validate = function(e)
			if not e.key then
				return false, "missing key"
			end
			if type(e.key) ~= "string" then
				return false, "key must be string"
			end
			return true
		end,
	},

	cache_delete = {
		type = "cache_delete",
		description = "Delete a value from cache",
		required = { "key" },
		optional = { "namespace" },
		validate = function(e)
			if not e.key then
				return false, "missing key"
			end
			if type(e.key) ~= "string" then
				return false, "key must be string"
			end
			return true
		end,
	},

	db_query = {
		type = "db_query",
		description = "Execute a database query (read-only by default)",
		required = { "query" },
		optional = { "params", "timeout", "read_only" },
		validate = function(e)
			if not e.query or type(e.query) ~= "string" then
				return false, "missing or invalid query"
			end
			local upper_query = string.upper(e.query)
			-- Block dangerous operations unless explicitly allowed
			local dangerous = { "DROP", "DELETE", "TRUNCATE", "ALTER", "CREATE", "INSERT", "UPDATE" }
			for _, word in ipairs(dangerous) do
				if string.find(upper_query, word) then
					if not e.read_only then
						return false,
							string.format("dangerous write query blocked: %s (use read_only=false to override)", word)
					end
				end
			end
			if e.params and type(e.params) ~= "table" then
				return false, "params must be table"
			end
			return true
		end,
	},

	-- ------------------------------------------------------------------------
	-- NETWORK EFFECTS
	-- ------------------------------------------------------------------------

	http_request = {
		type = "http_request",
		description = "Make an HTTP request to an external service",
		required = { "url", "method" },
		optional = { "headers", "body", "timeout", "retry" },
		validate = function(e)
			if not e.url or not e.method then
				return false, "missing url or method"
			end
			if not e.url:match("^https?://") then
				return false, "url must be HTTP or HTTPS"
			end
			local valid_methods = { GET = true, POST = true, PUT = true, DELETE = true, PATCH = true, HEAD = true }
			if not valid_methods[e.method] then
				return false, string.format("invalid HTTP method: %s", e.method)
			end
			if e.body and e.method == "GET" then
				return false, "GET requests cannot have body"
			end
			if e.timeout and type(e.timeout) ~= "number" then
				return false, "timeout must be number"
			end
			return true
		end,
	},

	websocket_send = {
		type = "websocket_send",
		description = "Send a message over a WebSocket connection",
		required = { "connection_id", "message" },
		optional = { "binary" },
		validate = function(e)
			if not e.connection_id or not e.message then
				return false, "missing connection_id or message"
			end
			return true
		end,
	},

	-- ------------------------------------------------------------------------
	-- COMMUNICATION EFFECTS
	-- ------------------------------------------------------------------------

	email = {
		type = "email",
		description = "Send an email message",
		required = { "to", "subject" },
		optional = { "body", "cc", "bcc", "from", "reply_to", "attachments" },
		validate = function(e)
			if not e.to or not e.subject then
				return false, "missing to or subject"
			end
			-- Validate email format
			local email_pattern = "^[%w._%%+-]+@[%w.-]+%.[a-zA-Z]{2,}$"
			if not e.to:match(email_pattern) then
				return false, string.format("invalid recipient email: %s", e.to)
			end
			if e.cc then
				if type(e.cc) == "string" and not e.cc:match(email_pattern) then
					return false, "invalid cc email"
				end
			end
			if type(e.subject) ~= "string" or #e.subject == 0 then
				return false, "subject must be non-empty string"
			end
			return true
		end,
	},

	notification = {
		type = "notification",
		description = "Send a push notification to a user device",
		required = { "user_id", "title", "body" },
		optional = { "data", "sound", "badge", "priority" },
		validate = function(e)
			if not e.user_id or not e.title or not e.body then
				return false, "missing user_id, title, or body"
			end
			if type(e.title) ~= "string" or #e.title == 0 then
				return false, "title must be non-empty string"
			end
			return true
		end,
	},

	-- ------------------------------------------------------------------------
	-- SYSTEM EFFECTS
	-- ------------------------------------------------------------------------

	sleep = {
		type = "sleep",
		description = "Delay execution for a duration",
		required = { "duration" },
		validate = function(e)
			if not e.duration then
				return false, "missing duration"
			end
			if type(e.duration) ~= "number" then
				return false, "duration must be number (seconds)"
			end
			if e.duration < 0 then
				return false, "duration cannot be negative"
			end
			if e.duration > 3600 then
				return false, "duration cannot exceed 3600 seconds (1 hour)"
			end
			return true
		end,
	},

	exit = {
		type = "exit",
		description = "Terminate the current execution context",
		required = { "code" },
		optional = { "message" },
		validate = function(e)
			if e.code == nil then
				return false, "missing exit code"
			end
			if type(e.code) ~= "number" then
				return false, "exit code must be number"
			end
			return true
		end,
	},
}

-- ============================================================================
-- CORE VALIDATION FUNCTIONS
-- ============================================================================

-- Validate a single effect against the contract
-- @param effect: table with 'type' field and effect-specific fields
-- @return: (ok, error_message, validated_effect)
function EffectContract.validate(effect)
	-- Type validation
	if type(effect) ~= "table" then
		return false, "effect must be a table"
	end

	if not effect.type then
		return false, "effect missing required 'type' field"
	end

	if type(effect.type) ~= "string" then
		return false, "effect.type must be string"
	end

	-- Schema lookup
	local schema = EffectContract.schemas[effect.type]
	if not schema then
		return false,
			string.format(
				"unknown effect type: %s (known types: %s)",
				effect.type,
				table.concat(EffectContract.list_types(), ", ")
			)
	end

	-- Required fields
	for _, field in ipairs(schema.required) do
		if effect[field] == nil then
			return false, string.format("missing required field '%s' in effect type '%s'", field, effect.type)
		end
	end

	-- Run custom validator
	if schema.validate then
		local ok, err = schema.validate(effect)
		if not ok then
			return false, err
		end
	end

	-- Return a clean copy (no extra fields)
	local validated = { type = effect.type }
	for _, field in ipairs(schema.required) do
		validated[field] = effect[field]
	end
	for _, field in ipairs(schema.optional or {}) do
		if effect[field] ~= nil then
			validated[field] = effect[field]
		end
	end

	return true, nil, validated
end

-- Validate a batch of effects (all-or-nothing)
-- @param effects: array of effect tables
-- @return: (ok, error_message, validated_effects)
function EffectContract.validate_batch(effects)
	if type(effects) ~= "table" then
		return false, "effects must be a table"
	end

	local validated = {}
	for i, effect in ipairs(effects) do
		local ok, err, cleaned = EffectContract.validate(effect)
		if not ok then
			return false, string.format("effect[%d]: %s", i, err), nil
		end
		validated[i] = cleaned
	end

	return true, nil, validated
end

-- ============================================================================
-- CAPABILITY MANAGEMENT
-- ============================================================================

-- Define capability sets for agents
EffectContract.capabilities = {
	-- Standard user-facing agent
	user_agent = {
		"log",
		"audit",
		"cache_get",
		"http_request",
	},

	-- Admin agent (elevated privileges)
	admin_agent = {
		"log",
		"audit",
		"metric",
		"trace",
		"cache_set",
		"cache_get",
		"cache_delete",
		"db_query",
		"http_request",
		"email",
		"notification",
	},

	-- System agent (full access)
	system_agent = {
		"log",
		"audit",
		"metric",
		"trace",
		"cache_set",
		"cache_get",
		"cache_delete",
		"db_query",
		"http_request",
		"websocket_send",
		"email",
		"notification",
		"sleep",
		"exit",
	},

	-- Read-only agent
	readonly_agent = {
		"log",
		"cache_get",
		"http_request",
	},
}

-- Check if an agent can emit a specific effect type
-- @param agent_type: string (e.g., "user_agent", "admin_agent")
-- @param effect_type: string
-- @return: boolean, optional error message
function EffectContract.check_capability(agent_type, effect_type)
	local caps = EffectContract.capabilities[agent_type]
	if not caps then
		return false, string.format("unknown agent type: %s", agent_type)
	end

	for _, cap in ipairs(caps) do
		if cap == effect_type then
			return true, nil
		end
	end

	return false, string.format("agent type '%s' cannot emit effect type '%s'", agent_type, effect_type)
end

-- Validate effect against agent capabilities
-- @param agent_type: string
-- @param effect: table
-- @return: (ok, error_message, validated_effect)
function EffectContract.validate_for_agent(agent_type, effect)
	-- First validate the effect structurally
	local ok, err, cleaned = EffectContract.validate(effect)
	if not ok then
		return false, err, nil
	end

	-- Then check capabilities
	local has_cap, cap_err = EffectContract.check_capability(agent_type, effect.type)
	if not has_cap then
		return false, cap_err, nil
	end

	return true, nil, cleaned
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- List all available effect types
function EffectContract.list_types()
	local types = {}
	for t, _ in pairs(EffectContract.schemas) do
		table.insert(types, t)
	end
	table.sort(types)
	return types
end

-- Get schema for a specific effect type
function EffectContract.get_schema(effect_type)
	return EffectContract.schemas[effect_type]
end

-- Generate a machine-readable contract specification
function EffectContract.get_spec()
	local spec = {
		version = EffectContract.version,
		name = EffectContract.name,
		description = EffectContract.description,
		effects = {},
		capabilities = EffectContract.capabilities,
	}

	for type, schema in pairs(EffectContract.schemas) do
		spec.effects[type] = {
			description = schema.description,
			required = schema.required,
			optional = schema.optional or {},
			levels = schema.levels or nil,
			metric_types = schema.metric_types or nil,
		}
	end

	return spec
end

-- ============================================================================
-- HOST ADAPTER INTERFACE
-- ============================================================================
-- Every host adapter MUST implement this function
-- @param effect: validated effect table
-- @param host_context: host-specific context (e.g., db connection, nginx ctx)
-- @return: result table with 'ok' and optional 'data' or 'error'

function EffectContract.execute(effect, host_context)
	error(
		string.format(
			"EffectContract.execute must be implemented by host adapter. "
				.. "Called with effect type '%s' but no handler registered.",
			effect.type
		)
	)
end

return EffectContract
