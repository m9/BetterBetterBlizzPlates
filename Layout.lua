-- Regroups the settings read by Harvest into task-based pages.
-- Rules use BetterBlizzPlates' setting keys, so they work in any language.
-- Anything no rule knows stays visible on a fallback page.

local _, ns = ...
local H = ns.Harvest
local Clean = H.Clean

local R = {}
ns.Layout = R

-- Page order in the sidebar.
local PAGES = {
    "Nameplates", "Size and stacking", "Names and text", "Colors", "Castbar",
    "Auras", "Indicators", "Personal bar", "System", "Other",
}
local FOLDED = { Indicators = true }

-- A BetterBlizzPlates group goes to `page` when it holds these settings.
--   has    = exact keys (strong match)      prefix = key prefixes
--   master = key of the checkbox that turns the feature on (shown in the group header)
--   title  = name to use when BetterBlizzPlates gives the group none
local GROUPS = {
    { id = "general", page = "Nameplates", has = { "classicNameplates", "smallPetsInPvP" } },
    { id = "enemy", page = "Nameplates", has = { "enemyColorName", "hideEnemyNameText" } },
    { id = "friendly", page = "Nameplates", has = { "friendlyColorName", "hideFriendlyNameText" } },
    { id = "features", page = "Nameplates", has = { "testAllEnabledFeatures" } },
    { id = "look", page = "Nameplates", has = { "useCustomFont", "useCustomTextureForBars" } },
    { id = "visibility", page = "Nameplates", has = { "nameplateShowAll", "setCVarAcrossAllCharacters" } },
    { id = "alpha", page = "Nameplates", has = { "enableNpNonTargetAlpha" } },

    { id = "fakeName", page = "Names and text", prefix = { "useFakeName", "fakeName" } },
    { id = "arena", page = "Names and text", has = { "shortArenaSpecName", "arenaIndicatorTestMode" },
        prefix = { "arenaI" } },
    { id = "targetText", page = "Names and text", prefix = { "targetText" }, master = "showNameplateTargetText" },
    { id = "healthNumbers", page = "Names and text", has = { "healthNumbersTestMode" },
        prefix = { "healthNumbers" }, master = "healthNumbers" },

    { id = "colorNPC", page = "Colors", prefix = { "colorNPC" } },
    { id = "threat", page = "Colors", title = "Threat Colors", master = "enemyColorThreat",
        prefix = { "threatColor", "enemyColorThreat", "threatPercent" } },

    { id = "castbar", page = "Castbar", has = { "nameplateCastbarTestMode", "enableCastbarCustomization" } },
    { id = "castbarSize", page = "Castbar", has = { "fitCastIconLeftOfCast" } },

    { id = "healerIndicator", page = "Indicators", prefix = { "healerIndicator" }, master = "healerIndicator" },
    { id = "classIndicator", page = "Indicators", prefix = { "classIndicator", "classIcon" }, master = "classIndicator" },
    { id = "targetIndicator", page = "Indicators", prefix = { "targetIndicator" }, master = "targetIndicator" },
    { id = "focusTargetIndicator", page = "Indicators", prefix = { "focusTargetIndicator" },
        master = "focusTargetIndicator" },
    { id = "partyPointer", page = "Indicators", prefix = { "partyPointer" }, master = "partyPointer" },
    { id = "executeIndicator", page = "Indicators", prefix = { "executeIndicator", "executeSkull" },
        master = "executeIndicator" },
    { id = "totemIndicator", page = "Indicators", prefix = { "totemIndicator" }, master = "totemIndicator" },
    { id = "combatIndicator", page = "Indicators", prefix = { "combatIndicator" }, master = "combatIndicator" },
    { id = "petIndicator", page = "Indicators", prefix = { "petIndicator" }, master = "petIndicator" },
    { id = "absorbIndicator", page = "Indicators", prefix = { "absorbIndicator" }, master = "absorbIndicator" },
    { id = "factionIndicator", page = "Indicators", prefix = { "factionIndicator" }, master = "factionIndicator" },
    { id = "questIndicator", page = "Indicators", prefix = { "questIndicator" }, master = "questIndicator" },
    { id = "bgIndicator", page = "Indicators", prefix = { "bgIndicator" }, master = "bgIndicator" },
    { id = "raidmark", page = "Indicators", prefix = { "raidmark", "hideRaidmark" } },

    { id = "resource", page = "Personal bar", has = { "nameplateResourceOnTarget", "hideResourceFrame" } },
    { id = "cvars", page = "System", title = "CVars", has = { "disableCVarForceOnLogin", "avoidCVarPickup" } },
    { id = "gui", page = "System", has = { "forceEnglishGUI", "guiFontEnabled" } },
}

-- Groups no rule matched: page by a setting their original page holds.
local SOURCES = {
    { page = "Auras", has = "enableNameplateAuraCustomisation" },
    { page = "Size and stacking", has = "nameplateStackingTypes_Enemy" },
    { page = "Castbar", has = "nameplateCastbarTestMode" },
    { page = "Indicators", has = "healerIndicatorTestMode" },
    { page = "Nameplates", has = "classicNameplates" },
    { page = "Nameplates", has = "nameplateResourceOnTarget" },
    { page = "Other", has = "showGuildNames" },
}

-- New groups made from single settings.
local EXTRA = {
    names = { page = "Names and text", title = "Names" },
    border = { page = "Colors", title = "Border and background" },
    personal = { page = "Personal bar", title = "Personal bar" },
}

-- Single settings that move to another group (group id or EXTRA id).
local ITEMS = {
    overShields = "absorbIndicator",
    showGuildNames = "names", showNpcTitle = "names", npcTitleColor = "names", showLastNameNpc = "names",
    anonMode = "names", pvpTitleMode = "names", toggleNamesOffDuringPVE = "names",
    scaleNpNameWithParent = "names", skipAdjustingFixedFonts = "names", customFontSizeEnabled = "names",
    showNameplateShadow = "border", changeNameplateBorderSize = "border",
    changeNameplateBorderColor = "border", changeNpHpBgColor = "border",
    prdLegacyLook = "personal", fancyPrdAltTexture = "personal", hidePersonalManaFX = "personal",
    personalNpTRP3Color = "personal", personalBarTweaks = "personal",
}

-- Settings without a key (sliders, dropdowns) that sit under the wrong heading.
-- Both sides are BetterBlizzPlates locale keys: the labels, and the group they belong to.
local LABEL_MOVES = {
    { to = "Personal_Resource_Display", labels = { "PRD_Auras_Per_Row", "PRD_Max_Auras", "PRD_Aura_Align" } },
}

-- Test modes become "Preview" buttons.
local PREVIEW_ALL = "testAllEnabledFeatures"
local function isPreviewKey(key)
    return type(key) == "string" and (key:find("TestMode$") ~= nil)
end

-- Test buttons (not checkboxes): locale keys of their off and on labels.
local PREVIEW_BUTTONS = {
    { off = "Test_Auras", on = "Stop_Test" },
    { off = "Test", on = "Label_Stop_Testing" },
}

------------------------------------------------------------
local function keysOf(sections)
    local keys = {}
    for _, section in ipairs(sections) do
        for _, item in ipairs(section.items) do
            if item.key then keys[item.key] = true end
        end
    end
    return keys
end

local function score(rule, keys)
    local total = 0
    for _, key in ipairs(rule.has or {}) do
        if keys[key] then total = total + 100 end
    end
    for key in pairs(keys) do
        for _, prefix in ipairs(rule.prefix or {}) do
            if key:sub(1, #prefix) == prefix then
                total = total + 1
                break
            end
        end
    end
    return total
end

local function bestRule(keys)
    local best, bestScore = nil, 0
    for _, rule in ipairs(GROUPS) do
        local s = score(rule, keys)
        if s > bestScore then best, bestScore = rule, s end
    end
    return best
end

-- Sections of one original page as families: a group plus its "Group: Sub" parts.
local function families(page)
    local list, byBase = {}, {}
    for _, section in ipairs(page.sections) do
        local base = section.base or section.name
        local family = byBase[base]
        if not family then
            family = { name = base, sections = {} }
            byBase[base] = family
            list[#list + 1] = family
        end
        family.sections[#family.sections + 1] = section
    end
    return list
end

-- Takes `item` and its nested settings out of `items`. Returns them as a list.
local function cut(items, index)
    local block = { table.remove(items, index) }
    local depth = block[1].depth or 0
    while items[index] and (items[index].depth or 0) > depth do
        block[#block + 1] = table.remove(items, index)
    end
    return block
end

function R.Build(source, generalName)
    local pages, pageByName = {}, {}
    for _, name in ipairs(PAGES) do
        local page = { name = name, sections = {}, items = {}, groups = {}, fold = FOLDED[name] or false }
        pages[#pages + 1] = page
        pageByName[name] = page
    end

    local groupById = {}
    local function newGroup(pageName, name, id)
        local page = pageByName[pageName] or pageByName.Other
        local group = { name = name, page = page, items = {}, subs = {}, subByName = {} }
        page.groups[#page.groups + 1] = group
        if id then groupById[id] = group end
        return group
    end

    -- 1. Whole groups.
    for _, srcPage in ipairs(source.pages) do
        local pageKeys = keysOf(srcPage.sections)
        local fallback = "Other"
        for _, entry in ipairs(SOURCES) do
            if pageKeys[entry.has] then
                fallback = entry.page
                break
            end
        end
        srcPage.fallback = fallback

        local lastPage
        for _, family in ipairs(families(srcPage)) do
            local keys = keysOf(family.sections)
            local rule = bestRule(keys)
            local group
            if rule then
                group = groupById[rule.id]
                if not group then
                    local name = family.name
                    if name == generalName and rule.title then name = rule.title end
                    group = newGroup(rule.page, name, rule.id)
                elseif group.name == generalName and family.name ~= generalName then
                    group.name = family.name
                end
            else
                group = newGroup(next(keys) == nil and lastPage or fallback, family.name)
            end
            lastPage = group.page.name

            for _, section in ipairs(family.sections) do
                local target = group.items
                if section.sub then
                    local sub = group.subByName[section.sub]
                    if not sub then
                        sub = { name = section.sub, items = {} }
                        group.subByName[section.sub] = sub
                        group.subs[#group.subs + 1] = sub
                    end
                    target = sub.items
                end
                for _, item in ipairs(section.items) do
                    item.srcPage = srcPage
                    target[#target + 1] = item
                end
            end
        end
    end

    -- 1b. Keyless settings under the wrong heading, matched by label.
    local labels = type(BBP) == "table" and BBP.L or nil
    if type(labels) == "table" then
        for _, move in ipairs(LABEL_MOVES) do
            local wanted, title = {}, Clean(labels[move.to])
            for _, key in ipairs(move.labels) do wanted[Clean(labels[key])] = true end
            for _, page in ipairs(pages) do
                local target
                for _, group in ipairs(page.groups) do
                    if group.name == title then target = group end
                end
                for _, group in ipairs(page.groups) do
                    local index = 1
                    while target and group ~= target and group.items[index] do
                        local item = group.items[index]
                        if not item.key and (item.depth or 0) == 0 and wanted[item.name] then
                            for _, moved in ipairs(cut(group.items, index)) do
                                target.items[#target.items + 1] = moved
                            end
                        else
                            index = index + 1
                        end
                    end
                end
            end
        end
    end

    -- 2. Single settings: feature switches, moved settings, the global test mode.
    local masterOf = {}
    for _, rule in ipairs(GROUPS) do
        if rule.master then masterOf[rule.master] = rule.id end
    end
    local previewAll
    local function sweep(group, items)
        local index = 1
        while items[index] do
            local item = items[index]
            local key = (item.depth or 0) == 0 and item.key or nil
            local masterGroup = key and groupById[masterOf[key]]
            local moveId = key and ITEMS[key]
            if key == PREVIEW_ALL then
                previewAll = cut(items, index)[1]
            elseif masterGroup and masterGroup ~= group and not masterGroup.master then
                local block = cut(items, index)
                masterGroup.master = block[1]
                for i = #block, 2, -1 do
                    local child = block[i]
                    child.depth = (child.depth or 1) - 1
                    if child.parent == block[1] then child.parent = nil end
                    table.insert(masterGroup.items, 1, child)
                end
            elseif moveId and (groupById[moveId] or EXTRA[moveId]) and groupById[moveId] ~= group then
                local target = groupById[moveId] or newGroup(EXTRA[moveId].page, EXTRA[moveId].title, moveId)
                for _, moved in ipairs(cut(items, index)) do
                    target.items[#target.items + 1] = moved
                end
            else
                index = index + 1
            end
        end
    end
    for _, page in ipairs(pages) do
        local count = #page.groups
        for i = 1, count do
            local group = page.groups[i]
            sweep(group, group.items)
            for _, sub in ipairs(group.subs) do sweep(group, sub.items) end
        end
    end

    -- 3. Previews: test checkboxes leave the list and become the group's Preview button.
    local previews = {}
    local function takePreviews(group, items)
        for index = #items, 1, -1 do
            local item = items[index]
            if item.kind == "check" and isPreviewKey(item.key) then
                table.remove(items, index)
                item.depth = 0
                group.previewItem = item
            end
        end
    end
    for _, page in ipairs(pages) do
        for _, group in ipairs(page.groups) do
            for i = #group.subs, 1, -1 do takePreviews(group, group.subs[i].items) end
            takePreviews(group, group.items)
            if group.previewItem then
                group.preview = { kind = "check", widget = group.previewItem.widget, name = group.name }
                previews[#previews + 1] = group.preview
            end
        end
    end
    if previewAll and pageByName.Indicators then
        pageByName.Indicators.preview = { kind = "check", widget = previewAll.widget, name = "Indicators" }
        pageByName.Indicators.previewItem = previewAll
        previews[#previews + 1] = pageByName.Indicators.preview
    end
    if type(labels) == "table" then
        for _, srcPage in ipairs(source.pages) do
            local page = pageByName[srcPage.fallback]
            for _, pair in ipairs(PREVIEW_BUTTONS) do
                local off, on = Clean(labels[pair.off]), Clean(labels[pair.on])
                for _, button in ipairs(srcPage.buttons or {}) do
                    if page and not page.preview and (button.text == off or button.text == on) then
                        page.preview = { kind = "button", widget = button.widget, onText = on, name = page.name }
                        previews[#previews + 1] = page.preview
                    end
                end
            end
        end
    end

    -- 4. Flatten groups into sections; drop empty ones.
    local model = { pages = {}, items = {}, previews = previews, source = source }
    for _, page in ipairs(pages) do
        local function adopt(item, section)
            item.page, item.section, item.sectionName = page, section, section.name
            page.items[#page.items + 1] = item
        end
        for _, group in ipairs(page.groups) do
            local size = #group.items
            for _, sub in ipairs(group.subs) do size = size + #sub.items end
            if size > 0 or group.master then
                local main = { name = group.name, items = group.items, page = page,
                    master = group.master, preview = group.preview, previewItem = group.previewItem }
                page.sections[#page.sections + 1] = main
                if group.master then
                    group.master.depth = 0
                    adopt(group.master, main)
                end
                if group.previewItem then adopt(group.previewItem, main) end
                for _, item in ipairs(group.items) do adopt(item, main) end
                for _, sub in ipairs(group.subs) do
                    if #sub.items > 0 then
                        local section = { name = group.name .. ": " .. sub.name, base = group.name,
                            sub = sub.name, items = sub.items, page = page }
                        page.sections[#page.sections + 1] = section
                        for _, item in ipairs(sub.items) do adopt(item, section) end
                    end
                end
            end
        end
        if page.previewItem then
            local first = page.sections[1]
            if first then adopt(page.previewItem, first) end
        end
        page.groups = nil
        if #page.items > 0 then
            model.pages[#model.pages + 1] = page
            for _, item in ipairs(page.items) do
                item.search = table.concat({
                    item.name or "", item.alt or "", item.tipTitle or "", Clean(item.tipText), Clean(item.tipSub),
                    item.cvar or "", item.key or "", item.sectionName or "", page.name,
                }, " "):lower()
                model.items[#model.items + 1] = item
            end
        end
    end
    return model
end
