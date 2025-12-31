local Log = require("DREAMBase/log").withTag("WO.HELPER.highlight")
local Time = require("WorldObserver/helpers/time")

local moduleName = ...
local Highlight = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Highlight = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = Highlight
	end
end

Highlight._state = Highlight._state or {
	active = {},
	activeCount = 0,
	onTickFn = nil,
	onTickAttached = false,
}

local DEFAULT_COLOR = { 0.2, 0.5, 1.0 }
local DEFAULT_ALPHA = 0.7
local DEFAULT_DURATION_MS = 1000

local function nowMillis()
	return Time.gameMillis()
end

local function secondsFrom(value)
	if type(value) == "table" then
		-- Accept both "effective" numeric knobs and merged band tables.
		return tonumber(value.desired) or tonumber(value.tolerable) or tonumber(value[1]) or 0
	end
	return tonumber(value) or 0
end

-- Patch seam: only define when nil so mods can override.
if Highlight.durationMsFromCooldownSeconds == nil then
	function Highlight.durationMsFromCooldownSeconds(cooldownSeconds)
		-- Use the same cadence rule as everywhere else: max(staleness,cooldown)/2.
		-- For cooldown-only callers, this is simply cooldown/2.
		return Highlight.durationMsFromCadenceSeconds(nil, cooldownSeconds)
	end
end

if Highlight.durationMsFromCadenceSeconds == nil then
	function Highlight.durationMsFromCadenceSeconds(stalenessSeconds, cooldownSeconds)
		local staleness = secondsFrom(stalenessSeconds)
		local cooldown = secondsFrom(cooldownSeconds)
		local cadence = math.max(staleness, cooldown)
		if cadence <= 0 then
			return 0
		end
		return math.floor((cadence * 1000) / 2)
	end
end

if Highlight.durationMsFromEffectiveCadence == nil then
	--- Resolve highlight duration from an effective interest spec (staleness/cooldown in seconds).
	--- Uses the cadence rule: max(staleness,cooldown)/2.
	--- @param effective table|nil
	--- @return number durationMs
	function Highlight.durationMsFromEffectiveCadence(effective)
		if type(effective) ~= "table" then
			return 0
		end
		return Highlight.durationMsFromCadenceSeconds(effective.staleness, effective.cooldown)
	end
end

-- Patch seam: only define when nil so mods can override.
-- Why: multiple fact plans accept `highlight = true | { r,g,b[,a], ... }` and need consistent parsing.
if Highlight.resolveColorAlpha == nil then
	--- Resolve highlight color/alpha from a preference value.
	--- @param pref any `true` or a table like `{ r, g, b, [a] }`
	--- @param fallbackColor table|nil
	--- @param fallbackAlpha number|nil
	--- @return table color
	--- @return number alpha
	function Highlight.resolveColorAlpha(pref, fallbackColor, fallbackAlpha)
		local color = fallbackColor
		local alpha = tonumber(fallbackAlpha) or DEFAULT_ALPHA
		if type(color) ~= "table" then
			color = DEFAULT_COLOR
		end
		if type(pref) == "table" then
			color = pref
			if type(pref[4]) == "number" then
				alpha = pref[4]
			end
		end
		return color, alpha
	end
end

if Highlight.highlightFloor == nil then
	--- Highlight a square's floor if available.
	--- @param square any
	--- @param durationMs number
	--- @param opts table|nil { color?, alpha?, blink? }
	--- @return table|nil handle
	--- @return string|nil reason
	function Highlight.highlightFloor(square, durationMs, opts)
		if square == nil or durationMs <= 0 then
			return nil, "noSquare"
		end
		if type(square.getFloor) ~= "function" then
			return nil, "noFloor"
		end
		local okFloor, floor = pcall(square.getFloor, square)
		if not okFloor or floor == nil then
			return nil, "noFloor"
		end
		if type(Highlight.highlightTarget) ~= "function" then
			return nil, "noTargetHelper"
		end
		opts = opts or {}
		if opts.durationMs == nil then
			opts.durationMs = durationMs
		end
		return Highlight.highlightTarget(floor, opts)
	end
end

local function callSetHighlighted(target, enabled, blink)
	if type(target.setHighlighted) ~= "function" then
		return
	end
	local ok = pcall(target.setHighlighted, target, enabled, blink)
	if not ok then
		pcall(target.setHighlighted, target, enabled)
	end
end

local function applyHighlight(entry, alpha)
	local target = entry and entry.target
	if target == nil then
		return
	end

	local color = entry.color or DEFAULT_COLOR
	local a = alpha or entry.startAlpha or DEFAULT_ALPHA
	if entry.useOutline and type(target.setOutlineHighlight) == "function" then
		if type(target.setOutlineHighlightColor) == "function" then
			pcall(target.setOutlineHighlightColor, target, color[1], color[2], color[3], a)
		end
		pcall(target.setOutlineHighlight, target, true)
	elseif type(target.setHighlightColor) == "function" then
		pcall(target.setHighlightColor, target, color[1], color[2], color[3], a)
	end
	callSetHighlighted(target, true, entry.blink)
end

local function clearHighlight(entry)
	local target = entry and entry.target
	if target == nil then
		return
	end
	if entry.useOutline and type(target.setOutlineHighlight) == "function" then
		pcall(target.setOutlineHighlight, target, false)
	end
	callSetHighlighted(target, false, entry.blink)
end

local function detachOnTickHookIfIdle(state)
	if not state.onTickAttached then
		return
	end
	if state.activeCount > 0 then
		return
	end

	local events = _G.Events
	local tick = events and events.OnTick
	if tick and type(tick.Remove) == "function" then
		local ok = pcall(tick.Remove, tick, state.onTickFn)
		if not ok then
			pcall(tick.Remove, state.onTickFn)
		end
	end
	state.onTickAttached = false
	state.onTickFn = nil
end

local function tickOnce(state)
	if state.activeCount <= 0 then
		detachOnTickHookIfIdle(state)
		return
	end

	local now = nowMillis()
	if now == nil then
		return
	end

	for target, entry in pairs(state.active) do
		local duration = entry.durationMs or DEFAULT_DURATION_MS
		local elapsed = now - (entry.startedMs or now)
		local done = false
		local alpha = entry.startAlpha or DEFAULT_ALPHA
		if duration <= 0 then
			done = true
			alpha = 0
		else
			local t = elapsed / duration
			if t >= 1 then
				done = true
				alpha = 0
			elseif t > 0 then
				alpha = alpha * (1 - t)
			end
		end

		if done then
			clearHighlight(entry)
			state.active[target] = nil
			state.activeCount = math.max(0, state.activeCount - 1)
		else
			applyHighlight(entry, alpha)
		end
	end

	if state.activeCount <= 0 then
		detachOnTickHookIfIdle(state)
	end
end

local function attachOnTickHookOnce(state)
	if state.onTickAttached then
		return true
	end

	local events = _G.Events
	local tick = events and events.OnTick
	if not (tick and type(tick.Add) == "function" and type(tick.Remove) == "function") then
		Log:warn("Highlight manager could not hook Events.OnTick; highlights will not fade")
		return false
	end

	local function onTick()
		tickOnce(state)
	end

	state.onTickFn = onTick
	state.onTickAttached = true
	tick.Add(onTick)
	return true
end

-- Patch seam: only define when nil so mods can override by reassigning Highlight.highlightTarget.
if Highlight.highlightTarget == nil then
	--- Highlight an object (e.g. IsoObject floor) that supports setHighlightColor/setHighlighted.
	--- @param target any
	--- @param opts table|nil { durationMs?, color?, alpha?, blink? }
	--- @return table|nil handle { stop = function() end } or nil on failure
	--- @return string|nil reason
	function Highlight.highlightTarget(target, opts)
		if target == nil then
			return nil, "noTarget"
		end

		opts = opts or {}
		local state = Highlight._state

		local durationMs = tonumber(opts.durationMs or opts.duration) or DEFAULT_DURATION_MS
		local startAlpha = tonumber(opts.alpha or opts.startAlpha) or DEFAULT_ALPHA
		local color = opts.color
		if type(color) ~= "table" then
			color = DEFAULT_COLOR
		end
		local blink = opts.blink == true
		local useOutline = opts.useOutline == true or (type(target.setOutlineHighlight) == "function" and type(target.setHighlightColor) ~= "function")

		local startedMs = nowMillis() or 0
		local entry = {
			target = target,
			startedMs = startedMs,
			durationMs = durationMs,
			color = color,
			startAlpha = startAlpha,
			blink = blink,
			useOutline = useOutline,
		}

		local existing = state.active[target]
		state.active[target] = entry
		if not existing then
			state.activeCount = (state.activeCount or 0) + 1
		end

		applyHighlight(entry, startAlpha)
		attachOnTickHookOnce(state)

		return {
			stop = function()
				local tracked = state.active[target]
				if tracked then
					clearHighlight(tracked)
					state.active[target] = nil
					state.activeCount = math.max(0, (state.activeCount or 1) - 1)
				end
				if state.activeCount <= 0 then
					detachOnTickHookIfIdle(state)
				end
			end,
		}
	end
end

return Highlight
