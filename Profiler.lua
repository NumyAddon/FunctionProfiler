local addonName = ...
--- @class FP_API
local ns = select(2, ...);

local s_trim = string.trim
local t_insert = table.insert

local API = ns.API;

local FP = {
    --- @type table<string, FP_MethodData>
    data = {},
};
ns.FP = FP;

local MAX_DATA_RETENTION = 600;

--- @enum FP_HeaderID
local HEADER_IDS = {
    owner = "owner",
    name = "name",
    totalTime = "totalTime",
    maxCallTime = "maxCallTime",
    latestCallTime = "latestCallTime",
    averageCallTime = "averageCallTime",
    maxTickTime = "maxTickTime",
    averageTickTime = "averageTickTime",
    latestCallMemory = "latestCallMemory",
    averageCallMemory = "averageCallMemory",
    maxCallMemory = "maxCallMemory",
    totalMem = "totalMem",
    callsPerTick = "callsPerTick",
    entries = "entries",
};
local ORDER_ASC = 1;
local ORDER_DESC = -1;
local UPDATE_INTERVAL = 1;

function FP:PurgeOldData()
    local cutoff = GetTime() - MAX_DATA_RETENTION;

    for _, entry in pairs(self.data) do
        entry.buffer:Purge(cutoff);
    end
end

function FP:PrepareFilteredData()
    self.latestCallTimestamp = GetTime()
    if self.oldRawDataSize ~= #self.data or self.oldMatch ~= self.curMatch or self.oldHistoryRange ~= self.curHistoryRange or self.latestCallTimestamp - self.oldTimestamp >= UPDATE_INTERVAL then
        local filteredData = {};
        self.dataProvider = nil;
        local cutoff = self.latestCallTimestamp - self.curHistoryRange;
        local oldestEntry = self.latestCallTimestamp

        for _, rawEntry in pairs(self.data) do
            if rawEntry.name:lower():match(self.curMatch) or rawEntry.owner:lower():match(self.curMatch) then
                --- @type FP_ElementData
                local data = {
                    entries = 0,
                    tickCount = 0,
                    owner = rawEntry.owner,
                    name = rawEntry.name,
                    fullName = rawEntry.owner .. rawEntry.name,
                    callsPerTick = 0,
                    totalTime = 0,
                    maxCallTime = 0,
                    latestCallTime = 0,
                    maxTickTime = 0,
                    totalMem = 0,
                    maxCallMemory = 0,
                    latestCallMemory = 0,
                    averageCallTime = 0,
                    averageCallMemory = 0,
                    averageTickTime = 0,
                };
                local oldestEntryInBuffer = rawEntry.buffer.buckets[1].tickMap[1]
                if oldestEntryInBuffer and oldestEntryInBuffer < oldestEntry then
                    oldestEntry = oldestEntryInBuffer;
                end

                for _, entry in rawEntry.buffer:IterateEntries(cutoff) do
                    data.tickCount = data.tickCount + 1;
                    data.entries = data.entries + entry.entryCount;
                    data.totalTime = data.totalTime + entry.totalTime;
                    data.totalMem = data.totalMem + entry.totalMem;
                    if entry.worstTime > data.maxCallTime then
                        data.maxCallTime = entry.worstTime;
                    end
                    if entry.worstMem > data.maxCallMemory then
                        data.maxCallMemory = entry.worstMem;
                    end
                    if entry.totalTime > data.maxTickTime then
                        data.maxTickTime = entry.totalTime;
                    end
                    data.latestCallTime = entry.worstTime;
                    data.latestCallMemory = entry.worstMem;
                end

                if data.entries > 0 then
                    data.averageCallTime = data.totalTime / data.entries;
                    data.averageCallMemory = data.totalMem / data.entries;
                    data.averageTickTime = data.totalTime / data.tickCount;
                    data.callsPerTick = data.entries / data.tickCount;

                    t_insert(filteredData, data);
                end
            end
        end

        self.dataProvider = CreateDataProvider(filteredData);
        if self.sortComparator then
            self:SortFilteredData();
        end

        local oldestAge = math.min(self.latestCallTimestamp - oldestEntry, self.curHistoryRange);
        self.Display.TimeText:Update(oldestAge);
        self.Display.Stats:Update();

        self.oldRawDataSize = #self.data;
        self.oldMatch = self.curMatch;
        self.oldHistoryRange = self.curHistoryRange;
        self.oldTimestamp = self.latestCallTimestamp;
    end
end

function FP:SortFilteredData()
    if self.dataProvider then
        self.dataProvider:SetSortComparator(self.sortComparator)
    end
end

function FP:InitUI()
    self.dataProvider = nil;

    local msText = "|cff808080ms|r";
    local xText = "|cff808080x|r";
    local kbText = "|cff808080KB|r";
    local mbText = "|cff808080MB|r";
    local greyColorFormat = "|cff808080%s|r";
    local whiteColorFormat = "|cfff8f8f2%s|r";

    local MEMORY_FORMAT = function(val)
        if val > 1000 then
            val = val / 1000;

            return ('%.2f %s'):format(val, mbText);
        end
        return ('%.0f %s'):format(val, kbText);
    end
    local TIME_FORMAT = function(val) return (val > 0.0005 and whiteColorFormat or greyColorFormat):format(("%.3f"):format(val)) .. msText; end;
    local ROUND_TIME_FORMAT = function(val) return (val > 0.0005 and whiteColorFormat or greyColorFormat):format(val) .. msText; end;
    local FRACTIONAL_COUNTER_FORMAT = function(val) return (val > 0.05 and whiteColorFormat or greyColorFormat):format(("%.1f"):format(val)) .. xText; end;
    local COUNTER_FORMAT = function(val) return (val > 0.0005 and whiteColorFormat or greyColorFormat):format(math.ceil(val)) .. xText; end;
    local RAW_FORMAT = function(val) return val; end;
    local PERCENT_FORMAT = function(val)
        local color = val > 0.00005 and whiteColorFormat or greyColorFormat;

        return val >= 1 and color:format("100.00%") or color:format(("%.2f%%"):format(val * 100));
    end;

    --- @type table<FP_HeaderID, FP_ColumnInfo.Column>
    local COLUMN_INFO = {};
    do
        local Inf = math.huge
        local function makeSortMethods(key)
            return {
                --- @param a FP_ElementData
                --- @param b FP_ElementData
                [ORDER_ASC] = function(a, b)
                    return (a[key] ~= Inf and a[key] < b[key]) or (a[key] == b[key] and a.fullName < b.fullName);
                end,
                --- @param a FP_ElementData
                --- @param b FP_ElementData
                [ORDER_DESC] = function(a, b)
                    return (a[key] ~= Inf and a[key] > b[key]) or (a[key] == b[key] and a.fullName > b.fullName);
                end,
            };
        end
        local counter = CreateCounter();

        COLUMN_INFO[HEADER_IDS.owner] = {
            ID = HEADER_IDS.owner,
            order = counter(),
            title = "Owner",
            width = 180,
            justifyLeft = true,
            textFormatter = RAW_FORMAT,
            textKey = "owner",
            sortMethods = makeSortMethods("owner"),
        };
        COLUMN_INFO[HEADER_IDS.name] = {
            ID = HEADER_IDS.name,
            order = counter(),
            title = "Name",
            width = 384,
            justifyLeft = true,
            textFormatter = RAW_FORMAT,
            textKey = "name",
            sortMethods = makeSortMethods("name"),
        };
        COLUMN_INFO[HEADER_IDS.latestCallTime] = {
            ID = HEADER_IDS.latestCallTime,
            order = counter(),
            title = "Last Call",
            width = 76,
            textFormatter = TIME_FORMAT,
            textKey = "latestCallTime",
            sortMethods = makeSortMethods("latestCallTime"),
        };
        COLUMN_INFO[HEADER_IDS.averageCallTime] = {
            ID = HEADER_IDS.averageCallTime,
            order = counter(),
            title = "Avg/call",
            width = 76,
            textFormatter = TIME_FORMAT,
            textKey = "averageCallTime",
            sortMethods = makeSortMethods("averageCallTime"),
        };
        COLUMN_INFO[HEADER_IDS.maxCallTime] = {
            ID = HEADER_IDS.maxCallTime,
            order = counter(),
            title = "Worst call",
            width = 76,
            textFormatter = TIME_FORMAT,
            textKey = "maxCallTime",
            sortMethods = makeSortMethods("maxCallTime"),
        };
        COLUMN_INFO[HEADER_IDS.averageTickTime] = {
            ID = HEADER_IDS.averageTickTime,
            order = counter(),
            title = "Avg/tick",
            width = 76,
            textFormatter = TIME_FORMAT,
            textKey = "averageTickTime",
            sortMethods = makeSortMethods("averageTickTime"),
        };
        COLUMN_INFO[HEADER_IDS.maxTickTime] = {
            ID = HEADER_IDS.maxTickTime,
            order = counter(),
            title = "Worst tick",
            width = 76,
            textFormatter = TIME_FORMAT,
            textKey = "maxTickTime",
            sortMethods = makeSortMethods("maxTickTime"),
        };
        COLUMN_INFO[HEADER_IDS.totalTime] = {
            ID = HEADER_IDS.totalTime,
            order = counter(),
            title = "Total",
            width = 96,
            textFormatter = TIME_FORMAT,
            textKey = "totalTime",
            sortMethods = makeSortMethods("totalTime"),
        };
        COLUMN_INFO[HEADER_IDS.latestCallMemory] = {
            ID = HEADER_IDS.latestCallMemory,
            order = counter(),
            title = "Last call",
            width = 76,
            textFormatter = MEMORY_FORMAT,
            textKey = "latestCallMemory",
            sortMethods = makeSortMethods("latestCallMemory"),
        };
        COLUMN_INFO[HEADER_IDS.averageCallMemory] = {
            ID = HEADER_IDS.averageCallMemory,
            order = counter(),
            title = "Avg call",
            width = 76,
            textFormatter = MEMORY_FORMAT,
            textKey = "averageCallMemory",
            sortMethods = makeSortMethods("averageCallMemory"),
        };
        COLUMN_INFO[HEADER_IDS.callsPerTick] = {
            ID = HEADER_IDS.callsPerTick,
            order = counter(),
            title = "Calls/tick",
            width = 96,
            textFormatter = FRACTIONAL_COUNTER_FORMAT,
            tooltip = "Only includes ticks where *any* call happened",
            textKey = "callsPerTick",
            sortMethods = makeSortMethods("callsPerTick"),
        }
        COLUMN_INFO[HEADER_IDS.entries] = {
            ID = HEADER_IDS.entries,
            order = counter(),
            title = "Calls",
            width = 96,
            textFormatter = COUNTER_FORMAT,
            textKey = "entries",
            sortMethods = makeSortMethods("entries"),
        }
    end
    local ROW_HEIGHT = 20

    self.activeSort = HEADER_IDS.totalTime;
    self.activeOrder = ORDER_DESC;
    FP.sortComparator = COLUMN_INFO[FP.activeSort].sortMethods[FP.activeOrder];

    local continuousUpdate = true;

    local HISTORY_RANGES = {5, 15, 30, 60, 120, 300, 600};

    self.curHistoryRange = 30;
    self.oldHistoryRange = 0;

    self.curMatch = ".+"
    self.oldMatch = ""

    self.latestCallTimestamp = 0
    self.oldTimestamp = 0

    self.oldRawDataSize = 0


    -------------
    -- DISPLAY --
    -------------
    do
        --- @class FP_Display: ButtonFrameTemplate
        local display = CreateFrame("Frame", "FunctionProfilerFrame", UIParent, "ButtonFrameTemplate");
        FP.Display = display;
        do
            local width = 40;
            for _, info in pairs(COLUMN_INFO) do
                width = width + (info.width - 2)
            end
            display:SetSize(width, 651);
            display:SetPoint("CENTER", 0, 0);
            display:SetMovable(true);
            display:EnableMouse(true);
            display:SetToplevel(true);
            display:SetScript("OnShow", function()
                display.elapsed = UPDATE_INTERVAL

                if continuousUpdate then
                    display:SetScript("OnUpdate", display.OnUpdate)
                end
            end);
            display:SetScript("OnHide", function()
                display:SetScript("OnUpdate", nil);
            end);
            display:Hide();

            function display:OnUpdate(elapsed)
               self.elapsed = (self.elapsed or 0) + elapsed
               if self.elapsed >= UPDATE_INTERVAL then
                   FP:PrepareFilteredData()

                   local perc = self.ScrollBox:GetScrollPercentage()
                   self.ScrollBox:Flush()

                   if FP.dataProvider then
                       self.ScrollBox:SetDataProvider(FP.dataProvider)
                       self.ScrollBox:SetScrollPercentage(perc)
                   end

                   self.elapsed = 0
               end
            end

            function display:RefreshActiveColumns()
                display.activeColumns = {}
                for ID, info in pairs(COLUMN_INFO) do
                    t_insert(display.activeColumns, info)
                end
                table.sort(display.activeColumns, function(a, b) return a.order < b.order end)
            end

            display:RefreshActiveColumns()

            ButtonFrameTemplate_HidePortrait(display)

            display:SetTitle("|cffe03d02Numy:|r Function Profiler")

            display.Inset:SetPoint("TOPLEFT", 8, -86)
            display.Inset:SetPoint("BOTTOMRIGHT", -4, 30)
        end

        local titleBar = CreateFrame("Frame", nil, display, "PanelDragBarTemplate")
        display.TitleBar = titleBar
        do
            titleBar:SetPoint("TOPLEFT", 0, 0)
            titleBar:SetPoint("BOTTOMRIGHT", display, "TOPRIGHT", 0, -32)
        end

        local historyMenu = CreateFrame("DropdownButton", nil, display, "WowStyle1DropdownTemplate");
        display.HistoryDropdown = historyMenu;
        do
            historyMenu:SetPoint("TOPRIGHT", -11, -32);
            historyMenu:SetWidth(150);
            historyMenu:SetFrameLevel(3);
            historyMenu:OverrideText("History Range");
            local historyOptions = {};
            for _, range in ipairs(HISTORY_RANGES) do
                local text = SecondsToTime(range, false, true);
                t_insert(historyOptions, {text, range});
            end
            local function isSelected(data)
                return data == FP.curHistoryRange;
            end
            local function onSelection(data)
                FP.curHistoryRange = data;

                display.elapsed = 50
            end
            MenuUtil.CreateRadioMenu(historyMenu, isSelected, onSelection, unpack(historyOptions));
        end

        local search = CreateFrame("EditBox", "$parentSearchBox", display, "SearchBoxTemplate")
        display.Search = search;
        do
            search:SetFrameLevel(3)
            search:SetPoint("TOPLEFT", 16, -31)
            search:SetSize(288, 22)
            search:SetAutoFocus(false)
            search:SetHistoryLines(1)
            search:SetMaxBytes(64)
            search:HookScript("OnTextChanged", function(self)
                local text = s_trim(self:GetText())
                FP.curMatch = text == "" and ".+" or text:lower()

                FP:PrepareFilteredData()

                local perc = display.ScrollBox:GetScrollPercentage()
                display.ScrollBox:Flush()

                if FP.dataProvider then
                    display.ScrollBox:SetDataProvider(FP.dataProvider)
                    display.ScrollBox:SetScrollPercentage(perc)
                end
            end)
        end

        --- @class FP_Display.Headers: ColumnDisplayTemplate
        local headers = CreateFrame("Button", "$parentHeaders", display, "ColumnDisplayTemplate")
        display.Headers = headers;
        do
            headers:SetPoint("BOTTOMLEFT", display.Inset, "TOPLEFT", 1, -1)
            headers:SetPoint("BOTTOMRIGHT", display.Inset, "TOPRIGHT", 0, -1)
            headers:LayoutColumns(display.activeColumns)

            local LeftClickAtlasMarkup = CreateAtlasMarkup('NPE_LeftClick', 18, 18);
            -- local RightClickAtlasMarkup = CreateAtlasMarkup('NPE_RightClick', 18, 18);

            --- @type FramePool<BUTTON,ColumnDisplayButtonTemplate>
            local headerPool = headers.columnHeaders
            for header in headerPool:EnumerateActive() do
                if not header.initialized then
                    header.initialized = true
                    local arrow = header:CreateTexture("OVERLAY")
                    arrow:SetAtlas("auctionhouse-ui-sortarrow", true)
                    arrow:SetPoint("LEFT", header:GetFontString(), "RIGHT", 0, 0)
                    arrow:Hide()
                    header.Arrow = arrow

                    header:SetScript("OnEnter", function(self)
                        local info = display.activeColumns[self:GetID()]
                        GameTooltip:SetOwner(self, "ANCHOR_TOP")
                        GameTooltip:AddLine(self:GetText())
                        if info.tooltip then
                            GameTooltip:AddLine(info.tooltip, 1, 1, 1, true)
                        end
                        GameTooltip_AddInstructionLine(GameTooltip, LeftClickAtlasMarkup .. " Click to sort")
                        -- GameTooltip_AddInstructionLine(GameTooltip, RightClickAtlasMarkup .. " Right-click to show / hide columns")

                        GameTooltip:Show()
                    end)
                    header:SetScript("OnLeave", function()
                        GameTooltip:Hide()
                    end)
                    header:SetScript("OnClick", function(self, button)
                        headers:OnHeaderClick(self:GetID(), button)
                    end)
                    header:RegisterForClicks("AnyDown")
                end
            end

            function headers:UpdateArrow()
                for header in headerPool:EnumerateActive() do
                    local columnID = display.activeColumns[header:GetID()].ID
                    if FP.activeSort == columnID then
                        header.Arrow:Show()

                        if FP.activeOrder == ORDER_ASC then
                            header.Arrow:SetTexCoord(0, 1, 1, 0)
                        else
                            header.Arrow:SetTexCoord(0, 1, 0, 1)
                        end
                    else
                        header.Arrow:Hide()
                    end
                end
            end

            function headers:OnHeaderClick(index, button)
                local columnID = display.activeColumns[index].ID;
                local columnChanged = FP.activeSort ~= columnID;
                local newSort, newOrder = columnID, ORDER_DESC;

                if not columnChanged then
                    newOrder = FP.activeOrder == ORDER_DESC and ORDER_ASC or ORDER_DESC;
                end
                FP.activeSort, FP.activeOrder = newSort, newOrder;

                FP.sortComparator = COLUMN_INFO[FP.activeSort].sortMethods[FP.activeOrder];
                FP:SortFilteredData();

                self:UpdateArrow();
            end

            headers:UpdateArrow()
            headers.Background:Hide()
            headers.TopTileStreaks:Hide()
        end

        local scrollBox = CreateFrame("Frame", "$parentScrollBox", display, "WowScrollBoxList")
        display.ScrollBox = scrollBox
        do
            scrollBox:SetPoint("TOPLEFT", display.Inset, "TOPLEFT", 4, -3)
            scrollBox:SetPoint("BOTTOMRIGHT", display.Inset, "BOTTOMRIGHT", -22, 2)

            local function alternateBG()
                local index = scrollBox:GetDataIndexBegin()
                scrollBox:ForEachFrame(function(button)
                    if index % 2 == 0 then
                        button.BG:SetColorTexture(0.1, 0.1, 0.1, 1)
                    else
                        button.BG:SetColorTexture(0.14, 0.14, 0.14, 1)
                    end

                    index = index + 1
                end)
            end
            scrollBox:RegisterCallback("OnDataRangeChanged", alternateBG, display)
        end

        local scrollBar = CreateFrame("EventFrame", "$parentScrollBar", display, "MinimalScrollBar")
        do
            scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, -4)
            scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 4)
            local thumb = scrollBar.Track.Thumb;
            local mouseDown = false
            thumb:HookScript("OnMouseDown", function(self, button)
                if button ~= "LeftButton" then return end
                mouseDown = true
                self:RegisterEvent("GLOBAL_MOUSE_UP")
            end)
            thumb:HookScript("OnEvent", function(self, event, ...)
                if event == "GLOBAL_MOUSE_UP" then
                    local button = ...
                    if button ~= "LeftButton" then return end
                    if mouseDown then
                        scrollBar.onButtonMouseUp(self, button)
                    end
                    mouseDown = false
                end
            end)
        end

        local view = CreateScrollBoxListLinearView(2, 0, 2, 2, 2)
        do
            --- @class FP_RowMixin: Button
            --- @field BG Texture?
            --- @field columnPool ObjectPool<FontString>
            --- @field initialized boolean
            --- @field GetElementData fun(self): FP_ElementData
            local rowMixin = {}
            do
                function rowMixin:OnEnter()
                    local data = self:GetElementData()
                    GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT", 5, 5)
                    GameTooltip:AddLine(data.name)
                    GameTooltip:Show()
                end

                function rowMixin:OnLeave()
                    GameTooltip:Hide()
                end

                function rowMixin:UpdateColumns()
                    local rowWidth = scrollBox:GetWidth() - 4
                    local offSet = 2
                    local padding = 4

                    self:SetSize(rowWidth, ROW_HEIGHT)
                    self.columnPool:ReleaseAll()

                    for _, column in ipairs(display.activeColumns) do
                        local text = self.columnPool:Acquire()
                        text:Show()
                        text.column = column
                        if column.justifyLeft then
                            text:SetPoint("LEFT", offSet, 0)
                        else
                            text:SetPoint("RIGHT", (offSet + column.width - (padding * 2)) - rowWidth, 0)
                        end
                        text:SetSize(column.width - (padding * 2.5), 0)
                        text:SetJustifyH(column.justifyLeft and "LEFT" or "RIGHT")
                        text:SetWordWrap(false)
                        offSet = offSet + (column.width - (padding / 2))
                    end
                end
            end
            local function initRow(row)
                Mixin(row, rowMixin)
                row:SetHighlightTexture("Interface\\BUTTONS\\WHITE8X8")
                row:GetHighlightTexture():SetVertexColor(0.1, 0.1, 0.1, 0.75)
                -- row:SetScript("OnEnter", row.OnEnter)
                -- row:SetScript("OnLeave", row.OnLeave)

                local function init()
                    return row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                end
                local function reset(_, obj)
                    if not obj then return end
                    obj:ClearAllPoints()
                    obj:SetText("")
                    obj:Hide()
                end
                row.columnPool = CreateObjectPool(init, reset) --[[@as ObjectPool<FontString>]]

                local bg = row:CreateTexture(nil, "BACKGROUND")
                bg:SetPoint("TOPLEFT")
                bg:SetPoint("BOTTOMRIGHT")
                row.BG = bg
            end

            view:SetElementExtent(20)

            --- @param row Button&FP_RowMixin
            view:SetElementInitializer("Button", function(row, data)
                if not row.initialized then
                    initRow(row);

                    row.initialized = true;
                end

                row:UpdateColumns();
                for columnText in row.columnPool:EnumerateActive() do
                    local column = columnText.column
                    local value = column.textFunc and column.textFunc(data) or data[column.textKey]
                    columnText:SetText(column.textFormatter(value))
                end
            end);
            ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view);
        end

        local playButton = CreateFrame("Button", nil, display);
        display.PlayButton = playButton;
        do
            playButton:SetPoint("BOTTOMLEFT", 4, 0);
            playButton:SetSize(32, 32);
            playButton:SetHitRectInsets(4, 4, 4, 4);
            playButton:SetNormalTexture("Interface\\Buttons\\UI-SquareButton-Up");
            playButton:SetPushedTexture("Interface\\Buttons\\UI-SquareButton-Down");
            playButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD");

            local playIcon = playButton:CreateTexture("OVERLAY")
            playButton.Icon = playIcon
            do
                playIcon:SetSize(11, 15)
                playIcon:SetPoint("CENTER")
                playIcon:SetBlendMode("ADD")
                playIcon:SetTexCoord(10 / 32, 21 / 32, 9 / 32, 24 / 32)
            end

            playButton:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT", -6, -4)
                GameTooltip:AddLine(continuousUpdate and "Pause" or "Resume")
                GameTooltip:Show()
            end)

            playButton:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            playButton:SetScript("OnMouseDown", function(self)
                self.Icon:SetPoint("CENTER", -2, -2)
            end)

            playButton:SetScript("OnMouseUp", function(self)
                self.Icon:SetPoint("CENTER", 0, 0)
            end)

            playButton:SetScript("OnClick", function(self)
                continuousUpdate = not continuousUpdate
                if continuousUpdate then
                    self.Icon:SetTexture("Interface\\TimeManager\\PauseButton")
                    self.Icon:SetVertexColor(0.84, 0.81, 0.52)

                    display:SetScript("OnUpdate", display.OnUpdate)
                    display.UpdateButton:Disable()
                else
                    self.Icon:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
                    self.Icon:SetVertexColor(1, 1, 1)

                    display:SetScript("OnUpdate", nil)
                    display.UpdateButton:Enable()
                end

                if GameTooltip:IsOwned(self) then
                    self:GetScript("OnEnter")(self)
                end
                display.Stats:Update();
            end)

            playButton:SetScript("OnShow", function(self)
                if continuousUpdate then
                    self.Icon:SetTexture("Interface\\TimeManager\\PauseButton")
                    self.Icon:SetVertexColor(0.84, 0.81, 0.52)
                else
                    self.Icon:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
                    self.Icon:SetVertexColor(1, 1, 1)
                end

                self.Icon:SetPoint("CENTER")
            end)
        end

        local updateButton = CreateFrame("Button", nil, display)
        display.UpdateButton = updateButton
        do
            updateButton:SetPoint("LEFT", playButton, "RIGHT", -6, 0)
            updateButton:SetSize(32, 32)
            updateButton:SetHitRectInsets(4, 4, 4, 4)
            updateButton:SetNormalTexture("Interface\\Buttons\\UI-SquareButton-Up")
            updateButton:SetPushedTexture("Interface\\Buttons\\UI-SquareButton-Down")
            updateButton:SetDisabledTexture("Interface\\Buttons\\UI-SquareButton-Disabled")
            updateButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

            local updateIcon = updateButton:CreateTexture("OVERLAY")
            updateButton.Icon = updateIcon
            do
                updateIcon:SetSize(16, 16)
                updateIcon:SetPoint("CENTER", -1, -1)
                updateIcon:SetBlendMode("ADD")
                updateIcon:SetTexture("Interface\\Buttons\\UI-RefreshButton")
            end

            updateButton:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT", -6, -4)
                GameTooltip:AddLine("Update")
                GameTooltip:Show()
            end)

            updateButton:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            updateButton:SetScript("OnMouseDown", function(self)
                if self:IsEnabled() then
                    self.Icon:SetPoint("CENTER", -3, -3)
                end
            end)

            updateButton:SetScript("OnMouseUp", function(self)
                if self:IsEnabled() then
                    self.Icon:SetPoint("CENTER", -1, -1)
                end
            end)

            updateButton:SetScript("OnClick", function()
                FP:PrepareFilteredData()

                local perc = display.ScrollBox:GetScrollPercentage()
                display.ScrollBox:Flush()

                if FP.dataProvider then
                    display.ScrollBox:SetDataProvider(FP.dataProvider)
                    display.ScrollBox:SetScrollPercentage(perc)
                end
            end)

            updateButton:SetScript("OnDisable", function(self)
                self.Icon:SetDesaturated(true)
                self.Icon:SetVertexColor(0.6, 0.6, 0.6)
            end)

            updateButton:SetScript("OnEnable", function(self)
                self.Icon:SetDesaturated(false)
                self.Icon:SetVertexColor(1, 1, 1)
            end)

            updateButton:SetScript("OnShow", function(self)
                if continuousUpdate then
                    self:Disable()
                else
                    self:Enable()
                end

                self.Icon:SetPoint("CENTER", -1, -1)
            end)
        end

        --- @class FP_Display.Stats: FontString
        local stats = display:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        display.Stats = stats
        do
            stats:SetPoint("LEFT", updateButton, "RIGHT", 6, 0)
            stats:SetHeight(20)
            stats:SetJustifyH("LEFT")
            stats:SetWordWrap(false)

            local STATS_FORMAT = "|cfff8f8f2%s|r"
            function stats:Update()
                self:SetFormattedText(STATS_FORMAT, API:IsLogging() and (continuousUpdate and "Live Updating List" or "Paused") or "")
            end
        end

        --- @class FP_Display.TimeText: FontString
        local timeText = display:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        display.TimeText = timeText
        do
            timeText:SetPoint("LEFT", stats, "RIGHT", 6, 0)
            timeText:SetHeight(20)
            timeText:SetJustifyH("LEFT")
            timeText:SetWordWrap(false)

            --- @param oldestEntryAge number
            function timeText:Update(oldestEntryAge)
                local seconds = math.ceil(oldestEntryAge)
                local minutes = seconds / 60
                self:SetFormattedText("%02d:%02d", minutes, seconds % 60)
            end
        end

        local toggleButton = CreateFrame("Button", "$parentToggle", display, "UIPanelButtonTemplate, UIButtonTemplate");
        display.ToggleButton = toggleButton;
        do
            toggleButton:SetPoint("BOTTOM", 0, 6);
            toggleButton:SetText("Enable");
            toggleButton.padding = 40;
            DynamicResizeButton_Resize(toggleButton);

            toggleButton:SetOnClickHandler(function()
                if API:IsLogging() then
                    API:DisableLogging();
                else
                    API:EnableLogging();
                end
            end);
        end

        local autoEnableCheckbox = CreateFrame("CheckButton", "$parentAutoEnableCheckbox", display, "UICheckButtonTemplate");
        display.AutoEnableCheckbox = autoEnableCheckbox;
        do
            autoEnableCheckbox:SetPoint("LEFT", toggleButton, "RIGHT", 15, 0);
            autoEnableCheckbox:SetSize(25, 25);
            autoEnableCheckbox:SetChecked(FP.db.startEnabled);

            autoEnableCheckbox.Text:SetText("Auto-enable on login");
            autoEnableCheckbox:SetHitRectInsets(0, -autoEnableCheckbox.Text:GetWidth() - 5, 0, 0);
            autoEnableCheckbox:SetScript("OnClick", function(btn)
                FP.db.startEnabled = btn:GetChecked();
            end);
        end
    end
end

function FP:RegisterIntoBlizzMove()
    --- @type BlizzMoveAPI?
    local BlizzMoveAPI = BlizzMoveAPI;
    if BlizzMoveAPI then
        BlizzMoveAPI:RegisterAddOnFrames(
            {
                [addonName] = {
                    [self.Display:GetName()] = {
                        SubFrames = {
                            [self.Display:GetName() .. '.TitleBar'] = {},
                            [self.Display:GetName() .. '.Headers'] = {},
                        },
                    },
                },
            }
        )
    end
end

function FP:Print(...)
    print('|cff33ff99FunctionProfiler|r:', ...);
end

--- @param message string
function FP:SlashCommand(message)
    message = message:trim():lower();
    if message == '' or message == 'ui' then
        API:ToggleFrame();
    elseif message == 'disable' then
        API:DisableLogging();
        self:Print('Logging has been disabled.')
    elseif message == 'enable' then
        API:EnableLogging();
        self:Print('Logging has been enabled.')
    elseif message == 'toggle' then
        if API:IsLogging() then
            API:DisableLogging();
            self:Print('Logging has been disabled.')
        else
            API:EnableLogging();
            self:Print('Logging has been enabled.')
        end
    elseif message == 'reset' then
        if API:IsLogging() then
            API:DisableLogging();
            API:EnableLogging();
        end
        if self.Display then
            self.Display.elapsed = 60;
        end
        self:Print('All collected data has been reset.');
    elseif message == 'minimap' then
        wipe(self.db.minimap);
        self.db.minimap.hide = false;
        local name = 'NumyFunctionProfiler';
        LibStub('LibDBIcon-1.0'):Hide(name);
        LibStub('LibDBIcon-1.0'):Show(name);

        self:Print('Minimap button has been restored.');
    else
        self:Print('Commands:');
        print('  help - show this help message');
        print('  ui (or nothing) - toggle the profiler frame');
        print('  disable - disable the profiler');
        print('  enable - enable the profiler');
        print('  toggle - disable / enable the profiler')
        print('  reset - reset all collected data');
        print('  minimap - reset the minimap button');
    end
end

function FP:InitMinimapButton()
    self.db.minimap = self.db.minimap or {};

    -- function copied from LibDBIcon-1.0.lua
    local function getAnchors(frame)
        local x, y = frame:GetCenter()
        if not x or not y then return "CENTER" end
        local hHalf = (x > UIParent:GetWidth()*2/3) and "RIGHT" or (x < UIParent:GetWidth()/3) and "LEFT" or ""
        local vHalf = (y > UIParent:GetHeight()/2) and "TOP" or "BOTTOM"
        return vHalf..hHalf, frame, (vHalf == "TOP" and "BOTTOM" or "TOP")..hHalf
    end

    local function showTooltip(minimapButton)
        GameTooltip:SetOwner(minimapButton, 'ANCHOR_NONE')
        GameTooltip:SetPoint(getAnchors(minimapButton))

        GameTooltip:AddLine('Function Profiler ' .. (
            API:IsLogging()
                and GREEN_FONT_COLOR:WrapTextInColorCode("enabled")
                or RED_FONT_COLOR:WrapTextInColorCode("disabled")
        ))
        GameTooltip:AddLine('|cffeda55fLeft-Click|r to toggle the frame')
        GameTooltip:AddLine('|cffeda55fRight-Click|r to toggle logging')

        GameTooltip:Show()
    end

    local name = 'NumyFunctionProfiler'
    local function getIcon()
        return API:IsLogging()
            and 'interface/icons/inv_misc_pocketwatch_01'
            or 'interface/icons/achievement_guild_timeoff'
    end
    local dataObject
    dataObject = LibStub('LibDataBroker-1.1'):NewDataObject(
        name,
        {
            type = 'launcher',
            text = 'FunctionProfiler',
            icon = getIcon(),
            OnClick = function(minimapButton, button)
            if IsShiftKeyDown() then
                self.db.minimap.hide = true;
                LibStub('LibDBIcon-1.0'):Hide(name);
                self:Print('Minimap button hidden. Use |cffeda55f/fp minimap|r to restore.');

                return;
            end
                if button == 'LeftButton' then
                    API:ToggleFrame()
                else
                    if API:IsLogging() then
                        API:DisableLogging()
                    else
                        API:EnableLogging()
                    end
                    showTooltip(minimapButton)
                end
            end,
            OnEnter = function(minimapButton)
                showTooltip(minimapButton)
            end,
            OnLeave = function()
                GameTooltip:Hide()
            end,
        }
    )
    LibStub('LibDBIcon-1.0'):Register(name, dataObject, self.db.minimap)
    self.UpdateMinimapIcon = function()
        dataObject.icon = API:IsLogging()
            and 'interface/icons/inv_misc_pocketwatch_01'
            or 'interface/icons/achievement_guild_timeoff'
    end
end

function FP:InitDB()
    _G.FunctionProfilerDB = FunctionProfilerDB or {};
    --- @type FP_DB
    self.db = FunctionProfilerDB;

    --- @class FP_DB
    local defaults = {
        startEnabled = false,
    };
    for k, v in pairs(defaults) do
        if self.db[k] == nil then self.db[k] = v; end
    end
end

function FP:Init()
    self:InitDB();
    self:InitUI();
    EventUtil.ContinueOnAddOnLoaded("BlizzMove", function()
        self:RegisterIntoBlizzMove();
    end);

    self:InitMinimapButton();

    SLASH_NUMY_FUNCTION_PROFILER1 = '/fp';
    SLASH_NUMY_FUNCTION_PROFILER2 = '/nfp';
    SLASH_NUMY_FUNCTION_PROFILER3 = '/functionprofiler';
    SlashCmdList['NUMY_FUNCTION_PROFILER'] = function(message)
        self:SlashCommand(message);
    end;

    -- self profiling.. be careful
    do
        ns.API:WrapInPlace("FunctionProfiler", "FP", self, "PurgeOldData");
        ns.API:WrapInPlace("FunctionProfiler", "FP", self, "PrepareFilteredData");
        ns.API:WrapInPlace("FunctionProfiler", "FP", self, "SortFilteredData");
        ns.API:WrapInPlace("FunctionProfiler", "Buffer", ns.Buffer, "Squash");
    end

    if self.db.startEnabled then
        ns.API:EnableLogging();
        self:Print("profiling on start-up has been enabled. Don't forget to turn it off if it starts to affect your performance.")
    end
end

FP:Init();
