# CREDITS AND INSPIRATIONS

## Direct Code Inspiration
- **lua-state-machine** by Kyle Conroy
  - URL: https://github.com/kyleconroy/lua-state-machine
  - License: MIT
  - What we used: Basic state machine pattern concept
  - What we changed: Everything else (architecture, patterns, features)

## Our Transformations
| Aspect | Original | CALYX Version |
|--------|----------|--------------|
| **API Style** | Functional | Objective-C/Smalltalk messaging |
| **Architecture** | Monolithic | Layered (IMPO/ALBEO/MNEME) |
| **Concurrency** | None | Async/Mailbox/Actor model |
| **Safety** | None | CALYX Guard constraints |
| **Use Case** | General | LLM-assisted development framework |

## Why This Isn't a Fork
This is a **conceptual derivative**, not a code fork:
- Different architecture (layered vs monolithic)
- Different use case (LLM systems vs general state machines)
- Different patterns (Objective-C messaging vs functional)
- Different feature set (async, mailboxes, CALYX integration)
