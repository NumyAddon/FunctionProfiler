--- @class FP_MethodData
--- @field owner string
--- @field name string
--- @field buffer FP_BufferContainer

--- @alias FP_EntryIteratorState { bucketIndex = number?, initialIndex = number? }

--- @class FP_Bucket
--- @field tickMap table<number, number> # tickIndex -> timestamp
--- @field entries table<number, FP_BufferSquashedEntry> # tickIndex -> squashedEntry
--- @field curTickIndex number

--- @class FP_BufferSquashedEntry
--- @field totalTime number
--- @field worstTime number
--- @field totalMem number
--- @field worstMem number
--- @field entryCount number

--- @class FP_ElementData
--- @field entries number # total number of calls
--- @field tickCount number # total number of frames/ticks in the data set
--- @field owner string
--- @field name string
--- @field fullName string # owner + name, to allow easy sorting
--- @field callsPerTick number
--- @field totalTime number
--- @field maxCallTime number
--- @field latestCallTime number
--- @field averageCallTime number
--- @field maxTickTime number # longest total time in 1 frame/tick
--- @field averageTickTime number # average total time in 1 frame/tick
--- @field totalMem number
--- @field maxCallMemory number
--- @field latestCallMemory number
--- @field averageCallMemory number

--- @class FP_ColumnInfo.Column
--- @field ID FP_HeaderID
--- @field order number
--- @field justifyLeft boolean? # defaults to false
--- @field title string
--- @field width number
--- @field textFormatter (fun(number): string)|(fun(string): string)
--- @field textFunc nil|fun(FP_ElementData): string|number # either textKey or textFunc must be defined
--- @field textKey nil|string # either textKey or textFunc must be defined
--- @field tooltip nil|string
--- @field sortMethods {[-1]: fun(FP_ElementData, FP_ElementData): boolean, [1]: fun(FP_ElementData, FP_ElementData): boolean}
