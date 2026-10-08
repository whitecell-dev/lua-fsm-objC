# KNOWN_ISSUES

Index of confirmed gaps that are **documented but not fixed**, plus the findings that had
no good inline site. Most gaps are marked with a `-- KNOWN:` comment at the exact source
line — this file is the index, not the detail.

Last reviewed: 2026-10-07, against commit `7d89a4b` plus the fixes in this session.

---

## Fixed in the 2026-10-07 session

Recorded so nobody "fixes" them again or assumes they were always right.

| Gap | Was | Now |
| --- | --- | --- |
| `fsm:can()` / `fsm:is()` silently returned `false` | declared dot-style, called colon-style repo-wide; the FSM was passed as the argument | self-taking declarations, `core/objc.lua:144,148` and `core/mailbox.lua:234,238` |
| `db_query` guard inverted vs. its own message | blocked writes when `read_only` was absent **or** `false`; only `true` allowed them | default blocks, `read_only = false` is the documented override, `effect_contract.lua:194-215` |
| `hardened.M.timed` crashed on Lua 5.1 / LuaJIT | used `table.unpack`, which is 5.2+ | `table.unpack or unpack`, `hardened.lua:642` |
| 3 tests could not run at all | `test_mailbox_debug.lua` was a syntax error; `test_context_loss.lua` and `test_mailbox_overflow.lua` crashed | see each test's inline `FIX:` note |
| Callback arity drift in tests | 15 callbacks declared `function(ctx)` while dispatchers pass `(fsm, ctx)` | corrected in all 4 affected tests |
| `test_hardened.lua` memory assertion | measured uncollected garbage; read 444 KB on a clean checkout against a 500 KB limit | `collectgarbage("collect")` before both readings; real value is 24.82 KB, `test_hardened.lua:382-396` |
| `email` effect validation rejected every address | pattern used `{2,}`, which Lua patterns do not support (`* + - ?` only), so `{2,}` matched literally and 100% of addresses failed — `/mock/emails` always generated 0 | `[a-zA-Z]+`, `effect_contract.lua:292` |
| `/stats` and `/debug` returned HTTP 500 | both called `ngx.start_time()`, which does not exist in ngx_lua | per-worker `worker_start_time`, `openresty/nginx.conf` |
| `/fsm/` was served from a stale installed copy | `content_by_lua_file` pointed at `/usr/local/openresty/site/lualib`, not the repo | points into the read-only `/app` mount |
| Container could not resolve its own `resty.core` | replacing the image's `nginx.conf` dropped the `lua_package_path` the OpenResty image would otherwise set | `/usr/local/openresty/lualib/?.lua` added explicitly |
| `os.getenv` was never called anywhere in the repo | the container's `CALYX_*` variables would have been inert | opt-in env plumbing added; defaults unchanged |

---

## Not fixed — inline `KNOWN:` markers

### Dead code that reads as live
* `core/core.lua` — `lock_metatable`, `check_event_collision`, `validate_event_name`,
  `validate_state_name`, `_dispatch_callback`, `create_base_fsm`, `:_transition`,
  `:_complete_transition`, `:can`, `:is` are never called. Banner at the top of the file.
* `core/stringbuffer.lua` — 294 lines, no callers anywhere.
* `validate.lua` — no callers, and does not catch the gaps the test suite fails on.
* `tools/semantic_monitor.lua`, `tools/summarize_reports.lua` — unreferenced.
* `tools/trace_transition.lua`, `failure_modes/workarounds/fix_invalid_stage.lua` — cannot
  load; both require `calyx_fsm_mailbox`, deleted in `9470a9c`.
* `failure_modes/workarounds/calyx_sil.lua` — calls `fsm:semantic_state()`, which does not exist.
* `effect_contract.lua` — `EffectContract.execute` is a stub that always errors and is never
  called; each host defines a private `execute_effect` instead.
* `core/abi.lua` — 7 of 17 `ERRORS` codes are never produced by any code path.

### Guards that cannot be reasoned about correctly
* `nginx_host.lua:240` — the `user_id == 123 or 456` stub auth also means the smoke test
  must use a *different* user for each /fsm/ check; re-using one makes the test
  order-dependent and it fails for the wrong reason (it did, once).
* `effect_contract.lua` — `db_query` keyword check is a substring match, so a benign
  `SELECT ... updated_at ...` trips `UPDATE`; `ATTACH` / `PRAGMA` / `VACUUM` / `REINDEX`
  are not covered at all.
* `hardened.lua` — strict mode blocks *creating* globals and *reading* undefined ones, but
  assigning to an existing global succeeds silently (`__newindex` only fires for absent keys).

### Silent data loss
* `core/ringbuffer.lua:214-232` — `set_mailbox_size` to a smaller value destroys queued
  messages with no result, error, or log.
* `core/mailbox.lua:351-355` — a message that fails 3 times is silently discarded.
* `core/mailbox.lua:137` — async resume matches by substring, so event `step` resumes an
  in-flight `step1_LEAVE_WAIT`.

### Contract problems
* `effect_contract.lua:65-87` — the `metric` effect type is unsatisfiable: `effect.type` is
  both the effect discriminator and the metric kind, so the schema can never be satisfied.
  Consequence: `run_demo.lua` and `mock_data.lua` always generate 0 metrics.
* Effect *validation* is all-or-nothing; effect *execution* is not, in all three hosts.
* `mock_data.lua` — unrecognized effect types are reported as successfully executed.
* `sqlite_host.lua` — `db_query` never checks `db:exec`'s error return, so a failed
  statement still reports `{ ok = true }`.
* `redis_host.lua` — `successful_auth` / `failed_auth` / `logouts` are declared and never
  incremented (`sqlite_host.lua` does increment them, so this is an omission).

### No real authentication
* `sqlite_host.lua:19` — any `user_id ~= 999` authenticates.
* `openresty/lualib/nginx_host.lua:240` — `user_id == 123 or 456`.
* `run_demo.lua:23-25` — `user_id >= 100 and user_id <= 199`.

### LLM-OS
* `LLM-OS/ollama.lua` — the model's classification is dispatched unconditionally: no
  `fsm:can()` check, no contract validation, unanchored substring matching.
* `LLM-OS/ollama.lua` — `fallback_models` is never read; no curl timeout; `Ollama.test()`
  always reports reachable.
* `LLM-OS/chat.lua:34` — calls `vim.inspect`, which does not exist in this repo.
* `LLM-OS/chat.lua` — EOF on `io.read()` loops forever.

### OpenResty
* ~~`openresty/nginx.conf:8` — `lua_package_path` excludes the repo root~~ **FIXED 2026-10-07.**
  It now points into the read-only `/app` mount; see the Fixed table above. What remains
  is that the paths are literal: nginx cannot substitute env vars into `lua_package_path`,
  so a bare-metal install must edit them or run `tools/sync_lualib.sh`.
* `openresty/lualib/nginx_host.lua` — calls `lpush`/`ltrim` on an `ngx.shared.DICT`, which
  has neither.
* `openresty/lualib/stream_mock.lua` — `duration` / `interval` are unbounded query params
  holding an nginx worker.

### Persistence / determinism
* `core/abi.lua:20-23` — the clock is one global counter shared by all FSM instances;
  `reset` has no callers.
* `core/mailbox.lua:24-27`, `core/utils.lua` — `math.randomseed(os.time())` reseeds the
  global PRNG on every FSM construction.
* objc and mailbox FSMs are in-memory only; only the three hosts persist.

---

## Not fixed — no good inline site

### The generated reports are stale and partly false
`survival_reports/` is overwritten wholesale by `tools/reportgen.lua` each run (mode `"w"`).
Two of the six files are hand-written rather than generated, and their contents no longer
match reality:

* `test_invalid_fsm_schema.json` claims `tests_executed: 24, tests_passed: 24,
  tests_failed: 0`. The suite currently **fails 10 of 24**.
* `test_mailbox_overflow.json` claims `status: RESOLVED`, `max_queue_size: 1000` and
  "9000 messages dropped"; the live test enqueues 10,000 against a 1000 cap.
* `test_summary.json` summarises one process run and so will not agree with the number of
  `*.report.json` files beside it.
* `duration_sec` is hardcoded to `0` in every report (`tools/reportgen.lua:195`).
* `pass` ignores `status`, so a `SKIPPED` test would be written as `pass = true`
  (`tools/reportgen.lua:191`).

Not mutated here: these are the repo's failure evidence, and rewriting them by hand would
be a worse lie than a stale one. Re-run the tests to regenerate.

### `luacheck` has no gate and currently reports 271 warnings
`.luacheckrc` is valid (0 errors, 48 files checked, `calyx_bundle.lua` now correctly
excluded — it previously excluded a filename that did not exist). There is no CI, no
Makefile, and no wrapper script, so nothing enforces it. Most of the 271 warnings are
pre-existing whitespace/unused-variable noise.

### Deleted, because they were provably false and generated by nothing in the repo
* `runtime_failures.txt` — 44 MB of captured stdout. Zero error or exception records; its
  own metrics contradict its conclusion (`-45090.87 KB` delta, final count 0, yet it reports
  "Significant memory increase suggests a leak").
* `static_failures.txt` — reported a lint warning in `core/calyx_fsm_mailbox.lua:406`, a
  file deleted 15 hours after that report was written.
* `survival_reports/md.md` — a `.md` file containing raw concatenated JSON, with no
  generator, whose contents assert `pass: true` for a test that now crashes.
* 6 zero-byte `breakage_suite/test_*.lua` placeholders — a claim of coverage with nothing
  behind it. Two of them (`test_concurrent_dispatch`, `test_strict_violation`) corresponded
  to real open gaps; those gaps remain open.
* 4 empty directories: `breakage_suite/patterns/`, `research_questions/`,
  `failure_modes/catalog/`, `failure_modes/root_cause_analysis/`.

All recoverable from `git log`.

---

## Open gaps with no test at all
* Concurrent dispatch / reentrancy (the removed `test_concurrent_dispatch.lua`).
* Circular message loops.
* Strict-mode behaviour (the removed `test_strict_violation.lua`).
* Bundle corruption, boot time, partial init (the other removed placeholders).
* Trace persistence.