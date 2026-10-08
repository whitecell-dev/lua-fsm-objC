-- .luacheckrc
-- LuaCheck configuration for CALYX Survival Lab

std = "lua51" -- Target Lua 5.1 (most compatible)

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

-- Ignore specific warnings
ignore = {
	"212", -- Unused argument (common in callbacks)
	"213", -- Unused loop variable
}

-- Exclude generated code.
-- FIX: this excluded "bundle.lua" / "*.bundle.lua", but the generated file is
-- actually named calyx_bundle.lua, so generated code was NOT being excluded.
-- (recon 7/B35)
exclude_files = {
	"calyx_bundle.lua",
}

-- Max line length
max_line_length = 120

-- Per-file overrides
-- FIX: the "core/calyx_fsm_mailbox.lua" override below referenced a file deleted
-- in commit 9470a9c, so it never applied. Removed. (recon 8.4)

files["hardened.lua"] = {
	globals = { "M" }, -- Module table
}
