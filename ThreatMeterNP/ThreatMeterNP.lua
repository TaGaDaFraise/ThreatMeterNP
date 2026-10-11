-- ThreatMeterNP
-- Adds a target-of-target label and a threat-gap number to enemy nameplates.
-- Generic across nameplate add-ons: anchors to the plate frame itself
-- (C_NamePlate.GetNamePlateForUnit), never to skin-specific internals
-- like Plater's unitFrame.healthBar, so it works on Blizzard default,
-- Plater, and ElvUI nameplates alike. See requirements.md / infos.md.
--
-- Display settings (position, font, size, color, visibility) live in
-- ThreatMeterNP.db.profile, set up by Options.lua — this file only reads
-- them at render time, never stores its own copy.

local UPDATE_THROTTLE = 0.2 -- seconds; see requirements.md §12, not user-configurable

local LSM = LibStub("LibSharedMedia-3.0")

-- =====================================================================
-- Target-of-target and threat helpers
-- =====================================================================

-- Standard Blizzard unit-token suffix chaining has no separator
-- (e.g. "targettarget", "party1target"). The WeakAura reference in
-- requirements.md used a "-target" suffix, but that's WeakAuras' own
-- custom unit-token sugar (aura_env), not a raw API convention — raw
-- addon code must NOT include the dash.
local function GetTargetToken(unitToken)
    return unitToken .. "target"
end

-- Shared by the real "color by class" lookups and the debug preview's
-- made-up classes (which have no real unit to query UnitClass on).
local function GetClassColorRGBByFilename(classFilename)
    if not classFilename then
        return nil
    end
    local color = C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(classFilename)
    if color then
        return color.r, color.g, color.b
    end
    local legacy = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFilename]
    if legacy then
        return legacy.r, legacy.g, legacy.b
    end
    return nil
end

-- Class color for the "color by class" target-of-target option.
-- Only meaningful for players; returns nil for NPCs so the caller can
-- fall back to the configured plain color.
local function GetClassColorRGB(unitToken)
    if not UnitIsPlayer(unitToken) then
        return nil
    end
    local _, classFilename = UnitClass(unitToken)
    return GetClassColorRGBByFilename(classFilename)
end

-- UnitDetailedThreatSituation (and friends) can return "secret" values
-- instead of plain ones — for numbers AND booleans alike. A secret
-- value still reports its normal type() (e.g. "number" or "boolean"),
-- so a type() check alone never catches it. Touching one directly —
-- comparing, arithmetic, or even `if secretBool then` — throws
-- ("attempt to ... a secret ... value, while execution tainted by
-- ..."). Every value pulled from these APIs must be filtered through
-- issecretvalue() before it's used for anything but storing/passing on.
local function IsUsable(value, expectedType)
    return value ~= nil and type(value) == expectedType and not issecretvalue(value)
end

local function IsUsableNumber(value)
    return IsUsable(value, "number")
end

-- Generic secret-or-nil check, for values of any type (not just numbers)
-- — matches the "Readable()" helper EllesmereUI's threat-list collector
-- uses (EllesmereUIForeverEssentials_ThreatData.lua). Confirmed by that
-- code that a *non-secret* threat value compares/sorts completely
-- normally; this only needs to guard the cases that are secret.
local function Readable(value)
    return value ~= nil and not issecretvalue(value)
end

-- 1=Numeric, 2=Percentage, 3=Numeric - Percentage (requirements.md §13).
local function GetDisplayFormat()
    return ThreatMeterNP.db.profile.threat.displayFormat or 2
end

-- "Display threat owner" (single-display mode only — hidden in options
-- while list mode is on, see Options.lua). The unit currently holding
-- top threat on a mob is, by definition, whoever that mob is actively
-- attacking — so this reuses the same mob-target lookup as the
-- target-of-target label instead of ranking/comparing threat values at
-- all. Returns "" (no prefix) when the setting is off or there's
-- nothing meaningful to show.
local function GetThreatOwnerPrefix(unitToken)
    if not ThreatMeterNP.db.profile.threat.showOwner then
        return ""
    end
    local ownerToken = unitToken .. "target"
    if not UnitExists(ownerToken) or UnitIsUnit(ownerToken, unitToken) then
        return ""
    end
    if UnitIsUnit(ownerToken, "player") then
        return "You: "
    end
    local name = UnitName(ownerToken)
    return name and (name .. ": ") or ""
end

-- Preferred path: an exact threat value for the player's own threat,
-- rendered via a *widget method* (FontString:SetFormattedText) rather
-- than Lua's own string.format. Technique confirmed working on this
-- exact client by EllesmereUI's nameplate threat-percent feature
-- (EllesmereUI_UICore.lua PaintThreatPct / EllesmereUINameplates.lua
-- NP_UpdateThreatPct — see infos.md): these values come back as
-- Blizzard "secret" values for nameplate units — addon Lua still can't
-- read, compare, or string.format them. But handing one directly to a
-- widget's own :SetFormattedText is a sanctioned "sink": the C-side
-- widget formats and renders it without ever exposing the value back
-- to Lua. That's why pct/rawThreat are never touched by
-- IsUsableNumber/issecretvalue here — only passed straight through.
local function ApplyExactThreatPercentage(text, unitToken)
    local isTanking, status, pct, _, rawThreat = UnitDetailedThreatSituation("player", unitToken)
    local format = GetDisplayFormat()
    local prefix = GetThreatOwnerPrefix(unitToken)

    if format == 1 then
        if type(rawThreat) ~= "number" then return false end
        text:SetFormattedText("%s%.0f", prefix, rawThreat)
    elseif format == 3 then
        if type(rawThreat) ~= "number" or type(pct) ~= "number" then return false end
        text:SetFormattedText("%s%.0f - %.0f%%", prefix, rawThreat, pct)
    else
        if type(pct) ~= "number" then return false end
        text:SetFormattedText("%s%.0f%%", prefix, pct)
    end

    if type(status) == "number" and not issecretvalue(status) then
        text:SetTextColor(GetThreatStatusColor(status))
    elseif type(isTanking) == "boolean" and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        -- isTanking may itself be secret. EvaluateColorValueFromBoolean
        -- is a Blizzard-provided "secret-safe select": it picks between
        -- two already-known PLAIN values based on a possibly-secret
        -- boolean condition, entirely C-side — Lua never reads the
        -- boolean itself. Same pattern EllesmereUI uses for off-tank
        -- coloring under identity restriction.
        local profile = ThreatMeterNP.db.profile.threat
        local onColor, offColor = profile.colorTanking, profile.colorNotTanking
        local fold = C_CurveUtil.EvaluateColorValueFromBoolean
        text:SetTextColor(
            fold(isTanking, onColor[1], offColor[1]),
            fold(isTanking, onColor[2], offColor[2]),
            fold(isTanking, onColor[3], offColor[3])
        )
    else
        text:SetTextColor(1, 1, 1)
    end

    return true
end

-- Fallback path: what the manual group-threat-table approach (now
-- removed) reliably produced on this client before this technique was
-- found — kept as a safety net for the rare case pct itself is nil
-- (genuinely no threat table yet, not just secret). One signal —
-- UnitThreatSituation's 0-3 status, the same function Blizzard's own
-- default unit frames use for a non-tank's aggro state
-- (CompactUnitFrame.lua) — bucketed into three words over a fixed,
-- non-configurable green->yellow->red gradient. Deliberately the same
-- three words for tanks and DPS alike: this describes how much threat
-- you're holding on the unit, not a role-specific safety judgment (a
-- tank always reads "High" while tanking, since holding the top threat
-- *is* high threat).
local THREAT_STEPS = {
    [0] = { text = "Low",    r = 0.2, g = 0.9, b = 0.2 }, -- far from pulling
    [1] = { text = "Medium", r = 1.0, g = 0.8, b = 0.1 }, -- next in line
    [2] = { text = "High",   r = 1.0, g = 0.2, b = 0.2 }, -- tanking, insecurely
    [3] = { text = "High",   r = 1.0, g = 0.2, b = 0.2 }, -- tanking, securely
}

local function ApplyThreatLevelFallback(text, unitToken)
    local status = UnitThreatSituation("player", unitToken)
    if not IsUsableNumber(status) then
        return false
    end
    local step = THREAT_STEPS[status] or THREAT_STEPS[0]
    text:SetFormattedText("%s%s", GetThreatOwnerPrefix(unitToken), step.text)
    text:SetTextColor(step.r, step.g, step.b)
    return true
end

-- =====================================================================
-- Widget lifecycle
-- =====================================================================

local plateWidgets = {} -- [plate] = { totText, threatText, threatBg, listRows }
local unitToPlate = {}  -- [unitToken] = plate

local function CreateLabel(plate)
    local text = plate:CreateFontString(nil, "OVERLAY")
    text:Hide()
    return text
end

local function EnsureWidgets(plate)
    local widgets = plateWidgets[plate]
    if widgets then return widgets end

    local bg = plate:CreateTexture(nil, "BACKGROUND")
    bg:Hide()

    widgets = {
        totText = CreateLabel(plate),
        threatText = CreateLabel(plate),
        threatBg = bg,
        listRows = {}, -- lazily populated FontStrings, up to 3 (see EnsureListRow)
    }
    plateWidgets[plate] = widgets
    return widgets
end

-- Lazily creates/returns the Nth row widget for list mode. Rows are
-- never destroyed once created (same pooling rationale as the plate
-- widgets themselves — nameplate frames get reused by Blizzard's pool,
-- so hiding and re-showing is the right lifecycle, not recreating).
local function EnsureListRow(widgets, plate, index)
    local row = widgets.listRows[index]
    if not row then
        row = CreateLabel(plate)
        widgets.listRows[index] = row
    end
    return row
end

local function HideListRows(widgets)
    for _, row in ipairs(widgets.listRows) do
        row:Hide()
    end
end

local function HideWidgets(plate)
    local widgets = plateWidgets[plate]
    if not widgets then return end
    widgets.totText:Hide()
    widgets.threatText:Hide()
    widgets.threatBg:Hide()
    HideListRows(widgets)
end

-- Resolves the profile's font setting to an actual font file path.
-- LSM:Fetch resolves a registered font *name* (what's stored in the
-- profile and shown in the dropdown) to its actual file path.
-- LSM:GetDefault returns a name too, not a path, so it must also go
-- through Fetch — a bare literal is the last-resort fallback.
local function ResolveFontPath(fontName)
    return LSM:Fetch("font", fontName)
        or LSM:Fetch("font", LSM:GetDefault("font"))
        or "Fonts\\FRIZQT__.TTF"
end

-- Applies current profile settings (position/font/size/alignment) to one
-- already created text widget. Color is applied separately in
-- UpdatePlate since the threat label's color depends on tanking state,
-- not just settings.
local function ApplyLabelSettings(text, plate, settings)
    text:SetFont(ResolveFontPath(settings.font), settings.fontSize, "OUTLINE")

    -- The alignment setting doubles as both the anchor point (which edge
    -- of the text sits at the X/Y offset — matching WoW anchor-point
    -- names directly) and the multi-line justification, since
    -- "LEFT"/"CENTER"/"RIGHT" are valid values for both SetPoint's point
    -- and SetJustifyH.
    local align = settings.align or "CENTER"
    text:SetJustifyH(align)
    text:ClearAllPoints()
    text:SetPoint(align, plate, "CENTER", settings.offsetX, settings.offsetY)
end

-- Stacks list rows vertically below row 1, which sits at the normal
-- X/Y-offset anchor point like any other label. Each later row anchors
-- its top edge to the previous row's bottom edge, using whichever pair
-- of points matches the configured horizontal alignment so the stack
-- stays flush on whichever side the text is anchored to.
local ROW_GAP = 2
local STACK_POINTS = {
    LEFT = { "TOPLEFT", "BOTTOMLEFT" },
    RIGHT = { "TOPRIGHT", "BOTTOMRIGHT" },
    CENTER = { "TOP", "BOTTOM" },
}

local function PositionListRow(row, plate, settings, index, previousRow)
    local align = settings.align or "CENTER"
    row:ClearAllPoints()
    if index == 1 or not previousRow then
        row:SetPoint(align, plate, "CENTER", settings.offsetX, settings.offsetY)
    else
        local points = STACK_POINTS[align] or STACK_POINTS.CENTER
        row:SetPoint(points[1], previousRow, points[2], 0, -ROW_GAP)
    end
end

-- Shows (or hides) a solid background spanning the rendered rows, with a
-- little padding — covers both the single display (firstWidget ==
-- lastWidget) and the player list the same way. Top/bottom come from
-- firstWidget/lastWidget (rows stack top-to-bottom in rank order, so
-- those two always bound the stack vertically). Left/right both come
-- from firstWidget too (row 1 is always full-size/unscaled, while every
-- row after it is shrunk by secondaryScale, so row 1 is virtually
-- always the widest rendered row) — deliberately NOT measured per-row
-- via GetStringWidth()/GetWidth(): those were tried once (then
-- reverted) and silently broke rendering of every row past the first,
-- because the row's text was set via the secret-value widget-sink
-- technique (see ApplyExactThreatPercentage/RenderListRow) and querying
-- geometry back off a widget that received secret-tainted text appears
-- to throw too, aborting the render loop before later rows ever ran.
local BG_PADDING = 4

local function ApplyBackground(bg, enabled, color, firstWidget, lastWidget)
    if not enabled or not color or not firstWidget or not lastWidget then
        bg:Hide()
        return
    end
    local alpha = color[4] or 1
    if alpha <= 0 then
        bg:Hide()
        return
    end
    bg:SetColorTexture(color[1], color[2], color[3], alpha)
    bg:ClearAllPoints()
    bg:SetPoint("TOP", firstWidget, "TOP", 0, BG_PADDING)
    bg:SetPoint("BOTTOM", lastWidget, "BOTTOM", 0, -BG_PADDING)
    bg:SetPoint("LEFT", firstWidget, "LEFT", -BG_PADDING, 0)
    bg:SetPoint("RIGHT", firstWidget, "RIGHT", BG_PADDING, 0)
    bg:Show()
end

-- =====================================================================
-- Player list mode (requirements.md §13 "threat list")
-- =====================================================================

local function IterateGroupMembers()
    local members = { "player" }
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            members[#members + 1] = "raid" .. i
        end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do
            members[#members + 1] = "party" .. i
        end
    end
    local index = 0
    return function()
        index = index + 1
        return members[index]
    end
end

-- Collects one row per group member with any threat registered on
-- unitToken, ranked by UnitThreatSituation's status (0-3) rather than
-- raw threat magnitude.
--
-- v0.6.x used raw threat for ranking (EllesmereUI's own pattern), which
-- in practice always came back secret for every member on this client —
-- confirmed by the user: list mode never showed more than one row. The
-- fix: rank by `status` instead. It's the same function the working
-- Low/Medium/High fallback and the single-display color logic already
-- rely on, so it's reliably readable where raw threat isn't. Because
-- Readable(status) is required for inclusion, every row's status is
-- *known* non-secret by the time it's used for sorting or color — no
-- special handling needed there, unlike the per-row *value*, which is
-- still shown via the widget-sink technique (see ApplyThreatList) since
-- it can be secret even when status isn't.
local function CollectThreatRows(unitToken)
    local rows = {}
    for member in IterateGroupMembers() do
        if UnitExists(member) then
            local status = UnitThreatSituation(member, unitToken)
            if Readable(status) then
                rows[#rows + 1] = { unit = member, status = status }
            end
        end
    end
    table.sort(rows, function(a, b) return a.status > b.status end)
    return rows
end

local function ColorEscape(r, g, b)
    return string.format("|cff%02x%02x%02x", (r or 1) * 255, (g or 1) * 255, (b or 1) * 255)
end

-- Single-value fallback chain shared by list mode's "nothing to rank"
-- case and the "My Threat" solo-list choice — both just mean "render
-- the ordinary single display into threatText."
local function ApplyThreatSingle(widgets, unitToken)
    if ApplyExactThreatPercentage(widgets.threatText, unitToken) then
        widgets.threatText:Show()
        return true
    end
    if ApplyThreatLevelFallback(widgets.threatText, unitToken) then
        widgets.threatText:Show()
        return true
    end
    return false
end

-- Renders one list row's position/font/color/text from already-resolved
-- display data. Shared by the real ranked list (ApplyThreatList, below)
-- and the debug preview (RenderDebugPreview, further down) so both
-- render pixel-identical for the same settings — only how raw/scaled
-- and the name color were obtained differs upstream. Returns the row
-- widget (so the caller can track it as "previousRow" for stacking).
local function RenderListRow(widgets, plate, profile, index, previousRow, name, nr, ng, nb, isTanking, raw, scaled, format)
    local rowWidget = EnsureListRow(widgets, plate, index)

    local fontSize = profile.fontSize
    if index > 1 then
        fontSize = fontSize * ((profile.secondaryScale or 100) / 100)
    end
    rowWidget:SetFont(ResolveFontPath(profile.font), fontSize, "OUTLINE")
    rowWidget:SetJustifyH(profile.align or "CENTER")
    PositionListRow(rowWidget, plate, profile, index, previousRow)

    local valueColor = isTanking and profile.colorTanking or profile.colorNotTanking
    if not nr then
        nr, ng, nb = valueColor[1], valueColor[2], valueColor[3]
    end

    local valueFormat
    local a1, a2
    if format == 1 then
        valueFormat, a1 = "%.0f", raw
    elseif format == 3 then
        valueFormat, a1, a2 = "%.0f - %.0f%%", raw, scaled
    else
        valueFormat, a1 = "%.0f%%", scaled
    end

    local lineFormat = string.format(
        "%s%s|r  %s%s|r",
        ColorEscape(nr, ng, nb), name,
        ColorEscape(valueColor[1], valueColor[2], valueColor[3]), valueFormat
    )
    rowWidget:SetFormattedText(lineFormat, a1, a2)
    rowWidget:SetTextColor(1, 1, 1)
    rowWidget:Show()
    return rowWidget
end

-- Renders up to profile.threat.listCount rows, one per group member,
-- each as its own FontString (widgets.listRows[i]) rather than one
-- multi-line block of text — necessary because WoW text has no way to
-- mix font sizes within a single FontString, and rows below #1 need to
-- be independently shrinkable (secondaryScale). Returns
-- (success, firstWidget, lastWidget) for ApplyBackground to span, or
-- false if there was nothing to rank at all (caller falls back to the
-- single display).
local function ApplyThreatList(widgets, plate, unitToken)
    local profile = ThreatMeterNP.db.profile.threat
    local rows = CollectThreatRows(unitToken)
    if #rows == 0 then
        return false
    end

    local format = GetDisplayFormat()
    local wanted = profile.listCount or 3
    local shown = 0
    local previousRow = nil

    for i = 1, #rows do
        if shown >= wanted then break end
        local row = rows[i]

        -- The display value (raw/percentage) is fetched fresh per row
        -- and handed straight to a FontString's own :SetFormattedText,
        -- the same sanctioned sink ApplyExactThreatPercentage uses — it
        -- can be secret even though status isn't, so it's never read or
        -- compared here, only passed through as a format argument.
        -- SetFormattedText needs a real number, though (nil errors), so
        -- a row whose value is genuinely absent (not just secret) — rare,
        -- but distinct from status being readable — is skipped rather
        -- than risking that.
        local _, _, scaled, _, raw = UnitDetailedThreatSituation(row.unit, unitToken)
        local needsRaw = format == 1 or format == 3
        local needsScaled = format == 2 or format == 3
        if (not needsRaw or type(raw) == "number") and (not needsScaled or type(scaled) == "number") then
            shown = shown + 1

            local name = UnitName(row.unit) or row.unit
            local nr, ng, nb
            if profile.listColorByClass then
                local cr, cg, cb = GetClassColorRGB(row.unit)
                if cr then nr, ng, nb = cr, cg, cb end
            end

            -- status is already confirmed non-secret (Readable, above),
            -- so this comparison and the color pick are both safe.
            local isTanking = row.status >= 2

            previousRow = RenderListRow(widgets, plate, profile, shown, previousRow, name, nr, ng, nb, isTanking, raw, scaled, format)
        end
    end

    -- Hide any previously-shown rows beyond what's needed this update
    -- (e.g. listCount dropped, or fewer members are readable now).
    for i = shown + 1, #widgets.listRows do
        widgets.listRows[i]:Hide()
    end

    if shown == 0 then
        return false
    end
    return true, widgets.listRows[1], widgets.listRows[shown]
end

-- Dispatches to the single display or the ranked list, per the profile,
-- and returns (success, firstWidget, lastWidget) so UpdatePlate can span
-- the optional background across whichever widget(s) actually rendered.
local function ApplyThreatDisplay(widgets, plate, unitToken)
    local profile = ThreatMeterNP.db.profile.threat

    local useList = profile.listMode and not (profile.listCount == 1 and profile.soloListMode == "mine")
    if useList then
        local ok, first, last = ApplyThreatList(widgets, plate, unitToken)
        if ok then
            widgets.threatText:Hide()
            return true, first, last
        end
        -- Nothing to rank right now — fall back to the single display.
        HideListRows(widgets)
    else
        HideListRows(widgets)
    end

    if ApplyThreatSingle(widgets, unitToken) then
        return true, widgets.threatText, widgets.threatText
    end
    widgets.threatText:Hide()
    return false
end

-- =====================================================================
-- Debug preview (requirements.md §13 "Debug Mode") — fake names/threat
-- on every nameplate, for checking appearance without needing a real
-- pull. Deliberately a separate path from the real one above rather
-- than threading fake data through it: these values are plain Lua
-- numbers (never secret), and reusing RenderListRow for the list case
-- means the preview renders pixel-identical to reality for whatever
-- settings are configured — only where the data comes from differs.
-- =====================================================================

local DEBUG_ROSTER_POOL = {
    { name = "Thrassian", class = "WARRIOR" },
    { name = "Lunaestra",  class = "PRIEST" },
    { name = "Grimjaw",    class = "DEATHKNIGHT" },
    { name = "Faelynn",    class = "DRUID" },
    { name = "Borak",      class = "SHAMAN" },
    { name = "Ilyndra",    class = "MAGE" },
    { name = "Doomhowl",   class = "WARLOCK" },
    { name = "Sarael",     class = "PALADIN" },
}

-- Built once, lazily, the first time debug mode actually renders — the
-- same roster (names/classes) stays stable for the rest of the session;
-- only each member's threat values re-roll every tick (see below), so
-- the preview looks like live combat without being unreadably jittery.
local debugRoster

local function EnsureDebugRoster()
    if debugRoster then return debugRoster end
    debugRoster = {}
    for _, entry in ipairs(DEBUG_ROSTER_POOL) do
        debugRoster[#debugRoster + 1] = { name = entry.name, class = entry.class }
    end
    return debugRoster
end

local function RollDebugRoster()
    for _, m in ipairs(debugRoster) do
        m.status = math.random(0, 3)
        m.isTanking = m.status >= 2
        m.raw = math.random(500, 50000)
        m.scaled = math.random(10, 150)
    end
end

-- Renders the fake preview for one nameplate: re-rolls the shared
-- roster (each plate gets its own independent-looking snapshot, since
-- rolling happens right before that plate's own render), then draws
-- target-of-target and threat exactly as the real path would, honoring
-- every current display setting (list mode, row count, display format,
-- colors, alignment, secondary scale, background).
local function RenderDebugPreview(plate)
    local profile = ThreatMeterNP.db.profile
    local widgets = EnsureWidgets(plate)

    EnsureDebugRoster()
    RollDebugRoster()
    local sorted = {}
    for _, m in ipairs(debugRoster) do sorted[#sorted + 1] = m end
    table.sort(sorted, function(a, b) return a.status > b.status end)
    local topMember = sorted[1]

    -- Target of target: the fake "aggro holder" is whoever ranks #1,
    -- same concept the real target-of-target label and "Display threat
    -- owner" both rely on.
    local totSettings = profile.targetOfTarget
    if totSettings.enabled ~= false then
        ApplyLabelSettings(widgets.totText, plate, totSettings)
        local tr, tg, tb = totSettings.color[1], totSettings.color[2], totSettings.color[3]
        if totSettings.colorByClass then
            local cr, cg, cb = GetClassColorRGBByFilename(topMember.class)
            if cr then tr, tg, tb = cr, cg, cb end
        end
        widgets.totText:SetFormattedText("T: %s", topMember.name)
        widgets.totText:SetTextColor(tr, tg, tb)
        widgets.totText:Show()
    else
        widgets.totText:Hide()
    end

    -- Threat: list or single, mirroring ApplyThreatDisplay's own logic
    -- but reading the fake roster instead of real UnitX() calls.
    local tprofile = profile.threat
    if tprofile.enabled ~= false then
        ApplyLabelSettings(widgets.threatText, plate, tprofile)
        local format = GetDisplayFormat()
        local first, last

        if tprofile.listMode then
            local wanted = tprofile.listCount or 3
            local previousRow = nil
            for i = 1, math.min(wanted, #sorted) do
                local m = sorted[i]
                local nr, ng, nb
                if tprofile.listColorByClass then
                    local cr, cg, cb = GetClassColorRGBByFilename(m.class)
                    if cr then nr, ng, nb = cr, cg, cb end
                end
                previousRow = RenderListRow(widgets, plate, tprofile, i, previousRow, m.name, nr, ng, nb, m.isTanking, m.raw, m.scaled, format)
                if i == 1 then first = previousRow end
                last = previousRow
            end
            for i = math.min(wanted, #sorted) + 1, #widgets.listRows do
                widgets.listRows[i]:Hide()
            end
            widgets.threatText:Hide()
        else
            HideListRows(widgets)
            local prefix = tprofile.showOwner and (topMember.name .. ": ") or ""
            local valueFormat, a1, a2
            if format == 1 then
                valueFormat, a1 = "%.0f", topMember.raw
            elseif format == 3 then
                valueFormat, a1, a2 = "%.0f - %.0f%%", topMember.raw, topMember.scaled
            else
                valueFormat, a1 = "%.0f%%", topMember.scaled
            end
            widgets.threatText:SetFormattedText(prefix .. valueFormat, a1, a2)
            local valueColor = topMember.isTanking and tprofile.colorTanking or tprofile.colorNotTanking
            widgets.threatText:SetTextColor(valueColor[1], valueColor[2], valueColor[3])
            widgets.threatText:Show()
            first, last = widgets.threatText, widgets.threatText
        end

        ApplyBackground(widgets.threatBg, tprofile.bgEnabled, tprofile.bgColor, first, last)
    else
        widgets.threatText:Hide()
        HideListRows(widgets)
        widgets.threatBg:Hide()
    end
end

-- =====================================================================
-- Update logic
-- =====================================================================

local function IsEnabledForGroupStatus()
    local visibility = ThreatMeterNP.db.profile.visibility
    if IsInRaid() then return visibility.raid end
    if IsInGroup() then return visibility.party end
    return visibility.solo
end

-- v1 scope: enemy/hostile nameplates only (requirements.md §4).
local function IsEligibleUnit(unitToken)
    return UnitExists(unitToken) and UnitCanAttack("player", unitToken)
end

local function UpdatePlate(unitToken, plate)
    if not UnitExists(unitToken) then
        HideWidgets(plate)
        return
    end

    -- Debug mode bypasses the enemy-only and solo/group/raid visibility
    -- checks below entirely — it's meant to preview on every nameplate,
    -- any time, without needing a real pull.
    if ThreatMeterNP.db.profile.debugMode then
        RenderDebugPreview(plate)
        return
    end

    if not IsEnabledForGroupStatus() or not IsEligibleUnit(unitToken) then
        HideWidgets(plate)
        return
    end

    local profile = ThreatMeterNP.db.profile
    local widgets = EnsureWidgets(plate)

    ApplyLabelSettings(widgets.totText, plate, profile.targetOfTarget)

    local totToken = GetTargetToken(unitToken)
    if profile.targetOfTarget.enabled ~= false and UnitExists(totToken) and not UnitIsUnit(totToken, unitToken) then
        local name = UnitName(totToken)
        widgets.totText:SetFormattedText("T: %s", name or "?")

        local r, g, b = profile.targetOfTarget.color[1], profile.targetOfTarget.color[2], profile.targetOfTarget.color[3]
        if profile.targetOfTarget.colorByClass then
            local cr, cg, cb = GetClassColorRGB(totToken)
            if cr then
                r, g, b = cr, cg, cb
            end
        end
        widgets.totText:SetTextColor(r, g, b)
        widgets.totText:Show()
    else
        widgets.totText:Hide()
    end

    if profile.threat.enabled ~= false then
        ApplyLabelSettings(widgets.threatText, plate, profile.threat)
        local _, first, last = ApplyThreatDisplay(widgets, plate, unitToken)
        ApplyBackground(widgets.threatBg, profile.threat.bgEnabled, profile.threat.bgColor, first, last)
    else
        widgets.threatText:Hide()
        HideListRows(widgets)
        widgets.threatBg:Hide()
    end
end

-- Called by Options.lua whenever a setting changes, so sliders/color
-- pickers/dropdowns update already-visible nameplates immediately
-- instead of waiting for the next add/remove event.
function ThreatMeterNP:RefreshAllWidgets()
    for unitToken, plate in pairs(unitToPlate) do
        local ok, err = pcall(UpdatePlate, unitToken, plate)
        if not ok then
            geterrorhandler()(err)
        end
    end
end

-- =====================================================================
-- Event / polling driver
-- =====================================================================

local driver = CreateFrame("Frame")
driver:RegisterEvent("NAME_PLATE_UNIT_ADDED")
driver:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")

local function ResyncAllPlates()
    unitToPlate = {}
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local unitToken = plate.unitToken
        if unitToken and UnitExists(unitToken) then
            unitToPlate[unitToken] = plate
        end
    end
end

driver:SetScript("OnEvent", function(_, event, unitToken)
    if event == "NAME_PLATE_UNIT_ADDED" then
        local plate = C_NamePlate.GetNamePlateForUnit(unitToken)
        if plate then
            unitToPlate[unitToken] = plate
            local ok, err = pcall(UpdatePlate, unitToken, plate)
            if not ok then
                geterrorhandler()(err)
            end
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local plate = unitToPlate[unitToken]
        if plate then
            HideWidgets(plate)
        end
        unitToPlate[unitToken] = nil
    elseif event == "PLAYER_ENTERING_WORLD" then
        ResyncAllPlates()
    end
end)

local elapsedSinceUpdate = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    elapsedSinceUpdate = elapsedSinceUpdate + elapsed
    if elapsedSinceUpdate < UPDATE_THROTTLE then return end
    elapsedSinceUpdate = 0

    -- pcall per unit: one unit erroring (e.g. an unexpected secret-value
    -- case) must not stop every other nameplate from updating this tick.
    for unitToken, plate in pairs(unitToPlate) do
        local ok, err = pcall(UpdatePlate, unitToken, plate)
        if not ok then
            geterrorhandler()(err)
        end
    end
end)
