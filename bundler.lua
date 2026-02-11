#!/usr/bin/env lua
-- ============================================================================
-- bundler.lua
-- CALYX Production Bundler
-- Topological dependency ordering + validation
-- Lua 5.1.5 Compatible
-- ============================================================================

local lfs = require("lfs")
local hardened = require("hardened")

local Bundler = {}
Bundler.__index = Bundler

-- ============================================================================
-- CONSTRUCTOR
-- ============================================================================

function Bundler.new(root, verbose)
	return setmetatable({
		root = root:gsub("/$", ""),
		verbose = verbose or false,
		modules = {},
		order = {},
		dep_graph = {},
		abi_loaded = false,
	}, Bundler)
end

function Bundler:log(msg)
	if self.verbose then
		print("[BUNDLER] " .. msg)
	end
end

-- ============================================================================
-- DEPENDENCY EXTRACTION
-- ============================================================================

function Bundler:extract_dependencies(path, content)
	local deps = {}

	-- Match require("...") and require('...')
	for dep in string.gmatch(content, "require%s*%(?%s*[\"']([^\"']+)[\"']%s*%)") do
		table.insert(deps, dep)
	end

	-- Check for __deps declaration (preferred)
	local deps_decl = string.match(content, "__deps%s*=%s*{([^}]+)}")
	if deps_decl then
		for dep in string.gmatch(deps_decl, "[\"']([^\"']+)[\"']") do
			table.insert(deps, dep)
		end
	end

	return deps
end

-- ============================================================================
-- TOPOLOGICAL SORT (Kahn's Algorithm)
-- ============================================================================

function Bundler:topological_sort()
	-- Build in-degree map
	local in_degree = {}
	local adj_list = {}

	for name, _ in pairs(self.modules) do
		in_degree[name] = 0
		adj_list[name] = {}
	end

	-- Build adjacency list and in-degrees
	for name, module in pairs(self.modules) do
		for _, dep in ipairs(module.deps) do
			-- Resolve dependency name
			local dep_full = "lua-fsm-objC." .. dep

			if self.modules[dep_full] then
				table.insert(adj_list[dep_full], name)
				in_degree[name] = in_degree[name] + 1
			elseif self.modules[dep] then
				table.insert(adj_list[dep], name)
				in_degree[name] = in_degree[name] + 1
			end
		end
	end

	-- Find all nodes with in-degree 0
	local queue = {}
	for name, degree in pairs(in_degree) do
		if degree == 0 then
			table.insert(queue, name)
		end
	end

	-- Kahn's algorithm
	local sorted = {}
	while #queue > 0 do
		local node = table.remove(queue, 1)
		table.insert(sorted, node)

		for _, neighbor in ipairs(adj_list[node]) do
			in_degree[neighbor] = in_degree[neighbor] - 1
			if in_degree[neighbor] == 0 then
				table.insert(queue, neighbor)
			end
		end
	end

	-- Detect cycles
	if #sorted ~= #self.order then
		local missing = {}
		for _, name in ipairs(self.order) do
			local found = false
			for _, sorted_name in ipairs(sorted) do
				if name == sorted_name then
					found = true
					break
				end
			end
			if not found then
				table.insert(missing, name)
			end
		end
		error(string.format("[FATAL] Dependency cycle detected. Modules not sorted: %s", table.concat(missing, ", ")))
	end

	return sorted
end

-- ============================================================================
-- PRE-FLIGHT VALIDATION (Lua 5.1 Compatible)
-- ============================================================================

function Bundler:validate_source(path, content, module_name)
	-- Check for Lua 5.2+ features
	if string.match(content, "goto%s+") then
		return false, "Lua 5.2+ feature detected: goto statement"
	end

	if string.match(content, "::") then
		return false, "Lua 5.2+ feature detected: label"
	end

	if string.match(content, "table%.pack") or string.match(content, "table%.unpack") then
		return false, "Lua 5.2+ feature detected: table.pack/unpack"
	end

	-- 5.1 uses loadstring
	local fn, err = loadstring(content, path)
	if not fn then
		return false, "Syntax Error: " .. tostring(err)
	end

	-- STUB REQUIRE: Prevent crashes on internal dependencies during dry-run
	local old_require = _G.require

	_G.require = function(modname)
		-- 1️⃣ Try real require first
		local status, result = pcall(old_require, modname)
		if status then
			return result
		end

		-- 2️⃣ Try package.preload (ABI might be primed here)
		local preload = package.preload[modname]
		if preload then
			return preload()
		end

		-- 3️⃣ If ABI not yet loaded and requested → hard fail
		if modname == "abi" or modname:match("%.abi$") or modname:match("^lua%-fsm%-objC%.abi$") then
			error("[VALIDATION] Critical ABI module missing: " .. modname .. " (required by " .. path .. ")")
		end

		-- 4️⃣ Fallback mock (safe for non-critical deps)
		self:log("  (Mocking dependency: " .. modname .. " for " .. path .. ")")
		return setmetatable({}, {
			__index = function()
				return function() end
			end,
			__call = function()
				return function() end
			end,
		})
	end

	-- Dynamic Check
	hardened.enable_strict_mode()
	local ok, result = pcall(fn)
	hardened.disable_strict_mode()

	-- Restore require immediately
	_G.require = old_require

	if not ok then
		-- Catch the specific case of a missing module error
		if type(result) == "string" and result:match("module '.-' not found") then
			self:log("  (Deferring dependency check for: " .. path .. ")")
			return true
		end
		return false, "Runtime Leak/Error: " .. tostring(result)
	end

	return true
end

-- ============================================================================
-- MODULE DISCOVERY
-- ============================================================================

function Bundler:find_modules(dir)
	dir = dir or self.root

	-- FIRST PASS: Look for abi.lua and force-load it immediately
	local abi_path = dir .. "/abi.lua"
	local abi_attr = lfs.attributes(abi_path)
	if abi_attr and abi_attr.mode == "file" then
		self:log("🔍 Found ABI module, priming first...")
		self:process_file(abi_path, "abi.lua")
	end

	-- SECOND PASS: Process all other files
	for file in lfs.dir(dir) do
		if file ~= "." and file ~= ".." and file ~= "abi.lua" then
			local path = dir .. "/" .. file
			local attr = lfs.attributes(path)

			if attr.mode == "directory" and not file:match("^%.") then
				self:find_modules(path)
			elseif attr.mode == "file" and file:match("%.lua$") then
				-- Exclude bundler and init files from being captured as modules
				if not file:match("bundler%.lua") and not file:match("init%.lua") then
					self:process_file(path, file)
				end
			end
		end
	end
end

function Bundler:process_file(path, filename)
	local rel_path = path:sub(#self.root + 2)
	local module_name = rel_path:gsub("%.lua$", ""):gsub("/", ".")

	-- Map core.* to lua-fsm-objC.* structure
	module_name = "lua-fsm-objC." .. module_name

	local f = io.open(path, "r")
	if f then
		local content = f:read("*all")
		f:close()

		-- Extract dependencies
		local deps = self:extract_dependencies(path, content)

		local ok, err = self:validate_source(path, content, module_name)
		if not ok then
			error(string.format("\n[FATAL] Validation failed for %s\n%s", path, err))
		end

		self.modules[module_name] = {
			content = content,
			deps = deps,
		}
		table.insert(self.order, module_name)
		self:log("✅ Validated & Captured: " .. module_name .. " (deps: " .. #deps .. ")")

		-- 👇 If this is ABI, prime preload for later validation passes
		if module_name:match("%.abi$") then
			self:log("  ⚡ Priming ABI preload for validation")

			-- Create the ABI module function
			local abi_fn = loadstring(content, module_name)

			-- Prime all possible ABI module names
			package.preload["abi"] = function()
				return abi_fn()
			end

			package.preload["core.abi"] = package.preload["abi"]
			package.preload["lua-fsm-objC.abi"] = package.preload["abi"]
			package.preload[module_name] = package.preload["abi"]

			self.abi_loaded = true
			self:log("  ✅ ABI primed successfully")
		end
	end
end

-- ============================================================================
-- BUNDLE GENERATION
-- ============================================================================

function Bundler:generate_bundle(output_path)
	-- Topologically sort modules
	self:log("\n🔄 Performing topological sort...")
	local sorted_order = self:topological_sort()

	local lines = {
		"-- CALYX BUNDLE GENERATED: " .. os.date(),
		"-- PRODUCTION HARDENED: Deterministic ordering + frozen API",
		"local bundle = { modules = {}, loaded = {} }",
		"",
	}

	-- Survival Loader (5.1 compatible)
	table.insert(lines, "local function load_module(name)")
	table.insert(lines, "    if bundle.loaded[name] then return bundle.loaded[name] end")
	table.insert(lines, "    local module = bundle.modules[name]")
	table.insert(lines, "    if not module then error('MODULE_MISSING: ' .. name) end")
	table.insert(lines, "    local fn, err = loadstring(module, name)")
	table.insert(lines, "    if not fn then error('LOAD_FAILURE ['..name..']: ' .. err) end")
	table.insert(lines, "    bundle.loaded[name] = fn()")
	table.insert(lines, "    return bundle.loaded[name]")
	table.insert(lines, "end\n")

	-- Add all discovered modules in topological order
	for _, name in ipairs(sorted_order) do
		local escaped = string.format("%q", self.modules[name].content)
		table.insert(lines, "bundle.modules['" .. name .. "'] = " .. escaped)
	end

	table.insert(lines, "\n-- Survival Lab Registration (Topologically Sorted)")

	-- Register FSM modules in sorted order
	for _, name in ipairs(sorted_order) do
		table.insert(lines, "package.preload['" .. name .. "'] = function() return load_module('" .. name .. "') end")
		if name:match("%.([^%.]+)$") then
			local short = name:match("%.([^%.]+)$")
			table.insert(lines, "package.preload['" .. short .. "'] = package.preload['" .. name .. "']")
		end
	end

	-- Register short aliases for core modules
	table.insert(lines, "\n-- Short aliases for core modules")
	table.insert(lines, "package.preload['abi'] = package.preload['lua-fsm-objC.abi']")
	table.insert(lines, "package.preload['core'] = package.preload['lua-fsm-objC.core']")
	table.insert(lines, "package.preload['mailbox'] = package.preload['lua-fsm-objC.mailbox']")
	table.insert(lines, "package.preload['objc'] = package.preload['lua-fsm-objC.objc']")
	table.insert(lines, "package.preload['utils'] = package.preload['lua-fsm-objC.utils']")
	table.insert(lines, "package.preload['ringbuffer'] = package.preload['lua-fsm-objC.ringbuffer']")

	table.insert(lines, "\n-- ===== CALYX FSM UNIFIED API =====\n")

	-- Load all required modules - use consistent naming
	table.insert(lines, "local lua_fsm_abi = require('lua-fsm-objC.abi')")
	table.insert(lines, "local lua_fsm_core = require('lua-fsm-objC.core')")
	table.insert(lines, "local lua_fsm_mailbox = require('lua-fsm-objC.mailbox')")
	table.insert(lines, "local lua_fsm_objc = require('lua-fsm-objC.objc')")
	table.insert(lines, "local lua_fsm_utils = require('lua-fsm-objC.utils')\n")

	-- Build the unified API that matches init.lua's expected schema
	table.insert(lines, "return {")
	table.insert(lines, "    -- Creation APIs")
	table.insert(lines, "    create_object_fsm = lua_fsm_objc.create,")
	table.insert(lines, "    create_mailbox_fsm = lua_fsm_mailbox.create,")
	table.insert(lines, "")
	table.insert(lines, "    -- Shared constants")
	table.insert(lines, "    ASYNC = lua_fsm_abi.STATES.ASYNC,")
	table.insert(lines, "    NONE = lua_fsm_abi.STATES.NONE,")
	table.insert(lines, "    STATES = lua_fsm_abi.STATES,")
	table.insert(lines, "    ERRORS = lua_fsm_abi.ERRORS,")
	table.insert(lines, "")
	table.insert(lines, "    -- Version info")
	table.insert(lines, "    VERSION = lua_fsm_abi.VERSION,")
	table.insert(lines, "    NAME = lua_fsm_abi.NAME,")
	table.insert(lines, "    SPEC = lua_fsm_abi.SPEC,")
	table.insert(lines, "")
	table.insert(lines, "    -- Diagnostics (debug mode only)")
	table.insert(lines, "    diagnostics = {")
	table.insert(lines, "        format_objc_call = lua_fsm_utils.format_objc_call,")
	table.insert(lines, "        serialize = lua_fsm_utils.serialize_table,")
	table.insert(lines, "        clock = lua_fsm_abi.clock,")
	table.insert(lines, "    },")
	table.insert(lines, "}")

	local f = io.open(output_path, "w")
	f:write(table.concat(lines, "\n"))
	f:close()

	print("\n[SUCCESS] Hardened 5.1 bundle generated: " .. output_path)
	print("[SUCCESS] Bundle includes " .. #sorted_order .. " modules (topologically sorted)")
	print("[SUCCESS] Dependency ordering verified (no cycles)")
	if self.abi_loaded then
		print("[SUCCESS] ABI primed and validated")
	end
end

-- ============================================================================
-- MAIN EXECUTION
-- ============================================================================

local function bundle_calyx_fsm()
	local root_dir = "core"
	local bundler = Bundler.new(root_dir, true)

	print("\n=== CALYX FSM Bundle Generation ===")
	print("Scanning directory: " .. root_dir)

	-- Verify directory exists
	local attr = lfs.attributes(root_dir)
	if not attr or attr.mode ~= "directory" then
		error(string.format("[FATAL] Directory not found: %s", root_dir))
	end

	bundler:find_modules()
	print(string.format("\n📦 Found %d FSM modules", #bundler.order))

	-- Display found modules in dependency order
	print("\n📋 Module capture order (ABI first):")
	for i, name in ipairs(bundler.order) do
		local deps = bundler.modules[name].deps
		local marker = name:match("%.abi$") and "🔷 " or "  • "
		print(string.format("  %s %s (deps: %d)", marker, name, #deps))
	end

	bundler:generate_bundle("calyx_bundle.lua")

	print("\n✅ Bundle generation complete")
	print("   Next: Run 'lua init.lua' to verify bundle")
end

-- Run the bundler
bundle_calyx_fsm()
