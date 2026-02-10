# CALYX FSM Bundle (Lua Edition) — Survival Lab

> A Finite State Machine engine with failure-mode documentation, semantic safety probes, and survival metrics.
> This is not a library — it is a research artifact designed to **break honestly** and **record how**.

---

## 📊 Survival Metrics (Last Run: 2026-02-10)

| Metric                 | Before Testing | After Testing                                                         |
| ---------------------- | -------------- | --------------------------------------------------------------------- |
| Known Failure Modes    | 0              | 3 (2 reproduced, 1 mitigated)                                         |
| Survival Rate          | UNTESTED       | **83%** (Breaks on resume-time context loss, message loss in batch 2) |
| Reproduction Coverage  | 0%             | Partial (Async resume and mailbox overflow now covered)               |
| Workarounds Documented | 0              | 1 (semantic bridge injection)                                         |

---

## ✅ Verified Working

* ✅ Basic FSM transitions (`demo.lua`)
* ✅ Async transitions with `machine.ASYNC` (controlled cases)
* ✅ Mailbox actor communication (`calyx_fsm_mailbox.lua`)
* ✅ Message routing between two FSMs
* ✅ Semantic bridge realignment for `_LEAVE_WAIT` drift
* ✅ Crash recovery via synthetic `_context` injection

---

## 🧨 Known to Break

| Breakage                      | Status       | Link                                                                                 |
| ----------------------------- | ------------ | ------------------------------------------------------------------------------------ |
| `ctx == nil` crash on resume  | REPRODUCED   | [003_resume_context_loss.md](failure_modes/catalog/003_resume_context_loss.md)       |
| Producer fails after 1 batch  | REPRODUCED   | [002_producer_state_failure.md](failure_modes/catalog/002_producer_state_failure.md) |
| Mailbox overflow logic        | UNTESTED     | [`mailbox_overflow.lua`](breakage_suite/mailbox_overflow.lua)                        |
| Concurrent message reentrancy | UNTESTED     | planned                                                                              |
| Circular message loops        | HYPOTHESIZED | not yet tested                                                                       |

---

## 📁 Repository Structure

```
calyx-fsm-lab/
│
├── core/                         # Original FSM logic (unmodified)
│
├── breakage_suite/               # Failure reproductions
│   ├── stress_test_autoheal.lua     # REPRO: ctx = nil crash
│   ├── mailbox_overflow.lua         # High-volume message test
│   └── patterns/
│       ├── batch_processing.lua     # Repeating producer pattern
│       └── self_messaging.lua       # Circular actor pattern
│
├── failure_modes/
│   ├── catalog/
│   │   ├── 002_producer_state_failure.md
│   │   ├── 003_resume_context_loss.md
│   │   └── template.md
│   ├── root_cause_analysis/
│   │   └── 003_resume_ctx_explainer.md
│   └── workarounds/
│       └── semantic_bridge_fix.lua
│
├── survival_reports/
│   ├── llm_compatibility.md
│   ├── semantic_bridge_coverage.md
│   └── pattern_survival_scores.md
│
├── tools/
│   ├── memory_monitor.lua
│   ├── semantic_inspector.lua
│   └── fsm_trace_logger.lua
│
└── research_questions/
    ├── does_llm_understand_mailbox.md
    └── can_resume_be_safely_recovered.md
```

---

## 🔬 Safety Claims vs Ground Truth

| Claim                            | Status                            | Evidence                             |
| -------------------------------- | --------------------------------- | ------------------------------------ |
| `NO MORE LIES` - ctx enforcement | ✅ Partially validated             | Breakage #003 proves failure w/o fix |
| `GUARD` - frozen APIs            | ❌ Not yet enforced                | No runtime mutation blocks in place  |
| Async transitions are safe       | ⚠️ Unsafe without semantic bridge | Confirmed in breakage logs           |
| LLM-compatible structure         | ✅ Verified on function call shape | Further comprehension testing needed |

---

## 🚧 Current Risks (Ranked by Likelihood)

1. ❗ `asyncState` transitions without valid `_context`
2. ❗ Message loss in multi-batch scenarios
3. ❗ Silent corruption from mailbox self-sends
4. ❗ Drift between FSM state and handler logic
5. ❓ Unbounded mailbox growth (OOM not yet triggered)

---

## 📌 Current Evidence Summary

| Area                                        | Status           | Next Step                        |
| ------------------------------------------- | ---------------- | -------------------------------- |
| Async FSM resilience                        | BROKEN           | Inject safety context on resume  |
| Mailbox system                              | PARTIALLY BROKEN | Add overflow, self-loop tests    |
| Transition lifecycle (`onleave`, `onenter`) | VALIDATED        | Needs LLM mutation test          |
| Semantic state tracking                     | ENABLED          | Validate audit coverage          |
| LLM safety                                  | UNVERIFIED       | Ask 3 models to explain FSM code |
| Recovery after crash                        | UNSUPPORTED      | Simulate crash mid-transition    |

---

## 📖 Contribution Guidelines (Failure-First)

We prioritize:

* 🔍 Reproducible breakages
* 📈 Measurable survival metrics
* 🧪 Raw logs and structured test artifacts
* 🛡️ Validation of semantic safety guarantees

We deprioritize:

* ✨ Feature additions without tests
* 🧠 Intuition-based optimizations
* 💬 Subjective feedback

---

## 🚨 This Is a Survival Lab

This is not a library. This is not a demo.
This is a system under observation.

It is built to:

* Break cleanly
* Record its own errors
* Invite outside pressure
* Track semantic drift
* Invite LLM and human understanding

---

## ✅ Next Experiments

### 📦 Validate `ctx` resilience under async resume

```lua
-- Setup FSM
fsm:warn()
fsm._context = nil
fsm:transition("warn")  -- Should no longer crash
```

### 📦 Test LLM comprehension

```markdown
Prompt GPT-4, Claude, and Gemini:
- "What does this FSM do?"
- "Add a new state 'paused'"
- "Explain what happens in an async transition"
```

### 📦 Simulate message storm

```lua
-- /breakage_suite/mailbox_overflow.lua
-- Send 10,000 messages to mailbox
-- Expect memory growth, dropped messages, or soft failure
```

---

## 🧭 Metrics That Matter

| Metric                | Meaning                                        |
| --------------------- | ---------------------------------------------- |
| Survival Rate         | % of test scenarios that complete successfully |
| Reproduction Coverage | % of known failure modes with tests            |
| Workaround Coverage   | % of breakages with documented patches         |
| LLM Compatibility     | % of prompts correctly interpreted             |
| Semantic Drift        | % of runs with state mismatch or missing ctx   |

---

## 🔍 Final Reminder

**Progress is not measured in features added.**
**It is measured in failures understood.**

Start by trying to break something.
Then document it.
Then survive it.

Ship early ship often


