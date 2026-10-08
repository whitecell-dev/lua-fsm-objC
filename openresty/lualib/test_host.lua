-- test_host.lua
-- Minimal test version
--
-- KNOWN: not wired to any location block in openresty/nginx.conf (recon 7/B23).
-- This file is a syntax-error fossil: the ngx.say(...) call was never closed,
-- so it could not have produced the message it claims. Parens fixed; whether
-- it should be routed at all is a deployment decision, not a code fix.
-- Not "fixed" beyond the parse error because no nginx.conf location loads it.

local cjson = require("cjson")

ngx.say(cjson.encode({
    status = "ok",
    message = "FSM endpoint working",
    timestamp = ngx.now()
}))
