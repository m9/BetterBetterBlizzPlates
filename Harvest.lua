-- Reads BetterBlizzPlates' own option widgets and builds a clean model:
-- pages -> sections -> items. Nothing here changes BetterBlizzPlates.

local _, ns = ...

local H = {}
ns.Harvest = H

H.panels = {}       -- sub page frames, in the order BetterBlizzPlates registers them

local MAX_CHAIN = 40
local MAX_HEADING = 40

------------------------------------------------------------
-- Safe helpers
------------------------------------------------------------
local function call(obj, method, ...)
    local fn = obj and obj[method]
    if type(fn) ~= "function" then return end
    local ok, a, b, c, d, e = pcall(fn, obj, ...)
    if ok then return a, b, c, d, e end
end
H.call = call

-- All return values of obj:method() as a list ({} on any failure).
local function list(obj, method)
    local fn = obj and obj[method]
    if type(fn) ~= "function" then return {} end
    local result = { pcall(fn, obj) }
    if not result[1] then return {} end
    table.remove(result, 1)
    return result
end
H.list = list

local function objType(obj)
    return type(obj) == "table" and call(obj, "GetObjectType") or nil
end

function H.Clean(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("|A.-|a", ""):gsub("|T.-|t", "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", " ")
    text = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    text = text:gsub("%s*:$", "")
    return text
end
local Clean = H.Clean

local function textOf(region)
    return Clean(call(region, "GetText"))
end

------------------------------------------------------------
-- Widget kinds
------------------------------------------------------------
local function kindOf(frame)
    local t = objType(frame)
    if not t then return end
    if t == "CheckButton" then
        if type(frame.bbpMouseDownHandlers) == "table" then return "check" end
        return
    end
    if t == "Slider" then
        if frame.searchCategory ~= nil and frame.Text then return "slider" end
        return "skip"
    end
    if t == "EditBox" then return "skip" end
    if type(frame.SetupMenu) == "function" and type(frame.SetDefaultText) == "function" then return "dropdown" end
    if t == "Frame" and frame.colorTexture and frame.text then return "color" end
end

local function popupTitle(frame)
    local container = rawget(frame, "TitleContainer")
    local title = type(container) == "table" and container.TitleText
    if title then
        local text = textOf(title)
        if text ~= "" then return text end
    end
end

-- First font string in `parent` that is anchored to `widget` (a caption).
local function captionFor(widget, parent)
    for _, region in ipairs(list(parent, "GetRegions")) do
        if objType(region) == "FontString" then
            local _, rel = call(region, "GetPoint", 1)
            if rel == widget then
                local text = textOf(region)
                if text ~= "" then return text end
            end
        end
    end
    return ""
end

local function sliderLabel(frame)
    local text = textOf(frame.Text)
    local label = text:match("^(.-)%s*:%s*%-?[%d%.]+$")
    return label or text
end

local function isShort(text)
    return text ~= "" and #text <= 40 and not text:find("%.$")
end

-- Returns name, alternative name, and (dropdowns without a label) a generic name.
local function nameOf(kind, frame)
    local tip = Clean(frame.tooltipTitle)
    if kind == "check" then
        local label = textOf(frame.Text)
        if label ~= "" then return label end
        return tip
    elseif kind == "slider" then
        local label = sliderLabel(frame)
        if label == "" then return tip end
        return label, isShort(tip) and tip or nil
    elseif kind == "dropdown" then
        if isShort(tip) then return tip end
        local label = frame.label and textOf(frame.label) or ""
        if label ~= "" then return label end
        label = captionFor(frame, call(frame, "GetParent"))
        if label ~= "" then return label end
        if frame.fontPool then return "", nil, "Font" end
        if frame.texturePool then return "", nil, "Texture" end
        return textOf(frame.Text)
    elseif kind == "color" then
        local label = textOf(frame.text)
        if label ~= "" then return label end
        if tip ~= "" then return tip end
        return captionFor(frame, call(frame, "GetParent"))
    end
    return ""
end

------------------------------------------------------------
-- Sections: follow the anchor chain up to a heading
------------------------------------------------------------
-- Pages that place everything by x/y offsets inside one container: the heading
-- is the nearest font string above the widget in the same column.
local function columnHeadings(container, cache)
    local found = cache[container]
    if found then return found end
    found = {}
    for _, region in ipairs(list(container, "GetRegions")) do
        if objType(region) == "FontString" then
            local point, rel, relPoint, x, y = call(region, "GetPoint", 1)
            if point == "TOPLEFT" and rel == container and relPoint == "TOPLEFT" then
                local text = textOf(region)
                if text ~= "" and #text <= MAX_HEADING then
                    found[#found + 1] = { x = tonumber(x) or 0, y = tonumber(y) or 0, text = text }
                end
            end
        end
    end
    cache[container] = found
    return found
end

local function columnHeading(widget, widgetSet, cache)
    local point, rel, relPoint, x, y = call(widget, "GetPoint", 1)
    if point ~= "TOPLEFT" or relPoint ~= "TOPLEFT" or type(rel) ~= "table" or widgetSet[rel] then return end
    if type(x) ~= "number" or type(y) ~= "number" then return end
    local scale = tonumber(call(widget, "GetScale")) or 1
    x, y = x * scale, y * scale
    local best, bestGap
    for _, heading in ipairs(columnHeadings(rel, cache)) do
        local dx, gap = x - heading.x, heading.y - y
        if gap >= 0 and dx >= -20 and dx <= 90 and (not bestGap or gap < bestGap) then
            best, bestGap = heading.text, gap
        end
    end
    return best
end

-- `stop` holds the item's ancestor widgets: reaching one means "same group as the parent".
local function headingFor(widget, pageFrame, widgetSet, stop, cache)
    local cur = widget
    for _ = 1, MAX_CHAIN do
        if cur == widget or widgetSet[cur] then
            local byColumn = columnHeading(cur, widgetSet, cache)
            if byColumn then return byColumn end
        end
        local _, rel = call(cur, "GetPoint", 1)
        if type(rel) ~= "table" or rel == pageFrame or rel == cur or stop[rel] then return end
        local t = objType(rel)
        if t == "FontString" then
            local owner = call(rel, "GetParent")
            local isOwnLabel = owner and widgetSet[owner]
                and (rel == rawget(owner, "Text") or rel == rawget(owner, "text") or rel == rawget(owner, "label"))
            if isOwnLabel then
                if stop[owner] then return end
                cur = owner
            else
                local text = textOf(rel)
                if text ~= "" and #text <= MAX_HEADING then return text end
                cur = rel
            end
        elseif t == nil then
            return
        else
            cur = rel
        end
    end
end

------------------------------------------------------------
-- Walk one page
------------------------------------------------------------
local pageButtons

local function walk(frame, ctx, out)
    if ctx.depthGuard > 25 then return end
    for _, child in ipairs(list(frame, "GetChildren")) do
        if type(child) == "table" and not call(child, "IsForbidden") then
            local kind = kindOf(child)
            local title = ctx.title
            if not kind then
                title = popupTitle(child) or title
            end
            if kind and kind ~= "skip" then
                local item = { kind = kind, widget = child, parent = ctx.parentItem, popup = ctx.title }
                out[#out + 1] = item
                ctx.widgetSet[child] = item
                if kind == "check" then
                    walk(child, { parentItem = item, title = title, widgetSet = ctx.widgetSet,
                        depthGuard = ctx.depthGuard + 1 }, out)
                end
            elseif kind ~= "skip" then
                -- Plain buttons with a label: kept so test buttons can be found later.
                if pageButtons and objType(child) == "Button" then
                    local text = textOf(child)
                    if text ~= "" then pageButtons[#pageButtons + 1] = { widget = child, text = text } end
                end
                walk(child, { parentItem = ctx.parentItem, title = title, widgetSet = ctx.widgetSet,
                    depthGuard = ctx.depthGuard + 1 }, out)
            end
        end
    end
end

local function buildPage(frame, name, general)
    local page = { frame = frame, name = name, sections = {}, items = {} }
    local raw, widgetSet, cache = {}, {}, {}
    page.buttons = {}
    pageButtons = page.buttons
    walk(frame, { widgetSet = widgetSet, depthGuard = 0 }, raw)
    pageButtons = nil

    local byName = {}
    local function sectionNamed(sectionName, base, sub)
        local section = byName[sectionName]
        if not section then
            section = { name = sectionName, base = base, sub = sub, items = {}, page = page }
            byName[sectionName] = section
            page.sections[#page.sections + 1] = section
        end
        return section
    end

    -- Names. `anchoredTo` maps a dropdown to the widget placed right next to it
    -- (usually the checkbox that switches it on).
    local anchoredTo = {}
    for _, item in ipairs(raw) do
        local w = item.widget
        item.name, item.alt, item.autoName = nameOf(item.kind, w)
        item.page = page
        item.tipTitle = Clean(w.tooltipTitle)
        item.tipText = type(w.tooltipMainText) == "string" and w.tooltipMainText or nil
        item.tipSub = type(w.tooltipSubText) == "string" and w.tooltipSubText or nil
        item.cvar = type(w.tooltipCVarName) == "string" and w.tooltipCVarName or nil
        item.key = type(w.option) == "string" and w.option or nil
        local _, rel = call(w, "GetPoint", 1)
        local target = rel and widgetSet[rel]
        if not target and objType(rel) == "FontString" then
            target = widgetSet[call(rel, "GetParent")]
        end
        if target and target ~= item then
            item.near = target
            if target.kind == "dropdown" and item.kind == "check" and not anchoredTo[target] then
                anchoredTo[target] = item
            end
        end
    end
    for _, item in ipairs(raw) do
        if item.autoName then
            local partner = anchoredTo[item]
            if partner and partner.name ~= "" then
                item.name = item.autoName .. " (" .. partner.name .. ")"
            else
                item.name = item.autoName
            end
        end
    end

    -- BetterBlizzPlates' own "Default" button next to a slider becomes that slider's reset.
    local defaultText = type(BBP) == "table" and type(BBP.L) == "table" and Clean(BBP.L["Default"]) or "Default"
    for _, button in ipairs(page.buttons) do
        if button.text == defaultText then
            local _, rel = call(button.widget, "GetPoint", 1)
            local target = rel and widgetSet[rel]
            if target and target.kind == "slider" and not target.reset then
                target.reset = button.widget
            end
        end
    end

    -- Sections and nesting. `raw` is in creation order, parents before children.
    for _, item in ipairs(raw) do
        if item.name ~= "" then
            local parent = item.parent
            while parent and not parent.section do parent = parent.parent end
            item.parent = parent

            local stop = {}
            local up = parent
            while up do
                stop[up.widget] = true
                up = up.parent
            end

            local heading, base, sub
            if item.popup then
                sub = columnHeading(item.widget, widgetSet, cache)
                if sub and sub ~= item.popup then
                    heading, base = item.popup .. ": " .. sub, item.popup
                elseif not (parent and parent.popup == item.popup) then
                    heading, sub = item.popup, nil
                end
            else
                heading = headingFor(item.widget, frame, widgetSet, stop, cache)
            end

            if parent and (not heading or heading == parent.section.name) then
                item.section = parent.section
                item.depth = parent.depth + 1
            else
                item.parent = nil
                item.section = sectionNamed(heading or general, base, base and sub or nil)
                item.depth = 0
            end
            table.insert(item.section.items, item)
            page.items[#page.items + 1] = item
        end
    end

    -- Sub groups ("Popup: Heading") go right after their base group.
    local ordered, placed = {}, {}
    for _, section in ipairs(page.sections) do
        if not section.base then
            ordered[#ordered + 1] = section
            placed[section] = true
            for _, other in ipairs(page.sections) do
                if other.base == section.name and not placed[other] then
                    ordered[#ordered + 1] = other
                    placed[other] = true
                end
            end
        end
    end
    for _, section in ipairs(page.sections) do
        if not placed[section] then
            section.base, section.sub = nil, nil
            ordered[#ordered + 1] = section
        end
    end
    page.sections = ordered

    -- A heading with a single setting is a caption, not a group: fold it into the group before.
    for i = #page.sections, 2, -1 do
        local section = page.sections[i]
        if #section.items == 1 then
            local item, prev = section.items[1], page.sections[i - 1]
            item.section, item.depth, item.parent = prev, 0, nil
            if item.name ~= section.name and section.name ~= general then
                item.alt = item.alt or section.name
            end
            table.insert(prev.items, item)
            table.remove(page.sections, i)
        end
    end

    -- Names that repeat inside a group: sliders take their longer name,
    -- dropdowns add the setting they sit next to.
    for _, section in ipairs(page.sections) do
        local seen = {}
        for _, item in ipairs(section.items) do
            seen[item.name] = (seen[item.name] or 0) + 1
        end
        for _, item in ipairs(section.items) do
            if seen[item.name] > 1 then
                if item.kind == "slider" and item.alt and item.alt ~= "" then
                    item.name, item.alt = item.alt, item.name
                elseif item.kind == "dropdown" then
                    local near = anchoredTo[item] or item.near
                    if near and near.name ~= "" and near.name ~= item.name then
                        item.name = item.name .. " (" .. near.name .. ")"
                    end
                end
            end
        end
    end

    for _, item in ipairs(page.items) do
        item.sectionName = item.section.name
        item.search = table.concat({
            item.name or "", item.alt or "", item.tipTitle or "", Clean(item.tipText), Clean(item.tipSub),
            item.cvar or "", item.key or "", item.sectionName, page.name,
        }, " "):lower()
    end
    return page
end

------------------------------------------------------------
-- Public
------------------------------------------------------------
-- Colour swatches: a colour texture cannot be read back, so remember what
-- BetterBlizzPlates sets. Only swatch textures are kept after the build.
H.swatchColor = setmetatable({}, { __mode = "k" })

local function hookSwatchColors()
    local probe = UIParent:CreateTexture()
    local meta = getmetatable(probe)
    local methods = meta and meta.__index
    if type(methods) ~= "table" or type(methods.SetColorTexture) ~= "function" then return end
    hooksecurefunc(methods, "SetColorTexture", function(texture, r, g, b, a)
        if H.capturing or H.swatchColor[texture] then
            H.swatchColor[texture] = { r, g, b, a }
        end
    end)
end

local hooked
function H.InstallHooks()
    if hooked then return end
    hooked = true
    if type(Settings) == "table" and type(Settings.RegisterCanvasLayoutSubcategory) == "function" then
        hooksecurefunc(Settings, "RegisterCanvasLayoutSubcategory", function(parentCategory, frame)
            if BBP and parentCategory == BBP.category and type(frame) == "table" then
                H.panels[#H.panels + 1] = frame
            end
        end)
    end

    pcall(hookSwatchColors)

    -- Watch colours only while BetterBlizzPlates builds its options.
    if type(BBP) == "table" and type(BBP.LoadGUI) == "function" then
        local loadGUI = BBP.LoadGUI
        local function finish(...)
            H.capturing = false
            return ...
        end
        BBP.LoadGUI = function(...)
            H.capturing = true
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function() H.capturing = false end)
            end
            return finish(loadGUI(...))
        end
    end
end

function H.IsReady()
    return type(BetterBlizzPlates) == "table" and BetterBlizzPlates.guiLoaded and true or false
end

local function findCategory(name)
    local root = BBP and BBP.category
    if not root then return end
    local subs = call(root, "GetSubcategories")
    if type(subs) ~= "table" then return end
    for _, sub in ipairs(subs) do
        if call(sub, "GetName") == name then return sub end
    end
end

-- Returns the model, or nil when BetterBlizzPlates' options are not built yet.
function H.Build(generalName)
    if not H.IsReady() then return end
    local model = { pages = {}, items = {} }
    local ok = pcall(function()
        local main = buildPage(BetterBlizzPlates, generalName, generalName)
        main.category = BBP and BBP.category
        model.pages[1] = main
        for _, frame in ipairs(H.panels) do
            local rawName = frame.name
            local name = Clean(rawName)
            if name == "" then name = "?" end
            local page = buildPage(frame, name, generalName)
            page.category = findCategory(rawName)
            model.pages[#model.pages + 1] = page
        end
    end)
    if not ok then return end
    local colors = setmetatable({}, { __mode = "k" })
    for _, page in ipairs(model.pages) do
        for _, item in ipairs(page.items) do
            model.items[#model.items + 1] = item
            if item.kind == "color" then
                local texture = item.widget.colorTexture
                colors[texture] = H.swatchColor[texture] or {}
            end
        end
    end
    H.swatchColor = colors
    return model
end
