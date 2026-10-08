# CALYX FSM Bundle (Lua Edition) — Survival Lab

> A Finite State Machine engine with failure-mode documentation, semantic safety probes, and survival metrics.
> This is not a library — it is a research artifact designed to **break honestly** and **record how**.

Every claim below was checked against the code. Where a claim used to live here and the code
did not support it, the claim was removed or corrected rather than left to mislead. Known
gaps that are **not** fixed are marked `KNOWN:` at the exact source line, and indexed in
[KNOWN_ISSUES.md](KNOWN_ISSUES.md).

---

## 🚨 Read This First: Three Things That Will Bite You

1. **`core/*.lua` cannot be loaded directly.** Every one of them does `require("abi")`,
   `require("core")`, etc. Those bare names resolve **only** via `package.preload` aliases
   installed by `calyx_bundle.lua` when it loads. Debugging by `require("core.objc")` gives
   you a second, disconnected copy of the module.

2. **`calyx_bundle.lua` is generated.** It is `core/*.lua` embedded verbatim — the two are
   byte-for-byte identical, and that invariant is meant to hold. Regenerate with
   `lua bundler.lua` from the repo root, then re-verify.

3. **`core/core.lua` is mostly dead code.** Only `build_transition_map`, `can_transition`,
   `create_context` and `warn` are live. In particular `lock_metatable`,
   `check_event_collision`, `validate_event_name` and `validate_state_name` are **never
   called**, which is why reserved event names and event-name formats are *not* enforced.
   See the banner at the top of that file.

---

## 📦 Running Things

Nothing in the repo documented this. There is **no** Makefile, no CI, and no test runner
script — each test file must be invoked individually, **from the repo root** (every `require`
is root-relative, and `bundler.lua` hardcodes `root_dir = "core"`).

```sh
# Regenerate the bundle from core/
lua bundler.lua

# Library use
lua -e 'local f = require("init"); local m = f.create{kind="mailbox",initial="IDLE",
  events={{name="go",from="IDLE",to="DONE"}}}; print(m:send"go"); print(m:process_mailbox())'

# Demos  (need their respective services running)
lua demo.lua
lua run_demo.lua        # writes ./session_demo.db; needs lsqlite3
lua run_redis_demo.lua  # FLUSHES THE REDIS DB at startup; needs redis on 127.0.0.1:6379
lua run_nginx_demo.lua  # needs OpenResty already running on :8080 (see caveat below)

# Tests — 8 files, no aggregate runner
lua test_hardened.lua
lua breakage_suite/test_context_loss.lua
lua breakage_suite/test_example_professional.lua
lua breakage_suite/test_unregistered_event.lua
lua breakage_suite/test_invalid_fsm_schema.lua
lua breakage_suite/test_mailbox_debug.lua
lua breakage_suite/test_mailbox_overflow.lua
lua breakage_suite/test_reporting_demo.lua

# Lint  (no gate exists in CI; this is informational)
luacheck .

# Bare-metal OpenResty install, and a drift check
tools/sync_lualib.sh [DEST]     # default /usr/local/openresty/site/lualib
tools/sync_lualib.sh --check    # non-zero exit = the installed copy has drifted
```

Two environment variables are honoured, and **only** when the matching constructor
argument is absent, so every existing caller is unaffected:

| Variable | Read by | Default |
| --- | --- | --- |
| `CALYX_REDIS_HOST`, `CALYX_REDIS_PORT` | `redis_host.lua:19-20` | `127.0.0.1`, `6379` |
| `CALYX_SQLITE_PATH` | `sqlite_host.lua:36` | `session_demo.db` |
| `CALYX_STRICT_MODE` | `init.lua:32-45` | enabled (set `off`/`0`/`false`/`no` to disable) |
```

## 🐳 Container

There is a working deployment stack. It was verified end to end, not just written:

```sh
docker-compose up -d --build
docker-compose run --rm smoke        # 13 checks against the live stack
docker-compose down -v
# host port is overridable: CALYX_PORT=8081 docker-compose up -d
```

* `openresty/Dockerfile` — OpenResty 1.27.1.2 + cjson, lsqlite3, luafilesystem, redis-lua.
* `openresty/nginx.conf` — `lua_package_path` and `content_by_lua_file` point **into the
  read-only `/app` mount**, not at an installed copy. See "Why read-only" below.
* `openresty/smoke.sh` — 13 checks, also runnable against a local instance:
  `BASE=http://127.0.0.1:8099 sh openresty/smoke.sh`.
* `tools/sync_lualib.sh` — bare-metal install, with `--check` to detect drift.

**Why read-only matters:** on the machine this was built on, `/usr/local/openresty/site/lualib`
held a *stale duplicate* of these Lua files that had silently drifted from the repo — every
file was out of date, and `/fsm/` was being served from that stale copy rather than the repo.
Mounting the repo read-only removes the entire class of bug: there is no second copy to rot.

**One endpoint is still broken by design:** `/fsm/` returns **HTTP 400** for a default
request. `nginx_host.lua` defaults `agent_type` to `user_agent`, which cannot emit `cache_set`,
but the successful-login effect list includes it — so the batch is rejected. Pass
`X-Agent-Type: admin_agent` and it returns `200 / state=authenticated`. That is a
capability-scoping decision, not a container problem. See [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

---

## 📊 Verified Working

Checked against the code on 2026-10-07.

* ✅ Basic FSM transitions — `demo.lua`, `core/objc.lua`, `core/mailbox.lua`
* ✅ Mailbox actor communication with a bounded ring buffer — `core/ringbuffer.lua`
* ✅ Async transitions with `machine.ASYNC` via an `onleave<state>` callback returning
  `ABI.STATES.ASYNC` — mailbox FSM only; `core/objc.lua` has **no** async support
* ✅ Result-table error contract (`{ok, code, message, details, tick}`) — `core/abi.lua:195-204`
* ✅ Three `__newindex` freeze guards — `init.lua:126`, `core/objc.lua:180`, `core/mailbox.lua:405`
* ✅ Bundle ABI shape validation at boot — `init.lua:57-63`
* ✅ Deterministic monotonic clock shared process-wide — `core/abi.lua:20-23`

---

## 🧨 Known to Break

These are **real, measured** gaps — not aspirations. Each has a reproducing test or a
`KNOWN:` marker at the site.

| Breakage | Status | Evidence |
| --- | --- | --- |
| Reserved event names not enforced (an event named `send` overwrites `send()`) | **REPRODUCED** | `core/abi.lua:137-168` vs dead `core/core.lua:179`; measured as `COLLISION_SEND_FAILED` by `breakage_suite/test_unregistered_event.lua` |
| No event / state name validation on any shipped path | **REPRODUCED** | `ABI.PATTERNS` (`core/abi.lua:116-125`) is read only by dead validators; `breakage_suite/test_invalid_fsm_schema.lua` fails 10 of 24 cases |
| Circular message loops / concurrent reentrancy | **UNTESTED** | no test; `breakage_suite/patterns/` and `test_concurrent_dispatch.lua` were removed as zero-byte placeholders |
| `fsm:can()` / `fsm:is()` returned `false` silently | **FIXED 2026-10-07** | declared dot-style, called colon-style everywhere; `core/objc.lua:144` now self-taking |
| Async resume matched by substring, so event `step` resumes an in-flight `step1_LEAVE_WAIT` | **KNOWN, not fixed** | `core/mailbox.lua:137` |
| Shrinking the mailbox silently destroys queued messages | **KNOWN, not fixed** | `core/ringbuffer.lua:214-232` |
| Message silently discarded after 3 failed retries | **KNOWN, not fixed** | `core/mailbox.lua:351-355` |
| `metric` effect type is unsatisfiable — `type` is both the effect discriminator and the metric kind | **KNOWN, not fixed** | `effect_contract.lua:65-87`; both mock generators always yield 0 metrics |
| `/stats` and `/debug` returned HTTP 500 on every request | **FIXED 2026-10-07** | both called `ngx.start_time()`, which does not exist in ngx_lua |
| `email` effect validation rejected **100%** of addresses | **FIXED 2026-10-07** | pattern used `{2,}`, a quantifier Lua patterns do not have |
| `/fsm/` served from a stale installed copy of the repo | **FIXED 2026-10-07** | `content_by_lua_file` pointed at `/usr/local/openresty/site/lualib`, not the repo |
| Strict mode blocks *creating* globals but permits *overwriting* existing ones | **KNOWN, not fixed** | `hardened.lua` — `_G.print = x` succeeds |
| No real authentication in any host | **KNOWN, not fixed** | `sqlite_host.lua:19` (`user_id ~= 999`), `nginx_host.lua:240` (`id == 123 or 456`) |

---

## 📁 Repository Structure

What is actually on disk, as of 2026-10-07.

```
lua-fsm-objC/
│
├── init.lua               # Bootstrap: strict mode -> load bundle -> ABI check -> frozen API
├── calyx_bundle.lua       # GENERATED. core/*.lua embedded verbatim, byte-for-byte
├── bundler.lua            # Regenerates calyx_bundle.lua. Scans core/ only
├── hardened.lua           # Global-variable firewall, safe helpers, shape validation
├── effect_contract.lua    # Effect algebra: 14 effect schemas + 4 agent capability sets
├── validate.lua           # Schema validation. HAS NO CALLERS (see header note)
├── session_fsm.lua        # Factory for the logged_out -> authenticating -> authenticated FSM
│
├── core/                  # The FSM engine -- the only tree that ships inside the bundle
│   ├── abi.lua            #   Constants, Result format, deterministic clock
│   ├── core.lua           #   Shared helpers. MOSTLY DEAD -- read the banner first
│   ├── objc.lua           #   Synchronous FSM (closure state + frozen proxy)
│   ├── mailbox.lua        #   Actor FSM (closure state + ring buffer + async resume)
│   ├── ringbuffer.lua     #   Bounded O(1) queue, 3 overflow policies
│   ├── stringbuffer.lua   #   Capacity-bounded string buffer. NO CALLERS
│   └── utils.lua          #   Formatters, serializer, table helpers
│
├── sqlite_host.lua        # SQLite host adapter (needs lsqlite3, cjson)
├── redis_host.lua         # Redis host adapter (needs redis, cjson). FLUSHALLs Redis
├── openresty/             # OpenResty HTTP host -- see nginx.conf KNOWN note
│   ├── nginx.conf         #   14 location blocks; lua_package_path problem documented inline
│   └── lualib/
│       ├── nginx_host.lua #     /fsm/ endpoint, effect handlers, capability scoping
│       ├── mock_data.lua  #     Synthetic data generators
│       ├── stream_mock.lua #    NDJSON streaming endpoint (unbounded duration)
│       ├── test_host.lua  #     Orphaned; parses now but no location loads it
│       └── calyx/session_fsm.lua  # Near-duplicate of ../session_fsm.lua (differs at line 31)
│
├── LLM-OS/                # Optional natural-language front end
│   ├── llm.lua            #   Introspects an FSM into LLM context
│   ├── ollama.lua         #   Classifies free text to one of 4 commands via curl
│   └── chat.lua           #   Interactive REPL. Contains a KNOWN vim.inspect bug
│
├── breakage_suite/       # 7 executable tests. No aggregate runner -- run them individually
│   ├── test_context_loss.lua
│   ├── test_example_professional.lua
│   ├── test_invalid_fsm_schema.lua
│   ├── test_mailbox_debug.lua
│   ├── test_mailbox_overflow.lua
│   ├── test_reporting_demo.lua
│   └── test_unregistered_event.lua
│
├── tools/
│   ├── reportgen.lua      #   Writes survival_reports/*.json (overwrites, "w" mode)
│   ├── test_runner.lua    #   Lua 5.1-only harness (uses setfenv); injects fail/warn/metric
│   ├── summarize_reports.lua  # UNREFERENCED, writes nothing
│   ├── semantic_monitor.lua   # UNREFERENCED and stale (reads a nonexistent fsm.mailbox)
│   ├── trace_transition.lua   # CANNOT LOAD (requires a deleted module)
│   └── prompts/           # LLM chat prompts. Read by no code
│
├── failure_modes/
│   └── workarounds/       # Both unreferenced; both KNOWN-marked as uncallable
│       ├── calyx_sil.lua
│       └── fix_invalid_stage.lua
│
└── survival_reports/      # GENERATED by tools/reportgen.lua. Overwritten each run
```

---

## 🔬 Safety Claims vs Ground Truth

| Claim | Status | Evidence |
| --- | --- | --- |
| Public API rejects new fields | **ENFORCED** | `init.lua:126-128` |
| FSM instance rejects new fields | **ENFORCED** | `core/objc.lua:197-204`, `core/mailbox.lua:427-433` |
| FSM metatable not introspectable | **ENFORCED** | `core/objc.lua:205-209`, `core/mailbox.lua:434-438` |
| Bundle ABI validated at boot | **ENFORCED** | `init.lua:57-63` |
| Effect capability scoping by agent role | **ENFORCED in 3 of 4 hosts** | `effect_contract.lua:500-533`; `sqlite_host.lua`, `redis_host.lua`, `nginx_host.lua`. **Not** in `mock_data.lua`, **not** in `run_demo.lua` Phase 2 |
| `NO MORE LIES` — context enforcement | **PARTIAL** | error Results are returned, but async resume still matches by substring (`core/mailbox.lua:137`) |
| `GUARD` — frozen APIs | **PARTIALLY TRUE** | three `__newindex` guards exist, but `fsm:can()`/`fsm:is()` were silently broken until 2026-10-07, which shows how little the guards covered |
| Async transitions are safe | **MOSTLY** | self-contained in `core/mailbox.lua:71-118`; the old "semantic bridge" is a deleted mechanism, not a requirement |
| Email address validation | **ENFORCED (was silently broken)** | `effect_contract.lua:292`; the `{2,}` quantifier does not exist in Lua patterns, so until 2026-10-07 it rejected every address |
| Effect execution is all-or-nothing | **FALSE** | validation is atomic; **execution is not**. `sqlite_host.lua:539-562`, `redis_host.lua:320-338`, `nginx_host.lua:304` |
| LLM-compatible structure | **UNVERIFIED** | `LLM-OS/` feeds FSM context to a model but nothing verifies comprehension |

---

## 🚧 Current Risks (Ranked by Likelihood)

1. ❗ Reserved event names silently clobber FSM methods
2. ❗ No input validation at FSM construction — malformed configs load and then misbehave
3. ❗ `can()`/`is()`-style silent-wrong-answer bugs (one found and fixed 2026-10-07; the class remains)
4. ❗ Strict mode gives a false sense of isolation — existing globals are still writable
5. ❓ Effect execution failures are logged and ignored, with no rollback
6. ❓ Mailbox shrink and retry-exhaustion destroy messages silently

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

## 🔍 Notes on the Reports

`survival_reports/` is regenerated by `tools/reportgen.lua`, which **overwrites** files in
`"w"` mode. Three caveats when reading them:

* `duration_sec` is hardcoded to `0` in every report (`tools/reportgen.lua`).
* `test_summary.json` summarises only the tests run **in that one process**, so it will not
  agree with the number of `*.report.json` files sitting next to it.
* `test_invalid_fsm_schema.json` and `test_mailbox_overflow.json` were hand-written, not
  emitted by `reportgen`, and their contents are stale — the schema one claims 24/24 passing
  when the suite currently fails 10 of 24.

The previous `survival_reports/md.md`, `static_failures.txt` and `runtime_failures.txt`
were removed: they were generated by no code in this repo, referenced deleted files, and
contradicted the metrics printed alongside them. `git log` preserves them.