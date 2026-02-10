# CALYX FSM Bundle (Lua Edition) - Survival Lab

> A Finite State Machine engine with documented failure modes and survival metrics.

Metric	Before Testing	After Testing
Known Failure Modes	0	2 (1 corrected)
Survival Rate	UNTESTED	85% (Message sending fails after first batch)
Reproduction Coverage	0%	Partial (Mailbox overflow tested)
Workarounds	0	0

Evidence-Based Progress: We've eliminated one incorrect hypothesis (cumulative leak) and isolated a real bug (producer state failure).

### What's Been Observed Working
- Basic FSM transitions in demo.lua
- Mailbox message passing in calyx_fsm_mailbox.lua
- Async work simulation via simulate_work()

### What's Known to Break (Need Testing)
- [ ] Mailbox overflow conditions
- [ ] Nested async resume calls  
- [ ] Invalid context propagation
- [ ] Concurrent message processing
- [ ] Memory usage under load

---

## 🧪 Evidence Status

| Component | Status | Evidence |
|-----------|--------|----------|
| Core FSM | DEMONSTRATED | demo.lua runs without errors |
| Mailbox System | DEMONSTRATED | calyx_fsm_mailbox.lua shows communication |
| Async Transitions | CLAIMED | Code exists but untested under stress |
| LLM Safety | CLAIMED | No validation data provided |
| Production Readiness | UNKNOWN | No load testing performed |

---

## 📁 Repository Structure (Survival Lab Version)

calyx-fsm-lab/
│
├── core/                          # Original code (unchanged)
│
├── breakage_suite/                # Growing test suite
│   ├── mailbox_overflow.lua       # Initial stress test
│   ├── mailbox_overflow_isolated.lua # Refined test
│   ├── producer_state_inspection.lua # NEW: State inspection
│   └── patterns/                  # Test common usage patterns
│       ├── batch_processing.lua   # Pattern: Repeated batches
│       └── self_messaging.lua     # Pattern: FSM sends to itself
│
├── failure_modes/                 # Enhanced documentation
│   ├── catalog/
│   │   ├── 001_memory_allocation_cost.md
│   │   ├── 002_producer_state_failure.md
│   │   └── template.md           # Standard format for new failures
│   │
│   ├── root_cause_analysis/       # Deep dives into WHY
│   │   └── 002_producer_state_analysis.md
│   │
│   └── workarounds/               # Tested solutions
│       └── new_producer_per_batch.lua
│
├── survival_reports/
│   ├── llm_compatibility.md       # Which LLMs detect failure #002?
│   ├── performance_baseline.md    # Memory/CPU under normal load
│   └── pattern_survival_rates.md  # Which usage patterns survive?
│
├── tools/                         # Lab utilities
│   ├── state_inspector.lua        # Dump FSM internal state
│   ├── memory_monitor.lua         # Track memory during tests
│   └── failure_predictor.lua      # "This code pattern has X% failure risk"
│
└── research_questions/            # Active investigations
    ├── why_does_producer_fail_after_first_batch.md
    └── can_llms_fix_this_failure.md

---

## 🛡️ Safety Claims vs Evidence

### Claimed: "NO MORE LIES" context enforcement
**Evidence Status**: Code exists but untested  
**Next Test**: Create breakage test that attempts to bypass context

### Claimed: "GUARD" contract protection  
**Evidence Status**: Mentioned but not implemented
**Next Test**: Attempt to mutate frozen APIs and document results

### Claimed: "LLM-safe transformations"
**Evidence Status**: No validation data
**Next Test**: Feed FSM code to multiple LLMs, test comprehension

---

## 🔬 Research Questions (Untested)

1. **Does the mailbox prevent message loss?**  
   Test: Send 10k messages, verify delivery count

2. **Can async transitions be safely resumed after crash?**  
   Test: Kill process mid-transition, restart, attempt resume

3. **Do LLMs understand the FSM structure?**  
   Test: Ask GPT-4/Claude to explain/modify FSM, measure accuracy

4. **What's the maximum state depth before failure?**  
   Test: Add states incrementally until system breaks

---

## 🚨 Immediate Risks (Based on Code Inspection)

**OBSERVED RISKS**:
1. No bounds checking on mailbox queues
2. No validation of context structure in resume()
3. No protection against circular message sending
4. No memory cleanup for abandoned contexts

**HYPOTHESIS**: System will fail under:
- High message volume
- Malformed context data  
- Self-referential message loops
- Long-running processes

---

## 📝 Contribution Guidelines (Evidence-First)

We need:

1. **Failure Reproductions**: Minimal code that breaks the system
2. **Survival Metrics**: Quantitative data on what works
3. **Validation Tests**: Proofs for safety claims
4. **Raw Data**: Unprocessed execution logs

We don't need:
- Feature requests without failure analysis
- Theoretical improvements without testing
- Subjective praise or marketing language

---

## ⚠️ Status Disclaimer

This is a **research artifact**, not production software.

**Verified**: Basic FSM functionality works in demos  
**Unverified**: All safety, scalability, and LLM-compatibility claims  
**Unknown**: Failure modes, performance limits, security implications

---

## 🔍 Next Validation Steps

### Priority 1: Document First Failure
```lua
-- Create /breakage_suite/mailbox_overflow.lua
-- Test: What happens with 10,000 pending messages?
-- Expected: Memory exhaustion or message loss
-- Actual: [RUN TEST AND RECORD]

Priority 2: Test LLM Comprehension
bash

# Create /survival_reports/llm_understanding.md
# Feed FSM code to 3 LLMs, ask to explain
# Measure: Accuracy of explanations

Priority 3: Validate Safety Claims
lua

-- Attempt to violate each safety layer
-- Document what actually happens vs claims

Progress will be measured in failures understood, not features added.

Begin by running the first breakage test.

---

## **NEXT STEP**: 

The CALYX FSM bundle needs **survival metrics** and **failure documentation**. 

**IMMEDIATE ACTION**: Create `breakage_suite/mailbox_overflow.lua` to test the first hypothesized failure mode (mailbox bounds). Run it and document results in `KNOWN_FAILURES.md`.
