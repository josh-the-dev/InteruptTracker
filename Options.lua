local addonName, ns = ...

------------------------------------------------------------------------
-- Defaults and saved variables
------------------------------------------------------------------------
local DEFAULTS = {
    maxRowsPerCol = 15,
    scale         = 1.0,
    locked        = false,
}

local SCALE_STEPS = { 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.5, 1.75, 2.0 }

local function DB() return InterruptTrackerDB end

------------------------------------------------------------------------
-- Apply saved settings to the tracker frame
------------------------------------------------------------------------
local function ApplySettings()
    local db = DB()
    ns.SetMaxRowsPerCol(db.maxRowsPerCol)
    ns.trackerFrame:SetScale(db.scale)
    local movable = not db.locked
    ns.trackerFrame:SetMovable(movable)
    ns.trackerFrame:EnableMouse(movable)
    if movable then
        ns.trackerFrame:RegisterForDrag("LeftButton")
    end
    ns.LayoutRows()
end

------------------------------------------------------------------------
-- Test data simulation
------------------------------------------------------------------------
local TEST_CLASSES = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "DEATHKNIGHT",
    "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER", "PRIEST",
}

local testGuids = {}

local function ClearTestData()
    for _, guid in ipairs(testGuids) do
        ns.RemoveRow(guid)
        ns.trackedPlayers[guid] = nil
    end
    testGuids = {}
    ns.LayoutRows()
end

local function SimulateGroup(count)
    ClearTestData()
    -- Real entries (e.g. the player themselves) already occupy slots
    local realCount = 0
    for guid in pairs(ns.trackedPlayers) do
        if not guid:find("^TEST%-") then realCount = realCount + 1 end
    end
    local toAdd = math.max(0, count - realCount)
    for i = 1, toAdd do
        local guid  = "TEST-" .. string.format("%04d", i)
        local class = TEST_CLASSES[((i - 1) % #TEST_CLASSES) + 1]
        local entry = ns.PRIMARY_INTERRUPT[class]
        local spellIDStr = type(entry) == "function" and entry(nil) or entry
        local spellInfo  = spellIDStr and C_Spell.GetSpellInfo(tonumber(spellIDStr))
        ns.trackedPlayers[guid] = {
            name    = class:sub(1, 1) .. class:sub(2):lower() .. " " .. i,
            class   = class,
            spellID = spellIDStr,
            icon    = spellInfo and spellInfo.iconID,
            cdEnd   = (i % 3 == 0) and (GetTime() + (i * 3) % 28 + 2) or 0,
        }
        ns.InitRow(guid)
        testGuids[#testGuids + 1] = guid
    end
    ns.LayoutRows()
end

------------------------------------------------------------------------
-- Panel helpers
------------------------------------------------------------------------
local panel = CreateFrame("Frame", "InterruptTrackerOptions", UIParent, "BackdropTemplate")
panel:SetSize(254, 282)
panel:SetPoint("CENTER")
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
panel:SetBackdrop({
    bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
panel:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
panel:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
panel:SetFrameStrata("DIALOG")
panel:Hide()

-- Close on Escape
table.insert(UISpecialFrames, "InterruptTrackerOptions")

local titleText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
titleText:SetPoint("TOP", panel, "TOP", 0, -10)
titleText:SetText("InterruptTracker Options")
titleText:SetTextColor(1, 0.82, 0)

local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)

local function MakeBtn(label, w, h, onClick)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(w, h)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

local function SectionLabel(text, yOff)
    local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, yOff)
    fs:SetText(text)
    fs:SetTextColor(0.75, 0.75, 0.75)
    return fs
end

local function Divider(yOff)
    local d = panel:CreateTexture(nil, "ARTWORK")
    d:SetSize(232, 1)
    d:SetPoint("TOPLEFT", panel, "TOPLEFT", 11, yOff)
    d:SetColorTexture(0.3, 0.3, 0.3, 1)
end

------------------------------------------------------------------------
-- Section: Max rows per column
------------------------------------------------------------------------
SectionLabel("Max Rows Per Column", -34)
Divider(-46)

local ROW_OPTIONS = { 10, 12, 15, 20, 25 }
local rowBtns     = {}

local function RefreshRowBtns()
    for idx, b in ipairs(rowBtns) do
        b:SetAlpha(ROW_OPTIONS[idx] == DB().maxRowsPerCol and 1.0 or 0.5)
    end
end

for idx, val in ipairs(ROW_OPTIONS) do
    local b = MakeBtn(tostring(val), 40, 22, function()
        DB().maxRowsPerCol = val
        ApplySettings()
        RefreshRowBtns()
    end)
    b:SetPoint("TOPLEFT", panel, "TOPLEFT", 8 + (idx - 1) * 46, -50)
    rowBtns[idx] = b
end

------------------------------------------------------------------------
-- Section: Scale
------------------------------------------------------------------------
SectionLabel("Scale", -84)
Divider(-96)

local scaleVal = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
scaleVal:SetPoint("TOPLEFT", panel, "TOPLEFT", 58, -84)
scaleVal:SetTextColor(1, 1, 1)

local function RefreshScale()
    scaleVal:SetText(string.format("%.2f", DB().scale))
end

local function GetScaleIdx()
    for i, v in ipairs(SCALE_STEPS) do
        if math.abs(v - DB().scale) < 0.01 then return i end
    end
    return 5  -- fallback: 1.0
end

local scMinus = MakeBtn("-", 32, 22, function()
    local i = GetScaleIdx()
    if i > 1 then DB().scale = SCALE_STEPS[i - 1]; ApplySettings(); RefreshScale() end
end)
scMinus:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -100)

local scPlus = MakeBtn("+", 32, 22, function()
    local i = GetScaleIdx()
    if i < #SCALE_STEPS then DB().scale = SCALE_STEPS[i + 1]; ApplySettings(); RefreshScale() end
end)
scPlus:SetPoint("LEFT", scMinus, "RIGHT", 4, 0)

------------------------------------------------------------------------
-- Section: Lock frame
------------------------------------------------------------------------
local lockBtn
local function RefreshLockBtn()
    lockBtn:SetText(DB().locked and "Unlock Frame" or "Lock Frame")
end

lockBtn = MakeBtn("Lock Frame", 120, 22, function()
    DB().locked = not DB().locked
    ApplySettings()
    RefreshLockBtn()
end)
lockBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -132)

------------------------------------------------------------------------
-- Section: Test preview
------------------------------------------------------------------------
Divider(-164)
SectionLabel("Test Preview", -172)

local TEST_GROUPS = {
    { "Solo",  1  }, { "Party", 5  }, { "10", 10 },
    { "20",    20 }, { "30",    30 }, { "40", 40 },
}

for i, info in ipairs(TEST_GROUPS) do
    local col = (i - 1) % 3
    local row = math.floor((i - 1) / 3)
    local b = MakeBtn(info[1], 58, 22, function() SimulateGroup(info[2]) end)
    b:SetPoint("TOPLEFT", panel, "TOPLEFT", 8 + col * 62, -190 - row * 26)
end

local clearBtn = MakeBtn("Clear Test Data", 160, 22, function() ClearTestData() end)
clearBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -246)

------------------------------------------------------------------------
-- ADDON_LOADED: initialise DB, sync UI state, apply settings
------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, name)
    if name ~= addonName then return end
    InterruptTrackerDB = InterruptTrackerDB or {}
    for k, v in pairs(DEFAULTS) do
        if InterruptTrackerDB[k] == nil then
            InterruptTrackerDB[k] = v
        end
    end
    RefreshRowBtns()
    RefreshScale()
    RefreshLockBtn()
    ApplySettings()
    self:UnregisterAllEvents()
end)

------------------------------------------------------------------------
-- Slash commands:  /inttracker  or  /itt
------------------------------------------------------------------------
SLASH_INTTRACKER1 = "/inttracker"
SLASH_INTTRACKER2 = "/itt"
SlashCmdList["INTTRACKER"] = function()
    if panel:IsShown() then
        panel:Hide()
    else
        RefreshRowBtns()
        RefreshScale()
        RefreshLockBtn()
        panel:Show()
    end
end
