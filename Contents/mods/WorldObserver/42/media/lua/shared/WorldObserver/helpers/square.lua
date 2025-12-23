-- helpers/square.lua -- square helper set (MVP) providing named filters for square observations.
local Log = require("LQR/util/log").withTag("WO.HELPER.square")
local Highlight = require("WorldObserver/helpers/highlight")
local moduleName = ...
local SquareHelpers = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		SquareHelpers = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = SquareHelpers
	end
	end
	SquareHelpers.record = SquareHelpers.record or {}
	SquareHelpers.stream = SquareHelpers.stream or {}

	-- Patch seam: only define when nil so mods can override.
	if SquareHelpers.record.tileLocationFromCoords == nil then
		function SquareHelpers.record.tileLocationFromCoords(x, y, z)
			if x == nil or y == nil then
				return nil
			end
			if type(z) ~= "number" then
				z = 0
			end
			return string.format("x%dy%dz%d", math.floor(x), math.floor(y), math.floor(z))
		end
	end

	local function squareField(observation, fieldName)
		-- Helpers should be forgiving if a stream remaps the square field.
	local square = observation[fieldName]
	if square == nil then
		if _G.WORLDOBSERVER_HEADLESS ~= true then
			Log:warn("square helper called without field '%s' on observation", tostring(fieldName))
		end
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

		local isoGridSquare = squareRecord.IsoGridSquare
		if isoGridSquare == nil and SquareHelpers.record and SquareHelpers.record.getIsoGridSquare then
			isoGridSquare = SquareHelpers.record.getIsoGridSquare(squareRecord)
		end
		if isoGridSquare == nil then
			return false
		end

		-- Prefer the direct boolean getter when available (matches how facts compute hasCorpse).
		if type(isoGridSquare.hasCorpse) == "function" then
			local ok, value = pcall(isoGridSquare.hasCorpse, isoGridSquare)
			return ok and value == true
		end

		-- Fallback: IsoGridSquare:getDeadBody() returns one body (or nil), getDeadBodys() returns a List.
		if type(isoGridSquare.getDeadBody) == "function" then
			local ok, body = pcall(isoGridSquare.getDeadBody, isoGridSquare)
			return ok and body ~= nil
		end

		return false
	end

	-- Stream sugar: apply a predicate to the square record directly.
	-- This avoids leaking LQR schema names (e.g. "SquareObservation") into mod code.
	if SquareHelpers.squareFilter == nil then
	function SquareHelpers.squareFilter(stream, fieldName, predicate)
		assert(type(predicate) == "function", "squareFilter predicate must be a function")
		local target = fieldName or "square"
		return stream:filter(function(observation)
			local square = squareField(observation, target)
			return predicate(square, observation) == true
		end)
	end
end
if SquareHelpers.stream.squareFilter == nil then
	function SquareHelpers.stream.squareFilter(stream, fieldName, ...)
		return SquareHelpers.squareFilter(stream, fieldName, ...)
	end
end

-- Patch seam convention:
-- We only define exported helper functions when the field is nil, so other mods can patch by reassigning
-- `SquareHelpers.<name>` (or `SquareHelpers.record.<name>`) and so module reloads (tests/console via `package.loaded`)
-- don't clobber an existing patch.
	if SquareHelpers.record.squareHasCorpse == nil then
		SquareHelpers.record.squareHasCorpse = squareHasCorpse
	end

	if SquareHelpers.squareHasCorpse == nil then
		function SquareHelpers.squareHasCorpse(stream, fieldName, ...)
			local target = fieldName or "square"
		return stream:filter(function(observation)
			local square = squareField(observation, target)
			return SquareHelpers.record.squareHasCorpse(square)
		end)
	end
end
	if SquareHelpers.stream.squareHasCorpse == nil then
		function SquareHelpers.stream.squareHasCorpse(stream, fieldName, ...)
			return SquareHelpers.squareHasCorpse(stream, fieldName, ...)
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

	local function validateIsoGridSquare(squareRecord, isoGridSquare)
		if type(squareRecord) ~= "table" then
			return nil
		end
		if isoGridSquare == nil then
			return nil
		end

		if type(isoGridSquare.getX) ~= "function" or type(isoGridSquare.getY) ~= "function" then
			return nil
		end

		local okX, x = pcall(isoGridSquare.getX, isoGridSquare)
		local okY, y = pcall(isoGridSquare.getY, isoGridSquare)
		if not okX or not okY then
			return nil
		end

		local z = nil
		if type(isoGridSquare.getZ) == "function" then
			local okZ, value = pcall(isoGridSquare.getZ, isoGridSquare)
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

		return isoGridSquare
	end

	local function hydrateIsoGridSquare(squareRecord, opts)
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
	SquareHelpers.record.validateIsoGridSquare = SquareHelpers.record.validateIsoGridSquare or validateIsoGridSquare
	SquareHelpers.record.hydrateIsoGridSquare = SquareHelpers.record.hydrateIsoGridSquare or hydrateIsoGridSquare

	-- Best-effort access to a live IsoGridSquare based on a square record (x/y/z + optional cached IsoGridSquare).
	-- Contract: returns IsoGridSquare when available, otherwise nil; never throws.
	if SquareHelpers.record.getIsoGridSquare == nil then
		function SquareHelpers.record.getIsoGridSquare(squareRecord, opts)
			if type(squareRecord) ~= "table" then
				return nil
			end

			local iso = SquareHelpers.record.validateIsoGridSquare(squareRecord, squareRecord.IsoGridSquare)
			if iso then
				return iso
			end

			local hydrated = SquareHelpers.record.hydrateIsoGridSquare(squareRecord, opts)
			iso = SquareHelpers.record.validateIsoGridSquare(squareRecord, hydrated)
			if iso then
				squareRecord.IsoGridSquare = iso
				return iso
			end

			squareRecord.IsoGridSquare = nil
			return nil
		end
	end

	local function squareHasIsoGridSquare(squareRecord, opts)
		if type(squareRecord) ~= "table" then
			return false
		end
		return SquareHelpers.record.getIsoGridSquare(squareRecord, opts) ~= nil
	end

	if SquareHelpers.record.squareHasIsoGridSquare == nil then
		SquareHelpers.record.squareHasIsoGridSquare = squareHasIsoGridSquare
	end

	-- Stream helper: keeps only observations whose square record resolves to a live IsoGridSquare.
	-- Side-effect: when resolution succeeds, caches it on the record as `square.IsoGridSquare`.
	if SquareHelpers.squareHasIsoGridSquare == nil then
		function SquareHelpers.squareHasIsoGridSquare(stream, fieldName, opts)
			local target = fieldName or "square"
			return stream:filter(function(observation)
				local square = squareField(observation, target)
				return SquareHelpers.record.squareHasIsoGridSquare(square, opts)
			end)
		end
	end
	if SquareHelpers.stream.squareHasIsoGridSquare == nil then
		function SquareHelpers.stream.squareHasIsoGridSquare(stream, fieldName, ...)
			return SquareHelpers.squareHasIsoGridSquare(stream, fieldName, ...)
		end
	end

	-- Highlight a square's floor for a duration with a fading alpha.
	if SquareHelpers.highlight == nil then
	function SquareHelpers.highlight(squareOrRecord, durationMs, opts)
		opts = opts or {}
		if type(durationMs) == "number" and opts.durationMs == nil then
			opts.durationMs = durationMs
		end

			local isoGridSquare = nil
			local t = type(squareOrRecord)
			if (t == "table" or t == "userdata") and type(squareOrRecord.getFloor) == "function" then
				isoGridSquare = squareOrRecord
			elseif t == "table" then
				isoGridSquare = SquareHelpers.record.getIsoGridSquare(squareOrRecord)
			end
			if isoGridSquare == nil then
				return nil, "noIsoGridSquare"
			end

			local okFloor, floor = pcall(isoGridSquare.getFloor, isoGridSquare)
			if not okFloor or floor == nil then
				return nil, "noFloor"
			end

		return Highlight.highlightTarget(floor, opts)
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
