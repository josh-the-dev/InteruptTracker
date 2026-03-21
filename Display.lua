local addonName, ns = ...

local ROW_HEIGHT       = 22
local ROW_PAD          = 2
local TOP_PAD          = 16
local MAX_ROWS_PER_COL = 15   -- mutable via ns.SetMaxRowsPerCol
local SLOT_WIDTH       = 220  -- frame width consumed per column

local rows = {}

function ns.SetMaxRowsPerCol(n)
    MAX_ROWS_PER_COL = n
end

------------------------------------------------------------------------
-- Main frame
------------------------------------------------------------------------
local frame = CreateFrame("Frame", "InterruptTrackerFrame", UIParent, "BackdropTemplate")
frame:SetSize(220, 10)
frame:SetPoint("CENTER", UIParent, "CENTER", 400, 0)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:SetBackdrop({
    bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left=3, right=3, top=3, bottom=3 },
})
frame:SetBackdropColor(0, 0, 0, 0.7)
frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

ns.trackerFrame = frame

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("TOP", frame, "TOP", 0, -4)
title:SetText("Interrupts")
title:SetTextColor(1, 1, 1)

------------------------------------------------------------------------
-- Row creation
------------------------------------------------------------------------
local function CreateRow()
    local row = CreateFrame("Frame", nil, frame)
    row:SetSize(210, ROW_HEIGHT)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_HEIGHT - 2, ROW_HEIGHT - 2)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.iconOverlay = row:CreateTexture(nil, "OVERLAY")
    row.iconOverlay:SetAllPoints(row.icon)
    row.iconOverlay:SetColorTexture(0, 0, 0, 0.6)
    row.iconOverlay:Hide()

    row.cdText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.cdText:SetPoint("CENTER", row.icon, "CENTER", 0, 0)
    row.cdText:SetTextColor(1, 1, 1)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.name:SetWidth(140)
    row.name:SetJustifyH("LEFT")

    return row
end

local function GetOrCreateRow(guid)
    if not rows[guid] then
        rows[guid] = CreateRow()
    end
    return rows[guid]
end

------------------------------------------------------------------------
-- Public: layout all rows top-to-bottom
------------------------------------------------------------------------
function ns.LayoutRows()
    local i = 0
    for guid in pairs(ns.trackedPlayers) do
        local row      = GetOrCreateRow(guid)
        local col      = math.floor(i / MAX_ROWS_PER_COL)
        local rowInCol = i % MAX_ROWS_PER_COL
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame, "TOPLEFT",
            col * SLOT_WIDTH + 5,
            -(TOP_PAD + rowInCol * (ROW_HEIGHT + ROW_PAD)))
        row:Show()
        i = i + 1
    end
    local numCols    = math.max(1, math.ceil(i / MAX_ROWS_PER_COL))
    local tallRows   = math.min(i, MAX_ROWS_PER_COL)
    frame:SetWidth(numCols * SLOT_WIDTH)
    frame:SetHeight(TOP_PAD + tallRows * (ROW_HEIGHT + ROW_PAD) + 4)
end

------------------------------------------------------------------------
-- Public: set static elements (icon, name, colour) — call once on new entry
------------------------------------------------------------------------
function ns.InitRow(guid)
    local data = ns.trackedPlayers[guid]
    if not data then return end

    local row = GetOrCreateRow(guid)

    row.icon:SetTexture(data.icon)

    local col = data.class and ns.CLASS_COLORS[data.class]
    if col then
        row.name:SetTextColor(col.r, col.g, col.b)
    else
        row.name:SetTextColor(1, 1, 1)
    end
    row.name:SetText(data.name or "Unknown")
end

------------------------------------------------------------------------
-- Public: update only the cooldown display — called by ticker
------------------------------------------------------------------------
function ns.UpdateRow(guid)
    local data = ns.trackedPlayers[guid]
    if not data then return end

    local row = GetOrCreateRow(guid)
    local remaining = data.cdEnd and (data.cdEnd - GetTime()) or 0

    if remaining > 0 then
        row.iconOverlay:Show()
        row.cdText:SetText(math.ceil(remaining))
    else
        row.iconOverlay:Hide()
        row.cdText:SetText("")
    end
end

------------------------------------------------------------------------
-- Public: hide and remove a row
------------------------------------------------------------------------
function ns.RemoveRow(guid)
    if rows[guid] then
        rows[guid]:Hide()
        rows[guid] = nil
    end
end

------------------------------------------------------------------------
-- Periodic refresh — only updates the countdown numbers
------------------------------------------------------------------------
C_Timer.NewTicker(0.1, function()
    for guid in pairs(ns.trackedPlayers) do
        ns.UpdateRow(guid)
    end
end)
