# Baseline Lint Report

Captured 2026-10-12. Behavior unchanged -- this phase touched only docs and
lint/format config (`CONTRIBUTING.md`, `.luacheckrc`, `stylua.toml`,
`.styluaignore`, this file). No `.lua` source was modified.

Tool versions: luacheck 1.2.0 (std lua51), StyLua 2.6.0 via
`johnnymorganz/stylua:2.6.0` Docker image (entrypoint `/stylua`).

## 1. luacheck: 271 warnings (old config) -> 74 warnings (tightened), 0 errors

Raw log of the 271 (pre-tightening config) is preserved at
`tools/luacheck_baseline.txt`. Regenerate the current count with `luacheck .`
from the repo root.

### What the tightening removed (197 warnings, all documented in `.luacheckrc`)

| Warnings | Mechanism | Exception |
|---|---|---|
| ~185 `accessing undefined variable fail/warn/metric/log` in `breakage_suite/*` | `tools/test_runner.lua:37-60` injects these via `setfenv` (Lua 5.1-only harness) -- the harness contract, not a leak | `files["breakage_suite/*.lua"]` read-only |
| ~70 `accessing undefined variable ngx` + `mutating non-standard global ngx` in `openresty/lualib/*` | `ngx` exists only inside nginx workers | `files["openresty/lualib/*.lua"]` writable (`ngx.status`/`ngx.header` writes are the response API) |
| 4 W122 `package.preload` writes in `bundler.lua` | Populating `package.preload` IS the bundler's job | `files["bundler.lua"]` ignore `122` only |

### Residual 74, by class (code in parentheses)

- Whitespace / format (41): W611 line-only-whitespace (27, mostly
  `breakage_suite/test_mailbox_debug.lua` + `sqlite_host.lua`), W612 trailing
  whitespace (11), W613 trailing whitespace in a string (3). **StyLua's job.**
- Unused / overwritten values (17): W211 unused `err` (9, `run_demo.lua` +
  `mock_data.lua`), W211 `test_report`/`CALYX`/`ABI`/`response`/`mock_users`/
  `hardened`, W311 unused `status`/`summary`/`status_icon`/`opts`/`result`,
  W314 overwritten `type` field (2), W241 `big_table` mutated-never-read.
  **Left warning: the ignored-`err` ones mark the "execution reports ok=true
  on failure" contract gap (KNOWN_ISSUES.md).**
- Deliberate failure evidence (4, never suppress): W113 `vim` in
  `LLM-OS/chat.lua:39` (no Vim shim exists -- real crash, recon 7/B20); W542
  empty branches in `core/mailbox.lua:351` (silent discard after 3 retries)
  and `hardened.lua:599`; W211 `validate.lua:19` (file has no callers).
- Shadowing / redefinition in demos (5, `demo.lua`): W421/W411 `result`/`fsm`.
  Review in the lint-cleanup pass, not the behavioral one.

### Per-file residual (top)

27 `test_mailbox_debug.lua` (whitespace) / 10 `run_demo.lua` / 9 `sqlite_host.lua`
(whitespace) / 6 `nginx_host.lua` / 5 `demo.lua` / 4 `fix_invalid_stage.lua` /
4 `mock_data.lua` / rest <= 3. `core/` contributes exactly 1 (W542, evidence).

## 2. StyLua `--check` (with `stylua.toml` + `.styluaignore`): 10 files

`LLM-OS/chat.lua`, `sqlite_host.lua`, `failure_modes/workarounds/fix_invalid_stage.lua`,
`openresty/lualib/stream_mock.lua`, `openresty/lualib/test_host.lua`,
`breakage_suite/test_mailbox_debug.lua`, `breakage_suite/test_mailbox_overflow.lua`,
`breakage_suite/test_invalid_fsm_schema.lua`, `breakage_suite/test_context_loss.lua`,
`breakage_suite/test_unregistered_event.lua`.

Sampled diff (`chat.lua`) is mechanical (call-arg reflow around comments) --
safe to apply in the big-bang reformat pass. `calyx_bundle.lua` is excluded
because it is a build artifact: format `core/`, run `lua bundler.lua`.
(No `CALYX_METADATA` header exists in the generated file; the header is a
plain-comment generation timestamp.)

## 3. Prioritized list (next passes, in order -- lint and behavior stay separate)

P0 (behavioral, each with fail-before/pass-after regression test):
1-3. Colon/dot convention, false-success effects, event-name collisions
(see CONTRIBUTING.md section 3).

P1 (lint cleanup, no behavior change): StyLua big-bang (`stylua .` on sources,
regenerate bundle, re-run 8 tests + container smoke); clear the 41 whitespace
warnings; scope `212`/`213` off global once callback arities are pinned.

P2 (review, may-be-dead): `validate.lua`, `stringbuffer.lua`, `test_host.lua`,
`semantic_monitor.lua`, `summarize_reports.lua` -- warnings confirm what
KNOWN_ISSUES.md already says. Delete or wire up; do not "fix" warnings on code
with no callers.
