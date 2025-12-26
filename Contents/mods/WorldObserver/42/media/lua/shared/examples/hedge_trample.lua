-- hedge_trample.lua — minimal example: inner join zombies + sprites on tileLocation.
--[[ Usage in PZ console:
package.loaded["examples/hedge_trample"] = nil -- optional, if you edited the file and want to reload it
ht = require("examples/hedge_trample")
ht.setEnableRemove(true) -- optional safety toggle (default: false)
ht.start()
-- and to stop
ht.stop()
]]
--

local HedgeTrample = {}

local MOD_ID = "examples/hedge_trample"

local leases = nil
local joined = nil

local state = {
	enabledRemove = false,
	lastSpritePresenceByKey = {},
	removedTileLocations = {},
}

function HedgeTrample.setEnableRemove(enabled)
	state.enabledRemove = enabled == true
end

local function say(fmt, ...)
	if type(_G.print) == "function" then
		_G.print(string.format(fmt, ...))
	elseif type(print) == "function" then
		print(string.format(fmt, ...))
	end
end

local function isoObjectPresentOnSquare(isoGridSquare, isoObject)
	if isoGridSquare == nil or isoObject == nil then
		return nil
	end
	if isoGridSquare.getObjects == nil then
		return nil
	end
	local ok, objects = pcall(isoGridSquare.getObjects, isoGridSquare)
	if not ok or objects == nil or objects.size == nil or objects.get == nil then
		return nil
	end
	local okSize, size = pcall(objects.size, objects)
	if not okSize or type(size) ~= "number" then
		return nil
	end
	for i = 0, size - 1 do
		local okGet, obj = pcall(objects.get, objects, i)
		if okGet and obj == isoObject then
			return true
		end
	end
	return false
end

function HedgeTrample.start()
	HedgeTrample.stop()

	local WorldObserver = require("WorldObserver")
	local Time = require("WorldObserver/helpers/time")
	local joinWindowMillis = 50 * 1000
	local accumulateMillis = 10 * 1000
	-- Join/group semantics:
	-- - `accumulateMillis` defines how long a zombie "counts" towards the threshold (event-time via zombie.sourceTime).
	-- - `dedupMillis` only reduces join spam; it must be MUCH smaller than accumulateMillis so "standing still" zombies
	--   continue to refresh their presence inside the accumulation window.
	local dedupMillis = 1500
	local joinWindow = { time = joinWindowMillis }
	local distinctWindow = { time = dedupMillis }
	-- Grouping runs on the LQR row-view (row.zombie, row.sprite), so use a dot-path for event time.
	local groupWindow = { time = accumulateMillis, field = "zombie.RxMeta.sourceTime", currentFn = Time.gameMillis }

	say(
		"[WO hedge_trample] start enabledRemove=%s accumulateMillis=%s dedupMillis=%s joinWindowMillis=%s",
		tostring(state.enabledRemove),
		tostring(accumulateMillis),
		tostring(dedupMillis),
		tostring(joinWindowMillis)
	)

	leases = {
		zombies = WorldObserver.factInterest:declare(MOD_ID, "zombies", {
			type = "zombies",
			scope = "allLoaded",
			radius = { desired = 25 },
			zRange = { desired = 1 },
			staleness = { desired = 1 },
			cooldown = { desired = 1 },
			highlight = { 1, 0.2, 0.2 },
		}),
		sprites = WorldObserver.factInterest:declare(MOD_ID, "sprites", {
			type = "sprites",
			scope = "near",
			radius = { desired = 25 },
			staleness = { desired = 10 },
			cooldown = { desired = 20 },
			highlight = { 0.2, 0.2, 0.8 },
			spriteNames = {
				"vegetation_ornamental_01_0",
				"vegetation_ornamental_01_1",
				"vegetation_ornamental_01_2",
				"vegetation_ornamental_01_3",
				"vegetation_ornamental_01_4",
				"vegetation_ornamental_01_5",
				"vegetation_ornamental_01_6",
				"vegetation_ornamental_01_7",
				"vegetation_ornamental_01_8",
				"vegetation_ornamental_01_9",
				"vegetation_ornamental_01_10",
				"vegetation_ornamental_01_11",
				"vegetation_ornamental_01_12",
				"vegetation_ornamental_01_13",
			},
		}),
	}

	local stream = WorldObserver.observations:derive({
		zombies = WorldObserver.observations:zombies(),
		sprites = WorldObserver.observations:sprites(),
	}, function(lqr)
		local query = lqr
			.zombies
			:innerJoin(lqr.sprites)
			:using({ zombie = "tileLocation", sprite = "tileLocation" })
			:joinWindow(joinWindow)
			:distinct("sprite", { by = "spriteKey", window = distinctWindow })
			:distinct("zombie", { by = "zombieId", window = distinctWindow })
			-- Keep only tiles with at least two distinct zombies seen within the accumulation window.
			:groupByEnrich(
				"tileLocation_grouped",
				function(row)
					local zombie = row and row.zombie
					return zombie and zombie.tileLocation
				end
			)
			:groupWindow(groupWindow)
			:aggregates({
				-- NOTE: In LQR, `aggregates.count` is computed only when `row_count` is enabled.
				-- Because we provide an explicit `count` entry below, LQR will not use the default per-schema row counts.
				row_count = true,
				count = {
					{
						path = "zombie.zombieId",
						distinctFn = function(row)
							local zombie = row and row.zombie
							if zombie == nil or zombie.zombieId == nil then
								return nil
							end
							-- Normalize types so 3 and "3" don't count as different ids.
							return tostring(zombie.zombieId)
						end,
					},
				},
			})

		-- Debug + optional removal live here. We use LQR's `withFinalTap` because WO's stream:filter maps
		-- to `QueryBuilder:where(...)`, and LQR only allows a single where call per query.
		return query:withFinalTap(function(observation)
			local zombie = observation and observation.zombie or nil
			local sprite = observation and observation.sprite or nil
			local nowMs = Time.gameMillis()
			local zombieTime = (type(zombie) == "table" and zombie.RxMeta and zombie.RxMeta.sourceTime)
				or (type(zombie) == "table" and zombie.sourceTime)
				or nil
			local spriteTime = (type(sprite) == "table" and sprite.RxMeta and sprite.RxMeta.sourceTime)
				or (type(sprite) == "table" and sprite.sourceTime)
				or nil
			local zombieAge = (type(nowMs) == "number" and type(zombieTime) == "number") and (nowMs - zombieTime) or nil
			local spriteAge = (type(nowMs) == "number" and type(spriteTime) == "number") and (nowMs - spriteTime) or nil

			local zombieCount = observation and observation._count and observation._count.zombie or 0
			local tileLocation = observation and observation._group_key or (zombie and zombie.tileLocation) or nil
			local spriteKey = type(sprite) == "table" and tostring(sprite.spriteKey) or nil

			local beforePresent = type(sprite) == "table"
					and isoObjectPresentOnSquare(sprite.IsoGridSquare, sprite.IsoObject)
				or nil

			if spriteKey ~= nil and beforePresent ~= nil then
				local last = state.lastSpritePresenceByKey[spriteKey]
				if last == true and beforePresent == false and state.enabledRemove ~= true then
					say(
						"[WO hedge_trample] sprite vanished without WO removal spriteKey=%s spriteTile=%s",
						tostring(spriteKey),
						tostring(sprite and sprite.tileLocation)
					)
				end
				state.lastSpritePresenceByKey[spriteKey] = beforePresent
			end

			say(
				"[WO hedge_trample] enableRemove=%s zombiesOnTile=%s tile=%s zombieId=%s zombieTile=%s spriteName=%s spriteKey=%s spriteTile=%s isoPresent=%s zombieAgeMs=%s spriteAgeMs=%s",
				tostring(state.enabledRemove),
				tostring(zombieCount),
				tostring(tileLocation),
				tostring(zombie and zombie.zombieId),
				tostring(zombie and zombie.tileLocation),
				tostring(sprite and sprite.spriteName),
				tostring(spriteKey),
				tostring(sprite and sprite.tileLocation),
				tostring(beforePresent),
				tostring(zombieAge),
				tostring(spriteAge)
			)

			-- We only remove once we have seen at least two distinct zombies on this tile within the window.
			if zombieCount < 2 then
				return
			end

			if tileLocation ~= nil and state.removedTileLocations[tileLocation] == true then
				return
			end

			local removeOk = nil
			local removeErr = nil
			if state.enabledRemove == true then
				if type(sprite) ~= "table" then
					removeOk = false
					removeErr = "no sprite table"
				elseif sprite.IsoGridSquare == nil then
					removeOk = false
					removeErr = "missing IsoGridSquare"
				elseif sprite.IsoObject == nil then
					removeOk = false
					removeErr = "missing IsoObject"
				else
					local ok, err = pcall(sprite.IsoGridSquare.RemoveTileObject, sprite.IsoGridSquare, sprite.IsoObject)
					removeOk = ok and true or false
					removeErr = ok and nil or err
				end
			else
				removeOk = nil
				removeErr = "disabled"
			end

			local afterPresent = type(sprite) == "table"
					and isoObjectPresentOnSquare(sprite.IsoGridSquare, sprite.IsoObject)
				or nil

			say(
				"[WO hedge_trample REMOVE] tile=%s removeOk=%s err=%s beforePresent=%s afterPresent=%s",
				tostring(tileLocation),
				tostring(removeOk),
				tostring(removeErr),
				tostring(beforePresent),
				tostring(afterPresent)
			)

			if removeOk == true and tileLocation ~= nil then
				state.removedTileLocations[tileLocation] = true
			end
		end)
	end)

	-- Important: derived streams only do work once subscribed.
	joined = stream:subscribe(function()
		-- all output is emitted via withFinalTap above
	end)
end

function HedgeTrample.stop()
	if joined and joined.unsubscribe then
		joined:unsubscribe()
	end
	joined = nil

	for _, lease in pairs(leases or {}) do
		if lease and lease.stop then
			lease:stop()
		end
	end
	leases = nil
end

return HedgeTrample
