-- ThreatMeterNP options: Ace3 addon object, SavedVariables (AceDB),
-- options panel (AceConfig/AceConfigDialog), minimap button
-- (LibDataBroker + LibDBIcon), and the slash command. See
-- requirements.md §13 for the spec this implements.

-- Global on purpose: ThreatMeterNP.lua (the nameplate engine) reads
-- ThreatMeterNP.db.profile at runtime.
ThreatMeterNP = LibStub("AceAddon-3.0"):NewAddon("ThreatMeterNP", "AceConsole-3.0")

local LSM = LibStub("LibSharedMedia-3.0")
local defaultFont = LSM:GetDefault("font") or "Friz Quadrata TT"

local defaults = {
    profile = {
        debugMode = false,
        visibility = {
            solo = true,
            party = true,
            raid = true,
        },
        targetOfTarget = {
            enabled = true,
            offsetX = 0,
            offsetY = -28,
            font = "Arial Narrow",
            fontSize = 10,
            align = "CENTER",
            color = { 1, 1, 1 },
            colorByClass = false,
        },
        threat = {
            enabled = true,
            offsetX = 74,
            offsetY = 0,
            font = defaultFont,
            fontSize = 12,
            align = "CENTER",
            colorTanking = { 0.3, 1, 0.3 },
            colorNotTanking = { 1, 0.3, 0.3 },
            displayFormat = 2, -- 1=Numeric, 2=Percentage, 3=Numeric - Percentage
            showOwner = false,
            bgEnabled = false,
            bgColor = { 0, 0, 0, 0.5 },
            listMode = false,
            listCount = 3,
            listColorByClass = false,
            soloListMode = "mine", -- "mine" or "top"; only matters when listCount == 1
            secondaryScale = 100, -- percent, rows below #1 in the list
        },
        minimap = {
            hide = false,
        },
    },
}

-- =====================================================================
-- Options table
-- =====================================================================

local function FontValues()
    local values = {}
    for _, name in ipairs(LSM:List("font")) do
        values[name] = name
    end
    return values
end

local function ColorGet(path)
    return function(_, ...)
        local c = ThreatMeterNP.db.profile
        for _, key in ipairs(path) do
            c = c[key]
        end
        return c[1], c[2], c[3]
    end
end

local function ColorSet(path)
    return function(_, r, g, b)
        local c = ThreatMeterNP.db.profile
        for _, key in ipairs(path) do
            c = c[key]
        end
        c[1], c[2], c[3] = r, g, b
        ThreatMeterNP:RefreshAllWidgets()
    end
end

-- Same as ColorGet/ColorSet but for a 4-element {r,g,b,a} color (the
-- background color, which needs alpha) rather than the plain 3-element
-- ones everywhere else.
local function ColorGetA(path)
    return function(_, ...)
        local c = ThreatMeterNP.db.profile
        for _, key in ipairs(path) do
            c = c[key]
        end
        return c[1], c[2], c[3], c[4]
    end
end

local function ColorSetA(path)
    return function(_, r, g, b, a)
        local c = ThreatMeterNP.db.profile
        for _, key in ipairs(path) do
            c = c[key]
        end
        c[1], c[2], c[3], c[4] = r, g, b, a
        ThreatMeterNP:RefreshAllWidgets()
    end
end

local function ValueGet(path)
    return function()
        local c = ThreatMeterNP.db.profile
        for _, key in ipairs(path) do
            c = c[key]
        end
        return c
    end
end

local function ValueSet(path)
    return function(_, value)
        local c = ThreatMeterNP.db.profile
        for i = 1, #path - 1 do
            c = c[path[i]]
        end
        c[path[#path]] = value
        ThreatMeterNP:RefreshAllWidgets()
    end
end

-- A full-width blank row, used between logical groups of options so the
-- panel reads as sections instead of one dense block.
local function Spacer(order)
    return { type = "description", name = " ", order = order, width = "full" }
end

-- width = "relative" + relWidth is AceConfigDialog's fractional-width
-- control (SetRelativeWidth) — confirmed in the vendored
-- AceConfigDialog-3.0 source — the precise way to put N controls on one
-- row (1/N each) rather than guessing with "half"/"double"/"normal",
-- which are multiples of a fixed "normal" unit, not container fractions.
local function Share(n)
    return "relative", 1 / n
end

local function LabelOptions(order, name, prefix, includeThreatColors, includeColorByClass, includeEnabledToggle)
    local o = order
    local function nextOrder() o = o + 1; return o end

    local xWidth, xRel = Share(3)
    local yWidth, yRel = Share(3)
    local alignWidth, alignRel = Share(3)
    local fontWidth, fontRel = Share(2)
    local fontSizeWidth, fontSizeRel = Share(2)

    local args = {
        header = { type = "header", name = name, order = nextOrder() },
    }

    if includeEnabledToggle then
        -- Checkbox reads as checked when unset (nil), matching the
        -- engine's own "enabled ~= false" default-true behavior for an
        -- existing profile predating this setting — ValueGet alone would
        -- show it unchecked (nil is falsy) despite the label actually
        -- showing, a visible mismatch.
        local rawGet = ValueGet({ prefix, "enabled" })
        args.enabled = {
            type = "toggle", name = "Show " .. name, width = "full",
            order = nextOrder(),
            get = function(...) return rawGet(...) ~= false end,
            set = ValueSet({ prefix, "enabled" }),
        }
    end

    args.offsetX = {
        type = "range", name = "X offset", min = -150, max = 150, step = 1,
        width = xWidth, relWidth = xRel,
        order = nextOrder(), get = ValueGet({ prefix, "offsetX" }), set = ValueSet({ prefix, "offsetX" }),
    }
    args.offsetY = {
        type = "range", name = "Y offset", min = -150, max = 150, step = 1,
        width = yWidth, relWidth = yRel,
        order = nextOrder(), get = ValueGet({ prefix, "offsetY" }), set = ValueSet({ prefix, "offsetY" }),
    }
    args.align = {
        type = "select", name = "Text alignment",
        width = alignWidth, relWidth = alignRel,
        order = nextOrder(),
        desc = "Which edge of the text sits at the X/Y offset: Left/Right anchor that " ..
            "edge there and the text grows away from it; Center (default) centers the " ..
            "text on the offset, as before.",
        values = { LEFT = "Left", CENTER = "Middle", RIGHT = "Right" },
        get = ValueGet({ prefix, "align" }), set = ValueSet({ prefix, "align" }),
    }
    args.spacer1 = Spacer(nextOrder())
    args.font = {
        type = "select", name = "Font",
        width = fontWidth, relWidth = fontRel,
        order = nextOrder(), values = FontValues, get = ValueGet({ prefix, "font" }), set = ValueSet({ prefix, "font" }),
    }
    args.fontSize = {
        type = "range", name = "Font size", min = 6, max = 32, step = 1,
        width = fontSizeWidth, relWidth = fontSizeRel,
        order = nextOrder(), get = ValueGet({ prefix, "fontSize" }), set = ValueSet({ prefix, "fontSize" }),
    }
    args.spacer2 = Spacer(nextOrder())

    if includeThreatColors then
        local exactValuesNote = "Only used when the game exposes an exact threat number " ..
            "(uncommon on this client — most of the time you'll see the fixed Low/Medium/High " ..
            "indicator instead, which has its own built-in colors)."
        local tankWidth, tankRel = Share(2)
        local notTankWidth, notTankRel = Share(2)
        local displayFormatWidth, displayFormatRel = Share(2)
        local showOwnerWidth, showOwnerRel = Share(2)
        args.colorTanking = {
            type = "color", name = "Color (tanking)", desc = exactValuesNote,
            width = tankWidth, relWidth = tankRel,
            order = nextOrder(), get = ColorGet({ prefix, "colorTanking" }), set = ColorSet({ prefix, "colorTanking" }),
        }
        args.colorNotTanking = {
            type = "color", name = "Color (not tanking)", desc = exactValuesNote,
            width = notTankWidth, relWidth = notTankRel,
            order = nextOrder(), get = ColorGet({ prefix, "colorNotTanking" }), set = ColorSet({ prefix, "colorNotTanking" }),
        }
        args.spacer3 = Spacer(nextOrder())
        local bgToggleWidth, bgToggleRel = Share(2)
        local bgColorWidth, bgColorRel = Share(2)
        args.bgEnabled = {
            type = "toggle", name = "Background",
            desc = "Shows a solid background behind the threat display — the single value or " ..
                "the whole player list, whichever is active.",
            width = bgToggleWidth, relWidth = bgToggleRel,
            order = nextOrder(),
            get = ValueGet({ prefix, "bgEnabled" }), set = ValueSet({ prefix, "bgEnabled" }),
        }
        args.bgColor = {
            type = "color", name = "Background color", hasAlpha = true,
            width = bgColorWidth, relWidth = bgColorRel,
            order = nextOrder(),
            get = ColorGetA({ prefix, "bgColor" }), set = ColorSetA({ prefix, "bgColor" }),
        }
        args.spacer3b = Spacer(nextOrder())
        args.displayFormat = {
            type = "select", name = "Display format",
            width = displayFormatWidth, relWidth = displayFormatRel,
            order = nextOrder(),
            values = { [1] = "Numeric", [2] = "Percentage", [3] = "Numeric - Percentage" },
            get = ValueGet({ prefix, "displayFormat" }), set = ValueSet({ prefix, "displayFormat" }),
        }
        args.showOwner = {
            type = "toggle", name = "Display threat owner",
            width = showOwnerWidth, relWidth = showOwnerRel,
            desc = "Shows the name of whoever currently has aggro on this unit before the " ..
                "number (e.g. \"Bob: 87%\"), or \"You\" when that's you. Uses the unit's " ..
                "current target, so it works regardless of the exact-value restrictions above.",
            order = nextOrder(),
            hidden = function() return ThreatMeterNP.db.profile.threat.listMode end,
            get = ValueGet({ prefix, "showOwner" }), set = ValueSet({ prefix, "showOwner" }),
        }
        args.spacer4 = Spacer(nextOrder())
        args.listMode = {
            type = "toggle", name = "Show a player list instead of your own threat", width = "full",
            desc = "Shows up to the configured number of group/raid members ranked by threat " ..
                "on this unit, instead of just your own. Only includes members whose threat " ..
                "value the game currently exposes to add-ons at that moment — may show fewer " ..
                "rows (or none) when it doesn't.",
            order = nextOrder(),
            get = ValueGet({ prefix, "listMode" }), set = ValueSet({ prefix, "listMode" }),
        }
        args.listCount = {
            type = "range", name = "Players shown", width = "full",
            min = 1, max = 3, step = 1,
            order = nextOrder(),
            hidden = function() return not ThreatMeterNP.db.profile.threat.listMode end,
            get = ValueGet({ prefix, "listCount" }), set = ValueSet({ prefix, "listCount" }),
        }
        args.soloListMode = {
            type = "select", name = "When showing 1 player", width = "full",
            desc = "With only one row shown, who should it be? \"My Threat\" always shows you " ..
                "(same as list mode being off). \"Top Threat\" shows whoever currently ranks " ..
                "#1, which might not be you.",
            values = { mine = "My Threat", top = "Top Threat" },
            order = nextOrder(),
            hidden = function()
                local t = ThreatMeterNP.db.profile.threat
                return not (t.listMode and t.listCount == 1)
            end,
            get = ValueGet({ prefix, "soloListMode" }), set = ValueSet({ prefix, "soloListMode" }),
        }
        args.secondaryScale = {
            type = "range", name = "Lower row size (%)", width = "full",
            min = 50, max = 100, step = 5,
            desc = "Size of rows below #1, as a percentage of the font size above. 100 = no " ..
                "change (default).",
            order = nextOrder(),
            hidden = function()
                local t = ThreatMeterNP.db.profile.threat
                return not (t.listMode and t.listCount > 1)
            end,
            get = ValueGet({ prefix, "secondaryScale" }), set = ValueSet({ prefix, "secondaryScale" }),
        }
        args.listColorByClass = {
            type = "toggle", name = "Color names by class", width = "full",
            order = nextOrder(),
            hidden = function() return not ThreatMeterNP.db.profile.threat.listMode end,
            get = ValueGet({ prefix, "listColorByClass" }), set = ValueSet({ prefix, "listColorByClass" }),
        }
    else
        local byClassWidth, byClassRel = Share(2)
        local colorWidth, colorRel = Share(2)
        if includeColorByClass then
            args.colorByClass = {
                type = "toggle", name = "Color by class",
                width = byClassWidth, relWidth = byClassRel,
                desc = "Color the name using the targeted unit's class color (players only) instead of the color below.",
                order = nextOrder(),
                get = ValueGet({ prefix, "colorByClass" }), set = ValueSet({ prefix, "colorByClass" }),
            }
        end
        args.color = {
            type = "color", name = "Color",
            width = colorWidth, relWidth = colorRel,
            order = nextOrder(),
            disabled = includeColorByClass and ValueGet({ prefix, "colorByClass" }) or nil,
            get = ColorGet({ prefix, "color" }), set = ColorSet({ prefix, "color" }),
        }
    end

    return args
end

local function BuildOptions()
    return {
        type = "group",
        name = "ThreatMeterNP",
        args = {
            visibility = {
                type = "group", inline = true, name = "Enabled when", order = 1,
                args = {
                    solo = {
                        type = "toggle", name = "Solo", order = 1,
                        get = ValueGet({ "visibility", "solo" }), set = ValueSet({ "visibility", "solo" }),
                    },
                    party = {
                        type = "toggle", name = "In a group", order = 2,
                        get = ValueGet({ "visibility", "party" }), set = ValueSet({ "visibility", "party" }),
                    },
                    raid = {
                        type = "toggle", name = "In a raid", order = 3,
                        get = ValueGet({ "visibility", "raid" }), set = ValueSet({ "visibility", "raid" }),
                    },
                },
            },
            targetOfTarget = {
                type = "group", inline = true, name = "Target of target", order = 2,
                args = LabelOptions(1, "Target of target", "targetOfTarget", false, true, true),
            },
            threat = {
                type = "group", inline = true, name = "Threat", order = 3,
                args = LabelOptions(1, "Threat", "threat", true, false, true),
            },
            debug = {
                type = "group", inline = true, name = "Debug", order = 4,
                args = {
                    debugMode = {
                        type = "toggle", name = "Debug Mode (preview)",
                        desc = "Shows made-up names and threat numbers on EVERY nameplate " ..
                            "(friendly or enemy, solo or grouped), updating live, so you can " ..
                            "check how your current settings look without needing a real " ..
                            "pull. Not real data — turn this off before actually playing.",
                        order = 1,
                        get = ValueGet({ "debugMode" }), set = ValueSet({ "debugMode" }),
                    },
                },
            },
        },
    }
end

-- =====================================================================
-- Lifecycle
-- =====================================================================

function ThreatMeterNP:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("ThreatMeterNPDB", defaults, true)

    LibStub("AceConfig-3.0"):RegisterOptionsTable("ThreatMeterNP", BuildOptions())
    self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ThreatMeterNP", "ThreatMeterNP")

    local LDB = LibStub("LibDataBroker-1.1")
    local dataObject = LDB:NewDataObject("ThreatMeterNP", {
        type = "launcher",
        icon = "Interface\\AddOns\\ThreatMeterNP\\media\\icon",
        OnClick = function()
            LibStub("AceConfigDialog-3.0"):Open("ThreatMeterNP")
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("ThreatMeterNP")
            tooltip:AddLine("|cffffffffClick|r to open options")
        end,
    })
    LibStub("LibDBIcon-1.0"):Register("ThreatMeterNP", dataObject, self.db.profile.minimap)

    self:RegisterChatCommand("threatmeternp", "SlashCommand")
    self:RegisterChatCommand("tmnp", "SlashCommand")
end

function ThreatMeterNP:SlashCommand()
    LibStub("AceConfigDialog-3.0"):Open("ThreatMeterNP")
end
