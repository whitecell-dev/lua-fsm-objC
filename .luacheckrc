-- .luacheckrc
-- LuaCheck configuration for CALYX Survival Lab
--
-- Every entry here names the mechanism that justifies it. Rule (see
-- CONTRIBUTING.md): no unexplained suppressions. Warnings deliberately left
-- active (e.g. `vim` in LLM-OS/chat.lua, W542 empty branches, W211 in
-- validate.lua) are failure evidence -- see KNOWN_ISSUES.md and
-- BASELINE_LINT.md.

std = "lua51" -- Target Lua 5.1 (most compatible)
codes = true -- Show warning codes (W111, W542, ...) to aid triage

-- Allow these globals (from hardened.lua strict mode)
globals = {
	"CALYX", -- Bundle API
	"_G", -- Explicit global access
}

-- Read-only globals (stdlib)
read_globals = {
	"require",
	"package",
	"table",
	"string",
	"math",
	"os",
	"io",
	"debug",
}

-- Ignore specific warnings.
-- 212 (unused argument) / 213 (unused loop variable): kept GLOBAL for now
-- because callback arity drifted repo-wide -- dispatchers pass (fsm, ctx)
-- while 15 test callbacks declare function(ctx) (KNOWN_ISSUES.md, 2026-10-07
-- session). GRADUATION PLAN: once the callback-arity regression test lands
-- (CONTRIBUTING.md), scope these to breakage_suite/ + hosts/ only and let
-- core/ warn.
ignore = {
	"212", -- Unused argument (common in callbacks)
	"213", -- Unused loop variable
}

-- Exclude generated code.
-- calyx_bundle.lua is EMBEDDED VERBATIM output of `lua bundler.lua`, not a
-- source file -- and its CALYX_METADATA header is not even valid Lua:
-- StyLua 2.6.0 fails to parse it (see BASELINE_LINT.md). Never lint or
-- format it; lint core/ instead and regenerate.
exclude_files = {
	"calyx_bundle.lua",
}

-- Max line length (matches stylua.toml column_width = 120)
max_line_length = 120

-- Per-file overrides. Each names its justifying mechanism -- no blanket
-- suppressions.

-- OpenResty runtime: `ngx` exists only inside nginx workers, and writing its
-- fields (ngx.status, ngx.header, ngx.shared, ...) is the normal response
-- API -- not a leak. Declared WRITABLE (not read-only) for exactly that
-- reason; bare `ngx = ...` reassignment would still be a bug, but no such
-- line exists (verified 2026-10-12: remaining hits were all field writes).
files["openresty/lualib/*.lua"] = {
	globals = { "ngx" },
}

-- Test-harness injection: tools/test_runner.lua:37-60 installs
-- fail/warn/metric/log/trace into the test env via setfenv (Lua 5.1-only
-- harness). breakage_suite/*.lua are written against that injected API, so
-- "accessing undefined variable fail/metric/..." is the harness contract,
-- not a leak. Do NOT extend this list without the same mechanism.
files["breakage_suite/*.lua"] = {
	read_globals = { "fail", "warn", "metric", "log", "trace" },
}

-- bundler.lua legitimately populates package.preload (that IS its job:
-- install the preload aliases init.lua depends on). W122 only, nothing else.
files["bundler.lua"] = {
	ignore = { "122" },
}

files["hardened.lua"] = {
	globals = { "M" }, -- Module table
}

-- DELIBERATELY NOT SUPPRESSED (failure evidence, see KNOWN_ISSUES.md):
-- * LLM-OS/chat.lua `vim` (undefined global): no Vim shim exists in the
--   repo; the warning documents a real crash (recon 7/B20). Whitelisting it
--   would hide the bug.
-- * W542 empty branches (core/mailbox.lua:351 silent discard after 3
--   retries; hardened.lua:599): the emptiness IS the finding.
-- * W211 validate.lua:19 (unused `hardened`): validate.lua has no callers;
--   the warning marks dead code as dead.
-- * Unused/overwritten `err` in run_demo.lua, mock_data.lua: these mark the
--   "execution is not atomic / reports ok=true on failure" contract gap.
--   Fix the code, not the lint.
