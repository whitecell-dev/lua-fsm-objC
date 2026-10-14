-- breakage_suite/test_log_host.lua
-- LOG HOST: append-only record, fold-derived state, checkpoint-as-hint.
-- Proves: record-format goldens, end-to-end login, refold-after-restart,
-- checkpoint-loss equivalence, corrupt-line survival + counting, seq-gap
-- evidence, rejection recording, unknown-type rejection, JSON codec.

local LogHost = require("log_host")
local Json = require("tools.json")

print("[BREAKAGE_SUITE] Starting log host test...")

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

local PATH = "/tmp/calyx_log_host_test.log"
local CP = PATH .. ".checkpoint"

local function wipe()
	os.remove(PATH)
	os.remove(CP)
end

local function read_lines(path)
	local fh = io.open(path, "r")
	if not fh then
		return {}
	end
	local out = {}
	for line in fh:lines() do
		out[#out + 1] = line
	end
	fh:close()
	return out
end

-- ============================================================================
-- 1. JSON codec (tools/json.lua): roundtrip + hostile input
-- ============================================================================
local sample = {
	v = 1,
	seq = 7,
	user_id = 101,
	effect = { type = "log", level = "info", message = 'q"u\\ote' },
	labels = { a = "1", b = "x" },
	n = 2.5,
	flag = true,
}
local enc = Json.encode(sample)
local dec = Json.decode(enc)
check("codec roundtrip", dec ~= nil and dec.seq == 7 and dec.effect.message == 'q"u\\ote')
check("codec sorted keys", enc:sub(1, 12) == '{"effect":{"', enc:sub(1, 20))
check("codec rejects corrupt", Json.decode("{bad") == nil)
check("codec rejects truncation", Json.decode('{"a":[1,2') == nil)
check("codec rejects trailing garbage", Json.decode("[1]x") == nil)
check("codec rejects bad escape", Json.decode('"\\q"') == nil)
check("codec depth cap", Json.decode(string.rep("[", 101)) == nil)
check(
	"codec nested arrays",
	(function()
		local a = Json.decode('[1,"x",true,[2]]')
		return a and a[1] == 1 and a[3] == true and a[4][1] == 2
	end)()
)

-- ============================================================================
-- 2. End-to-end login through handle_event (admin: cache_set allowed)
-- ============================================================================
wipe()
local h = LogHost.new({ path = PATH, agent_type = "admin_agent" })
local r = h:handle_event(101, "login_attempt", { user_id = 101 })
check("login ok", r.ok == true, tostring(r.error))
check("login state authenticated", r.state == "authenticated", tostring(r.state))
check("login recorded 3 effects", #r.effects == 3, tostring(#r.effects))

local lines = read_lines(PATH)
check("3 records appended", #lines == 3, tostring(#lines))
local rec1 = Json.decode(lines[1])
check(
	"record schema",
	rec1 ~= nil
		and rec1.v == 1
		and rec1.seq == 1
		and rec1.user_id == 101
		and rec1.event == "login_attempt"
		and rec1.to == "authenticated"
		and rec1.effect.type == "log"
		and rec1.agent == "admin_agent"
		and rec1.ok == true
)
check("seq monotonic", Json.decode(lines[2]).seq == 2 and Json.decode(lines[3]).seq == 3)

-- ============================================================================
-- 3. Restart: fresh host folds the same state from the log
-- ============================================================================
local h2 = LogHost.new({ path = PATH, agent_type = "admin_agent" })
local fsm2 = h2:get_or_create_fsm(101)
check("refold after restart", fsm2:get_state() == "authenticated", fsm2:get_state())
check("seq counter recovered", h2.next_seq == 4, tostring(h2.next_seq))
local all = h2:replay_all()
check("replay_all agrees", all["101"] == "authenticated", tostring(all["101"]))

-- ============================================================================
-- 4. Checkpoint is a hint: fold with and without it must agree
-- ============================================================================
local with_cp = h2:fold_user(101)
os.remove(CP)
local h3 = LogHost.new({ path = PATH, agent_type = "admin_agent" })
local without_cp = h3:fold_user(101)
check("checkpoint-loss equivalence", with_cp == without_cp and with_cp == "authenticated")

-- ============================================================================
-- 5. Corrupt lines: skipped, counted once, fold survives
-- ============================================================================
local fh = io.open(PATH, "a")
fh:write("THIS IS NOT JSON\n")
fh:write('{"v":1,"seq":999,"user_id":101}\n') -- valid JSON, wrong shape for fold scope
fh:close()
local h4 = LogHost.new({ path = PATH, agent_type = "admin_agent" })
local before = h4:get_stats().log.corrupt_records
check("constructor counted corrupt", before >= 1, tostring(before))
local s4 = h4:fold_user(101)
check("fold survives corruption", s4 == "authenticated", tostring(s4))
local after = h4:get_stats().log.corrupt_records
h4:fold_user(101)
check(
	"counting idempotent",
	h4:get_stats().log.corrupt_records == after,
	string.format("%d vs %d", h4:get_stats().log.corrupt_records, after)
)

-- ============================================================================
-- 6. Rejection is recorded, not silent (user_agent cannot cache_set)
-- ============================================================================
wipe()
local hu = LogHost.new({ path = PATH, agent_type = "user_agent" })
local ru = hu:handle_event(102, "login_attempt", { user_id = 102 })
check("user login rejected (cache_set)", ru.ok == false, tostring(ru.state))
check("rejection names cause", ru.error and ru.error:find("cache_set") ~= nil, tostring(ru.error))
local rlines = read_lines(PATH)
local rej = Json.decode(rlines[#rlines])
check(
	"rejection recorded",
	rej ~= nil and rej.ok == false and rej.note and rej.note:find("rejected_effect") ~= nil
)

-- ============================================================================
-- 7. Unknown effect type rejected, never recorded as success
-- ============================================================================
local unk = hu:execute_effect({ type = "teleport", target = "mars" })
check("unknown type rejected", unk.ok == false, tostring(unk.ok))

-- ============================================================================
-- 8. Failed login path + logout path fold correctly
-- ============================================================================
wipe()
local ha = LogHost.new({ path = PATH, agent_type = "admin_agent" })
local rf = ha:handle_event(999, "login_attempt", { user_id = 999 })
-- 999 trips the stub auth (same stub as sqlite_host.lua:18): authenticating
-- runs with user_id 999 -> authenticate false -> auth_failure -> logged_out.
check("stub-auth failure ok", rf.ok == true, tostring(rf.error))
check("stub-auth ends logged_out", rf.state == "logged_out", tostring(rf.state))
local rl = ha:handle_event(103, "login_attempt", { user_id = 103 })
check("second login ok", rl.ok == true and rl.state == "authenticated")
local ro = ha:handle_event(103, "logout", {})
check("logout ok", ro.ok == true and ro.state == "logged_out", tostring(ro.state))
local hb = LogHost.new({ path = PATH, agent_type = "admin_agent" })
check("logout refold", hb:fold_user(103) == "logged_out")
check("stats counters", ha:get_stats().runtime.logouts == 1)

-- ============================================================================
-- 9. No cjson / no external requires in the host
-- ============================================================================
local src = io.open("log_host.lua", "r"):read("*a")
check("no cjson require", src:find('require("cjson")', 1, true) == nil)
check("no socket require", src:find("socket", 1, true) == nil)

wipe()

-- ============================================================================
-- SUMMARY
-- ============================================================================
print(string.rep("=", 60))
print(string.format("Log host: %d passed, %d failed", passed, failed))
if failed == 0 then
	print("ALL LOG HOST TESTS PASSED")
else
	print("LOG HOST FAILURES DETECTED")
end
print(string.rep("=", 60))
print("[BREAKAGE_SUITE] Log host test complete")
