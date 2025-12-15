-- helpers/square.lua -- square helper set (MVP) providing named filters for square observations.
local Log = require("LQR/util/log").withTag("WO.HELPER.square")
local moduleName = ...
local SquareHelpers = {}
if type(moduleName) == "string" then
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		SquareHelpers = loaded
	else
		package.loaded[moduleName] = SquareHelpers
	end
end
SquareHelpers.record = SquareHelpers.record or {}

local function squareField(observation, fieldName)
	-- Helpers should be forgiving if a stream remaps the square field.
	local square = observation[fieldName]
	if square == nil then
		Log:warn("square helper called without field '%s' on observation", tostring(fieldName))
		return nil
	end
	return square
end

local function squareHasCorpse(squareRecord)
	-- This predicate is used by stream helpers after they extracted `square` from an observation.
	-- It expects the WorldObserver square record shape (a table) and may use best-effort hydration.
	if type(squareRecord) ~= "table" then
		return false
	end

	-- Preferred: fact already materialized the boolean.
	if squareRecord.hasCorpse ~= nil then
		return squareRecord.hasCorpse == true
	end

	local isoSquare = squareRecord.IsoSquare
	if isoSquare == nil and SquareHelpers.record and SquareHelpers.record.getIsoSquare then
		isoSquare = SquareHelpers.record.getIsoSquare(squareRecord)
	end
	if isoSquare == nil then
		return false
	end

	-- Prefer the direct boolean getter when available (matches how facts compute hasCorpse).
	if type(isoSquare.hasCorpse) == "function" then
		local ok, value = pcall(isoSquare.hasCorpse, isoSquare)
		return ok and value == true
	end

	-- Fallback: IsoGridSquare:getDeadBody() returns one body (or nil), getDeadBodys() returns a List.
	if type(isoSquare.getDeadBody) == "function" then
		local ok, body = pcall(isoSquare.getDeadBody, isoSquare)
		return ok and body ~= nil
	end

	return false
end

-- Patch seam convention:
-- We only define exported helper functions when the field is nil, so other mods can patch by reassigning
-- `SquareHelpers.<name>` (or `SquareHelpers.record.<name>`) and so module reloads (tests/console via `package.loaded`)
-- don't clobber an existing patch.
if SquareHelpers.record.squareHasCorpse == nil then
	SquareHelpers.record.squareHasCorpse = squareHasCorpse
end
if SquareHelpers.squareHasBloodSplat == nil then
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
end

-- Filter-style helper: returns a filtered stream (not a boolean).
if SquareHelpers.whereSquareNeedsCleaning == nil then
	function SquareHelpers.whereSquareNeedsCleaning(stream, fieldName)
		local target = fieldName or "square"
		return stream:filter(function(observation)
			local square = squareField(observation, target)
			if type(square) ~= "table" then
				return false
			end

			-- For WorldObserver square records, these booleans are already materialized at fact time.
			return SquareHelpers.record.squareHasCorpse(square) or (square.hasBloodSplat == true) or (square.hasTrashItems == true)
		end)
	end
end

-- Backwards-compat alias kept for older docs/examples.
if SquareHelpers.squareNeedsCleaning == nil then
	function SquareHelpers.squareNeedsCleaning(stream, fieldName)
		return SquareHelpers.whereSquareNeedsCleaning(stream, fieldName)
	end
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

local function validateIsoSquare(squareRecord, isoSquare)
	if type(squareRecord) ~= "table" then
		return nil
	end
	if isoSquare == nil then
		return nil
	end

	if type(isoSquare.getX) ~= "function" or type(isoSquare.getY) ~= "function" then
		return nil
	end

	local okX, x = pcall(isoSquare.getX, isoSquare)
	local okY, y = pcall(isoSquare.getY, isoSquare)
	if not okX or not okY then
		return nil
	end

	local z = nil
	if type(isoSquare.getZ) == "function" then
		local okZ, value = pcall(isoSquare.getZ, isoSquare)
		if not okZ then
			return nil
		end
		z = value
	end

	if x ~= squareRecord.x or y ~= squareRecord.y then
		return nil
	end
	local rz = squareRecord.z or 0
	if z ~= nil and z ~= rz then
		return nil
	end

	return isoSquare
end

local function hydrateIsoSquare(squareRecord, opts)
	if type(squareRecord) ~= "table" then
		return nil
	end
	local x, y, z = squareRecord.x, squareRecord.y, squareRecord.z or 0
	if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
		return nil
	end

	local cell = nil
	if type(opts) == "table" and opts.cell and type(opts.cell.getGridSquare) == "function" then
		cell = opts.cell
	else
		local getWorld = _G.getWorld
		if type(getWorld) == "function" then
			local okWorld, world = pcall(getWorld)
			if okWorld and world and type(world.getCell) == "function" then
				local okCell, c = pcall(world.getCell, world)
				if okCell then
					cell = c
				end
			end
		end
		if not cell then
			local getCell = _G.getCell
			if type(getCell) == "function" then
				local okCell, c = pcall(getCell)
				if okCell then
					cell = c
				end
			end
		end
	end

	if not cell or type(cell.getGridSquare) ~= "function" then
		return nil
	end

	local okSquare, isoSquare = pcall(cell.getGridSquare, cell, x, y, z)
	if okSquare and isoSquare ~= nil then
		return isoSquare
	end
	return nil
end

-- Patch seam: only assign defaults when nil, to preserve mod overrides across reloads.
SquareHelpers.record.validateIsoSquare = SquareHelpers.record.validateIsoSquare or validateIsoSquare
SquareHelpers.record.hydrateIsoSquare = SquareHelpers.record.hydrateIsoSquare or hydrateIsoSquare

-- Best-effort access to a live IsoGridSquare based on a square record (x/y/z + optional cached IsoSquare).
-- Contract: returns IsoGridSquare when available, otherwise nil; never throws.
if SquareHelpers.record.getIsoSquare == nil then
	function SquareHelpers.record.getIsoSquare(squareRecord, opts)
		if type(squareRecord) ~= "table" then
			return nil
		end

		local iso = SquareHelpers.record.validateIsoSquare(squareRecord, squareRecord.IsoSquare)
		if iso then
			return iso
		end

		local hydrated = SquareHelpers.record.hydrateIsoSquare(squareRecord, opts)
		iso = SquareHelpers.record.validateIsoSquare(squareRecord, hydrated)
		if iso then
			squareRecord.IsoSquare = iso
			return iso
		end

		squareRecord.IsoSquare = nil
		return nil
	end
end

-- Stream helper: keeps only observations whose square record resolves to a live IsoGridSquare.
-- Side-effect: when resolution succeeds, caches it on the record as `square.IsoSquare`.
if SquareHelpers.whereSquareHasIsoSquare == nil then
	function SquareHelpers.whereSquareHasIsoSquare(stream, fieldName, opts)
		local target = fieldName or "square"
		return stream:filter(function(observation)
			local square = squareField(observation, target)
			if type(square) ~= "table" then
				return false
			end
			return SquareHelpers.record.getIsoSquare(square, opts) ~= nil
		end)
	end
end

if SquareHelpers.squareHasHedge == nil then
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
end

if SquareHelpers.squareHasGrass == nil then
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
end

return SquareHelpers
