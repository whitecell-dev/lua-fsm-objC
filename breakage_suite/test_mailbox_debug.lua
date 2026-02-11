-- breakage_suite/test_mailbox_debug.lua
-- DIAGNOSTIC: Comprehensive mailbox debugging
-- This test will dump state at every step to identify the root cause

local bundle = require("init")
local ReportGen = require("tools.reportgen")

print("\n" .. string.rep("=", 80))
print("MAILBOX DEBUGGING SUITE")
print(string.rep("=", 80))

local report = ReportGen.new("survival_reports/debug")
report:start_test("mailbox_debug")

-- ============================================================================
-- TEST 1: Create FSM with mailbox and inspect structure
-- ============================================================================
print("\n[TEST 1] Creating mailbox FSM...")

local fsm = bundle.create({
    kind = "mailbox",
    name = "DEBUG_FSM",
    initial = "idle",
    mailbox_size = 100,
    debug = true,  -- Enable debug output
    events = {
        { name = "msg", from = "idle", to = "idle" },
        { name = "start", from = "idle", to = "running" },
        { name = "stop", from = "running", to = "idle" },
    },
    callbacks = {
        onbeforemsg = function(f, ctx) 
            print("[DEBUG] onbeforemsg triggered")
            return true 
        end,
        onaftermsg = function(f, ctx)
            print("[DEBUG] onaftermsg triggered")
        end,
    }
})

-- Dump FSM structure
print("\n--- FSM STRUCTURE DUMP ---")
print("FSM type:", type(fsm))
print("FSM methods available:")
local methods = {}
for k, v in pairs(fsm) do
    if type(v) == "function" then
        table.insert(methods, k)
    end
end
table.sort(methods)
for _, m in ipairs(methods) do
    print("  - " .. m)
end

-- Check specific required methods
local required_methods = {
    "send", "process_mailbox", "mailbox_stats", "clear_mailbox",
    "get_state", "can", "is", "resume", "msg", "start", "stop"
}

print("\n--- REQUIRED METHOD CHECK ---")
for _, method in ipairs(required_methods) do
    local status = fsm[method] and "✅ EXISTS" or "❌ MISSING"
    print(string.format("  %-20s: %s", method, status))
    report:add_metric("method_" .. method, status == "✅ EXISTS", "boolean")
end

-- Check mailbox property
print("\n--- MAILBOX PROPERTY ---")
if fsm.mailbox then
    print("  mailbox: ✅ EXISTS")
    print("  mailbox type:", type(fsm.mailbox))
    
    -- Dump mailbox methods
    local mb_methods = {}
    for k, v in pairs(fsm.mailbox) do
        if type(v) == "function" then
            table.insert(mb_methods, k)
        end
    end
    print("  mailbox methods:")
    table.sort(mb_methods)
    for _, m in ipairs(mb_methods) do
        print("    - " .. m)
    end
    
    report:add_metric("mailbox_exists", true, "boolean")
else
    print("  mailbox: ❌ MISSING")
    report:add_metric("mailbox_exists", false, "boolean")
    report:add_failure("MAILBOX_MISSING", "CRITICAL", "FSM has no mailbox property", 
                       "Cannot test mailbox functions", "Check closure exports")
end

-- ============================================================================
-- TEST 2: Test send() method with different signatures
-- ============================================================================
print("\n[TEST 2] Testing send() method...")

local send_tests = {
    { name = "String event", call = function() 
        return fsm:send("msg", { data = { id = 1 } }) 
    end},
    { name = "Table event", call = function() 
        return fsm:send({ event = "msg", data = { id = 2 } }) 
    end},
}

for i, test in ipairs(send_tests) do
    print("\n--- Send Test " .. i .. ": " .. test.name)
    local ok, result = pcall(test.call)
    
    if not ok then
        print("  ❌ ERROR: " .. tostring(result))
        report:add_failure("SEND_FAILED", "MAJOR", "Send crashed: " .. test.name, 
                           tostring(result), "Check send() implementation")
    else
        print("  ✅ Call succeeded")
        print("  Result type:", type(result))
        
        -- Dump result structure
        if type(result) == "table" then
            print("  Result fields:")
            for k, v in pairs(result) do
                print(string.format("    %s: %s (%s)", k, tostring(v), type(v)))
            end
            
            if result.ok then
                print("  ✅ Send successful")
                report:add_metric("send_success_" .. i, true, "boolean")
            else
                print("  ❌ Send failed: " .. (result.message or "unknown error"))
                report:add_metric("send_success_" .. i, false, "boolean")
            end
        end
    end
end

-- ============================================================================
-- TEST 3: Inspect mailbox internals
-- ============================================================================
print("\n[TEST 3] Inspecting mailbox internals...")

-- Send a few messages
for i = 1, 5 do
    fsm:send("msg", { data = { count = i } })
end

-- Try to call mailbox_stats
print("\n--- Testing mailbox_stats() ---")
local stats_ok, stats_result = pcall(function() return fsm:mailbox_stats() end)

if not stats_ok then
    print("  ❌ mailbox_stats() ERROR: " .. tostring(stats_result))
    report:add_failure("STATS_MISSING", "CRITICAL", "mailbox_stats() not callable",
                       tostring(stats_result), "Add mailbox_stats method")
else
    print("  ✅ mailbox_stats() callable")
    print("  Result type:", type(stats_result))
    
    if type(stats_result) == "table" then
        print("  Stats fields:")
        for k, v in pairs(stats_result) do
            print(string.format("    %s: %s (%s)", k, tostring(v), type(v)))
        end
    end
end

-- Direct mailbox inspection if accessible
if fsm.mailbox then
    print("\n--- Direct mailbox inspection ---")
    
    -- Try to call count/has_messages
    local count_ok, count_val = pcall(function() return fsm.mailbox.count end)
    print("  mailbox.count accessible:", count_ok and "✅" or "❌")
    if count_ok then print("    count =", count_val) end
    
    local has_ok, has_val = pcall(function() return fsm.mailbox:has_messages() end)
    print("  mailbox:has_messages() callable:", has_ok and "✅" or "❌")
    if has_ok then print("    has_messages =", has_val) end
    
    local dequeue_ok = pcall(function() return fsm.mailbox:dequeue() end)
    print("  mailbox:dequeue() callable:", dequeue_ok and "✅" or "❌")
end

-- ============================================================================
-- TEST 4: Test process_mailbox()
-- ============================================================================
print("\n[TEST 4] Testing process_mailbox()...")

-- Clear any existing messages
if fsm.clear_mailbox then
    pcall(function() fsm:clear_mailbox() end)
end

-- Send test messages
print("Sending 10 test messages...")
for i = 1, 10 do
    fsm:send("msg", { data = { id = i } })
end

-- Check queue size before processing
local before_stats = fsm:mailbox_stats() and fsm:mailbox_stats() or {}
local before_count = (type(before_stats) == "table" and before_stats.queued) or 
                     (fsm.mailbox and fsm.mailbox.count) or "unknown"
print("Messages in queue before processing:", before_count)

-- Process mailbox
print("\nCalling process_mailbox()...")
local process_ok, process_result = pcall(function() return fsm:process_mailbox() end)

if not process_ok then
    print("  ❌ process_mailbox() ERROR: " .. tostring(process_result))
    report:add_failure("PROCESS_FAILED", "CRITICAL", "process_mailbox() crashed",
                       tostring(process_result), "Check process_mailbox implementation")
else
    print("  ✅ process_mailbox() callable")
    print("  Result type:", type(process_result))
    
    if type(process_result) == "table" then
        print("  Result fields:")
        for k, v in pairs(process_result) do
            print(string.format("    %s: %s (%s)", k, tostring(v), type(v)))
        end
        
        if process_result.ok then
            print("  ✅ Processing successful")
            if process_result.data then
                print("    Processed:", process_result.data.processed or 0)
                print("    Failed:", process_result.data.failed or 0)
                print("    Remaining:", process_result.data.remaining or 0)
                
                report:add_metric("messages_processed", process_result.data.processed or 0, "count")
                report:add_metric("messages_failed", process_result.data.failed or 0, "count")
            end
        else
            print("  ❌ Processing failed: " .. (process_result.message or "unknown"))
            report:add_metric("process_success", false, "boolean")
        end
    end
end

-- Check queue size after processing
local after_stats = fsm:mailbox_stats and fsm:mailbox_stats() or {}
local after_count = (type(after_stats) == "table" and after_stats.queued) or 
                    (fsm.mailbox and fsm.mailbox.count) or "unknown"
print("Messages in queue after processing:", after_count)

-- ============================================================================
-- TEST 5: Test mailbox_stats() functionality
-- ============================================================================
print("\n[TEST 5] Testing mailbox_stats() integration...")

if fsm.mailbox_stats then
    local stats = fsm:mailbox_stats()
    print("mailbox_stats() result:")
    
    if type(stats) == "table" then
        -- Check for expected fields
        local expected_fields = {
            "queued", "max_size", "dropped", "free_slots",
            "total_processed", "total_failed", "total_enqueued", "utilization"
        }
        
        for _, field in ipairs(expected_fields) do
            local present = stats[field] ~= nil
            print(string.format("  %-20s: %s", field, present and "✅" or "❌"))
            if present then
                print(string.format("    value = %s", tostring(stats[field])))
            end
        end
        
        report:add_metric("stats_complete", true, "boolean")
    else
        print("  ❌ mailbox_stats() did not return a table")
        report:add_metric("stats_complete", false, "boolean")
    end
else
    print("  ❌ mailbox_stats() method missing")
end

-- ============================================================================
-- TEST 6: Test event method invocation
-- ============================================================================
print("\n[TEST 6] Testing event method invocation...")

-- Direct call
print("Direct call to msg():")
local direct_ok, direct_result = pcall(function() 
    return fsm:msg({ data = { direct = true } })
end)

if direct_ok then
    print("  ✅ Direct msg() call succeeded")
    if type(direct_result) == "table" then
        print("    ok =", direct_result.ok)
    end
else
    print("  ❌ Direct msg() call failed:", tostring(direct_result))
end

-- Through send/process
print("\nThrough send/process pipeline:")
fsm:send("msg", { data = { pipeline = true } })
local proc_result = fsm:process_mailbox()

if proc_result and proc_result.ok then
    print("  ✅ Pipeline processed")
    print("    Processed:", proc_result.data.processed)
    print("    Failed:", proc_result.data.failed)
end

-- ============================================================================
-- SUMMARY
-- ============================================================================
print("\n" .. string.rep("=", 80))
print("DEBUG SUMMARY")
print(string.rep("=", 80))

local test_report = report:end_test(
    fsm and fsm.mailbox_stats and "PASS" or "FAIL",
    "Mailbox debugging complete"
)

report:print_console_report("mailbox_debug")

local summary = report:generate_summary()
print(string.format("\nTotal Failures: %d", summary.total_failures))
print(string.format("Total Warnings: %d", summary.total_warnings))

print("\n[BREAKAGE_SUITE] Debug test complete")
print("Check 'survival_reports/debug/' directory for JSON reports")

-- Return the FSM for interactive inspection if needed
return fsm
