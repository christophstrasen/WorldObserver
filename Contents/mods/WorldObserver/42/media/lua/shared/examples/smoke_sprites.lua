-- smoke_sprites.lua — console-friendly smoke test for WorldObserver sprites.
-- Usage in PZ console:
--[[ @AI agent dont change this
	_G.WORLDOBSERVER_CONFIG_OVERRIDES = { facts = { sprites = { probe = { infoLogEveryMs = 500, logEachSweep = true } } } }
	smokes = require("examples/smoke_sprites")
	smokes.start({ distinctSeconds = 5 }) -- just subscribes + prints a startup banner
	smokes.enableOnLoad() -- MapObjects.OnLoadWithSprite based
	smokes.enableSquare() -- square-based near sweep
	smokes.disableOnLoad()
	smokes.disableSquare()
	smokes.setSpriteNames({ "fixtures_bathroom_01_0" })
	smokes.stop()
]]
--
-- Notes:
-- - Square sensor = sprite sweep over nearby/vision squares (near + vision scopes).
-- - OnLoad sensor = MapObjects.OnLoadWithSprite event stream (scope=onLoadWithSprite).
-- - Highlight duration is derived from cooldown; it is capped to ~5s.

local SmokeSprites = {}

local DEFAULT_SPRITE_NAMES = {
	"fixtures_bathroom_01_1",
	"fixtures_bathroom_01_3",
}

local DEFAULT_SPRITE_NAMES = {
	-- Hedges / tall ornamental vegetation (commonly used in yards).
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
}

local LEASE_OPTS = {
	ttlSeconds = 60 * 60,
}

-- Why this exists:
-- - In PZ, Log.info can be suppressed by global log-level state (and module caching means setLevel() may not re-run).
-- - `_G.print` is the most reliable way to see output while debugging from the in-game console.
local function say(fmt, ...)
	if type(_G.print) == "function" then
		_G.print(string.format("[smoke.sprites] " .. fmt, ...))
	elseif type(print) == "function" then
		print(string.format("[smoke.sprites] " .. fmt, ...))
	end
end

local state = {
	modId = "examples/smoke_sprites",
	spriteNames = DEFAULT_SPRITE_NAMES,
	highlight = true,
	distinctSeconds = nil,
	subscription = nil,
	leases = {
		near = nil,
		onLoad = nil,
	},
}

local function ensureSubscription()
	if state.subscription then
		return
	end
	local WorldObserver = require("WorldObserver")
	local stream = WorldObserver.observations:sprites()
	if state.distinctSeconds ~= nil then
		stream = stream:distinct("sprite", state.distinctSeconds)
	end
	say("subscribing to sprites (distinctSeconds=%s)", tostring(state.distinctSeconds))
	state.subscription = stream:subscribe(function(observation)
		local sprite = observation.sprite
		if type(sprite) ~= "table" then
			return
		end
		say(
			"sprite name=%s id=%s key=%s idx=%s loc=(%s,%s,%s) square=%s source=%s",
			tostring(sprite.spriteName),
			tostring(sprite.spriteId),
			tostring(sprite.spriteKey),
			tostring(sprite.objectIndex),
			tostring(sprite.x),
			tostring(sprite.y),
			tostring(sprite.z),
			tostring(sprite.squareId),
			tostring(sprite.source)
		)
	end)
end

function SmokeSprites.setSpriteNames(value)
	local list = nil
	if type(value) == "string" and value ~= "" then
		list = { value }
	elseif type(value) == "table" then
		-- Accept both { "a", "b" } and { a=true, b=true } styles.
		list = {}
		local seen = {}
		for key, v in pairs(value) do
			if type(v) == "string" and v ~= "" then
				if not seen[v] then
					list[#list + 1] = v
					seen[v] = true
				end
			elseif v == true and type(key) == "string" and key ~= "" then
				if not seen[key] then
					list[#list + 1] = key
					seen[key] = true
				end
			end
		end
		if list[1] == nil then
			list = nil
		else
			table.sort(list)
		end
	end

	state.spriteNames = list or DEFAULT_SPRITE_NAMES
	say("spriteNames updated (%d entries)", #state.spriteNames)

	if state.leases.near then
		pcall(function()
			state.leases.near:declare({
				type = "sprites",
				scope = "near",
				staleness = { desired = 5, tolerable = 15 },
				radius = { desired = 8, tolerable = 5 },
				cooldown = { desired = 20, tolerable = 40 },
				highlight = state.highlight,
				spriteNames = state.spriteNames,
			}, LEASE_OPTS)
		end)
	end
	if state.leases.onLoad then
		pcall(function()
			state.leases.onLoad:declare({
				type = "sprites",
				scope = "onLoadWithSprite",
				cooldown = { desired = 300, tolerable = 600 },
				highlight = state.highlight,
				spriteNames = state.spriteNames,
			}, LEASE_OPTS)
		end)
	end
end

function SmokeSprites.enableSquare(opts)
	opts = opts or {}
	ensureSubscription()
	local WorldObserver = require("WorldObserver")
	local spriteNames = state.spriteNames or DEFAULT_SPRITE_NAMES
	if opts.near ~= false and state.leases.near == nil then
		state.leases.near = WorldObserver.factInterest:declare(state.modId, "sprites.near", {
			type = "sprites",
			scope = "near",
			staleness = { desired = 5, tolerable = 15 },
			radius = { desired = 8, tolerable = 5 },
			cooldown = { desired = 300, tolerable = 600 },
			highlight = state.highlight,
			spriteNames = spriteNames,
		}, LEASE_OPTS)
		say("near sprite sweep enabled (square-based)")
	end
end

function SmokeSprites.disableSquare()
	if state.leases.near and state.leases.near.stop then
		local ok = pcall(function()
			state.leases.near:stop()
		end)
		if ok then
			say("near sprite sweep disabled (square-based)")
		end
	end
	state.leases.near = nil
end

function SmokeSprites.enableOnLoad()
	if state.leases.onLoad then
		return
	end
	ensureSubscription()
	local WorldObserver = require("WorldObserver")
	local spriteNames = state.spriteNames or DEFAULT_SPRITE_NAMES
	state.leases.onLoad = WorldObserver.factInterest:declare(state.modId, "sprites.onLoad", {
		type = "sprites",
		scope = "onLoadWithSprite",
		cooldown = { desired = 300, tolerable = 600 },
		highlight = state.highlight,
		spriteNames = spriteNames,
	}, LEASE_OPTS)
	say("onLoadWithSprite enabled")
end

function SmokeSprites.disableOnLoad()
	if state.leases.onLoad and state.leases.onLoad.stop then
		local ok = pcall(function()
			state.leases.onLoad:stop()
		end)
		if ok then
			say("onLoadWithSprite disabled")
		end
	end
	state.leases.onLoad = nil
end

function SmokeSprites.start(opts)
	opts = opts or {}
	-- Ensure WorldObserver (and its LQR bootstrap) is loaded before we try to configure logging.
	require("WorldObserver")
	do
		local ok, Log = pcall(require, "LQR/util/log")
		if ok and type(Log) == "table" and type(Log.setLevel) == "function" then
			pcall(Log.setLevel, opts.logLevel or "info")
		end
	end
	say("start() logLevel=%s", tostring(opts.logLevel or "info"))

	if opts.highlight ~= nil then
		state.highlight = opts.highlight
	end
	if opts.spriteNames ~= nil then
		SmokeSprites.setSpriteNames(opts.spriteNames)
	end
	state.distinctSeconds = opts.distinctSeconds
	ensureSubscription()
	-- Intentionally does not enable any sensors automatically.
	-- Why: we want this smoke test to read linearly in the console (explicit enable/disable calls).
	return SmokeSprites
end

function SmokeSprites.stop()
	SmokeSprites.disableSquare()
	SmokeSprites.disableOnLoad()
	if state.subscription and state.subscription.unsubscribe then
		state.subscription:unsubscribe()
		state.subscription = nil
		say("sprites subscription stopped")
	end
end

return SmokeSprites
