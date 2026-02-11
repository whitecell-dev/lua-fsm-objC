#!/usr/bin/env lua
local lfs = require("lfs")
local hardened = require("hardened")

local SimpleBundler = {}
SimpleBundler.__index = SimpleBundler

function SimpleBundler.new(root, verbose)
	return setmetatable({
		root = root:gsub("/$", ""),
		verbose = verbose or false,
		modules = {},
		order = {},
	}, SimpleBundler)
end

function SimpleBundler:log(msg)
	if self.verbose then
		print("[LAB-BUNDLER] " .. msg)
	end
end

-- PRE-FLIGHT VALIDATION (Lua 5.1 Compatible)
function SimpleBundler:validate_source(path, content)
	-- 5.1 uses loadstring
	local fn, err = loadstring(content, path)
	if not fn then
		return false, "Syntax Error: " .. tostring(err)
	end

	-- STUB REQUIRE: Prevent crashes on internal dependencies during dry-run
	local old_require = _G.require
	_G.require = function(modname)
		-- Try real require, if it fails, return a dummy table
		local status, result = pcall(old_require, modname)
		if status then
			return result
		end

		self:log("  (Mocking dependency: " .. modname .. ")")
		return setmetatable({}, {
			__index = function()
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

function SimpleBundler:find_modules(dir)
	dir = dir or self.root
	for file in lfs.dir(dir) do
		if file ~= "." and file ~= ".." then
			local path = dir .. "/" .. file
			local attr = lfs.attributes(path)

			if attr.mode == "directory" and not file:match("^%.") then
				self:find_modules(path)
			elseif attr.mode == "file" and file:match("%.lua$") then
				if not file:match("bundler%.lua") and not file:match("init%.lua") then
					local rel_path = path:sub(#self.root + 2)
					local module_name = rel_path:gsub("%.lua$", ""):gsub("/", ".")

					local f = io.open(path, "r")
					if f then
						local content = f:read("*all")
						f:close()

						local ok, err = self:validate_source(path, content)
						if not ok then
							error(string.format("\n[FATAL] Validation failed for %s\n%s", path, err))
						end

						self.modules[module_name] = { content = content }
						table.insert(self.order, module_name)
						self:log("Validated & Captured: " .. module_name)
					end
				end
			end
		end
	end
end

function SimpleBundler:generate_bundle(output_path)
	local lines = {
		"-- CALYX BUNDLE GENERATED: " .. os.date(),
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

	-- Add all discovered modules
	for _, name in ipairs(self.order) do
		local escaped = string.format("%q", self.modules[name].content)
		table.insert(lines, "bundle.modules['" .. name .. "'] = " .. escaped)
	end

	table.insert(lines, "\n-- Survival Lab Registration")
	for _, name in ipairs(self.order) do
		table.insert(lines, "package.preload['" .. name .. "'] = function() return load_module('" .. name .. "') end")
		if name:match("%.") then
			local short = name:gsub("^.*%.", "")
			table.insert(lines, "package.preload['" .. short .. "'] = package.preload['" .. name .. "']")
		end
	end

	table.insert(lines, "\n-- ===== ABI ASSEMBLY =====")

	-- Dynamically find the main FSM module (looking for modules containing "fsm")
	local main_fsm_module = nil
	for _, name in ipairs(self.order) do
		if name:match("fsm") and not name:match("objc") then
			main_fsm_module = name
			break
		end
	end

	-- If no specific fsm found, use the first module
	if not main_fsm_module and #self.order > 0 then
		main_fsm_module = self.order[1]
	end

	if main_fsm_module then
		table.insert(lines, "local machine = load_module('" .. main_fsm_module .. "')")

		-- Create a states table from the machine's constants
		table.insert(lines, "local STATES = {")
		table.insert(lines, "    NONE = machine.NONE or 'none',")
		table.insert(lines, "    ASYNC = machine.ASYNC or 'async',")
		table.insert(lines, "}")

		table.insert(lines, "")
		table.insert(lines, "return {")
		table.insert(lines, "    create = machine.create,")
		table.insert(lines, "    NONE = STATES.NONE,")
		table.insert(lines, "    ASYNC = STATES.ASYNC,")
		table.insert(lines, "}")
	else
		-- Fallback if no modules found
		table.insert(lines, "return {")
		table.insert(lines, "    create = function() error('No FSM modules found') end,")
		table.insert(lines, "    NONE = 'none',")
		table.insert(lines, "    ASYNC = 'async',")
		table.insert(lines, "}")
	end

	local f = io.open(output_path, "w")
	f:write(table.concat(lines, "\n"))
	f:close()
	print("[SUCCESS] Hardened 5.1 bundle generated: " .. output_path)
end

-- Main execution
local root_dir = "core"
local bundler = SimpleBundler.new(root_dir, true)
print("Scanning directory: " .. root_dir)
bundler:find_modules()
print("Found " .. #bundler.order .. " modules")
bundler:generate_bundle("calyx_bundle.lua")
