{"timestamp_end":"2026-02-11 01:52:48","timestamp_start":"2026-02-11 01:52:48","pass":true,"duration_sec":0,"summary":"Duration: 0 seconds","metrics":{"deep_chain_process_5":{"value":true,"timestamp":"2026-02-11 01:52:48","unit":"boolean"},"deep_chain_step_A":{"value":1770792768,"timestamp":"2026-02-11 01:52:48","unit":"timestamp"},"rapid_fire_fail_reason_14":{"value":"invalid_transition_for_current_state","timestamp":"2026-02-11 01:52:48","unit":"string"},"rapid_fire_fail_reason_11":{"value":"invalid_transition_for_current_state","timestamp":"2026-02-11 01:52:48","unit":"string"},"rapid_fire_fail_reason_6":{"value":"invalid_transition_for_current_state","timestamp":"2026-02-11 01:52:48","unit":"string"},"rapid_fire_fail_reason_18":{"value":"invalid_transition_for_current_state","timestamp":"2026-02-11 01:52:48","unit":"string"},"rapid_fire_fail_reason_20":{"value":"invalid_transition_for_current_state","timestamp":"2026-02-11 01:52:48","unit":"string"},"deep_chain_process_2":{"value":true,"timestamp":"2026-02-11 01:52:48","unit":"boolean"},"rapid_fire_fail_reason_8":{"value":"invalid_transition_for_current_state","timestamp":"2026-02-11 01:52:48","unit":"string"},"rapid_fire_fail_reason_5":{"value":"invalid_transition_for_current_state","timestamp":"2026-02-11 01:52:48","unit":"string"},"rapid_fire_success_1":{"value":true,"timestamp":"2026-02-11 01:52:48","unit":"boolean"},"rapid_fire_fail_reason_10":{"value":"invalid_transition_for_current_state","timestamp":"2026-02-11 01:52:48","unit":"string"},"test_start":{"value":1770792768,"timestamp":"2026-02-11 01:52:48","unit":"timestamp"},"rapid_fire_success_2":{"value":true,"timestamp":"2026-02-11 01:52:48","unit":"boolean"},"test_end":{"value":1770792768,"timestamp":"2026-02-11 01:52:48","unit":"timestamp"},"rapid_fire_fail_reason_19":{"value":"invalid_transition_for_current_state","timestamp":"2026-02-11 01:52:48","unit":"string"},"rapid_fire_fail_reason_15":{"value":"invalid_transition_for_current_state","timestamp":"2026-02-11 01:52:48","unit":"string"},"rapid_expected_fails":{"value":18,"timestamp":"2026-02-11 01:52:48","unit":"count"},"fsms_created":{"value":50,"timestamp":"2026-02-11 01:52:48","unit":"count"},"memory_end_kb":{"value":208.4619140625,"timestamp":"2026-02-11 01:52:48","unit":"KB"},"deep_chain_process_4":{"value":true,"timestamp":"2026-02-11 01:52:48","unit":"boolean"},"memory_difference_kb":{"value":9.0625,"timestamp":"2026-02-11 01:52:48","unit":"KB"},"rapid_fire_fail_reason_13":{"value":"invalid_transition_for_current_state","timestamp":"2026-02-11 01:52:48","unit":"string"},"synthetic_recovery_success":{"value":false,"timestamp":"2026-02-11 01:52:48","unit":"boolean"},"rapid_fire_fail_reason_12":{"value":"invalid_transition_for_current_state","timestamp":"2026-02-11 01:52:48","unit":"string"},"synthetic_recovery_attempted":{"value":true,"timestamp":"2026-02-11 01:52:48","unit":"boolean"},"rapid_unexpected_fails":{"value":0,"timestamp":"2026-02-11 01:52:48","unit":"count"},"deep_chain_started":{"value":true,"timestamp":"2026-02-11 01:52:48","unit":"boolean"},"rapid_fire_fail_reason_17":{"value":"invalid_transition_for_current_state","timestamp":"2026-02-11 01:52:48","unit":"string"},"rapid_fire_fail_reason_9":{"value":"invalid_transition_for_current_state","timestamp":"2026-02-11 01:52:48","unit":"string"},"rapid_success":{"value":2,"timestamp":"2026-02-11 01:52:48","unit":"count"},"rapid_total":{"value":20,"timestamp":"2026-02-11 01:52:48","unit":"count"},"rapid_fire_fail_reason_4":{"value":"invalid_transition_for_current_state","timestamp":"2026-02-11 01:52:48","unit":"string"},"rapid_fire_fail_reason_3":{"value":"invalid_transition_for_current_state","timestamp":"2026-02-11 01:52:48","unit":"string"},"rapid_fire_fail_reason_16":{"value":"invalid_transition_for_current_state","timestamp":"2026-02-11 01:52:48","unit":"string"},"memory_start_kb":{"value":199.3994140625,"timestamp":"2026-02-11 01:52:48","unit":"KB"},"deep_chain_process_1":{"value":true,"timestamp":"2026-02-11 01:52:48","unit":"boolean"},"rapid_fire_fail_reason_7":{"value":"invalid_transition_for_current_state","timestamp":"2026-02-11 01:52:48","unit":"string"},"deep_chain_final_state":{"value":"A","timestamp":"2026-02-11 01:52:48","unit":"string"},"deep_chain_process_3":{"value":true,"timestamp":"2026-02-11 01:52:48","unit":"boolean"}},"test":"test_context_loss","failures":[],"status":"COMPLETED","warnings":[{"message":"Synthetic recovery failed: no_context","timestamp":"2026-02-11 01:52:48","category":"context_recovery"}]}
{"timestamp_end":"2026-02-11 01:43:04","timestamp_start":"2026-02-11 01:43:04","pass":true,"duration_sec":0,"summary":"Duration: 0 seconds","metrics":{"initial_state":{"value":"IDLE","timestamp":"2026-02-11 01:43:04","unit":"string"},"mailbox_send_success":{"value":true,"timestamp":"2026-02-11 01:43:04","unit":"boolean"},"can_activate":{"value":true,"timestamp":"2026-02-11 01:43:04","unit":"boolean"},"fsm_created":{"value":true,"timestamp":"2026-02-11 01:43:04","unit":"boolean"},"queue_size_after_send":{"value":1,"timestamp":"2026-02-11 01:43:04","unit":"messages"},"can_check_1000_iterations_ms":{"value":0.214,"timestamp":"2026-02-11 01:43:04","unit":"ms"},"test_start_time":{"value":1770792184,"timestamp":"2026-02-11 01:43:04","unit":"timestamp"}},"test":"test_fsm_basic","failures":[],"status":"COMPLETED","warnings":[]}
{
  "test": "test_invalid_fsm_schema.lua",
  "status": "VALIDATION_VERIFIED",
  "tests_executed": 24,
  "tests_passed": 24,
  "tests_failed": 0,
  "warnings": 6,
  "validation_catalog": [
    {
      "id": "EVENT_NAME_VALIDATION",
      "requirement": "Event name must be string",
      "status": "IMPLEMENTED",
      "coverage": "FULL",
      "evidence": "Test 04, 05: Missing/non-string names rejected with clear error",
      "error_message": "event[1].name must be string, got [type]"
    },
    {
      "id": "EVENT_TO_VALIDATION",
      "requirement": "Event 'to' field is required (non-nil)",
      "status": "IMPLEMENTED",
      "coverage": "FULL",
      "evidence": "Test 07, 08: Missing/nil 'to' fields rejected",
      "error_message": "event[1].to is required"
    },
    {
      "id": "EVENT_FROM_VALIDATION",
      "requirement": "Event 'from' must be string, table, or nil",
      "status": "IMPLEMENTED",
      "coverage": "FULL",
      "evidence": "Test 09, 22: Non-string/table 'from' values rejected",
      "error_message": "event[1].from must be string or table, got [type]"
    },
    {
      "id": "REQUIRED_EVENTS_FIELD",
      "requirement": "'events' field is mandatory",
      "status": "IMPLEMENTED",
      "coverage": "FULL",
      "evidence": "Test 01, 19, 20: Missing events field causes assertion failure",
      "error_message": "events required"
    },
    {
      "id": "CALLBACK_TYPE_VALIDATION",
      "requirement": "Callback types should be functions",
      "status": "NOT_IMPLEMENTED",
      "coverage": "NONE",
      "evidence": "Test 14: Non-function callbacks accepted (runtime errors expected)",
      "warning": "Non-function callbacks cause runtime errors"
    },
    {
      "id": "MAILBOX_SIZE_VALIDATION",
      "requirement": "Mailbox size bounds checking",
      "status": "NOT_IMPLEMENTED",
      "coverage": "NONE",
      "evidence": "Test 16, 17, 18: Negative/zero/huge sizes accepted",
      "warning": "Any numeric value accepted (design choice)"
    },
    {
      "id": "EVENT_UNIQUENESS",
      "requirement": "Event name uniqueness",
      "status": "NOT_IMPLEMENTED",
      "coverage": "NONE",
      "evidence": "Test 11: Duplicate event names allowed (override behavior)",
      "warning": "Duplicate event names silently override"
    },
    {
      "id": "STATE_NAME_VALIDATION",
      "requirement": "State name format validation",
      "status": "NOT_IMPLEMENTED",
      "coverage": "PARTIAL",
      "evidence": "Test 12, 13a: Any type allowed for state names",
      "note": "State names can be any Lua value (table keys)"
    }
  ],
  "validation_strategy": {
    "critical_fields": "STRICT_VALIDATION",
    "data_integrity": "MODERATE_VALIDATION",
    "runtime_safety": "MINIMAL_VALIDATION",
    "flexibility": "HIGH"
  },
  "design_tradeoffs": [
    {
      "area": "Event validation",
      "choice": "Strict validation at creation",
      "rationale": "Prevents runtime state machine corruption",
      "impact": "Better error messages, less flexibility"
    },
    {
      "area": "Callback validation",
      "choice": "No type checking",
      "rationale": "Lua's dynamic nature, callback flexibility",
      "impact": "Runtime errors for wrong types"
    },
    {
      "area": "Mailbox configuration",
      "choice": "No bounds checking",
      "rationale": "System-level configuration freedom",
      "impact": "Potential memory issues if misconfigured"
    },
    {
      "area": "State names",
      "choice": "Any type allowed",
      "rationale": "Lua table key flexibility",
      "impact": "Complex state machines possible, but careful naming needed"
    }
  ],
  "recommendations": [
    {
      "priority": "LOW",
      "recommendation": "Add callback type warning (not validation)",
      "rationale": "Debugging aid without breaking existing code"
    },
    {
      "priority": "MEDIUM",
      "recommendation": "Add mailbox size bounds (min=0, max=1_000_000)",
      "rationale": "Prevent accidental memory exhaustion"
    },
    {
      "priority": "LOW",
      "recommendation": "Optional event name uniqueness check",
      "rationale": "Debugging aid for complex state machines"
    },
    {
      "priority": "NONE",
      "recommendation": "State name format validation",
      "rationale": "Current flexibility is valuable for advanced use cases"
    }
  ],
  "test_date": "2026-02-10",
  "notes": "Validation focuses on critical path safety while maintaining Lua's dynamic flexibility. The 6 warnings document intentional design choices rather than failures."
}
{
  "test": "test_mailbox_overflow.lua",
  "status": "RESOLVED",
  "failures_catalog": [
    {
      "id": "UNBOUNDED_QUEUE",
      "severity": "CRITICAL", 
      "status": "FIXED",
      "evidence": "Queue limited to 1000 messages, 9000 messages dropped",
      "impact": "Memory exhaustion / DOS",
      "resolution": "Added queue size limit (default 1000) with configurable max_size",
      "validation": "Test now shows: 'QUEUE_LIMIT_OK: 1000 messages enqueued (limit: 1000)'"
    },
    {
      "id": "MEMORY_RETENTION",
      "severity": "CRITICAL",
      "status": "FIXED",
      "evidence": "Memory reclaimed after explicit cleanup (-19.52 KB growth)",
      "impact": "Linear growth on unflushed queues",
      "resolution": "Added automatic cleanup in process_mailbox() + explicit clear_mailbox() API",
      "validation": "Test now shows: 'MEMORY_RETENTION_OK: All messages cleared'"
    },
    {
      "id": "RETRY_STORM",
      "severity": "MAJOR",
      "status": "FIXED", 
      "evidence": "Invalid transitions retried 3 times (5 messages → 16 failures)",
      "impact": "Processing overhead and queue slot waste",
      "resolution": "Added no_retry flag for invalid state transitions in send()",
      "validation": "Warnings now show: '(no retry)' for invalid transitions"
    },
    {
      "id": "STATE_TRANSITION_CONFUSION",
      "severity": "MEDIUM",
      "status": "PARTIALLY_FIXED",
      "evidence": "Warnings emitted but messages still enqueued",
      "impact": "Runtime errors for invalid transitions",
      "resolution": "Added warnings in send() for invalid current state",
      "validation": "Test shows warnings: 'Event load not valid from state LOADING'"
    },
    {
      "id": "CONTEXT_PRESERVATION",
      "severity": "MINOR",
      "status": "PASSED",
      "evidence": "No synthetic contexts created, nil guard working",
      "impact": "None — patch validated",
      "resolution": "Context nil-safety guard in _complete()",
      "validation": "Test shows: 'Context corruption detected: false'"
    }
  ],
  "system_improvements": [
    "Queue size limits with backpressure",
    "Automatic message cleanup after processing",
    "Retry logic with limits (max 3 retries)",
    "Invalid transition warnings",
    "Mailbox statistics tracking",
    "Explicit cleanup API (clear_mailbox)",
    "Memory management utilities (force_gc_cleanup)"
  ],
  "remaining_concerns": [
    "Zero/negative mailbox sizes accepted (design choice)",
    "Duplicate event names allowed (override behavior)",
    "Unprocessed messages stay until explicit cleanup (expected behavior)"
  ],
  "test_date": "2026-02-10",
  "survival_metrics": {
    "max_queue_size": 1000,
    "memory_reclaim_efficiency": "100% after cleanup",
    "retry_limit": 3,
    "validation_coverage": "Critical paths protected"
  }
}{"timestamp_end": "2026-02-11 01:23:20", "timestamp_start": "2026-02-11 01:23:20", "pass": true, "duration_sec": 0, "summary": "Basic FSM functionality test", "metrics": {"mailbox_send": {"value": "success", "timestamp": "2026-02-11 01:23:20", "unit": "status"}, "fsm_creation": {"value": "success", "timestamp": "2026-02-11 01:23:20", "unit": "status"}, "initial_state": {"value": "IDLE", "timestamp": "2026-02-11 01:23:20", "unit": "state"}, "transition_result": {"value": "success", "timestamp": "2026-02-11 01:23:20", "unit": "status"}, "test_iterations": {"value": 1000, "timestamp": "2026-02-11 01:23:20", "unit": "iterations"}, "mailbox_queue_size": {"value": 1, "timestamp": "2026-02-11 01:23:20", "unit": "messages"}, "can_start_transition": {"value": true, "timestamp": "2026-02-11 01:23:20", "unit": "boolean"}, "memory_growth": {"value": "16.18", "timestamp": "2026-02-11 01:23:20", "unit": "KB"}, "new_state": {"value": "RUNNING", "timestamp": "2026-02-11 01:23:20", "unit": "state"}}, "test": "test_reporting_demo", "failures": [], "status": "COMPLETED", "warnings": []}
{"tests":[{"name":"test_context_loss","warnings":1,"status":"COMPLETED","failures":0,"pass":true,"timestamp":"2026-02-11 01:52:48"}],"total_warnings":1,"generated_at":"2026-02-11 01:52:48","total_failures":0,"total_tests":1,"passed":1,"failed":0}