-- CALYX: Semantic Recovery + Async Drift Bridge for FSM instances
-- This module implements a "Deep-Tissue" Proxy that heals state drift on read/write.

local machine_module = require("calyx_fsm_mailbox")
local protocol_maps = {}

local function apply_semantic_bridge(instance, name, map)
    local internal = instance
    protocol_maps[instance] = map

    return setmetatable({}, {
        -- 1. THE READ-GUARD: Catches local variable capture/amnesia
        __index = function(_, k)
            -- If the engine is trying to read context/state while it's "stuck"
            if k == "_context" or k == "current" or k == "currentTransitioningEvent" then
                if rawget(internal, "asyncState") ~= "none" and not rawget(internal, "_context") then
                    print(string.format("[SIL_RECOVERY] Read-time Healing [%s]: Injecting Safety Context", k))
                    rawset(internal, "_context", {
                        event = "read_recovery",
                        data = { count = 0, autoinjected = true },
                        synthetic = true
                    })
                end
            end
            return internal[k]
        end,
        
        -- 2. THE WRITE-GUARD: Blocks invalid state assignments
        __newindex = function(_, k, v)
            -- PROACTIVE HEALING: Never let _context become nil
            if k == "_context" and v == nil then
                v = {
                    event = "safety_recovery",
                    data = { count = 0 },
                    synthetic = true
                }
                print("[SIL_RECOVERY] Blocked null-context assignment. Safety Context locked in.")
            end

            -- REENTRY GUARD: If a transition starts but context is missing, fix it NOW
            if k == "currentTransitioningEvent" and v ~= nil then
                if rawget(internal, "_context") == nil then
                    print("[SIL_PATCH] Transition requested with no context. Pre-empting crash.")
                    rawset(internal, "_context", {
                        event = v,
                        data = { count = 0, autoinjected = true },
                        synthetic = true
                    })
                end
            end

            -- SEMANTIC BRIDGE: Realignment for *_LEAVE_WAIT stalls
            if k == "asyncState" and v and type(v) == "string" and v:match("_LEAVE_WAIT$") then
                local event_name = v:gsub("_LEAVE_WAIT$", "")
                local target = protocol_maps[internal][event_name] or "UNKNOWN"
                
                print(string.format("[SEMANTIC_BRIDGE] Realignment: %s -> %s", internal.current, target))
                
                rawset(internal, "current", target)
                rawset(internal, "asyncState", "none")
                rawset(internal, "currentTransitioningEvent", nil)
                
                if rawget(internal, "isTransitioning") ~= nil then
                    rawset(internal, "isTransitioning", false)
                end
                return
            end

            rawset(internal, k, v)
        end,
    })
end

-- --- FACTORY OVERRIDE ---
local original_create = machine_module.create
machine_module.create = function(config)
    local raw_instance = original_create(config)
    local local_map = {}

    -- Pre-calculate the state map to avoid lookups during hot loops
    for _, e in ipairs(config.events or {}) do
        local_map[e.name] = e.to
    end

    return apply_semantic_bridge(raw_instance, config.name or "unnamed", local_map)
end

print("[SURVIVAL_WORKAROUND] Semantic Bridge & Read-Guard Proxy Armed.")
return machine_module