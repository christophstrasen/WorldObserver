local Log = require("LQR/util/log").withTag("WO.HELPER.highlight")
local Time = require("WorldObserver/helpers/time")

local moduleName = ...
local Highlight = {}
if type(moduleName) == "string" then
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Highlight = loaded
	else
		package.loaded[moduleName] = Highlight
	end
end

Highlight._state = Highlight._state or {
	active = {},
	activeCount = 0,
	onTickFn = nil,
	onTickRegistered = false,
}

local DEFAULT_COLOR = { 0.2, 0.5, 1.0 }
local DEFAULT_ALPHA = 0.7
local DEFAULT_DURATION_MS = 1000

local function nowMillis()
	return Time.gameMillis()
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
	if type(target.setHighlightColor) == "function" then
		pcall(target.setHighlightColor, target, color[1], color[2], color[3], a)
	end
	callSetHighlighted(target, true, entry.blink)
end

local function clearHighlight(entry)
	local target = entry and entry.target
	if target == nil then
		return
	end
	callSetHighlighted(target, false, entry.blink)
end

local function maybeDetachTick(state)
	if not state.onTickRegistered then
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
	state.onTickRegistered = false
	state.onTickFn = nil
end

local function tickOnce(state)
	if state.activeCount <= 0 then
		maybeDetachTick(state)
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
		maybeDetachTick(state)
	end
end

local function ensureTickHook(state)
	if state.onTickRegistered then
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
	state.onTickRegistered = true
	tick.Add(onTick)
	return true
end

-- Patch seam: only define when nil so mods can override by reassigning Highlight.highlightTarget.
if Highlight.highlightTarget == nil then
	--- Highlight an object (e.g. IsoObject floor) that supports setHighlightColor/setHighlighted.
	--- @param target any
	--- @param opts table|nil { durationMs?, color?, alpha?, blink? }
	--- @return table|nil handle { stop = function() end } or nil on failure
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

		local startedMs = nowMillis() or 0
		local entry = {
			target = target,
			startedMs = startedMs,
			durationMs = durationMs,
			color = color,
			startAlpha = startAlpha,
			blink = blink,
		}

		local existing = state.active[target]
		state.active[target] = entry
		if not existing then
			state.activeCount = (state.activeCount or 0) + 1
		end

		applyHighlight(entry, startAlpha)
		ensureTickHook(state)

		return {
			stop = function()
				local tracked = state.active[target]
				if tracked then
					clearHighlight(tracked)
					state.active[target] = nil
					state.activeCount = math.max(0, (state.activeCount or 1) - 1)
				end
				if state.activeCount <= 0 then
					maybeDetachTick(state)
				end
			end,
		}
	end
end

return Highlight
