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

-- Exclude files
exclude_files = {
	"bundle.lua", -- Generated code, don't check
	"*.bundle.lua",
}

-- Max line length
max_line_length = 120

-- Per-file overrides
files["core/calyx_fsm_mailbox.lua"] = {
	globals = { "machine", "STATES", "Mailbox" },
}

files["hardened.lua"] = {
	globals = { "M" }, -- Module table
}
