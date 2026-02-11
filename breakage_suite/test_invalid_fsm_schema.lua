-- breakage_suite/test_invalid_fsm_schema.lua
-- STRESS: malformed create() inputs and schema validation
-- UPDATED: Matches new validation in calyx_fsm_mailbox.lua

local bundle = require("init")
local FSM = bundle.create

print("[BREAKAGE_SUITE] Starting invalid FSM schema test...")

local test_cases = {
	-- ============================================================
	-- TEST GROUP 1: MISSING REQUIRED FIELDS
	-- ============================================================
	{
		name = "MISSING_EVENTS",
		config = {
			initial = "IDLE",
			callbacks = { onleaveIDLE = function() end },
		},
		expected_error = "events required",
		error_type = "assertion",
	},

	{
		name = "MISSING_INITIAL",
		config = {
			events = { { name = "start", from = "IDLE", to = "RUNNING" } },
		},
		expected_error = nil,
		should_succeed = true,
		note = "initial defaults to 'none'",
	},

	-- ============================================================
	-- TEST GROUP 2: INVALID EVENT DEFINITIONS (NEW VALIDATION)
	-- ============================================================
	{
		name = "EMPTY_EVENTS_ARRAY",
		config = {
			initial = "IDLE",
			events = {},
		},
		expected_error = nil,
		should_succeed = true,
		note = "Empty events array creates FSM with no transitions",
	},

	{
		name = "EVENT_MISSING_NAME",
		config = {
			initial = "IDLE",
			events = {
				{ from = "IDLE", to = "RUNNING" },
			},
		},
		expected_error = "event[1].name must be string, got nil",
		error_type = "validation",
	},

	{
		name = "EVENT_NAME_NOT_STRING",
		config = {
			initial = "IDLE",
			events = {
				{ name = 123, from = "IDLE", to = "RUNNING" },
			},
		},
		expected_error = "event[1].name must be string, got number",
		error_type = "validation",
	},

	{
		name = "EVENT_MISSING_FROM",
		config = {
			initial = "IDLE",
			events = {
				{ name = "start", to = "RUNNING" },
			},
		},
		expected_error = nil,
		should_succeed = true,
		note = "'from' can be nil for wildcard transitions",
	},

	{
		name = "EVENT_MISSING_TO",
		config = {
			initial = "IDLE",
			events = {
				{ name = "start", from = "IDLE" },
			},
		},
		expected_error = "event[1].to is required",
		error_type = "validation",
	},

	{
		name = "EVENT_TO_IS_NIL",
		config = {
			initial = "IDLE",
			events = {
				{ name = "start", from = "IDLE", to = nil },
			},
		},
		expected_error = "event[1].to is required",
		error_type = "validation",
	},

	{
		name = "FROM_NOT_STRING_OR_TABLE",
		config = {
			initial = "IDLE",
			events = {
				{ name = "start", from = 123, to = "RUNNING" },
			},
		},
		expected_error = "event[1].from must be string or table, got number",
		error_type = "validation",
	},

	{
		name = "FROM_TABLE_WITH_NON_STRINGS",
		config = {
			initial = "IDLE",
			events = {
				{ name = "start", from = { "IDLE", 123 }, to = "RUNNING" },
			},
		},
		expected_error = nil, -- Table contents not validated
		should_succeed = true,
		warning = "Table 'from' with mixed types may cause issues",
	},

	{
		name = "DUPLICATE_EVENT_NAMES",
		config = {
			initial = "IDLE",
			events = {
				{ name = "start", from = "IDLE", to = "RUNNING" },
				{ name = "start", from = "RUNNING", to = "STOPPED" },
			},
		},
		expected_error = nil,
		should_succeed = true,
		warning = "Duplicate event names silently override",
	},

	-- ============================================================
	-- TEST GROUP 3: STATE NAME VALIDATION
	-- ============================================================
	{
		name = "INITIAL_STATE_NIL",
		config = {
			initial = nil,
			events = { { name = "start", from = "IDLE", to = "RUNNING" } },
		},
		expected_error = nil,
		should_succeed = true,
		note = "nil initial becomes 'none'",
	},

	{
		name = "NUMERIC_STATE_NAME_VALID",
		config = {
			initial = 123, -- Numeric initial state IS allowed
			events = { { name = "start", from = "123", to = 456 } }, -- String 'from'
		},
		expected_error = nil,
		should_succeed = true,
		note = "Numeric state names allowed, 'from' must be string representation",
	},

	{
		name = "NUMERIC_FROM_FIELD_INVALID",
		config = {
			initial = 123,
			events = { { name = "start", from = 123, to = 456 } },
		},
		expected_error = "event[1].from must be string or table, got number",
		error_type = "validation",
		note = "Numeric 'from' field correctly rejected",
	},

	-- ============================================================
	-- TEST GROUP 4: CALLBACK VALIDATION
	-- ============================================================
	{
		name = "CALLBACK_NOT_FUNCTION",
		config = {
			initial = "IDLE",
			events = { { name = "start", from = "IDLE", to = "RUNNING" } },
			callbacks = {
				onleaveIDLE = "not a function",
			},
		},
		expected_error = nil,
		should_succeed = true,
		warning = "Non-function callbacks cause runtime errors",
		note = "No callback type validation",
	},

	{
		name = "INVALID_CALLBACK_NAME",
		config = {
			initial = "IDLE",
			events = { { name = "start", from = "IDLE", to = "RUNNING" } },
			callbacks = {
				not_a_real_callback = function() end,
			},
		},
		expected_error = nil,
		should_succeed = true,
		note = "Extra callback fields ignored",
	},

	-- ============================================================
	-- TEST GROUP 5: MAILBOX CONFIGURATION
	-- ============================================================
	{
		name = "NEGATIVE_MAILBOX_SIZE",
		config = {
			initial = "IDLE",
			events = { { name = "start", from = "IDLE", to = "RUNNING" } },
			mailbox_size = -100,
		},
		expected_error = nil,
		should_succeed = true,
		warning = "Negative mailbox size accepted",
	},

	{
		name = "ZERO_MAILBOX_SIZE",
		config = {
			initial = "IDLE",
			events = { { name = "start", from = "IDLE", to = "RUNNING" } },
			mailbox_size = 0,
		},
		expected_error = nil,
		should_succeed = true,
		warning = "Zero-size mailbox drops all messages",
	},

	{
		name = "HUGE_MAILBOX_SIZE",
		config = {
			initial = "IDLE",
			events = { { name = "start", from = "IDLE", to = "RUNNING" } },
			mailbox_size = 1000000,
		},
		expected_error = nil,
		should_succeed = true,
		warning = "Large mailbox consumes memory",
	},

	-- ============================================================
	-- TEST GROUP 6: EDGE CASES
	-- ============================================================
	{
		name = "EMPTY_CONFIG",
		config = {},
		expected_error = "events required",
		error_type = "assertion",
	},

	{
		name = "NIL_CONFIG",
		config = nil,
		expected_error = "events required",
		error_type = "assertion",
	},

	{
		name = "COMPLEX_STATE_NAMES",
		config = {
			initial = "state-with-dashes",
			events = {
				{
					name = "transition-event",
					from = { "state-with-dashes", "another_state" },
					to = "final.state.with.dots",
				},
			},
		},
		expected_error = nil,
		should_succeed = true,
		note = "Complex state names work",
	},

	-- ============================================================
	-- TEST GROUP 7: MULTIPLE VALIDATION ERRORS
	-- ============================================================
	{
		name = "MULTIPLE_INVALID_EVENTS",
		config = {
			initial = "IDLE",
			events = {
				{ from = "IDLE", to = "RUNNING" }, -- missing name
				{ name = 456, to = "RUNNING" }, -- non-string name
				{ name = "test3", from = "IDLE" }, -- missing to
				{ name = "test4", from = 789, to = "RUNNING" }, -- invalid from
			},
		},
		expected_error = "event[1].name must be string, got nil",
		error_type = "validation",
		note = "First validation error stops processing",
	},

	{
		name = "VALID_COMPLEX_CONFIG",
		config = {
			name = "ComplexFSM",
			initial = "ready",
			mailbox_size = 500,
			events = {
				{ name = "initialize", from = "ready", to = "initializing" },
				{ name = "complete", from = "initializing", to = "complete" },
				{ name = "reset", from = { "initializing", "complete" }, to = "ready" },
			},
			callbacks = {
				onleaveready = function(ctx)
					print("Leaving ready")
				end,
				onentercomplete = function(ctx)
					print("Entered complete")
				end,
			},
		},
		expected_error = nil,
		should_succeed = true,
		note = "Complex valid configuration should work",
	},
}

-- ============================================================================
-- EXECUTION AND VALIDATION
-- ============================================================================

print("\nExecuting " .. #test_cases .. " test cases...\n")

local passed = 0
local failed = 0
local warnings = 0

for i, test in ipairs(test_cases) do
	print(string.format("[TEST %02d] %-30s", i, test.name))

	local ok, fsm_or_err = pcall(FSM, test.config)
	local error_message = not ok and tostring(fsm_or_err) or ""

	if test.expected_error then
		if not ok then
			if string.find(error_message, test.expected_error, 1, true) then
				print(string.format("  ✓ Expected error: %s", test.expected_error))
				passed = passed + 1
			else
				print(
					string.format(
						"  ✗ Wrong error:\n     Got:      %s\n     Expected: %s",
						error_message:sub(1, 80),
						test.expected_error
					)
				)
				failed = failed + 1
			end
		else
			print(string.format("  ✗ Expected error '%s' but succeeded", test.expected_error))
			failed = failed + 1
		end
	else
		if ok then
			if test.should_succeed then
				print("  ✓ Succeeded as expected")
				passed = passed + 1

				if test.warning then
					print(string.format("    ⚠️  %s", test.warning))
					warnings = warnings + 1
				end

				if test.note then
					print(string.format("    ℹ️  %s", test.note))
				end
			else
				print("  ✗ Succeeded but should have failed")
				failed = failed + 1
			end
		else
			if test.should_succeed then
				print(string.format("  ✗ Failed but should have succeeded: %s", error_message:sub(1, 60)))
				failed = failed + 1
			else
				print(string.format("  ✓ Failed as expected: %s", error_message:sub(1, 60)))
				passed = passed + 1
			end
		end
	end

	if ok and fsm_or_err and fsm_or_err.clear_mailbox then
		fsm_or_err:clear_mailbox()
	end

	print()
end

-- ============================================================================
-- FAILURE CATALOG ENTRY
-- ============================================================================

print(string.rep("=", 60))
print("FAILURE CATALOG: INVALID_FSM_SCHEMA")
print(string.rep("=", 60))
print(string.format("Total tests: %d", #test_cases))
print(string.format("Passed: %d", passed))
print(string.format("Failed: %d", failed))
print(string.format("Warnings: %d", warnings))

if failed == 0 then
	print("\n✅ ALL TESTS PASSED - Validation working correctly")
else
	print("\n❌ VALIDATION FAILURES DETECTED")
end

print("\n" .. string.rep("-", 60))
print("VALIDATION SUMMARY")
print(string.rep("-", 60))

print("\n✅ NEW VALIDATION IN PLACE:")
print("  • Event 'name' must be string")
print("  • Event 'to' field is required (non-nil)")
print("  • Event 'from' must be string, table, or nil")

print("\n⚠️  STILL NO VALIDATION:")
print("  • Callback types (can be any value)")
print("  • Mailbox size bounds (any number accepted)")
print("  • Event name uniqueness (duplicates allowed)")
print("  • State name format (any value allowed)")

print("\n📊 COVERAGE:")
print("  • Critical fields: ✅ Name, To, From types")
print("  • Data integrity: ⚠️  Some gaps remain")
print("  • Runtime safety: ⚠️  Callbacks not validated")

print(string.rep("=", 60))
print("[BREAKAGE_SUITE] Invalid FSM schema test complete")
