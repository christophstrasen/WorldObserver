-- debug.lua -- minimal debug helpers to introspect whether facts/streams are registered.
local Log = require("LQR.util.log").withTag("WO.DEBUG")

local Debug = {}

function Debug.new(factRegistry, observationRegistry)
	return {
		describeFacts = function(typeName)
			if factRegistry:hasType(typeName) then
				Log:info("Facts for '%s' registered", tostring(typeName))
			else
				Log:warn("Facts for '%s' not registered", tostring(typeName))
			end
		end,

		describeStream = function(name)
			if observationRegistry:hasStream(name) then
				Log:info("ObservationStream '%s' registered", tostring(name))
			else
				Log:warn("ObservationStream '%s' not registered", tostring(name))
			end
		end,
	}
end

return Debug
