-- PZ-style loader smoke test for the workshop build.
-- Run after syncing to catch missing debug/package or path issues before launching the game.

local function join(...)
	return table.concat({ ... }, ";")
end

-- Default to the synced workshop tree. Override with PZ_LUA_PATH to point elsewhere.
local default_path = join(
	"./Contents/mods/WorldObserver/42/media/lua/shared/?.lua",
	"./Contents/mods/WorldObserver/42/media/lua/shared/?/init.lua",
	"?.lua",
	"?.lua",
	";;"
)

local lua_path = os.getenv("PZ_LUA_PATH") or default_path
if package and package.path then
	package.path = lua_path
end

local modules = {}
if #arg > 0 then
	for i = 1, #arg do
		table.insert(modules, arg[i])
	end
else
	modules = { "WorldObserver", "LQR", "reactivex" }
end

local function run_modules()
	local loaded = {}
	for _, m in ipairs(modules) do
		local ok, result = pcall(require, m)
		if not ok then
			error(("require('%s') failed: %s"):format(m, result), 0)
		end
		loaded[m] = result
	end
	return loaded
end

local function module_list(loaded)
	local keys = {}
	for k in pairs(loaded or {}) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	return table.concat(keys, ",")
end

local function exercise_modules(loaded)
	local rx = loaded.reactivex
	if rx then
		local acc = {}
		rx.Observable.fromTable({ 1, 2 }):map(function(x)
			return x + 1
		end):subscribe(function(x)
			acc[#acc + 1] = x
		end)
		assert(acc[1] == 2 and acc[2] == 3, "reactivex pipeline failed")

		if rx.scheduler and rx.scheduler.reset then
			rx.scheduler.reset(0)
			rx.scheduler.schedule(function() end, 0)
			rx.scheduler.start(0, 1)
		end
	end

	local LQR = loaded.LQR
	if LQR and rx then
		local rows = {}
		local ok, err = pcall(function()
			local source = LQR.observableFromTable("SmokeRow", { { id = 1, n = 1 }, { id = 2, n = 2 } })
			LQR.Query.from(source, "SmokeRow")
				:where(function(row)
					return row.SmokeRow and row.SmokeRow.n ~= nil
				end)
				:into(rows)
				:subscribe()
		end)
		if not ok then
			error(string.format("LQR pipeline failed - query error (%s) modules[%s]", tostring(err), module_list(loaded)), 0)
		end
		if #rows ~= 2 then
			error(string.format("LQR pipeline failed - got %d rows (expected 2) modules[%s]", #rows, module_list(loaded)), 0)
		end
	end

	local WorldObserver = loaded.WorldObserver
	if WorldObserver then
		assert(type(WorldObserver) == "table", "WorldObserver did not return a table")
		assert(WorldObserver.observations ~= nil, "WorldObserver missing observations surface")
	end
end

local stdout = io and io.stdout or nil
local stderr = io and io.stderr or nil

local function write_out(handle, msg)
	if handle and handle.write then
		handle:write(msg)
	else
		print(msg)
	end
end

local function probe(label, setup)
	local old_debug = _G.debug
	local old_package = package
	local old_os = os
	local old_io = io

	local ok, err = pcall(function()
		setup()
		local loaded = run_modules()
		exercise_modules(loaded)
	end)

	_G.debug = old_debug
	package = old_package
	os = old_os
	io = old_io

	if ok then
		write_out(stdout, ("[pass] %s\n"):format(label))
		return true
	else
		write_out(stderr, ("[fail] %s: %s\n"):format(label, tostring(err)))
		return false
	end
end

local all_ok = true

-- Probe 1: debug missing (as in PZ runtime).
all_ok = probe("no-debug", function()
	_G.debug = nil
end) and all_ok

-- Probe 2: package present but minimal (guards package.loaded accesses).
all_ok = probe("package-minimal", function()
	_G.debug = nil
	local original = package or {}
	package = {
		path = original.path,
		cpath = original.cpath,
		config = original.config,
		searchers = original.searchers or original.loaders,
		preload = original.preload,
		loaded = {},
	}
end) and all_ok

-- Probe 3: package missing entirely (simulates stricter hosts).
all_ok = probe("package-nil", function()
	_G.debug = nil
	package = nil
end) and all_ok

-- Probe 4: io missing (simulate hosts without io.* helpers).
all_ok = probe("io-nil", function()
	_G.debug = nil
	package = nil
	io = nil
end) and all_ok

-- Probe 5: package locked down (no searchers/path; only our injected loaders allowed).
all_ok = probe("package-locked", function()
	_G.debug = nil
	package = {
		path = "",
		cpath = "",
		config = "",
		searchers = {},
		loaders = {},
		preload = {},
		loaded = {},
	}
end) and all_ok

-- Probe 6: os missing (simulate runtimes without os.*).
all_ok = probe("os-nil", function()
	_G.debug = nil
	package = nil
	io = nil
	os = nil
end) and all_ok

if not all_ok then
	if os and os.exit then
		os.exit(1)
	end
end
