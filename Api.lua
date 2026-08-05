--- @class FP_API
local ns = select(2, ...);

local Buffer = ns.Buffer;

--- @class NumyFunctionProfiler
local API = {};
ns.API = API;
_G.NumyFunctionProfiler = API;

local NAME_FORMAT = "|cfff8f8f2%s:|r|cff66d9ef%s|r"

--- @param owner string
--- @param obj string?
--- @param method string
--- @param time number
--- @param mem number
--- @private
function API:Log(owner, obj, method, time, mem)
    local name = obj and NAME_FORMAT:format(obj, method) or method
    local id = owner..name
    local buffer = Buffer:GetContainer(id)
    buffer:Insert(time, mem)

    if not ns.FP.data[id] then
        ns.FP.data[id] = {
            owner = owner,
            name = name,
            buffer = buffer,
        }
    end
end

--- @private
API.WRAPPERS = {}

--- @generic T: fun
--- @param owner string
--- @param obj string?
--- @param name string
--- @param func T
--- @return T
function API:Wrap(owner, obj, name, func)
    if self.WRAPPERS[func] then return self.WRAPPERS[func] end
    local wrapper = function(...)
        if self:IsLogging() then
            local timeStart, memStart = debugprofilestop(), collectgarbage("count")
            local results = {func(...)}
            local executionTime, executionMem = debugprofilestop() - timeStart, collectgarbage("count") - memStart
            self:Log(owner, obj, name, executionTime, executionMem)

            return unpack(results)
        else
            return func(...)
        end
    end
    self.WRAPPERS[wrapper] = wrapper

    return wrapper
end

--- @param owner string
--- @param objectName string
--- @param object table
--- @param funcName string
function API:WrapInPlace(owner, objectName, object, funcName)
    assert(type(object) == 'table', "object must be a table");
    assert(type(object[funcName]) == 'function', "function not found");
    object[funcName] = self:Wrap(owner, objectName, funcName, object[funcName]);
end

--- @param owner string
--- @param currName string?
--- @param module table
--- @param maxDepth number? max recursion depth, defaults to 1
--- @param currentDepth number? current recursion depth, should not be set
function API:WrapModules(owner, currName, module, maxDepth, currentDepth)
    currentDepth = (currentDepth or 0) + 1
    if currentDepth > (maxDepth or 1) then return end
    if module.IsProtected and type(module.IsProtected) == 'function' and module:IsProtected() then return end
    for name, object in pairs(module) do
        if type(object) == 'function' then
            if (type(name) == 'string' and securecall(issecurevariable, module, name)) or name == 'SetID' then return end
            module[name] = self:Wrap(owner, currName, name, object)
        elseif type(object) == 'table' then
            local longName = currName and (currName .. "." .. tostring(name)) or tostring(name)
            self:WrapModules(owner, longName, object, maxDepth, currentDepth)
        end
    end
end

function API:IsLoaded()
    return true
end

local isLogging = false

function API:IsLogging()
    return isLogging
end

function API:EnableLogging()
    ns.FP.Display.ToggleButton:SetText("Disable")
    ns.FP.Display.ToggleButton.padding = 40
    DynamicResizeButton_Resize(ns.FP.Display.ToggleButton)

    isLogging = true

    if ns.FP.purgeTicker then
        ns.FP.purgeTicker:Cancel()
    end

    ns.FP.purgeTicker = C_Timer.NewTicker(5, function() ns.FP:PurgeOldData() end)

    ns.FP.Display.ScrollBox:Flush()
    ns.FP:UpdateMinimapIcon()
end

function API:DisableLogging()
    ns.FP.Display.ToggleButton:SetText("Enable")
    ns.FP.Display.ToggleButton.padding = 40
    DynamicResizeButton_Resize(ns.FP.Display.ToggleButton)

    isLogging = false

    if ns.FP.purgeTicker then
        ns.FP.purgeTicker:Cancel()
    end

    ns.FP.data = {}
    ns.FP.dataProvider = nil
    ns.FP:UpdateMinimapIcon()
    ns.Buffer:Reset()
end

function API:ToggleFrame()
    ns.FP.Display:SetShown(not ns.FP.Display:IsShown())
end