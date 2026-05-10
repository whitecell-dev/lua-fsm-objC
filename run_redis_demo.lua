-- run_redis_demo.lua
-- Redis demo with EFFECT CONTRACT integration

local RedisHost = require("redis_host")
local EffectContract = require("effect_contract") -- NEW

print("=" .. string.rep("=", 60))
print("CALYX FSM + REDIS DEMO")
print("Effect Contract v" .. EffectContract.version)
print("=" .. string.rep("=", 60))

-- Make sure Redis is running: redis-server
-- NEW: Create host with agent type
local host = RedisHost.new("127.0.0.1", 6379, "admin_agent") -- Full capabilities

-- Clear previous data
host.client:flushall()
print("\nΓ£à Redis flushed, starting fresh\n")

-- Show available effect types
local effect_types = EffectContract.list_types()
print(string.format("≡ƒôï Available effect types (%d): %s", #effect_types, table.concat(effect_types, ", ")))
print()

-- Run same scenarios as SQLite
local scenarios = {
	{ user_id = 123, event = "login_attempt", data = { user_id = 123 }, desc = "Valid user login" },
	{ user_id = 123, event = "logout", data = {}, desc = "Valid user logout" },
	{ user_id = 999, event = "login_attempt", data = { user_id = 999 }, desc = "Invalid user login" },
	{ user_id = 456, event = "login_attempt", data = { user_id = 456 }, desc = "Another valid user" },
	{ user_id = 456, event = "logout", data = {}, desc = "Another user logout" },
}

local results = {}
for _, scenario in ipairs(scenarios) do
	print(string.format("\nΓû╢ Scenario: %s", scenario.desc))
	local result = host:handle_event(scenario.user_id, scenario.event, scenario.data)
	table.insert(results, result)

	-- Show if effects were rejected
	if result.stats and result.stats.rejected > 0 then
		print(string.format("  ΓÜá∩╕Å %d effect(s) rejected", result.stats.rejected))
	end
end

-- Show Redis stats (updated with contract info)
local stats = host:get_stats()
print("\n≡ƒôè Redis Statistics:")
print(string.format("  Total events processed: %d", stats.runtime.total_events))
print(string.format("  Successful auth: %d", stats.runtime.successful_auth))
print(string.format("  Failed auth: %d", stats.runtime.failed_auth))
print(string.format("  Logouts: %d", stats.runtime.logouts))
print(string.format("  Users in Redis: %d", stats.redis.total_users))
print(string.format("  Audit log entries: %d", stats.redis.audit_entries))
print(string.format("  Active FSMs in memory: %d", stats.redis.active_in_memory))
print(string.format("  Agent type: %s", stats.contract.agent_type))
print(string.format("  Rejected effects: %d", stats.contract.rejected_effects))

-- NEW: Show Redis cache contents
print("\n≡ƒùä∩╕Å Redis Cache Contents:")
local cache_keys = host.client:keys("user:*:session")
for _, key in ipairs(cache_keys) do
	local value = host.client:get(key)
	print(string.format("  %s = %s", key, value))
end

-- NEW: Show audit log
print("\n≡ƒôï Audit Log (last 5 entries):")
local audit_entries = host.client:lrange("audit:log", 0, 4)
for i, entry in ipairs(audit_entries) do
	print(string.format("  %d. %s", i, entry))
end

-- NEW: Demonstrate capability checking
print("\n≡ƒöÆ Capability Demo:")
local test_agent = "user_agent"
local test_effect = { type = "cache_set", key = "test", value = "demo" }
local ok, err = EffectContract.validate_for_agent(test_agent, test_effect)
print(string.format("  Agent '%s' can emit 'cache_set': %s", test_agent, ok and "YES" or "NO"))
if not ok then
	print(string.format("    Reason: %s", err))
end

local test_effect2 = { type = "db_query", query = "SELECT * FROM users" }
local ok2, err2 = EffectContract.validate_for_agent(test_agent, test_effect2)
print(string.format("  Agent '%s' can emit 'db_query': %s", test_agent, ok2 and "YES" or "NO"))
if not ok2 then
	print(string.format("    Reason: %s", err2))
end

host:close()
print("\n--- Redis Demo Complete ---")
