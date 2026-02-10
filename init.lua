-- init.lua
local bundle_path = "calyx_bundle.lua"
local f = io.open(bundle_path, "r")
if not f then
	error("FATAL: calyx_bundle.lua missing.")
end
f:close()

local bundle = dofile(bundle_path)
-- We do NOT require the patch here to avoid the loop.
print("[LAB_INIT] Base Environment Verified.")
return bundle
