-- observations/wo_meta.lua -- compute and attach WoMeta keys for observation emissions.
local moduleName = ...
local WoMeta = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		WoMeta = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = WoMeta
	end
end
WoMeta._internal = WoMeta._internal or {}

local function listSortedKeys(tbl)
	local keys = {}
	local count = 0
	for key in pairs(tbl or {}) do
		if type(key) == "string" and key ~= "" then
			count = count + 1
			keys[count] = key
		end
	end
	table.sort(keys)
	return keys, count
end

local function buildSegment(familyName, recordKey)
	if type(familyName) ~= "string" or familyName == "" then
		return nil
	end
	if type(recordKey) ~= "string" or recordKey == "" then
		return nil
	end
	return "#" .. familyName .. "(" .. recordKey .. ")"
end

local function computeKeyFromJoinResult(observation)
	if type(observation) ~= "table" then
		return nil, "not_table"
	end
	local rxMeta = observation.RxMeta
	local schemaMap = type(rxMeta) == "table" and rxMeta.schemaMap or nil
	if type(schemaMap) ~= "table" then
		return nil, "missing_schema_map"
	end
	local familyNames, familyCount = listSortedKeys(schemaMap)
	if familyCount == 0 then
		return nil, "missing_schema_map"
	end

	local segments = {}
	local segmentCount = 0
	for i = 1, familyCount do
		local familyName = familyNames[i]
		local record = observation[familyName]
		if record == nil then
			-- Left joins can omit families; we skip nils on purpose.
		elseif type(record) == "table" then
			local recordKey = record.woKey
			if type(recordKey) ~= "string" or recordKey == "" then
				return nil, "missing_record_woKey"
			end
			local segment = buildSegment(familyName, recordKey)
			if not segment then
				return nil, "bad_segment"
			end
			segmentCount = segmentCount + 1
			segments[segmentCount] = segment
		else
			return nil, "bad_record"
		end
	end
	if segmentCount == 0 then
		return nil, "no_segments"
	end
	return table.concat(segments), nil
end

local function computeKeyFromRecord(record)
	if type(record) ~= "table" then
		return nil, "not_table"
	end
	local rxMeta = record.RxMeta
	local schema = type(rxMeta) == "table" and rxMeta.schema or nil
	if type(schema) ~= "string" or schema == "" then
		return nil, "missing_schema"
	end
	local recordKey = record.woKey
	if type(recordKey) ~= "string" or recordKey == "" then
		return nil, "missing_record_woKey"
	end
	local segment = buildSegment(schema, recordKey)
	if not segment then
		return nil, "bad_segment"
	end
	return segment, nil
end

local function normalizeGroupKey(groupKey)
	if type(groupKey) == "string" and groupKey ~= "" then
		return groupKey
	end
	if type(groupKey) == "number" then
		return tostring(groupKey)
	end
	return nil
end

local function computeKeyFromGroupAggregate(observation)
	if type(observation) ~= "table" then
		return nil, "not_table"
	end
	local rxMeta = observation.RxMeta
	if type(rxMeta) ~= "table" then
		return nil, "missing_rxmeta"
	end
	local groupName = rxMeta.groupName or rxMeta.schema
	if type(groupName) ~= "string" or groupName == "" then
		return nil, "missing_group_name"
	end
	local groupKey = normalizeGroupKey(rxMeta.groupKey)
	if groupKey == nil then
		return nil, "missing_group_key"
	end
	local segment = buildSegment(groupName, groupKey)
	if not segment then
		return nil, "bad_segment"
	end
	return segment, nil
end

local function listFamiliesFromObservation(observation)
	local rxMeta = type(observation) == "table" and observation.RxMeta or nil
	local schemaMap = type(rxMeta) == "table" and rxMeta.schemaMap or nil
	if type(schemaMap) == "table" then
		local names = {}
		local count = 0
		for key in pairs(schemaMap) do
			if type(key) == "string" and key ~= "" and not key:match("^_groupBy:") then
				count = count + 1
				names[count] = key
			end
		end
		table.sort(names)
		return names, count
	end

	local names = {}
	local count = 0
	for key, value in pairs(observation or {}) do
		if key ~= "RxMeta" and key ~= "WoMeta" and type(key) == "string" and type(value) == "table" then
			if key:match("^_groupBy:") then
				-- Skip synthetic group-by rows for group_enriched keying.
			else
			local hasSchema = type(value.RxMeta) == "table" and type(value.RxMeta.schema) == "string"
			if type(value.woKey) == "string" or hasSchema then
				count = count + 1
				names[count] = key
			end
			end
		end
	end
	table.sort(names)
	return names, count
end

local function computeKeyFromGroupEnriched(observation)
	if type(observation) ~= "table" then
		return nil, "not_table"
	end
	local familyNames, familyCount = listFamiliesFromObservation(observation)
	if familyCount == 0 then
		return nil, "no_family_keys"
	end

	local segments = {}
	local segmentCount = 0
	for i = 1, familyCount do
		local familyName = familyNames[i]
		local record = observation[familyName]
		if record == nil then
			-- Allow missing families (left join), same as join_result.
		elseif type(record) == "table" then
			local recordKey = record.woKey
			if type(recordKey) ~= "string" or recordKey == "" then
				return nil, "missing_record_woKey"
			end
			local segment = buildSegment(familyName, recordKey)
			if not segment then
				return nil, "bad_segment"
			end
			segmentCount = segmentCount + 1
			segments[segmentCount] = segment
		else
			return nil, "bad_record"
		end
	end
	if segmentCount == 0 then
		return nil, "no_segments"
	end
	return table.concat(segments), nil
end

local function attachWoMeta(observation)
	if type(observation) ~= "table" then
		return false, "not_table"
	end

	local rxMeta = observation.RxMeta
	local shape = type(rxMeta) == "table" and rxMeta.shape or nil
	local key, reason
	if shape == "join_result" then
		key, reason = computeKeyFromJoinResult(observation)
	elseif shape == "group_aggregate" then
		key, reason = computeKeyFromGroupAggregate(observation)
	elseif shape == "group_enriched" then
		key, reason = computeKeyFromGroupEnriched(observation)
	elseif shape == "record" then
		key, reason = computeKeyFromRecord(observation)
	else
		key, reason = computeKeyFromRecord(observation)
		if not key and reason == "missing_schema" then
			reason = "unknown_shape"
		end
	end

	if not key then
		return false, reason or "missing_key"
	end

	observation.WoMeta = observation.WoMeta or {}
	observation.WoMeta.key = key
	return true, nil
end

-- Patch seam: define only when nil so mods can override and reloads don't clobber patches.
WoMeta.buildSegment = WoMeta.buildSegment or buildSegment
WoMeta.computeKeyFromJoinResult = WoMeta.computeKeyFromJoinResult or computeKeyFromJoinResult
WoMeta.computeKeyFromRecord = WoMeta.computeKeyFromRecord or computeKeyFromRecord
WoMeta.computeKeyFromGroupAggregate = WoMeta.computeKeyFromGroupAggregate or computeKeyFromGroupAggregate
WoMeta.computeKeyFromGroupEnriched = WoMeta.computeKeyFromGroupEnriched or computeKeyFromGroupEnriched
WoMeta.attachWoMeta = WoMeta.attachWoMeta or attachWoMeta

WoMeta._internal.listSortedKeys = WoMeta._internal.listSortedKeys or listSortedKeys
WoMeta._internal.listFamiliesFromObservation = WoMeta._internal.listFamiliesFromObservation or listFamiliesFromObservation
WoMeta._internal.normalizeGroupKey = WoMeta._internal.normalizeGroupKey or normalizeGroupKey

return WoMeta
