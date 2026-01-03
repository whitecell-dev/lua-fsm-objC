# 🛡️ GUARD.md — FSM Boundary Contract

This file declares all **frozen contracts** for CALYX FSM modules in Lua. These are enforced by the `GUARD` layer to prevent LLM-assisted edits from breaking valid execution, mailboxes, or inter-FSM agreements.

---

## 🎯 Scope

This file protects:

* Public event names and state transitions
* FSM API method signatures
* Mailbox message formats
* Resume state expectations

---

## 🔐 Frozen Event Signatures

```lua
-- calyx_fsm_objc FSM
startWithFile({ data: { file_path: string }, options: { user_id: number, timeout: number } })
loaded({})
validated({})
completeWithMode({ data: { transform_mode: string }, options: { parallel: boolean } })
savedToDB({ options: { db_endpoint: string } })
```

```lua
-- calyx_fsm_mailbox FSM: PRODUCER
start({ data: { dataset_name: string }, options: { consumer_fsm: FSM } })
generated({})
sent({ options: { consumer_fsm: FSM } })
acknowledged({})
```

```lua
-- calyx_fsm_mailbox FSM: CONSUMER
receive({ data: { dataset: string, records: number, format: string } })
validated({})
processed({})
acknowledged({ options: { producer_fsm: FSM } })
```

---

## 📦 Frozen API Contracts

### Required Methods on Every FSM

```lua
fsm:create({ initial, events, callbacks })
fsm:can(event_name)
fsm:is(state_name)
fsm:resume()
fsm:send(event_name, { to_fsm, data, options })
fsm:process_mailbox()
```

### Forbidden Changes

* Do **not** change the order or arity of these methods
* Do **not** remove support for `resume()` or mailbox
* Do **not** mutate `fsm._context`, `fsm.asyncState`, or internal suffixes

---

## 📨 Mailbox Protocol Constraints

### Message Format

```lua
{
  event = string,         -- Event to trigger
  data = table,           -- Input payload
  options = table,        -- Optional routing/meta
  from_fsm = string,      -- Sender name
  to_fsm = string|FSM,    -- Target FSM or name
  timestamp = string      -- ISO-ish timestamp
}
```

### Guard Rules

* All messages **must** include `event`, `data`, and `options`
* Mailbox names must be stringifiable (for logging)
* Mailbox queue size should not exceed 1024 (for safety)
* `fsm:process_mailbox()` must not mutate unrelated state

---

## 🔄 Async State Constraints

FSMs must only use these suffixes:

```lua
fsm.asyncState ∈ {
  NONE,
  <event>_LEAVE_WAIT,
  <event>_ENTER_WAIT
}
```

Any deviation from this pattern is disallowed.

---

## 🔬 Mutation Rules for LLMs

LLM systems generating or modifying FSMs:

* ✅ May add new events (if declared in `events`) and add optional fields to `data/options`
* ❌ May not change existing event names or remove states
* ❌ May not introduce dynamic field injection or reflection inside transitions

---

## 📁 Guard Metadata

This file belongs alongside `README.md`, `NOMORELIES.md`, and the FSM Lua bundle.

To enforce GUARD, use CI tools that check:

* Method signatures via `luainspect`
* Event lists against this file
* Mailbox structure with snapshot tests

---

✅ **Status: LOCKED** — This contract is enforced.

