-- helpers/square.lua -- square helper set (MVP) providing named filters for square observations.
local Log = require("LQR/util/log").withTag("WO.HELPER.square")
local SquareHelpers = {}

local function squareField(observation, fieldName)
	-- Helpers should be forgiving if a stream remaps the square field.
	local square = observation[fieldName]
	if square == nil then
		Log:warn("square helper called without field '%s' on observation", tostring(fieldName))
		return nil
	end
	return square
end

local function squareHasCorpse(square)
	local IsoSquare = square.IsoSquare
	-- Support both shapes:
	-- - WorldObserver square records (preferred): precomputed boolean fields
	-- - Vanilla IsoGridSquare (fallback): compute via API calls
	if type(square) == "table" and square.hasCorpse ~= nil then
		return square.hasCorpse == true
	end
	if type(IsoSquare) == "userdata" and type(IsoSquare.getDeadBody) == "function" then
		-- IsoGridSquare:getDeadBody() returns one body (or nil), getDeadBodys() returns a List.
		-- Prefer getDeadBody() as the cheapest "any corpse?" check.
		local ok, body = pcall(IsoSquare.getDeadBody, IsoSquare)
		return ok and body ~= nil
	end
	return false
end

function SquareHelpers.squareHasBloodSplat(stream, fieldName)
	local target = fieldName or "square"
	return stream:filter(function(observation)
		local square = squareField(observation, target)
		if square == nil then
			return false
		end

		-- Preferred: WorldObserver square records already carry a boolean flag.
		if type(square) == "table" and square.hasBloodSplat ~= nil then
			return square.hasBloodSplat == true
		end

		-- Fallback: if a caller streams raw IsoGridSquare objects, we currently have no verified
		-- vanilla API path for a "has blood splat" boolean. Keep this conservative.
		return false
	end)
end

-- Filter-style helper: returns a filtered stream (not a boolean).
function SquareHelpers.whereSquareNeedsCleaning(stream, fieldName)
	local target = fieldName or "square"
	return stream:filter(function(observation)
		local square = squareField(observation, target)
		if square == nil then
			return false
		end

		-- For WorldObserver square records, these booleans are already materialized at fact time.
		if type(square) == "table" then
			return squareHasCorpse(square) or (square.hasBloodSplat == true) or (square.hasTrashItems == true)
		end

		-- Fallback shape: IsoGridSquare. We only have a reliable corpse check right now.
		return squareHasCorpse(square)
	end)
end

-- Backwards-compat alias kept for older docs/examples.
function SquareHelpers.squareNeedsCleaning(stream, fieldName)
	return SquareHelpers.whereSquareNeedsCleaning(stream, fieldName)
end

local GRASS_PREFIX = "blends_natural"

local KNOWN_HEDGE_SPRITES = {
	-- Tall Hedge sprites. (Keep this list small and curated.)
	vegetation_ornamental_01_0 = true,
	vegetation_ornamental_01_1 = true,
	vegetation_ornamental_01_2 = true,
	vegetation_ornamental_01_3 = true,
	vegetation_ornamental_01_4 = true,
	vegetation_ornamental_01_5 = true,
	vegetation_ornamental_01_6 = true,
	vegetation_ornamental_01_7 = true,
	vegetation_ornamental_01_10 = true,
	vegetation_ornamental_01_11 = true,
	vegetation_ornamental_01_12 = true,
	vegetation_ornamental_01_13 = true,
}

function SquareHelpers.squareHasHedge(square)
	if not square then
		return false
	end

	local list = square:getLuaTileObjectList()
	if not list then
		return false
	end

	for i = 1, #list do
		local obj = list[i]
		if obj then
			local sn = obj:getSpriteName()
			if sn then
				-- Fast exact match first.
				if KNOWN_HEDGE_SPRITES[sn] then
					return true
				end

				-- Optional slow fallback: avoid if you can maintain a real list.
				-- If you keep it, do a case-sensitive find first (cheaper, no alloc).
				if string.find(sn, "hedge", 1, true) ~= nil then
					return true
				end
			end
		end
	end

	return false
end

function SquareHelpers.squareHasGrass(square)
	if not square then
		return false
	end

	local floor = square:getFloor()
	if not floor then
		return false
	end

	local sn = floor:getSpriteName()
	if not sn then
		return false
	end

	-- Prefix check without substring allocation.
	return string.find(sn, GRASS_PREFIX, 1, true) == 1
end

return SquareHelpers
