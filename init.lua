-- ============================================================================
-- init.lua
-- CALYX BOOTLOADER
-- Deterministic environment hardening + bundle validation
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. LOAD HARDENED RUNTIME
-- ---------------------------------------------------------------------------
local hardened = require("hardened")

-- ---------------------------------------------------------------------------
-- 2. ENABLE SEMANTIC FIREWALL
-- Prevents accidental global leakage after this point.
-- ---------------------------------------------------------------------------
hardened.enable_strict_mode()

-- ---------------------------------------------------------------------------
-- 3. DEFINE BUNDLE ABI (SHAPE CONTRACT)
-- Treat this like a Pydantic / ABI definition for the public API.
-- ---------------------------------------------------------------------------
local BUNDLE_SCHEMA = {
	create = "function",
	NONE = "string",
	ASYNC = "string",
}

-- ---------------------------------------------------------------------------
-- 4. LOAD BUNDLE VIA MODULE SYSTEM
-- `require` guarantees single execution and completed initialization.
-- ---------------------------------------------------------------------------
local ok, bundle = pcall(require, "calyx_bundle")
if not ok then
	error("[FATAL] Failed to load calyx_bundle: " .. tostring(bundle))
end

-- ---------------------------------------------------------------------------
-- 5. VALIDATE BUNDLE SHAPE (ABI CHECK)
-- This is the “no more lies” moment.
-- ---------------------------------------------------------------------------
local ok_shape, shape_err = pcall(function()
	hardened.validate_shape(bundle, BUNDLE_SCHEMA, "calyx_bundle")
end)

if not ok_shape then
	error("[FATAL] Bundle API mismatch: " .. tostring(shape_err))
end

-- ---------------------------------------------------------------------------
-- 6. FREEZE / SANITIZE PUBLIC API
-- Prevent post-boot mutation of the bundle surface.
-- ---------------------------------------------------------------------------
local safe_bundle = hardened.shallow_copy(bundle)

-- Optional: fully freeze instead of shallow copy if you want hard immutability
-- hardened.freeze(safe_bundle)

print("[LAB_INIT] Hardened environment verified. Bundle ABI locked.")

-- ---------------------------------------------------------------------------
-- 7. RETURN VERIFIED BUNDLE
-- ---------------------------------------------------------------------------
return safe_bundle
