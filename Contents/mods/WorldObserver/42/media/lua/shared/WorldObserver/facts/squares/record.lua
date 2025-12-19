-- facts/squares/record.lua -- builds stable square fact records from IsoGridSquare objects.
local Log = require("LQR/util/log").withTag("WO.FACTS.squares")
local Time = require("WorldObserver/helpers/time")

local moduleName = ...
local Record = {}
if type(moduleName) == "string" then
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Record = loaded
	else
		package.loaded[moduleName] = Record
	end
end
Record._internal = Record._internal or {}

local function nowMillis()
	return Time.gameMillis() or math.floor(os.time() * 1000)
end

local function coordOf(square, getterName)
	if square and type(square[getterName]) == "function" then
		local ok, value = pcall(square[getterName], square)
		if ok then
			return value
		end
	end
	return nil
end

local function deriveSquareId(square, x, y, z)
	if square and type(square.getID) == "function" then
		local ok, id = pcall(square.getID, square)
		if ok and id ~= nil then
			return id
		end
	end
	if x and y and z then
		return (z * 1e9) + (x * 1e4) + y
	end
	return nil
end

local function detectFlag(square, detector)
	if not square then
		return false
	end
	if type(detector) == "function" then
		local ok, value = pcall(detector, square)
		if ok then
			return value == true
		end
	end
	return false
end

local function detectCorpse(square)
	if not square then
		return false
	end
	if type(square.getDeadBody) == "function" then
		local ok, body = pcall(square.getDeadBody, square)
		if ok and body ~= nil then
			return true
		end
	end
	-- Some builds expose a list-returning API; treat any non-empty list as "has corpse".
	if type(square.getDeadBodys) == "function" then
		local ok, list = pcall(square.getDeadBodys, square)
		if ok and list ~= nil then
			if type(list.size) == "function" then
				local okSize, size = pcall(list.size, list)
				if okSize and type(size) == "number" then
					return size > 0
				end
			end
			-- Best-effort: if we can't introspect size, a non-nil list still suggests corpses may exist.
			-- Keep this conservative: only treat it as "true" when we can prove it's non-empty.
		end
	end
	return detectFlag(square, square.hasCorpse)
end

--- Build a square fact record.
--- Intentionally returns a tiny, stable "snapshot" so we can buffer safely and keep downstream pure.
--- @param square any
--- @param source string|nil
--- @return table|nil record
if Record.makeSquareRecord == nil then
	function Record.makeSquareRecord(square, source)
		if not square then
			return nil
		end

		local x = coordOf(square, "getX")
		local y = coordOf(square, "getY")
		local z = coordOf(square, "getZ") or 0
		if x == nil or y == nil then
			Log:warn("Skipped square record: missing coordinates")
			return nil
		end

		local ts = nowMillis()
		return {
			squareId = deriveSquareId(square, x, y, z),
			x = x,
			y = y,
			z = z,
			hasBloodSplat = detectFlag(square, square.hasBlood),
			hasCorpse = detectCorpse(square),
			hasTrashItems = false, -- placeholder until we wire real trash detection
			observedAtTimeMS = ts,
			sourceTime = ts,
			IsoSquare = square,
			source = source,
		}
	end
end

Record._internal.coordOf = coordOf
Record._internal.deriveSquareId = deriveSquareId
Record._internal.detectFlag = detectFlag
Record._internal.detectCorpse = detectCorpse
Record._internal.nowMillis = nowMillis

return Record
