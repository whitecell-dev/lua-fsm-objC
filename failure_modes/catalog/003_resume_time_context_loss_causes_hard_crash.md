003: Resume-Time Context Loss Causes Hard Crash (ctx == nil)

Evidence Status: REPRODUCED
Date: 02/10/2026
Test: /breakage_suite/stress_test_autoheal.lua

Observable Behavior

During stress testing with async FSM transitions enabled:

The FSM enters an async wait state (*_LEAVE_WAIT or equivalent).

Before the transition completes, the internal _context is cleared.

When the FSM attempts to resume the transition, execution crashes with:

lua: [string "calyx_fsm_mailbox"]:171: attempt to index local 'ctx' (a nil value)


The crash occurs consistently once _context is lost prior to resume.

Semantic auto‑healing via __newindex does not prevent the crash.

Failure Mode

The FSM captures _context into a local variable (ctx) during transition execution.

If _context becomes nil before capture, the local ctx is permanently nil for the remainder of that transition.

Subsequent callback execution (onenter*, onafter*, etc.) attempts to index ctx, causing a hard runtime error.

This failure cannot be recovered from by later mutation of fsm._context.

Confirmed Root Cause

Local variable capture beats runtime guards.

Specifically:

FSM transition logic executes:

local ctx = self._context


_context is nil at that moment.

ctx is now permanently nil inside the closure.

Semantic bridge / metatable healing runs after capture, too late.

Callback attempts ctx.data → crash.

This is a capture‑time invariant violation, not an assignment‑time one.

Why This Is Subtle

_context may appear valid when inspected later.

Metatable guards correctly block or replace future _context = nil writes.

None of that matters once a local has captured nil.

This behavior is invisible at the API surface and only detectable through deep runtime tracing.

Workarounds / Fixes

IMPLEMENTED: Capture-Time Context Injection

The FSM engine must guarantee that _context is non‑nil at the moment it is first captured.

Effective fix pattern:

local ctx = self._context
if ctx == nil then
  ctx = {
    event = current_event,
    data = {},
    synthetic = true,
    injected_at = "capture_time"
  }
  self._context = ctx
end


This ensures:

No local ctx can ever be nil

Semantic recovery happens before capture

Async resumes are safe even after partial state loss

Invalidated Approaches

The following were tested and proven insufficient:

❌ Metatable __newindex guards on _context

❌ Auto‑healing when asyncState resets to "none"

❌ Re‑injecting _context during resume

❌ Mailbox‑level recovery logic

All fail because they operate after the critical capture point.

Notes

This failure demonstrates a fundamental property of Lua (and Python):

Local variable capture is stronger than object mutation.

Once violated, semantic correctness cannot be restored without engine‑level intervention.

This failure mode does not exist in SSA / SIL / LLVM‑IR due to enforced lifetime and borrow rules.

Status

Reproduced: ✅

Root Cause Identified: ✅

Engine-Level Fix Applied: ✅

Regression Test Needed: ⏳
