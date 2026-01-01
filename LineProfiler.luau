local LineProfiler = {};

type ProfileEnvironment = {
	Hits : {
		[number] : number
	},
	TimeSpent : {
		[number] : number
	},
	LastProfiled : number,
}

type FakeValue<T> = T & {
	_RealValue : T,
	_Cache : {FakeValue<any>},
}

local function RecordLine(ProfileEnvironment: ProfileEnvironment)
	local ThisLine = debug.info(3, "l")
	local Delta = os.clock() - ProfileEnvironment.LastProfiled
	ProfileEnvironment.Hits[ThisLine] = (ProfileEnvironment.Hits[ThisLine] or 0) + 1
	ProfileEnvironment.TimeSpent[ThisLine] = (ProfileEnvironment.TimeSpent[ThisLine] or 0) + Delta
end

local function MakeReal(FakeVal, Seen)
	Seen = Seen or {}

	-- Handle primitives and nil
	if type(FakeVal) ~= "table" then
		return FakeVal
	end

	-- Check if we've already processed this table (cycle detection)
	if Seen[FakeVal] then
		return Seen[FakeVal]
	end

	-- Check if it's a FakeValue wrapper
	local isFakeValue = rawget(FakeVal, "_RealValue") ~= nil
	local sourceTable = isFakeValue and rawget(FakeVal, "_RealValue") or FakeVal

	-- Handle non-table wrapped values
	if isFakeValue and type(sourceTable) ~= "table" then
		return sourceTable
	end

	-- Create a copy and register it immediately (before recursion) to handle cycles
	local Copy = {}
	Seen[FakeVal] = Copy

	-- If it's a wrapped table, also mark the real value as seen pointing to same copy
	if isFakeValue then
		Seen[sourceTable] = Copy
	end

	-- Copy metatable if present (but not for FakeValue wrappers)
	if not isFakeValue then
		local mt = getmetatable(sourceTable)
		if mt then
			setmetatable(Copy, mt)
		end
	end

	-- Recursively copy all key-value pairs
	for Key, Value in sourceTable do
		-- Recursively unwrap both keys and values
		local realKey = MakeReal(Key, Seen)
		local realValue = MakeReal(Value, Seen)
		Copy[realKey] = realValue
	end

	return Copy
end

function LineProfiler.ReplaceValue<T>(ProfileEnvironment: ProfileEnvironment, RealValue: T, Forced): FakeValue<T>
	-- Handle primitives and nil directly
	local valueType = type(RealValue)
	if not Forced then
		if valueType == "nil" or valueType == "boolean" or valueType == "number" or valueType == "string"  then
			return RealValue
		end
	end
	

	-- If already wrapped, return as-is
	if type(RealValue) == "table" and rawget(RealValue, "_RealValue") then
		return RealValue
	end
	
	return setmetatable({_RealValue = RealValue, _Cache = {}}, {
		__index = function(self, Index)
			RecordLine(ProfileEnvironment)
			
			if Index == "_dbgIndex" then
				return function(index)
					return RealValue[index]
				end
			end
			
			local RealValue = self._RealValue

			if not self._Cache[Index] then
				local realResult = RealValue[Index]
				self._Cache[Index] = LineProfiler.ReplaceValue(ProfileEnvironment, realResult)
			end

			return self._Cache[Index]
		end,

		__newindex = function(self, Index, Value)
			RecordLine(ProfileEnvironment)
			local RealValue = self._RealValue

			-- Unwrap if Value is a FakeValue
			local realValue = Value
			if type(Value) == "table" and rawget(Value, "_RealValue") then
				realValue = Value._RealValue
			end

			RealValue[Index] = realValue

			-- Invalidate cache for this index
			self._Cache[Index] = nil
		end,

		__call = function(self, ...)
			RecordLine(ProfileEnvironment)
			local RealValue = self._RealValue

			-- Unwrap arguments
			local args = {...}
			for i = 1, select("#", ...) do
				args[i] = MakeReal(args[i])
				
			end
			
			-- Call and wrap results
			local results = {RealValue(table.unpack(args, 1, select("#", ...)))}
			for i = 1, #results do
				results[i] = LineProfiler.ReplaceValue(ProfileEnvironment, results[i])
			end

			return table.unpack(results, 1, #results)
		end,

		--__tostring = function(self)
		--	RecordLine(ProfileEnvironment)
		--	return tostring(self._RealValue)
		--end,

		__concat = function(left, right)
			RecordLine(ProfileEnvironment)

			-- Unwrap both sides
			local leftReal = left
			local rightReal = right
			if type(left) == "table" and rawget(left, "_RealValue") then
				leftReal = left._RealValue
			end
			if type(right) == "table" and rawget(right, "_RealValue") then
				rightReal = right._RealValue
			end

			local result = leftReal .. rightReal
			return LineProfiler.ReplaceValue(ProfileEnvironment, result)
		end,

		__unm = function(self)
			RecordLine(ProfileEnvironment)
			local result = -self._RealValue
			return LineProfiler.ReplaceValue(ProfileEnvironment, result)
		end,

		__add = function(left, right)
			RecordLine(ProfileEnvironment)
			local leftReal = type(left) == "table" and rawget(left, "_RealValue") or left
			local rightReal = type(right) == "table" and rawget(right, "_RealValue") or right
			local result = leftReal + rightReal
			return LineProfiler.ReplaceValue(ProfileEnvironment, result)
		end,

		__sub = function(left, right)
			RecordLine(ProfileEnvironment)
			local leftReal = type(left) == "table" and rawget(left, "_RealValue") or left
			local rightReal = type(right) == "table" and rawget(right, "_RealValue") or right
			local result = leftReal - rightReal
			return LineProfiler.ReplaceValue(ProfileEnvironment, result)
		end,

		__mul = function(left, right)
			RecordLine(ProfileEnvironment)
			local leftReal = type(left) == "table" and rawget(left, "_RealValue") or left
			local rightReal = type(right) == "table" and rawget(right, "_RealValue") or right
			local result = leftReal * rightReal
			return LineProfiler.ReplaceValue(ProfileEnvironment, result)
		end,

		__div = function(left, right)
			RecordLine(ProfileEnvironment)
			local leftReal = type(left) == "table" and rawget(left, "_RealValue") or left
			local rightReal = type(right) == "table" and rawget(right, "_RealValue") or right
			local result = leftReal / rightReal
			return LineProfiler.ReplaceValue(ProfileEnvironment, result)
		end,

		__mod = function(left, right)
			RecordLine(ProfileEnvironment)
			local leftReal = type(left) == "table" and rawget(left, "_RealValue") or left
			local rightReal = type(right) == "table" and rawget(right, "_RealValue") or right
			local result = leftReal % rightReal
			return LineProfiler.ReplaceValue(ProfileEnvironment, result)
		end,

		__pow = function(left, right)
			RecordLine(ProfileEnvironment)
			local leftReal = type(left) == "table" and rawget(left, "_RealValue") or left
			local rightReal = type(right) == "table" and rawget(right, "_RealValue") or right
			local result = leftReal ^ rightReal
			return LineProfiler.ReplaceValue(ProfileEnvironment, result)
		end,

		__eq = function(left, right)
			RecordLine(ProfileEnvironment)
			local leftReal = type(left) == "table" and rawget(left, "_RealValue") or left
			local rightReal = type(right) == "table" and rawget(right, "_RealValue") or right
			return leftReal == rightReal
		end,

		__lt = function(left, right)
			RecordLine(ProfileEnvironment)
			local leftReal = type(left) == "table" and rawget(left, "_RealValue") or left
			local rightReal = type(right) == "table" and rawget(right, "_RealValue") or right
			return leftReal < rightReal
		end,

		__le = function(left, right)
			RecordLine(ProfileEnvironment)
			local leftReal = type(left) == "table" and rawget(left, "_RealValue") or left
			local rightReal = type(right) == "table" and rawget(right, "_RealValue") or right
			return leftReal <= rightReal
		end,

		__len = function(self)
			RecordLine(ProfileEnvironment)
			return #self._RealValue
		end,

		__iter = function(self)
			RecordLine(ProfileEnvironment)
			local RealValue = self._RealValue
			local Iter = RealValue
			local State, Index
			
			if typeof(RealValue) == "table" then
				Iter, State, Index = pairs(self._RealValue)
			end

			-- Wrap the iterator function
			return function(s, i)
				RecordLine(ProfileEnvironment)
				local key, value = Iter(s, i)
				if key ~= nil then
					return key, LineProfiler.ReplaceValue(ProfileEnvironment, value)
				end
				return nil, nil
			end, State, Index
		end,

		__namecall = function(self, ...)
			RecordLine(ProfileEnvironment)
			local RealValue = self._RealValue
			local method = getnamecallmethod()

			-- Unwrap arguments
			local args = {...}
			for i = 1, select("#", ...) do
				if type(args[i]) == "table" and rawget(args[i], "_RealValue") then
					args[i] = MakeReal(args[i])--._RealValue
				end
			end

			-- Call method and wrap results
			local results = {RealValue[method](RealValue, table.unpack(args, 1, select("#", ...)))}
			for i = 1, #results do
				results[i] = LineProfiler.ReplaceValue(ProfileEnvironment, results[i])
			end

			return table.unpack(results, 1, #results)
		end,

		__metatable = "Locked"
	})
end

function LineProfiler.ProfileFunction<T>(fn : T) : T
	local fenv = getfenv(fn)
	return function(...)

		local ProfileEnvironment = {Hits = {}, TimeSpent = {}, LastProfiled = os.clock()}
		local FnValue = LineProfiler.ReplaceValue(ProfileEnvironment, fenv)
		rawset(FnValue, "__incl", function(v)
			return LineProfiler.ReplaceValue(ProfileEnvironment, v, true)
		end)
		setfenv(fn, FnValue)
		
		
		
		local Converted = {}
		for i, v in {...} do
			Converted[i] = LineProfiler.ReplaceValue(ProfileEnvironment, v)
		end
		local results = fn(table.unpack(Converted))
		print(ProfileEnvironment)
		return results
	end
end

return LineProfiler