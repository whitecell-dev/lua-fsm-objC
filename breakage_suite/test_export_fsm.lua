-- breakage_suite/test_export_fsm.lua
-- PHASE 2: machine visualization export (JSON / PlantUML / trace format).
-- The export input is the SAME config table passed to create(), so the
-- artifacts always describe the real machine definition.

local bundle = require("init")
local Export = require("tools.export_fsm")

print("[BREAKAGE_SUITE] Starting export FSM test...")

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

-- ============================================================================
-- The canonical session machine (mirrors session_fsm.lua event-for-event).
-- This ONE table drives both create() and the exporter below.
-- ============================================================================
local session_config = {
	name = "USER_SESSION",
	initial = "logged_out",
	events = {
		{ name = "login_attempt", from = "logged_out", to = "authenticating" },
		{ name = "auth_success", from = "authenticating", to = "authenticated" },
		{ name = "auth_failure", from = "authenticating", to = "logged_out" },
		{ name = "logout", from = "authenticated", to = "logged_out" },
	},
}

-- 1. The export input must be a genuinely valid machine (Phase-1 gate).
local ok_create, fsm_or_err = pcall(bundle.create, {
	kind = "mailbox",
	name = session_config.name,
	initial = session_config.initial,
	events = session_config.events,
})
check("session config accepted by create()", ok_create == true)
local fsm = ok_create and fsm_or_err or nil

-- 2. Spec normalization.
local spec = Export.to_spec(session_config)
check("spec name", spec.name == "USER_SESSION")
check("spec initial", spec.initial == "logged_out")
check(
	"spec states",
	table.concat(spec.states, ",") == "authenticated,authenticating,logged_out",
	table.concat(spec.states, ",")
)
check("spec event count", #spec.events == 4, tostring(#spec.events))
check(
	"spec events sorted",
	table.concat({ spec.events[1].name, spec.events[2].name, spec.events[3].name, spec.events[4].name }, ",")
		== "auth_failure,auth_success,login_attempt,logout"
)

-- 3. JSON golden (deterministic: sorted keys, sorted events).
local json_golden = '{"events":[{"from":["authenticating"],"name":"auth_failure","to":"logged_out","wildcard":false},'
	.. '{"from":["authenticating"],"name":"auth_success","to":"authenticated","wildcard":false},'
	.. '{"from":["logged_out"],"name":"login_attempt","to":"authenticating","wildcard":false},'
	.. '{"from":["authenticated"],"name":"logout","to":"logged_out","wildcard":false}],'
	.. '"initial":"logged_out","name":"USER_SESSION","states":["authenticated","authenticating","logged_out"]}'
local json_out = Export.to_json(spec)
check("JSON golden", json_out == json_golden, string.sub(json_out, 1, 80))

-- 4. PlantUML golden (states aliased s1..sN in sorted order).
local puml_golden = "@startuml\n"
	.. "title USER_SESSION\n"
	.. 'state "authenticated" as s1\n'
	.. 'state "authenticating" as s2\n'
	.. 'state "logged_out" as s3\n'
	.. "[*] --> s3\n"
	.. "s2 --> s3 : auth_failure\n"
	.. "s2 --> s1 : auth_success\n"
	.. "s3 --> s2 : login_attempt\n"
	.. "s1 --> s3 : logout\n"
	.. "@enduml"
local puml_out = Export.to_plantuml(spec)
check("PlantUML golden", puml_out == puml_golden)

-- 5. Determinism: same input, byte-identical output.
check("JSON deterministic", Export.to_json(Export.to_spec(session_config)) == json_out)
check("PlantUML deterministic", Export.to_plantuml(Export.to_spec(session_config)) == puml_out)

-- 6. Roundtrip: every exported event exists on the live machine.
if fsm then
	local caps = {}
	for _, c in ipairs(fsm.capabilities) do
		caps[c] = true
	end
	local all_present = true
	for _, ev in ipairs(spec.events) do
		if not caps[ev.name] then
			all_present = false
		end
	end
	check("spec events all in fsm.capabilities", all_present)
	check("fsm can take first transition", fsm:can("login_attempt"))
else
	check("spec events all in fsm.capabilities", false, "no FSM")
	check("fsm can take first transition", false, "no FSM")
end

-- 7. Trace formatter goldens.
check(
	"trace ok line",
	Export.format_trace({ tick = 7, from = "logged_out", to = "authenticating", event = "login_attempt", ok = true })
		== "[7] logged_out --login_attempt--> authenticating ok"
)
check(
	"trace fail line",
	Export.format_trace({
		tick = 8,
		from = "authenticating",
		to = "authenticating",
		event = "bogus",
		ok = false,
		code = "invalid_transition",
	}) == "[8] authenticating --bogus--> authenticating FAIL(invalid_transition)"
)

-- 8. Numeric states render without error (Phase-1 allows them).
local num_ok, num_spec = pcall(Export.to_spec, {
	initial = 123,
	events = { { name = "start", from = "123", to = 456 } },
})
check("numeric spec builds", num_ok == true)
if num_ok then
	local num_json_golden = '{"events":[{"from":["123"],"name":"start","to":"456","wildcard":false}],'
		.. '"initial":"123","name":"unnamed","states":["123","456"]}'
	check("numeric JSON", Export.to_json(num_spec) == num_json_golden)
	local num_puml = Export.to_plantuml(num_spec, "num")
	check("numeric PlantUML has aliased states", string.find(num_puml, 'state "123" as s1', 1, true) ~= nil)
end

-- 9. Malformed export inputs fail early (mirrors create() strictness).
check("non-table config rejected", pcall(Export.to_spec, nil) == false)
check("missing events rejected", pcall(Export.to_spec, { initial = "A" }) == false)
check(
	"nameless event rejected",
	pcall(Export.to_spec, { events = { { from = "A", to = "B" } } }) == false
)
check("trace non-table rejected", pcall(Export.format_trace, nil) == false)

-- ============================================================================
-- SUMMARY
-- ============================================================================
print(string.rep("=", 60))
print(string.format("Export FSM: %d passed, %d failed", passed, failed))
if failed == 0 then
	print("ALL EXPORT TESTS PASSED")
else
	print("EXPORT FAILURES DETECTED")
end
print(string.rep("=", 60))
print("[BREAKAGE_SUITE] Export FSM test complete")
