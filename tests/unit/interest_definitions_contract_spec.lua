_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true

local Definitions = require("WorldObserver/interest/definitions")

describe("interest definitions contract", function()
	it("declared types are wired as facts + observations", function()
		-- This loads the public facade and registers facts/streams in headless mode.
		local wo = require("WorldObserver")
		assert.is_table(wo)
		assert.is_table(wo._internal)
		assert.is_table(wo._internal.facts)
		assert.is_table(wo.observations)

		for typeName, typeDef in pairs(Definitions.types or {}) do
			assert.is_true(wo._internal.facts:hasType(typeName), ("missing fact type registration: %s"):format(typeName))
			assert.is_function(wo.observations[typeName], ("missing observation stream: %s"):format(typeName))

			if type(typeDef) == "table" and type(typeDef.defaultScope) == "string" and typeDef.defaultScope ~= "" then
				if typeDef.strictScopes == true and type(typeDef.allowedScopes) == "table" then
					assert.is_true(
						typeDef.allowedScopes[typeDef.defaultScope] == true,
						("defaultScope not in allowedScopes: %s.%s"):format(typeName, typeDef.defaultScope)
					)
				end
			end

			-- Smoke the stream builder + subscription path (headless-safe): should not throw.
			local stream = wo.observations[typeName](wo.observations, {})
			assert.is_table(stream)
			assert.is_function(stream.subscribe)
			local sub = stream:subscribe(function() end)
			assert.is_table(sub)
			assert.is_function(sub.unsubscribe)
			sub:unsubscribe()
		end
	end)
end)
