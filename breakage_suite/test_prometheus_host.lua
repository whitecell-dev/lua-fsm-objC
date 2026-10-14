-- breakage_suite/test_prometheus_host.lua
-- PROMETHEUS HOST: metric intake without validate_for_agent, accumulation,
-- exposition goldens, capability gating, non-metric rejection, snapshot.
-- Proves the run_demo.lua double-`type` table is absorbed, user_agent is
-- denied, and the exposition output is byte-exact Prometheus text.

local PrometheusHost = require("prometheus_host")

print("[BREAKAGE_SUITE] Starting prometheus host test...")

local passed = 0
local failed = 0

local function check(name, cond, detail)
	if cond then
		print(string.format("  PASS  %-40s", name))
		passed = passed + 1
	else
		print(string.format("  FAIL  %-40s %s", name, detail or ""))
		failed = failed + 1
	end
end

local SNAP = "/tmp/calyx_prom_snapshot_test.json"
local PROM = "/tmp/calyx_prom_textfile_test.prom"

local function wipe()
	os.remove(SNAP)
	os.remove(PROM)
end

-- ============================================================================
-- 1. Intake: the unsatisfiable-metric bypass, mechanism by mechanism
-- ============================================================================
wipe()
local h = PrometheusHost.new({ agent_type = "admin_agent" })

-- The exact run_demo.lua:148-157 failure shape: `type` written twice, so Lua
-- keeps only the kind. validate() rejects it (unknown type "counter"); the
-- host must absorb it.
local demo_shape = { type = "counter", name = "user_logins", value = 5, labels = { source = "demo" } }
local r1 = h:execute_effect(demo_shape)
check("double-type table absorbed", r1.ok == true, tostring(r1.error))

-- Canonical contract shape (type="metric" + kind field).
local r2 = h:execute_effect({ type = "metric", kind = "gauge", name = "temp_c", value = 21.5 })
check("gauge accepted", r2.ok == true, tostring(r2.error))

-- Bare minimum: kind defaults to counter.
local r3 = h:execute_effect({ type = "metric", name = "jobs", value = 1 })
check("kind defaults to counter", r3.ok == true, tostring(r3.error))

-- Malformed intake rejected, not accumulated.
check("missing name rejected", h:execute_effect({ type = "metric", value = 1 }).ok == false)
check("non-number value rejected", h:execute_effect({ type = "metric", name = "x", value = "1" }).ok == false)
check("bad kind rejected", h:execute_effect({ type = "metric", kind = "meter", name = "x", value = 1 }).ok == false)
check(
	"non-table labels rejected",
	h:execute_effect({ type = "metric", name = "x", value = 1, labels = "s" }).ok == false
)
check("non-table effect rejected", h:execute_effect("metric").ok == false)

-- ============================================================================
-- 2. Capability gating (effect_contract.lua:462-499)
-- ============================================================================
local hu = PrometheusHost.new({ agent_type = "user_agent" })
local denied = hu:execute_effect({ type = "metric", name = "m", value = 1 })
check("user_agent denied metric", denied.ok == false, tostring(denied.ok))
check("denial names capability", denied.error and denied.error:find("cannot emit") ~= nil, tostring(denied.error))
local hs = PrometheusHost.new({ agent_type = "system_agent" })
check("system_agent allowed metric", hs:execute_effect({ type = "metric", name = "m", value = 1 }).ok == true)

-- ============================================================================
-- 3. Non-metric effects REJECTED (never silent no-ops)
-- ============================================================================
local others = {
	{ type = "log", level = "info", message = "x" },
	{ type = "audit", action = "a", actor = 1, status = "s" },
	{ type = "trace", name = "n", operation = "o" },
	{ type = "cache_set", key = "k", value = "v" },
	{ type = "cache_get", key = "k" },
	{ type = "cache_delete", key = "k" },
	{ type = "db_query", query = "SELECT 1" },
	{ type = "http_request", url = "http://x", method = "GET" },
	{ type = "websocket_send", connection_id = "c", message = "m" },
	{ type = "email", to = "a@b.c", subject = "s" },
	{ type = "notification", target = "t", message = "m" },
	{ type = "sleep", duration = 1 },
	{ type = "exit", code = 0 },
	{ type = "teleport", target = "mars" },
}
local all_rejected = true
for _, eff in ipairs(others) do
	local res = h:execute_effect(eff)
	if res.ok ~= false then
		all_rejected = false
	end
end
check("all 13 non-metric + unknown rejected", all_rejected)

-- ============================================================================
-- 4. Accumulation semantics
-- ============================================================================
local ha = PrometheusHost.new({ agent_type = "admin_agent" })
ha:execute_effect({ type = "metric", kind = "counter", name = "hits", value = 2 })
ha:execute_effect({ type = "metric", kind = "counter", name = "hits", value = 3 })
ha:execute_effect({ type = "metric", kind = "gauge", name = "level", value = 9 })
ha:execute_effect({ type = "metric", kind = "gauge", name = "level", value = 4 })
local out = ha:render()
check("counter accumulates", out:find('hits{calyx_type="metric"} 5', 1, true) ~= nil, out)
check("gauge overwrites", out:find('level{calyx_type="metric"} 4', 1, true) ~= nil, out)
local conflict = ha:execute_effect({ type = "metric", kind = "gauge", name = "hits", value = 1 })
check("kind conflict rejected", conflict.ok == false, tostring(conflict.ok))

-- Labels split series.
ha:execute_effect({ type = "metric", kind = "counter", name = "req", value = 1, labels = { route = "/a" } })
ha:execute_effect({ type = "metric", kind = "counter", name = "req", value = 7, labels = { route = "/b" } })
local out2 = ha:render()
check(
	"label series split",
	out2:find('req{calyx_type="metric",route="/a"} 1', 1, true) ~= nil
		and out2:find('req{calyx_type="metric",route="/b"} 7', 1, true) ~= nil
)

-- Histogram bound.
local hh = PrometheusHost.new({ agent_type = "admin_agent", histogram_bound = 4 })
for i = 1, 6 do
	hh:execute_effect({ type = "metric", kind = "histogram", name = "lat", value = i })
end
local hout = hh:render()
check(
	"histogram count+sum",
	hout:find('lat_count{calyx_type="metric"} 4', 1, true) ~= nil
		and hout:find('lat_sum{calyx_type="metric"} 18', 1, true) ~= nil,
	hout
)
check("histogram drops counted", hh:get_stats().prometheus.dropped_observations == 2)

-- ============================================================================
-- 5. Exposition golden (byte-exact)
-- ============================================================================
local hg = PrometheusHost.new({ agent_type = "admin_agent" })
hg:execute_effect({ type = "metric", kind = "counter", name = "g", value = 1 })
local golden = "# HELP g calyx counter\n# TYPE g counter\ng{calyx_type=\"metric\"} 1\n"
check("exposition golden", hg:render() == golden, string.format("%q", hg:render()))

-- ============================================================================
-- 6. End-to-end login emits metrics, not rejections
-- ============================================================================
local he = PrometheusHost.new({ agent_type = "admin_agent" })
local ev = he:handle_event(101, "login_attempt", { user_id = 101 })
check("e2e login ok", ev.ok == true, tostring(ev.error))
check("e2e authenticated", ev.state == "authenticated", tostring(ev.state))
local eout = he:render()
check("e2e login counter", eout:find("calyx_login_attempts_total", 1, true) ~= nil)
check("e2e success counter", eout:find("calyx_auth_success_total", 1, true) ~= nil)
check("e2e no rejections", he:get_stats().runtime.rejected_effects == 0)

-- ============================================================================
-- 7. Snapshot roundtrip + textfile fallback
-- ============================================================================
wipe()
local hp = PrometheusHost.new({ agent_type = "admin_agent", snapshot_path = SNAP })
hp:execute_effect({ type = "metric", kind = "counter", name = "persisted", value = 11 })
hp:close()
local hq = PrometheusHost.new({ agent_type = "admin_agent", snapshot_path = SNAP })
check("snapshot restores series", hq:render():find("persisted", 1, true) ~= nil)
local tw = hq:write_textfile(PROM)
check("textfile written", tw.ok == true, tostring(tw.error))
local pfh = io.open(PROM, "r")
local pbody = pfh and pfh:read("*a")
if pfh then
	pfh:close()
end
check("textfile matches render", pbody == hq:render())
local nop = PrometheusHost.new({})
check("textfile without path rejected", nop:write_textfile(nil).ok == false)

-- Corrupt snapshot: host starts empty, never crashes.
local cfh = io.open(SNAP, "w")
cfh:write("NOT JSON{{")
cfh:close()
local hc = PrometheusHost.new({ agent_type = "admin_agent", snapshot_path = SNAP })
check("corrupt snapshot tolerated", hc:get_stats().prometheus.series == 0)

-- ============================================================================
-- 8. No listener, no new dependencies in the host source
-- ============================================================================
local src = io.open("prometheus_host.lua", "r"):read("*a")
check(
	"no socket require",
	src:find('require("socket")', 1, true) == nil and src:find("require 'socket'", 1, true) == nil
)
check("no cjson require", src:find('require("cjson")', 1, true) == nil)
check("no listen call", src:find("listen(", 1, true) == nil and src:find(":listen(", 1, true) == nil)

wipe()

-- ============================================================================
-- SUMMARY
-- ============================================================================
print(string.rep("=", 60))
print(string.format("Prometheus host: %d passed, %d failed", passed, failed))
if failed == 0 then
	print("ALL PROMETHEUS HOST TESTS PASSED")
else
	print("PROMETHEUS HOST FAILURES DETECTED")
end
print(string.rep("=", 60))
print("[BREAKAGE_SUITE] Prometheus host test complete")
