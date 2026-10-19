--!strict

local TableUtil = {}

function TableUtil.copy<T>(t: {T}): {T}
	local copy = table.create(#t)
	for i, v in t do
		copy[i] = v
	end
	return copy
end

function TableUtil.deepCopy<T>(t: T): T
	local copy = {}
	for k, v in t :: any do
		copy[k] = if type(v) == "table" then TableUtil.deepCopy(v) else v
	end
	return copy :: T
end

function TableUtil.shuffle<T>(t: {T}): {T}
	for i = #t, 2, -1 do
		local j = math.random(i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

function TableUtil.sample<T>(t: {T}): T
	return t[math.random(#t)]
end

function TableUtil.find<T>(t: {T}, predicate: (T) -> boolean): T?
	for _, v in t do
		if predicate(v) then return v end
	end
	return nil
end

function TableUtil.filter<T>(t: {T}, predicate: (T) -> boolean): {T}
	local result = {}
	for _, v in t do
		if predicate(v) then
			table.insert(result, v)
		end
	end
	return result
end

function TableUtil.map<T, U>(t: {T}, transform: (T) -> U): {U}
	local result = table.create(#t)
	for i, v in t do
		result[i] = transform(v)
	end
	return result
end

function TableUtil.reduce<T>(t: {T}, reducer: (T, T) -> T, initial: T?): T
	local acc = initial or t[1]
	local start = if initial ~= nil then 1 else 2
	for i = start, #t do
		acc = reducer(acc, t[i])
	end
	return acc
end

function TableUtil.keys<K, V>(t: {[K]: V}): {K}
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	return keys
end

function TableUtil.values<K, V>(t: {[K]: V}): {V}
	local vals = {}
	for _, v in t do
		table.insert(vals, v)
	end
	return vals
end

function TableUtil.contains<T>(t: {T}, value: T): boolean
	for _, v in t do
		if v == value then return true end
	end
	return false
end

function TableUtil.count<T>(t: {T}, predicate: ((T) -> boolean)?): number
	if not predicate then return #t end
	local n = 0
	for _, v in t do
		if predicate(v) then n += 1 end
	end
	return n
end

return TableUtil