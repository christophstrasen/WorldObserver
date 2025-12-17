-- interest_effective.lua -- shared helper to resolve "effective interest" for a fact family.
local InterestPolicy = require("WorldObserver/interest/policy")
local Log = require("LQR/util/log").withTag("WO.FACTS.interest")

local moduleName = ...
local InterestEffective = {}
if type(moduleName) == "string" then
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		InterestEffective = loaded
	else
		package.loaded[moduleName] = InterestEffective
	end
end
InterestEffective._internal = InterestEffective._internal or {}

--- Resolve merged interest for `interestType` and pass it through the adaptive policy.
--- Stores state in `state._interestPolicyState` and caches the effective settings in `state._effectiveInterestByType`.
--- @param state table
--- @param interestRegistry table|nil
--- @param runtime table|nil
--- @param interestType string
--- @param opts table|nil
--- @return table|nil effective
if InterestEffective.ensure == nil then
	function InterestEffective.ensure(state, interestRegistry, runtime, interestType, opts)
		state = state or {}
		opts = opts or {}
		local log = opts.log or Log

		local merged = nil
		if interestRegistry and interestRegistry.effective then
			local ok, res = pcall(function()
				return interestRegistry:effective(interestType)
			end)
			if ok then
				merged = res
			else
				log:warn("[interest] failed to merge interest for %s: %s", tostring(interestType), tostring(res))
				return nil
			end
		end

		if not merged then
			if opts.allowDefault then
				merged = opts.defaultInterest
				if not merged then
					return nil
				end
				state._interestWarnings = state._interestWarnings or {}
				if not state._interestWarnings[interestType] then
					log:info("[interest] using default interest bands for %s (no active leases)", tostring(interestType))
					state._interestWarnings[interestType] = true
				end
			else
				return nil
			end
		end

		local runtimeStatus = runtime and runtime.status_get and runtime:status_get() or nil
		state._interestPolicyState = state._interestPolicyState or {}
		local policyState = state._interestPolicyState[interestType]

		local policyOpts = {
			label = opts.label or tostring(interestType),
			signals = opts.signals,
		}

		local effective
		policyState, effective = InterestPolicy.update(policyState, merged, runtimeStatus, policyOpts)
		state._interestPolicyState[interestType] = policyState

		state._effectiveInterestByType = state._effectiveInterestByType or {}
		state._effectiveInterestByType[interestType] = effective
		return effective
	end
end

return InterestEffective
