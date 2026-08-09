local ns = select(2, ...);
local tInsert = table.insert;
local tRemoveMulti = table.removemulti

--- @class FP_Buffer
local Buffer = {
    --- @type FP_BufferContainer[]
    containers = {},
    pendingSquash = false,
    curTickIndex = 1,
    tickMap = { [1] = GetTime() },
};
ns.Buffer = Buffer;

local BUCKET_CUTOFF = 2000; -- rather arbitrary number, but interestingly, the lower your fps, the less often actual work will be performed to purge old data ^^

local frame = CreateFrame("Frame");
local doTick = function() Buffer:Tick(); end;
frame:SetScript("OnUpdate", nil);

--- @class FP_BufferContainer
local BufferContainerMixin = {};

--- @return FP_BufferContainer
function Buffer:GetContainer(owner)
    if not self.containers[owner] then
        local container = CreateAndInitFromMixin(BufferContainerMixin);
        self.containers[owner] = container;
    end

    return self.containers[owner];
end

function Buffer:Tick()
    self.curTickIndex = self.curTickIndex + 1;
    self.tickMap[self.curTickIndex] = GetTime();
    if not Buffer.pendingSquash then
        Buffer.pendingSquash = true;
        C_Timer.After(1, function() Buffer:Squash(); end);
    end
end

function Buffer:Squash()
    self.pendingSquash = false;
    frame:SetScript("OnUpdate", nil);
    for _, container in pairs(self.containers) do
        container:Squash();
    end
    self.curTickIndex = 1;
    self.tickMap = { [1] = GetTime() };
end

function Buffer:Reset()
    self.containers = {}
end

----------------------------------------------------------
function BufferContainerMixin:Init()
    --- @type FP_BufferSquashedEntry[]
    self.entries = {};
    --- @type {time: number, mem: number, tick: number}[]
    self.buffer = {};
    --- @type FP_Bucket[]
    self.buckets = {};
    self:InitNewBucket();
    self.pending = false;
end

function BufferContainerMixin:Insert(time, mem)
    frame:SetScript("OnUpdate", doTick);
    self.pending = true;
    tInsert(self.buffer, { time = time, mem = mem, tick = Buffer.curTickIndex });
end

function BufferContainerMixin:InitNewBucket()
    --- @type FP_Bucket
    local lastBucket = { curTickIndex = 0, tickMap = {}, entries = {} };

    tInsert(self.buckets, lastBucket);
    self.lastBucket = lastBucket;

    return lastBucket;
end

--- @param buckets FP_Bucket[]
--- @param state FP_EntryIteratorState
--- @return (FP_EntryIteratorState state, FP_BufferSquashedEntry! entry) | (nil)
local function iter(buckets, state)
    if not state.initialIndex or not state.initialIndex then return end
    state.initialIndex = state.initialIndex + 1;
    local bucket = buckets[state.bucketIndex];
    if not bucket then return end
    local entry = bucket.entries[state.initialIndex];
    if entry then
        return state, entry
    end
    state.bucketIndex = state.bucketIndex + 1;
    state.initialIndex = 1;
    bucket = buckets[state.bucketIndex];
    if not bucket then return end
    entry = bucket.entries[state.initialIndex];
    if not entry then return end

    return state, entry
end

--- @param cutoff number
--- @return fun(table: FP_Bucket[], state?: FP_EntryIteratorState): FP_EntryIteratorState, FP_BufferSquashedEntry!
--- @return FP_Bucket[]
--- @return FP_EntryIteratorState
function BufferContainerMixin:IterateEntries(cutoff)
    local state = { bucketIndex = nil, initialIndex = nil };
    for bucketIndex, bucket in ipairs(self.buckets) do
        if not state.bucketIndex then
            if bucket.tickMap[bucket.curTickIndex] and bucket.tickMap[bucket.curTickIndex] > cutoff then
                for tickIndex, timestamp in pairs(bucket.tickMap) do
                    if timestamp > cutoff then
                        state.bucketIndex = bucketIndex;
                        state.initialIndex = tickIndex - 1;
                        break;
                    end
                end
            end
        end
    end

    return iter, self.buckets, state;
end

function BufferContainerMixin:Purge(cutoff)
    if self.lastBucket.curTickIndex > BUCKET_CUTOFF then
        self:InitNewBucket();
    end

    local buckets = self.buckets
    local firstBucket = buckets[1];
    if not buckets[2] or not firstBucket.tickMap[1] then
        return;
    end

    if firstBucket.tickMap[1] > cutoff then
        return;
    end

    local to;
    for i, bucket in ipairs(buckets) do
        if bucket.tickMap[1] and bucket.tickMap[1] > cutoff then
            to = i - 1;
            break;
        end
    end

    if to and to > 1 then
        tRemoveMulti(buckets, 1, to);
    end
end

function BufferContainerMixin:Squash()
    if not self.pending then return; end
    local lastBucket = self.lastBucket;
    local tickIndex = nil;
    local squashed = nil;
    for _, entry in pairs(self.buffer) do
        if entry.tick ~= tickIndex then
            tickIndex = entry.tick;
            squashed = {
                totalTime = 0,
                worstTime = 0,
                totalMem = 0,
                worstMem = 0,
                entryCount = 0,
            };

            local curTickIndex = lastBucket.curTickIndex + 1;
            lastBucket.curTickIndex = curTickIndex;
            lastBucket.tickMap[curTickIndex] = Buffer.tickMap[tickIndex];
            lastBucket.entries[curTickIndex] = squashed;
        end

        squashed.entryCount = squashed.entryCount + 1;
        squashed.totalTime = squashed.totalTime + entry.time;
        squashed.totalMem = squashed.totalMem + entry.mem;
        if entry.time > squashed.worstTime then
            squashed.worstTime = entry.time;
        end
        if entry.mem > squashed.worstMem then
            squashed.worstMem = entry.mem;
        end
    end

    self.buffer = {};
    self.pending = false;
end
