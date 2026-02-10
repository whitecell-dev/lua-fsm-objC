#!/usr/bin/env lua
local lfs = require("lfs")

local SimpleBundler = {}
SimpleBundler.__index = SimpleBundler

function SimpleBundler.new(root, verbose)
	return setmetatable({
		root = root:gsub("/$", ""), -- Strip trailing slash
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

function SimpleBundler:find_modules(dir)
	dir = dir or self.root
	for file in lfs.dir(dir) do
		if file ~= "." and file ~= ".." then
			local path = dir .. "/" .. file
			local attr = lfs.attributes(path)

			if attr.mode == "directory" and not file:match("^%.") then
				self:find_modules(path)
			elseif attr.mode == "file" and file:match("%.lua$") then
				-- CRITICAL: Prevent the bundler or tests from bundling themselves
				if not file:match("bundler%.lua") and not file:match("init%.lua") then
					-- Extract module name relative to the ROOT (e.g., core/fsm.lua -> fsm)
					local rel_path = path:sub(#self.root + 2)
					local module_name = rel_path:gsub("%.lua$", ""):gsub("/", ".")

					local f = io.open(path, "r")
					if f then
						local content = f:read("*all")
						f:close()
						self.modules[module_name] = { content = content }
						table.insert(self.order, module_name)
						self:log("Captured: " .. module_name)
					end
				end
			end
		end
	end
end

function SimpleBundler:generate_bundle(output_path)
	local lines = { "local bundle = { modules = {}, loaded = {} }", "" }

	-- Optimized Loader for Survival (handles 5.1 and 5.2+)
	table.insert(lines, "local function load_module(name)")
	table.insert(lines, "    if bundle.loaded[name] then return bundle.loaded[name] end")
	table.insert(lines, "    local module = bundle.modules[name]")
	table.insert(lines, "    if not module then error('MODULE_MISSING: ' .. name) end")
	table.insert(lines, "    local loader = _G.loadstring or _G.load")
	table.insert(lines, "    local fn, err = loader(module, name)")
	table.insert(lines, "    if not fn then error('LOAD_FAILURE ['..name..']: ' .. err) end")
	table.insert(lines, "    bundle.loaded[name] = fn()")
	table.insert(lines, "    return bundle.loaded[name]")
	table.insert(lines, "end\n")

	-- Register Captured Modules
	for _, name in ipairs(self.order) do
		local escaped = string.format("%q", self.modules[name].content)
		table.insert(lines, "bundle.modules['" .. name .. "'] = " .. escaped)
	end

	-- Preload Registration
	table.insert(lines, "\n-- Survival Lab Registration")
	for _, name in ipairs(self.order) do
		table.insert(lines, "package.preload['" .. name .. "'] = function() return load_module('" .. name .. "') end")
		-- Alias for deep paths (core.fsm -> fsm)
		if name:match("%.") then
			local short = name:gsub("^.*%.", "")
			table.insert(lines, "package.preload['" .. short .. "'] = package.preload['" .. name .. "']")
		end
	end

	table.insert(lines, "\nreturn bundle")
	local f = io.open(output_path, "w")
	f:write(table.concat(lines, "\n"))
	f:close()
end

-- Execution
local root_dir = "core" -- TARGET ONLY THE CORE
local bundler = SimpleBundler.new(root_dir, true)
bundler:find_modules()
bundler:generate_bundle("calyx_bundle.lua")
