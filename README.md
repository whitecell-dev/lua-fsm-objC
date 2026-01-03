# CALYX FSM Bundle (Lua Edition)

A modular, LLM-friendly Finite State Machine engine in Lua with full async support, mailbox-based actor communication, and Objective-C-style message signatures. Optimized for CALYX-style development: structured, debuggable, portable, and secure.

---

## 📦 Overview

This bundle includes the following FSM implementations:

* **`calyx_fsm_objc`**: Core FSM engine with Objective-C-style named parameters
* **`calyx_fsm_mailbox`**: Extended FSM with mailbox-based asynchronous message passing (Actor model)
* **`data_handlers`**: Simulated ALBEO async work handlers (e.g., validation, transformation)
* **`demo`**: Example pipeline orchestrator (IMPO layer)

All modules are layered according to CALYX architecture:

| Layer   | Purpose                          |
| ------- | -------------------------------- |
| UTILITY | Stateless logic modules          |
| ALBEO   | Data-intensive, side-effect work |
| IMPO    | Orchestration and control flow   |

---

## ⚙️ Features

### ✅ Async Transition Support

Each FSM transition can be paused mid-leave or mid-enter, and resumed manually or via message passing.

### 📨 Actor Model

FSMs can send messages to each other via internal mailboxes. This enables parallel, modular workflows across FSM boundaries.

### 🧠 Objective-C Style Messaging

Transitions accept structured `{ data, options }` tables for clarity and extensibility, emulating Objective-C named parameters:

```lua
fsm:sendReport({
  data = { report_id = 42 },
  options = { format = "pdf", retries = 3 }
})
```

### 🔄 Resume Flow

You can resume paused transitions manually:

```lua
fsm:resume()
```

Or process messages in bulk:

```lua
fsm:process_mailbox()
```

---

## 🧪 Demo Scenarios

### `demo.lua`

A complete ingestion pipeline with 5 async stages:

* `startWithFile`
* `loaded`
* `validated`
* `completeWithMode`
* `savedToDB`

Each transition simulates async work via `simulate_work()`.

### `calyx_fsm_mailbox.lua`

Two demo FSMs interact in:

* **Producer → Consumer pattern**
* **Ping ↔ Pong circular communication**

Mailbox queues are used to send/receive events safely.

---

## 🔐 Safety Layers

### `NO MORE LIES`: Enforce Honest Context

All events and resume logic must carry explicit `{ data, options }`. The FSM stores `_context` for safe continuation.

### `GUARD`: Protect Contract Boundaries

Transition signatures, async states, and exported FSM methods are guarded against unsafe mutations. For production, consider defining:

* `guard.lua` or `guard.yaml`: freeze `fsm:resume`, `fsm:event(...)`, and mailbox shape
* Static assertions or CI checks for FSM event integrity

### `ATLAS`: Architectural Metadata

The included bundle defines:

* `MODULE_MAP`
* `DEPENDENCY_GRAPH`
* `CALYX_METADATA`

These support tooling, tracing, and LLM-safe transformations.

---

## 🧩 Extending

To add your own FSM:

```lua
local my_fsm = machine.create({
  name = "MYFSM",
  initial = "IDLE",
  events = {
    { name = "init", from = "IDLE", to = "STARTED" },
    -- more transitions
  },
  callbacks = {
    onleaveIDLE = function(fsm, ctx)
      -- do work
    end,
  },
})
```

To enable messaging:

```lua
my_fsm:send("event_name", { to_fsm = other_fsm, data = {...} })
```

---

## 🛠️ Tools

Expose or use the bundled introspection tools:

```lua
bundle.get_module("demo")
bundle.list_modules("UTILITY")
bundle.get_dependencies("demo")
```

---

## 🧱 Runtime Integration

The `_calyx_import_shim()` sets up `package.loaded` with all module contents for safe local `require()` usage inside the bundle.

Use it in standalone or embedded form.

---

## 📜 Attribution

### Conceptual Inspiration

This project's state machine design was inspired by Kyle Conroy's [lua-state-machine](https://github.com/kyleconroy/lua-state-machine).

### But this is a full architectural shift:

| Aspect           | Inspiration       | CALYX FSM                |
| ---------------- | ----------------- | ------------------------ |
| **Pattern**      | Basic FSM         | Objective-C messaging    |
| **Architecture** | Monolithic        | Layered (IMPO/ALBEO)     |
| **Concurrency**  | None (sync only)  | Actor model w/ mailboxes |
| **Safety**       | None              | Guarded + resumable      |
| **Use Case**     | General scripting | LLM-integrated pipelines |

We reimagined the FSM paradigm through CALYX principles: **modularity, async control, actor messaging, and LLM-boundary enforcement**.

---

## 📁 Suggested Files to Add

* `GUARD.md`: Define frozen FSM APIs, exported event signatures, allowed async states.
* `NOMORELIES.md`: Document context honesty, error propagation, and async discipline.
* `ATLAS.json`: Exported metadata for mapping, tracing, and LLM digestion.

These enforce structure when LLMs are allowed to refactor or evolve FSM systems.

---

## ✅ Status

> ✅ Fully Working • 🧪 Demo Included • 🔁 Async Flow • 📨 Mailboxes Enabled • 🔐 Safe for LLM Use

---

## 🚀 Run It

Run `demo.lua` or `calyx_fsm_mailbox.lua` directly for live simulations.

---

## 🌍 CALYX Ecosystem

This FSM is part of the CALYX reasoning OS, optimized for:

* LLM-assisted logic pipelines
* Multi-agent state reasoning
* Offline-first systems on embedded or edge devices

For more, visit the CALYX project.

---

**Licensed under MIT.**

