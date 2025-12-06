-- WorldObserver.lua — public façade for the async scanning framework.

-- local Config = require("WorldObserver/config")

local okLuaEvent, LuaEventOrError = pcall(require, "Starlit/LuaEvent")
if okLuaEvent then
	Events.setLuaEvent(LuaEventOrError)
	Runtime.setLuaEventError(nil)
else
	Events.setLuaEvent(nil)
	Runtime.setLuaEventError(LuaEventOrError)
end

local WorldObserver = {}

return WorldObserver
