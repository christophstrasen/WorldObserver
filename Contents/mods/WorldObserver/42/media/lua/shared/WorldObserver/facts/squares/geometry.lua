-- facts/squares/geometry.lua -- helper geometry routines for square-based scanning.
local moduleName = ...
local Geometry = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Geometry = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = Geometry
	end
end
Geometry._internal = Geometry._internal or {}

local function coordOf(square, getterName)
	if square and type(square[getterName]) == "function" then
		local ok, value = pcall(square[getterName], square)
		if ok then
			return value
		end
	end
	return nil
end

if Geometry.squaresPerRadius == nil then
	--- Return the number of squares in a Chebyshev radius square: (2r+1)^2.
	--- @param radius number
	--- @return number
	function Geometry.squaresPerRadius(radius)
		radius = math.max(0, math.floor(tonumber(radius) or 0))
		local side = (radius * 2) + 1
		return side * side
	end
end

if Geometry.buildRingOffsets == nil then
	--- Build a dense, unique Chebyshev sweep (center -> rings outward).
	--- @param radius number
	--- @return table offsets
	function Geometry.buildRingOffsets(radius)
		radius = math.max(0, math.floor(tonumber(radius) or 0))
		local offsets = {}
		for dist = 0, radius do
			if dist == 0 then
				offsets[#offsets + 1] = { 0, 0 }
			else
				for dx = -dist, dist do
					offsets[#offsets + 1] = { dx, -dist }
					offsets[#offsets + 1] = { dx, dist }
				end
				for dy = -dist + 1, dist - 1 do
					offsets[#offsets + 1] = { -dist, dy }
					offsets[#offsets + 1] = { dist, dy }
				end
			end
		end
		return offsets
	end
end

if Geometry.iterSquaresInRing == nil then
	--- Collect squares in Chebyshev rings around the center square.
	--- Stops early once `budget` is reached (used for sampling).
	--- @param centerSquare any
	--- @param innerRadius number
	--- @param outerRadius number
	--- @param budget number
	--- @return table squares
	function Geometry.iterSquaresInRing(centerSquare, innerRadius, outerRadius, budget)
		local results = {}
		if not centerSquare or budget <= 0 then
			return results
		end

		local cellGetter = centerSquare.getCell
		local cell = nil
		if type(cellGetter) == "function" then
			local ok, c = pcall(cellGetter, centerSquare)
			if ok then
				cell = c
			end
		end
		if not cell or type(cell.getGridSquare) ~= "function" then
			return results
		end

		local cx = coordOf(centerSquare, "getX")
		local cy = coordOf(centerSquare, "getY")
		local cz = coordOf(centerSquare, "getZ") or 0
		if not cx or not cy then
			return results
		end

		-- Iterate outward by Chebyshev distance (rings) so limited budgets still cover all directions.
		-- A naive nested loop biases toward one quadrant because we stop early when `budget` is small.
		local function maybeAdd(dx, dy)
			if #results >= budget then
				return false
			end
			local ok, square = pcall(cell.getGridSquare, cell, cx + dx, cy + dy, cz)
			if ok and square then
				results[#results + 1] = square
			end
			return #results < budget
		end

		innerRadius = math.max(0, math.floor(tonumber(innerRadius) or 0))
		outerRadius = math.max(innerRadius, math.floor(tonumber(outerRadius) or 0))

		for dist = innerRadius, outerRadius do
			if dist == 0 then
				if not maybeAdd(0, 0) then
					return results
				end
			else
				-- Top/bottom edges (including corners).
				for dx = -dist, dist do
					if not maybeAdd(dx, -dist) then
						return results
					end
					if not maybeAdd(dx, dist) then
						return results
					end
				end
				-- Left/right edges excluding corners (already covered by top/bottom).
				for dy = -dist + 1, dist - 1 do
					if not maybeAdd(-dist, dy) then
						return results
					end
					if not maybeAdd(dist, dy) then
						return results
					end
				end
			end
		end
		return results
	end
end

return Geometry
