# 🧠 NOMORELIES.md — Transition Discipline for LLM-Safe FSMs

This document defines the strict behavioral rules enforced by CALYX under the `NO MORE LIES` doctrine.

> **LLMs must tell the truth to the runtime.** No fake returns. No hidden errors. No skipped cleanup. Every transition must obey the FSM contract **exactly**.

---

## 🎯 Purpose

This file defines:

* Honest error propagation
* Explicit context shape enforcement
* Safe `resume()` behavior
* Transition lifecycle expectations

---

## 📦 FSM Context Contract

### Required Fields

Each FSM transition and resume **must** include a context with:

```lua
{
  event = string,
  from = string,
  to = string,
  data = table,     -- user-supplied inputs
  options = table,  -- flags, metadata
}
```

### Forbidden Omissions

* `data` and `options` **must always** be present (may be empty)
* `event`, `from`, and `to` must be accurate or transition will be rejected

---

## 🧾 Error Handling Contract

### `failure()` Must Return:

```lua
false, {
  ok = false,
  error_type = "<reason>",
  details = <optional>,
  timestamp = "<generated>",
}
```

This return signature is frozen. Any mutation or shortcut breaks downstream LLM expectations and structured logging.

---

## 🔁 Resume Integrity

### `fsm:resume()` Must Enforce:

* A valid `fsm._context` exists
* The `fsm.asyncState` is not `NONE`
* Transition resumes with original context
* Final cleanup occurs (clearing context and state)

LLMs may not simulate `resume()` without obeying this exact logic.

---

## 🧪 Transition Lifecycle (3 Stages)

FSM transitions move through:

```text
→ onbefore<Event>
→ onleave<FromState>
→ onenter<ToState>
→ onafter<Event>
```

`onstatechange(ctx)` is triggered after a successful completion.

Each stage may:

* Return `false` → Cancel transition
* Return `machine.ASYNC` → Pause transition
* Return `nil`/`true` → Proceed synchronously

LLMs must declare and respect this branching.

---

## 🔍 Logging Discipline

Each stage must log using:

```lua
log_trace("BEFORE", ctx)
log_trace("ENTER", ctx)
log_trace("AFTER", ctx)
```

LLMs may not suppress logging unless explicitly instructed.

---

## ✅ Transition Return Values

FSM transition methods **must always** return:

```lua
true, result_table   -- if success
false, error_table   -- if failure or cancelled
```

Never return `nil`, strings, or ambiguous booleans. Do not fake success.

---

## 🔒 Required Truth Surfaces

| Surface          | Must Be Honored         |
| ---------------- | ----------------------- |
| `fsm._context`   | Must be accurate        |
| `fsm.asyncState` | Must follow suffix spec |
| `resume()`       | Must call `_complete()` |
| Callbacks        | May not be skipped      |
| Returns          | Must match contract     |

---

## 🧠 Why This Exists

LLMs hallucinate partial transitions. They omit `false` returns. They skip error branches.

`NO MORE LIES` **forbids this.** Transitions must:

* Carry structured context
* Emit accurate logs
* Handle errors explicitly
* Resume faithfully

---

✅ **Status: MANDATORY** — All FSMs must obey this discipline.

