-- test_host.lua
-- Minimal test version

local cjson = require("cjson")

ngx.say(cjson.encode({
    status = "ok",
    message = "FSM endpoint working",
    timestamp = ngx.now()
}
