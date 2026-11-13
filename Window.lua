-- The new options window. Every control here drives BetterBlizzPlates' own
-- (hidden) control, so its logic stays in charge.

local _, ns = ...
local H = ns.Harvest
local call, Clean = H.call, H.Clean

local W = {}
ns.Window = W

local ROW_H = 26
local SIDEBAR_W = 196
local TOP_H = 40
local HEADER_H = 44
local CONTROL_W = 336
local SCROLL_W = 14
local PAD = 12
local GUTTER = 10
local INDENT = 18
local PEEK_ALPHA = 0.25
local ACCENT_R, ACCENT_G, ACCENT_B = 0, 0.75, 1

W.rows = {}
W.pageButtons = {}
W.display = {}
W.offset = 0
W.query = ""

local frame, model, stopBar

------------------------------------------------------------
-- Small helpers
------------------------------------------------------------
local function db()
    BetterBetterBlizzPlatesDB = BetterBetterBlizzPlatesDB or {}
    local saved = BetterBetterBlizzPlatesDB
    saved.collapsed = saved.collapsed or {}
    return saved
end

local function fill(parent, layer, r, g, b, a)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetColorTexture(r, g, b, a)
    return texture
end

-- Run BetterBlizzPlates code; report its errors without breaking this window.
local function run(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, ...)
    if not ok and geterrorhandler then
        pcall(geterrorhandler(), err)
    end
end

local function setEnabled(control, enabled)
    if control.SetEnabled then
        control:SetEnabled(enabled)
    elseif enabled then
        control:Enable()
    else
        control:Disable()
    end
end

local function formatValue(value, step)
    if type(value) ~= "number" then return "" end
    if value % 1 == 0 then return tostring(math.floor(value)) end
    return string.format((step and step < 0.01) and "%.3f" or "%.2f", value)
end

local function isChecked(item)
    return call(item.widget, "GetChecked") and true or false
end

local function isEnabled(item)
    local w = item.widget
    if item.kind == "color" then
        return (tonumber(call(w, "GetAlpha")) or 1) > 0.9
    end
    if call(w, "IsShown") == false then return false end
    return call(w, "IsEnabled") ~= false
end

local function moreHandlers(item)
    if item.kind ~= "check" then return end
    local handlers = item.widget.bbpMouseDownHandlers
    if type(handlers) == "table" and #handlers > 0 then return handlers end
end

local function runMore(item)
    local handlers = moreHandlers(item)
    if not handlers then return end
    if GameTooltip then GameTooltip:Hide() end
    for _, handler in ipairs(handlers) do
        run(handler, item.widget, "RightButton")
    end
end

-- Label colour BetterBlizzPlates gave the control (blue = friendly, red = enemy).
local function tintOf(item)
    if item.tint ~= nil then return item.tint end
    local w = item.widget
    local source = item.kind == "dropdown" and w.label or w.Text
    local r, g, b = call(source, "GetTextColor")
    local tint = false
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
        local gold = r > 0.9 and g > 0.7 and g < 0.9 and b < 0.25
        local white = r > 0.9 and g > 0.9 and b > 0.9
        if not gold and not white then tint = { r, g, b } end
    end
    item.tint = tint
    return tint
end

-- Font or bar texture file for a name from LibSharedMedia (BetterBlizzPlates ships it).
local function media(kind, name)
    if type(name) ~= "string" or name == "" or not LibStub then return end
    local ok, lib = pcall(LibStub, "LibSharedMedia-3.0", true)
    if not ok or type(lib) ~= "table" or type(lib.Fetch) ~= "function" then return end
    local found, path = pcall(lib.Fetch, lib, kind, name, true)
    if found and type(path) == "string" then return path end
end

-- "2 of 4 on" for dropdowns that hold several switches.
local function multiSummary(w)
    if type(w.options) ~= "table" or type(w.IsOptionOn) ~= "function" then return end
    local on, total = 0, 0
    for _, option in ipairs(w.options) do
        if type(option) == "table" and not option.onClick then
            total = total + 1
            if call(w, "IsOptionOn", option) then on = on + 1 end
        end
    end
    if total > 0 then return on .. " of " .. total .. " on" end
end

-- The selected choice of a dropdown, read from BetterBlizzPlates' own menu
-- builder. Its hidden dropdown does not update its text when we show the menu.
local fakeElement = setmetatable({}, { __index = function() return function() end end })

local function currentChoice(w)
    local generator = w.menuGenerator
    if type(generator) ~= "function" or w.fontPool or w.texturePool then return end
    local chosen
    local root = setmetatable({}, { __index = function(_, method)
        if method == "CreateRadio" then
            return function(_, text, isSelected, _, data)
                if not chosen and type(isSelected) == "function" then
                    local ok, on = pcall(isSelected, data)
                    if ok and on then chosen = text end
                end
                return fakeElement
            end
        end
        return function() return fakeElement end
    end })
    if pcall(generator, w, root) and type(chosen) == "string" then
        return Clean(chosen)
    end
end

------------------------------------------------------------
-- Previews (BetterBlizzPlates' test modes)
------------------------------------------------------------
local function previewOn(preview)
    if not preview then return false end
    if preview.kind == "check" then
        return call(preview.widget, "GetChecked") and true or false
    end
    return Clean(call(preview.widget, "GetText")) == preview.onText
end

local function previewUsable(preview)
    return call(preview.widget, "IsEnabled") ~= false
end

local function togglePreview(preview)
    run(preview.widget.Click, preview.widget)
    W.RefreshRows()
end

local function anyPreviewOn()
    if not model then return false end
    for _, preview in ipairs(model.previews or {}) do
        if previewOn(preview) then return true end
    end
    return false
end

function W.StopPreviews()
    if not model then return end
    for _, preview in ipairs(model.previews or {}) do
        if previewOn(preview) then run(preview.widget.Click, preview.widget) end
    end
    W.RefreshRows()
    W.UpdateStopBar()
end

local function stylePreviewButton(button, preview)
    local on = previewOn(preview)
    button:SetText(on and "Stop preview" or "Preview")
    setEnabled(button, on or previewUsable(preview))
    if on then button:LockHighlight() else button:UnlockHighlight() end
end

-- Small bar on screen while a preview runs and the window is closed.
local function createStopBar()
    stopBar = CreateFrame("Frame", "BetterBetterBlizzPlatesPreviewBar", UIParent)
    stopBar:SetSize(300, 34)
    stopBar:SetPoint("TOP", UIParent, "TOP", 0, -150)
    stopBar:SetFrameStrata("HIGH")
    stopBar:EnableMouse(true)
    stopBar:Hide()
    local bg = fill(stopBar, "BACKGROUND", 0.07, 0.07, 0.08, 0.95)
    bg:SetAllPoints()
    local bar = fill(stopBar, "ARTWORK", ACCENT_R, ACCENT_G, ACCENT_B, 1)
    bar:SetWidth(3)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("BOTTOMLEFT")

    local text = stopBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", stopBar, "LEFT", 14, 0)
    text:SetText("Preview is on")

    local options = CreateFrame("Button", nil, stopBar, "UIPanelButtonTemplate")
    options:SetSize(74, 22)
    options:SetPoint("RIGHT", stopBar, "RIGHT", -8, 0)
    options:SetText("Options")
    options:SetScript("OnClick", function()
        if ns.Open and not W.IsShown() then ns.Open(false) end
    end)

    local stop = CreateFrame("Button", nil, stopBar, "UIPanelButtonTemplate")
    stop:SetSize(60, 22)
    stop:SetPoint("RIGHT", options, "LEFT", -6, 0)
    stop:SetText("Stop")
    stop:SetScript("OnClick", function() W.StopPreviews() end)

    local elapsed = 0
    stopBar:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed >= 0.5 then
            elapsed = 0
            if W.IsShown() or not anyPreviewOn() then self:Hide() end
        end
    end)
end

function W.UpdateStopBar()
    local show = not W.IsShown() and anyPreviewOn()
    if show and not stopBar then createStopBar() end
    if stopBar then stopBar:SetShown(show) end
end

------------------------------------------------------------
-- Talking to BetterBlizzPlates' controls
------------------------------------------------------------
-- Font and texture dropdowns draw a sample on every menu row from their own pool.
-- BetterBlizzPlates hides those samples when its dropdown's menu closes. We show
-- the menu ourselves, so we must do it: the game reuses menu rows, and a sample
-- left behind shows up in the next menu.
local openPools, poolsSeen, poolsWait

local function eachPooled(w, fn)
    -- Not ipairs({ w.fontPool, w.texturePool }): that stops at the first missing pool.
    for _, key in ipairs({ "fontPool", "texturePool" }) do
        local pool = w[key]
        if type(pool) == "table" then
            for _, region in pairs(pool) do
                if fn(region) then return true end
            end
        end
    end
    return false
end

local function hidePools()
    local w = openPools
    openPools, poolsSeen, poolsWait = nil, false, 0
    if not w then return end
    eachPooled(w, function(region)
        call(region, "Hide")
        call(region, "SetParent", w)   -- off the menu row, back to its hidden owner
    end)
end

-- Runs every frame while one of those menus may be open: once its samples were
-- on screen and are gone again, the menu has closed.
local function watchPools(dt)
    local w = openPools
    if not w then return end
    if eachPooled(w, function(region) return call(region, "IsVisible") end) then
        poolsSeen = true
    elseif poolsSeen then
        hidePools()
    else
        poolsWait = (poolsWait or 0) + (dt or 0)
        if poolsWait > 3 then hidePools() end
    end
end

local function openMenu(item, owner)
    local w = item.widget
    local generator = w.menuGenerator
    if type(generator) ~= "function" or not (MenuUtil and MenuUtil.CreateContextMenu) then
        W.OpenOriginal(item.srcPage)
        return
    end
    hidePools()
    local ok, menu = pcall(MenuUtil.CreateContextMenu, owner, function(_, root)
        generator(w, root)
    end)
    if not ok then
        W.OpenOriginal(item.srcPage)
        return
    end
    if w.fontPool or w.texturePool then
        openPools, poolsSeen, poolsWait = w, false, 0
        if type(menu) == "table" and type(menu.SetClosedCallback) == "function" then
            pcall(menu.SetClosedCallback, menu, function()
                if openPools == w then hidePools() end
            end)
        end
    end
end

local function setSliderExact(item, number)
    local w = item.widget
    for _, child in ipairs(H.list(w, "GetChildren")) do
        if call(child, "GetObjectType") == "EditBox" then
            local script = call(child, "GetScript", "OnEnterPressed")
            if script then
                call(child, "SetText", tostring(number))
                run(script, child)
                return
            end
        end
    end
    run(w.SetValue, w, number)
end

local function stepSlider(item, direction)
    local w = item.widget
    local step = tonumber(call(w, "GetValueStep")) or 1
    local value = tonumber(call(w, "GetValue")) or 0
    local low, high = call(w, "GetMinMaxValues")
    local target = value + direction * step
    if type(low) == "number" and target < low then target = low end
    if type(high) == "number" and target > high then target = high end
    run(w.SetValue, w, target)
end

local function pickColor(item)
    local w = item.widget
    run(call(w, "GetScript", "OnMouseDown"), w, "LeftButton")
end

-- While a slider is held the window fades, so the nameplates behind it show.
local peekRow
function W.Peek(row, on)
    if not frame then return end
    if peekRow and peekRow.SetIgnoreParentAlpha then peekRow:SetIgnoreParentAlpha(false) end
    peekRow = nil
    if on and row and row.SetIgnoreParentAlpha then
        row:SetIgnoreParentAlpha(true)
        peekRow = row
        frame:SetAlpha(PEEK_ALPHA)
    else
        frame:SetAlpha(1)
    end
end

------------------------------------------------------------
-- Rows
------------------------------------------------------------
local function tipItem(owner, item)
    if not item or not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(item.tipTitle ~= "" and item.tipTitle or item.name)
    if item.tipText then GameTooltip:AddLine(item.tipText, 1, 1, 1, true) end
    if item.tipSub then GameTooltip:AddLine(item.tipSub, 1, 1, 1, true) end
    if item.cvar then GameTooltip:AddLine("CVar: " .. item.cvar, 0.6, 0.6, 0.6) end
    if moreHandlers(item) then GameTooltip:AddLine("Right-click: more.", 0.2, 0.97, 0.58) end
    local parent = item.parent
    if parent and parent.kind == "check" and not isEnabled(item) and not isChecked(parent) then
        GameTooltip:AddLine("Needs: " .. parent.name, 1, 0.35, 0.35)
    end
    GameTooltip:AddLine(item.page.name .. " / " .. item.sectionName, 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function tipText(owner, title, text)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title)
    if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
    GameTooltip:Show()
end

local function showTip(row)
    row.hl:Show()
    local entry = row.entry
    if entry and entry.item then tipItem(row, entry.item) end
end

local function hideTip(row)
    row.hl:Hide()
    if GameTooltip then GameTooltip:Hide() end
end

local function passHover(control, row)
    control:HookScript("OnEnter", function() showTip(row) end)
    control:HookScript("OnLeave", function() hideTip(row) end)
end

local function refreshHeader(row, entry)
    local section = entry.section
    local master = not entry.fixed and section.master or nil
    local on = true
    if master then
        on = isChecked(master)
        row.master:SetChecked(on)
        setEnabled(row.master, isEnabled(master))
        row.state:SetText(on and "On" or "Off")
        row.state:SetTextColor(on and 0.3 or 0.55, on and 0.9 or 0.55, on and 0.4 or 0.55)
    end
    if on then
        row.label:SetTextColor(1, 0.82, 0)
    else
        row.label:SetTextColor(0.6, 0.6, 0.6)
    end
    if not entry.fixed and section.preview then
        stylePreviewButton(row.preview, section.preview)
    end
end

local function refreshRow(row)
    local entry = row.entry
    if not entry then return end
    if entry.section then
        refreshHeader(row, entry)
        return
    end
    local item = entry.item
    local w = item.widget
    local enabled = isEnabled(item)
    local tint = tintOf(item)
    if not enabled then
        row.label:SetTextColor(0.45, 0.45, 0.45)
    elseif tint then
        row.label:SetTextColor(tint[1], tint[2], tint[3])
    else
        row.label:SetTextColor(1, 1, 1)
    end

    if item.kind == "check" then
        row.check:SetChecked(isChecked(item))
        setEnabled(row.check, enabled)
        row.check:SetAlpha(enabled and 1 or 0.4)
        row.more:SetShown(moreHandlers(item) ~= nil)
    elseif item.kind == "slider" then
        local low, high = call(w, "GetMinMaxValues")
        local step = tonumber(call(w, "GetValueStep")) or 1
        local value = tonumber(call(w, "GetValue")) or 0
        row.updating = true
        if type(low) == "number" and type(high) == "number" then
            row.slider:SetMinMaxValues(low, high)
        end
        if step > 0 then row.slider:SetValueStep(step) end
        row.slider:SetValue(value)
        row.updating = false
        for _, control in ipairs({ row.slider, row.value, row.minus, row.plus, row.reset }) do
            setEnabled(control, enabled)
            control:SetAlpha(enabled and 1 or 0.4)
        end
        if not row.value:HasFocus() then
            row.value:SetText(formatValue(value, step))
        end
    elseif item.kind == "dropdown" then
        local raw = call(w.Text, "GetText")
        local text = currentChoice(w) or Clean(raw)
        local drop = row.drop
        local font = w.fontPool and media("font", raw) or nil
        local bar = w.texturePool and media("statusbar", raw) or nil
        if text == "" or text == item.name then
            text = multiSummary(w) or "Select"
        end
        drop.value:SetFontObject(GameFontHighlightSmall)
        if font then drop.value:SetFont(font, 12, "") end
        drop.value:SetText(text)
        drop.value:SetTextColor(enabled and 1 or 0.5, enabled and 1 or 0.5, enabled and 1 or 0.5)
        drop.sample:SetShown(bar ~= nil)
        if bar then drop.sample:SetTexture(bar) end
        drop.value:SetPoint("RIGHT", drop, "RIGHT", bar and -100 or -24, 0)
        setEnabled(drop, enabled)
    elseif item.kind == "color" then
        local c = H.swatchColor[w.colorTexture]
        if c and c[1] then
            row.swatch.color:SetColorTexture(c[1], c[2] or 1, c[3] or 1, 1)
            row.swatch.unknown:Hide()
        else
            row.swatch.color:SetColorTexture(0.25, 0.25, 0.25, 1)
            row.swatch.unknown:Show()
        end
        setEnabled(row.swatch, enabled)
        row.swatch:SetAlpha(enabled and 1 or 0.4)
    end
end

local CONTROLS = { "check", "more", "slider", "value", "minus", "plus", "reset", "drop", "swatch", "master", "preview" }

local function setupRow(row, entry)
    row.entry = entry
    for _, key in ipairs(CONTROLS) do row[key]:Hide() end
    row.chevron:Hide()
    row.line:Hide()
    row.state:Hide()
    row.label:ClearAllPoints()

    if entry.section then
        local section = entry.section
        local x = entry.sub and 26 or 8
        row.chevron:SetTexture(entry.collapsed and "Interface\\Buttons\\UI-PlusButton-Up"
            or "Interface\\Buttons\\UI-MinusButton-Up")
        row.chevron:ClearAllPoints()
        row.chevron:SetPoint("LEFT", row, "LEFT", x, 0)
        row.chevron:SetShown(not entry.fixed)
        row.label:SetPoint("LEFT", row, "LEFT", x + (entry.fixed and 0 or 20), 0)
        row.label:SetFontObject(entry.sub and GameFontNormalSmall or GameFontNormal)
        row.label:SetText(entry.text .. "  |cff808080" .. entry.count .. "|r")
        row.line:SetShown(not entry.sub)

        local right = -8
        if not entry.fixed and section.master then
            row.master:Show()
            row.state:Show()
            right = right - 62
        end
        if not entry.fixed and section.preview then
            row.preview:ClearAllPoints()
            row.preview:SetPoint("RIGHT", row, "RIGHT", right, 0)
            row.preview:Show()
            right = right - 106
        end
        row.label:SetPoint("RIGHT", row, "RIGHT", right, 0)
        refreshRow(row)
        return
    end

    local item = entry.item
    local x = GUTTER + (entry.depth or 0) * INDENT
    row.check:ClearAllPoints()
    row.check:SetPoint("LEFT", row, "LEFT", x, 0)
    row.label:SetPoint("LEFT", row, "LEFT", x + 28, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", item.kind == "check" and -76 or -(CONTROL_W + 8), 0)
    row.label:SetFontObject(GameFontHighlight)
    row.label:SetText(item.name)

    if item.kind == "check" then
        row.check:Show()
    elseif item.kind == "slider" then
        row.slider:Show()
        row.value:Show()
        row.minus:Show()
        row.plus:Show()
        row.reset:SetShown(item.reset ~= nil)
    elseif item.kind == "dropdown" then
        row.drop:Show()
    elseif item.kind == "color" then
        row.swatch:Show()
    end
    refreshRow(row)
end

local function createRow(index)
    local list = frame.list
    local row = CreateFrame("Button", nil, list)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(index - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", list, "TOPRIGHT", -(SCROLL_W + 4), -(index - 1) * ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.hl = fill(row, "BACKGROUND", 1, 1, 1, 0.06)
    row.hl:SetAllPoints()
    row.hl:Hide()

    row.line = fill(row, "ARTWORK", 1, 0.82, 0, 0.25)
    row.line:SetHeight(1)
    row.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 1)
    row.line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 1)

    row.chevron = row:CreateTexture(nil, "ARTWORK")
    row.chevron:SetSize(14, 14)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    local function item()
        return row.entry and row.entry.item
    end

    -- Group header: feature switch and preview.
    row.master = CreateFrame("CheckButton", nil, row, "InterfaceOptionsCheckButtonTemplate")
    row.master:SetSize(24, 24)
    row.master:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.master:SetHitRectInsets(0, 0, 0, 0)
    if row.master.Text then row.master.Text:SetText("") end
    row.master:SetScript("OnClick", function()
        local section = row.entry and row.entry.section
        local master = section and section.master
        if master then run(master.widget.Click, master.widget) end
        W.RefreshRows()
    end)
    row.master:HookScript("OnEnter", function(self)
        local section = row.entry and row.entry.section
        if section and section.master then tipItem(self, section.master) end
    end)
    row.master:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    row.state = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.state:SetPoint("RIGHT", row.master, "LEFT", -2, 0)

    row.preview = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.preview:SetSize(100, 20)
    row.preview:SetScript("OnClick", function()
        local section = row.entry and row.entry.section
        if section and section.preview then togglePreview(section.preview) end
    end)
    row.preview:HookScript("OnEnter", function(self)
        tipText(self, "Preview", "Shows it on nameplates for testing. Stays on until you stop it.")
    end)
    row.preview:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    -- Checkbox: left of the label.
    row.check = CreateFrame("CheckButton", nil, row, "InterfaceOptionsCheckButtonTemplate")
    row.check:SetSize(24, 24)
    row.check:SetHitRectInsets(0, 0, 0, 0)
    if row.check.Text then row.check.Text:SetText("") end
    row.check:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.check:SetScript("OnClick", function(_, button)
        local it = item()
        if not it then return end
        if button == "RightButton" then
            runMore(it)
        else
            run(it.widget.Click, it.widget)
        end
        W.RefreshRows()
    end)

    row.more = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.more:SetSize(62, 20)
    row.more:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.more:SetText("More")
    row.more:SetScript("OnClick", function()
        local it = item()
        if it then runMore(it) end
        W.RefreshRows()
    end)

    local col = -CONTROL_W

    -- Slider: step buttons, slider, exact value.
    row.minus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.minus:SetSize(20, 20)
    row.minus:SetPoint("LEFT", row, "RIGHT", col, 0)
    row.minus:SetText("-")
    row.minus:SetScript("OnClick", function()
        local it = item()
        if it then stepSlider(it, -1) end
        W.RefreshRows()
    end)

    row.slider = CreateFrame("Slider", nil, row, "OptionsSliderTemplate")
    row.slider:SetOrientation("HORIZONTAL")
    row.slider:SetSize(150, 16)
    row.slider:SetPoint("LEFT", row.minus, "RIGHT", 6, 0)
    row.slider:SetObeyStepOnDrag(true)
    for _, key in ipairs({ "Text", "Low", "High" }) do
        if row.slider[key] then row.slider[key]:SetText("") end
    end
    row.slider:SetScript("OnValueChanged", function(_, value)
        if row.updating then return end
        local it = item()
        if not it then return end
        run(it.widget.SetValue, it.widget, value)
        if not row.value:HasFocus() then
            row.value:SetText(formatValue(tonumber(call(it.widget, "GetValue")) or value,
                tonumber(call(it.widget, "GetValueStep"))))
        end
    end)
    row.slider:HookScript("OnMouseDown", function() W.Peek(row, true) end)
    row.slider:HookScript("OnMouseUp", function() W.Peek(row, false) end)

    row.plus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.plus:SetSize(20, 20)
    row.plus:SetPoint("LEFT", row.slider, "RIGHT", 6, 0)
    row.plus:SetText("+")
    row.plus:SetScript("OnClick", function()
        local it = item()
        if it then stepSlider(it, 1) end
        W.RefreshRows()
    end)

    row.value = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.value:SetSize(54, 18)
    row.value:SetPoint("LEFT", row.plus, "RIGHT", 14, 0)
    row.value:SetAutoFocus(false)
    row.value:SetFontObject(GameFontHighlightSmall)
    row.value:SetJustifyH("CENTER")
    row.value:SetScript("OnEnterPressed", function(self)
        local it = item()
        local number = tonumber((self:GetText():gsub(",", ".")))
        self:ClearFocus()
        if it and number then setSliderExact(it, number) end
        W.RefreshRows()
    end)
    row.value:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        W.RefreshRows()
    end)

    -- Shown where BetterBlizzPlates has its own "Default" button for the slider.
    row.reset = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.reset:SetSize(52, 20)
    row.reset:SetPoint("LEFT", row.value, "RIGHT", 6, 0)
    row.reset:SetText("Reset")
    row.reset:SetScript("OnClick", function()
        local it = item()
        if it and it.reset then run(it.reset.Click, it.reset) end
        W.RefreshRows()
    end)

    -- Dropdown: current choice, optional bar sample, arrow.
    local drop = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    drop:SetSize(250, 22)
    drop:SetPoint("LEFT", row, "RIGHT", col, 0)
    drop:SetText("")
    drop.value = drop:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    drop.value:SetPoint("LEFT", drop, "LEFT", 10, 0)
    drop.value:SetPoint("RIGHT", drop, "RIGHT", -24, 0)
    drop.value:SetJustifyH("LEFT")
    drop.value:SetWordWrap(false)
    drop.sample = drop:CreateTexture(nil, "OVERLAY")
    drop.sample:SetSize(70, 10)
    drop.sample:SetPoint("RIGHT", drop, "RIGHT", -24, 0)
    drop.sample:SetVertexColor(ACCENT_R, ACCENT_G, ACCENT_B)
    drop.sample:Hide()
    drop.arrow = drop:CreateTexture(nil, "OVERLAY")
    drop.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    drop.arrow:SetSize(12, 12)
    drop.arrow:SetPoint("RIGHT", drop, "RIGHT", -7, 0)
    drop.arrow:SetRotation(-math.pi / 2)
    drop:SetScript("OnClick", function(self)
        local it = item()
        if it then openMenu(it, self) end
    end)
    row.drop = drop

    row.swatch = CreateFrame("Button", nil, row)
    row.swatch:SetSize(22, 22)
    row.swatch:SetPoint("LEFT", row, "RIGHT", col + 1, 0)
    local border = fill(row.swatch, "BACKGROUND", 0.6, 0.6, 0.6, 1)
    border:SetAllPoints()
    row.swatch.color = fill(row.swatch, "ARTWORK", 0.25, 0.25, 0.25, 1)
    row.swatch.color:SetPoint("TOPLEFT", 1, -1)
    row.swatch.color:SetPoint("BOTTOMRIGHT", -1, 1)
    row.swatch.unknown = row.swatch:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.swatch.unknown:SetPoint("CENTER")
    row.swatch.unknown:SetText("?")
    row.swatch:SetScript("OnClick", function()
        local it = item()
        if it then pickColor(it) end
    end)

    row:SetScript("OnEnter", showTip)
    row:SetScript("OnLeave", hideTip)
    for _, control in ipairs({ row.check, row.more, row.slider, row.value, row.minus, row.plus, row.reset, drop,
        row.swatch }) do
        passHover(control, row)
    end
    row:SetScript("OnClick", function(self, button)
        local entry = self.entry
        if not entry then return end
        if entry.section then
            if not entry.fixed then
                db().collapsed[entry.key] = not entry.collapsed
                W.Rebuild()
            end
            return
        end
        local it = entry.item
        if button == "RightButton" then
            runMore(it)
        elseif it.kind == "check" and isEnabled(it) then
            run(it.widget.Click, it.widget)
        elseif it.kind == "dropdown" and isEnabled(it) then
            openMenu(it, self.drop)
        elseif it.kind == "color" and isEnabled(it) then
            pickColor(it)
        end
        W.RefreshRows()
    end)

    W.rows[index] = row
    return row
end

------------------------------------------------------------
-- List
------------------------------------------------------------
local function visibleRows()
    local height = frame.list:GetHeight() or 0
    return math.max(1, math.floor(height / ROW_H))
end

function W.RefreshRows()
    if not frame or not frame:IsShown() then return end
    for _, row in ipairs(W.rows) do
        if row:IsShown() then refreshRow(row) end
    end
    local page = W.query == "" and W.page or nil
    if page and page.preview then stylePreviewButton(frame.pagePreview, page.preview) end
end

function W.Render()
    if not frame then return end
    local visible = visibleRows()
    local maxOffset = math.max(0, #W.display - visible)
    if W.offset > maxOffset then W.offset = maxOffset end
    if W.offset < 0 then W.offset = 0 end

    for i = 1, visible do
        local row = W.rows[i] or createRow(i)
        local entry = W.display[W.offset + i]
        if entry then
            setupRow(row, entry)
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
    for i = visible + 1, #W.rows do
        W.rows[i].entry = nil
        W.rows[i]:Hide()
    end

    local bar = frame.scroll
    bar.updating = true
    bar:SetMinMaxValues(0, maxOffset)
    bar:SetValue(W.offset)
    bar.updating = false
    bar:SetShown(maxOffset > 0)
    frame.empty:SetShown(#W.display == 0)
end

local function matches(item, words)
    for _, word in ipairs(words) do
        if not item.search:find(word, 1, true) then return false end
    end
    return true
end

local function isFolded(page, section)
    local key = page.name .. "/" .. section.name
    local folded = db().collapsed[key]
    if folded == nil then folded = page.fold and true or false end
    return folded, key
end

function W.Rebuild()
    if not frame or not model then return end
    local display = {}
    local query = W.query
    local page = W.page

    if query ~= "" then
        local words = {}
        for word in query:lower():gmatch("%S+") do words[#words + 1] = word end
        local total = 0
        for _, p in ipairs(model.pages) do
            local found, order = {}, {}
            for _, item in ipairs(p.items) do
                if matches(item, words) then
                    local list = found[item.section]
                    if not list then
                        list = {}
                        found[item.section] = list
                        order[#order + 1] = item.section
                    end
                    list[#list + 1] = item
                end
            end
            for _, section in ipairs(order) do
                local list = found[section]
                total = total + #list
                display[#display + 1] = { section = section, fixed = true, count = #list,
                    text = p.name .. " / " .. section.name }
                for _, item in ipairs(list) do
                    display[#display + 1] = { item = item, depth = 0 }
                end
            end
        end
        frame.title:SetText("Search")
        frame.info:SetText(total == 1 and "1 result" or (total .. " results"))
        frame.empty:SetText("No results.")
        frame.foldAll:Hide()
        frame.pagePreview:Hide()
    elseif page then
        local shownBase, hiddenBase = {}, {}
        local anyOpen = false
        for _, section in ipairs(page.sections) do
            local isSub = section.base and shownBase[section.base] or false
            if not (isSub and hiddenBase[section.base]) then
                local collapsed, key = isFolded(page, section)
                if not collapsed then anyOpen = true end
                display[#display + 1] = { section = section, key = key, collapsed = collapsed, sub = isSub,
                    count = #section.items, text = isSub and section.sub or section.name }
                if not section.base then
                    shownBase[section.name] = true
                    hiddenBase[section.name] = collapsed
                end
                if not collapsed then
                    for _, item in ipairs(section.items) do
                        display[#display + 1] = { item = item, depth = (item.depth or 0) + (isSub and 1 or 0) }
                    end
                end
            end
        end
        frame.title:SetText(page.name)
        frame.info:SetText(#page.items == 1 and "1 setting" or (#page.items .. " settings"))
        frame.empty:SetText("Nothing here.")
        frame.foldAll.fold = anyOpen
        frame.foldAll:SetText(anyOpen and "Fold all" or "Unfold all")
        frame.foldAll:Show()
        frame.pagePreview:SetShown(page.preview ~= nil)
        if page.preview then stylePreviewButton(frame.pagePreview, page.preview) end
    end

    W.display = display
    for _, button in ipairs(W.pageButtons) do
        local selected = query == "" and button.page == page
        button.selected:SetShown(selected)
        button.bar:SetShown(selected)
    end
    W.Render()
end

function W.FoldAll(fold)
    local page = W.page
    if not page then return end
    local saved = db().collapsed
    for _, section in ipairs(page.sections) do
        saved[page.name .. "/" .. section.name] = fold and true or false
    end
    W.offset = 0
    W.Rebuild()
end

-- Each page keeps its scroll position while the window lives.
local scrollOf = {}

function W.SelectPage(page)
    if W.page and W.query == "" then scrollOf[W.page.name] = W.offset end
    W.page = page
    W.offset = page and scrollOf[page.name] or 0
    db().page = page and page.name or nil
    if W.query ~= "" then
        W.query = ""
        frame.search:SetText("")
    end
    W.Rebuild()
end

function W.SetQuery(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == W.query then return end
    W.query = text
    W.offset = 0
    W.Rebuild()
end

-- `srcPage` is one of BetterBlizzPlates' own pages (nil = its main page).
function W.OpenOriginal(srcPage)
    local category = srcPage and srcPage.category or (BBP and BBP.category)
    local id = category and call(category, "GetID")
    if not id or not (Settings and Settings.OpenToCategory) then return end
    if frame then frame:Hide() end
    run(Settings.OpenToCategory, id)
end

------------------------------------------------------------
-- Frame
------------------------------------------------------------
local function savePlace()
    local saved = db()
    local point, _, relPoint, x, y = frame:GetPoint(1)
    if point then saved.point = { point, relPoint, x, y } end
    saved.width, saved.height = frame:GetWidth(), frame:GetHeight()
end

local function createPageButton(index)
    local side = frame.side
    local button = CreateFrame("Button", nil, side)
    button:SetHeight(ROW_H)
    button:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -8 - (index - 1) * ROW_H)
    button:SetPoint("TOPRIGHT", side, "TOPRIGHT", 0, -8 - (index - 1) * ROW_H)

    button.selected = fill(button, "BACKGROUND", ACCENT_R, ACCENT_G, ACCENT_B, 0.16)
    button.selected:SetAllPoints()
    button.bar = fill(button, "ARTWORK", ACCENT_R, ACCENT_G, ACCENT_B, 1)
    button.bar:SetWidth(3)
    button.bar:SetPoint("TOPLEFT")
    button.bar:SetPoint("BOTTOMLEFT")
    local hover = fill(button, "HIGHLIGHT", 1, 1, 1, 0.06)
    hover:SetAllPoints()

    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    button.text:SetPoint("LEFT", button, "LEFT", 14, 0)
    button.text:SetPoint("RIGHT", button, "RIGHT", -34, 0)
    button.text:SetJustifyH("LEFT")
    button.text:SetWordWrap(false)

    button.count = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    button.count:SetPoint("RIGHT", button, "RIGHT", -10, 0)

    button:SetScript("OnClick", function(self) W.SelectPage(self.page) end)
    W.pageButtons[index] = button
    return button
end

local function createFrame()
    local saved = db()
    frame = CreateFrame("Frame", "BetterBetterBlizzPlatesFrame", UIParent)
    frame:SetSize(saved.width or 900, saved.height or 620)
    if saved.point then
        frame:SetPoint(saved.point[1], UIParent, saved.point[2], saved.point[3], saved.point[4])
    else
        frame:SetPoint("CENTER")
    end
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetClampedToScreen(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(760, 400, 1500, 1100)
    elseif frame.SetMinResize then
        frame:SetMinResize(760, 400)
    end
    frame:Hide()
    if UISpecialFrames then table.insert(UISpecialFrames, "BetterBetterBlizzPlatesFrame") end

    local bg = fill(frame, "BACKGROUND", 0.07, 0.07, 0.08, 0.97)
    bg:SetAllPoints()
    for _, edge in ipairs({
        { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil },
    }) do
        local line = fill(frame, "BORDER", 0, 0, 0, 1)
        line:SetPoint(edge[1])
        line:SetPoint(edge[2])
        if edge[3] then line:SetWidth(edge[3]) end
        if edge[4] then line:SetHeight(edge[4]) end
    end

    -- Top bar: title, search, close. Drag it to move.
    local top = CreateFrame("Frame", nil, frame)
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:SetHeight(TOP_H)
    top:EnableMouse(true)
    top:RegisterForDrag("LeftButton")
    top:SetScript("OnDragStart", function() frame:StartMoving() end)
    top:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePlace()
    end)
    local topBg = fill(top, "BACKGROUND", 0.12, 0.12, 0.14, 1)
    topBg:SetAllPoints()

    local name = top:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    name:SetPoint("LEFT", top, "LEFT", PAD + 2, 0)
    name:SetText("|cffffffffBetter Better|r|cff00c0ffBlizz|r|cffffffffPlates|r")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -4)
    close:SetFrameLevel(top:GetFrameLevel() + 5)
    close:SetScript("OnClick", function() frame:Hide() end)

    local search = CreateFrame("EditBox", nil, top, "InputBoxTemplate")
    search:SetSize(230, 20)
    search:SetPoint("RIGHT", top, "RIGHT", -44, 0)
    search:SetAutoFocus(false)
    search:SetFontObject(GameFontHighlight)
    search:SetTextInsets(0, 18, 0, 0)
    search.hint = search:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    search.hint:SetPoint("LEFT", search, "LEFT", 2, 0)
    search.hint:SetText("Search settings")
    search.clear = CreateFrame("Button", nil, search)
    search.clear:SetSize(16, 16)
    search.clear:SetPoint("RIGHT", search, "RIGHT", -2, 0)
    local cross = search.clear:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    cross:SetPoint("CENTER")
    cross:SetText("x")
    search.clear:Hide()
    search.clear:SetScript("OnClick", function()
        search:SetText("")
        search:ClearFocus()
    end)
    search:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        self.hint:SetShown(text == "")
        self.clear:SetShown(text ~= "")
        W.SetQuery(text)
    end)
    search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    frame.search = search

    -- Pages
    local side = CreateFrame("Frame", nil, frame)
    side:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -TOP_H)
    side:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
    side:SetWidth(SIDEBAR_W)
    local sideBg = fill(side, "BACKGROUND", 0.1, 0.1, 0.115, 1)
    sideBg:SetAllPoints()
    frame.side = side

    local all = CreateFrame("Button", nil, side, "UIPanelButtonTemplate")
    all:SetSize(SIDEBAR_W - 2 * PAD, 22)
    all:SetPoint("BOTTOM", side, "BOTTOM", 0, PAD)
    all:SetText("Original settings")
    all:SetScript("OnClick", function() W.OpenOriginal(nil) end)
    all:HookScript("OnEnter", function(self)
        tipText(self, "Original settings", "Lists, profiles, import and export are there.")
    end)
    all:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    local reload = CreateFrame("Button", nil, side, "UIPanelButtonTemplate")
    reload:SetSize(SIDEBAR_W - 2 * PAD, 22)
    reload:SetPoint("BOTTOM", all, "TOP", 0, 6)
    reload:SetText("Reload UI")
    reload:SetScript("OnClick", function()
        if ns.MarkReopen then ns.MarkReopen() end
        if ReloadUI then ReloadUI() end
    end)
    reload:HookScript("OnEnter", function(self)
        tipText(self, "Reload UI", "Some settings need it. This window opens again after.")
    end)
    reload:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    frame.reload = reload

    -- Page header
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDEBAR_W + PAD + 4, -(TOP_H + 14))
    title:SetTextColor(1, 1, 1)
    frame.title = title

    local info = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    info:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 10, 1)
    frame.info = info

    local foldAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    foldAll:SetSize(90, 22)
    foldAll:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(TOP_H + 10))
    foldAll:SetScript("OnClick", function(self) W.FoldAll(self.fold) end)
    frame.foldAll = foldAll

    local pagePreview = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    pagePreview:SetSize(110, 22)
    pagePreview:SetPoint("RIGHT", foldAll, "LEFT", -8, 0)
    pagePreview:SetScript("OnClick", function()
        local page = W.page
        if page and page.preview then togglePreview(page.preview) end
    end)
    pagePreview:HookScript("OnEnter", function(self)
        tipText(self, "Preview", "Shows this page's features on nameplates for testing. Stays on until you stop it.")
    end)
    pagePreview:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    frame.pagePreview = pagePreview

    -- Settings list
    local list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDEBAR_W + PAD, -(TOP_H + HEADER_H))
    list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 20)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        W.offset = W.offset - delta * 3
        W.Render()
    end)
    list:SetScript("OnSizeChanged", function() W.Render() end)
    frame.list = list

    local empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOP", list, "TOP", 0, -40)
    empty:Hide()
    frame.empty = empty

    local bar = CreateFrame("Slider", nil, list)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(SCROLL_W - 4)
    bar:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 0)
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(1)
    bar:SetValue(0)
    local track = fill(bar, "BACKGROUND", 1, 1, 1, 0.05)
    track:SetAllPoints()
    local thumb = fill(bar, "ARTWORK", 1, 1, 1, 0.35)
    thumb:SetSize(SCROLL_W - 4, 40)
    bar:SetThumbTexture(thumb)
    bar:SetScript("OnValueChanged", function(self, value)
        if self.updating then return end
        W.offset = math.floor((value or 0) + 0.5)
        W.Render()
    end)
    frame.scroll = bar

    -- Resize grip
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        savePlace()
        W.Render()
    end)

    -- Keep rows in sync with BetterBlizzPlates (popups, the original page, other toggles).
    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, dt)
        watchPools(dt)
        elapsed = elapsed + (dt or 0)
        if elapsed >= 0.3 then
            elapsed = 0
            W.RefreshRows()
        end
    end)
    frame:SetScript("OnShow", function() W.UpdateStopBar() end)
    frame:SetScript("OnHide", function()
        W.Peek(nil, false)
        hidePools()
        if GameTooltip then GameTooltip:Hide() end
        W.UpdateStopBar()
    end)
end

function W.IsShown()
    return frame ~= nil and frame:IsShown()
end

function W.Hide()
    if frame then frame:Hide() end
end

-- `newModel` comes from Layout.Build.
function W.Show(newModel)
    if not frame then createFrame() end
    if newModel and newModel ~= model then
        model = newModel
        W.model = model
        for index, page in ipairs(model.pages) do
            local button = W.pageButtons[index] or createPageButton(index)
            button.page = page
            button.text:SetText(page.name)
            button.count:SetText(#page.items)
            button:Show()
        end
        for index = #model.pages + 1, #W.pageButtons do
            W.pageButtons[index]:Hide()
        end
        local wanted = db().page
        W.page = model.pages[1]
        for _, page in ipairs(model.pages) do
            if page.name == wanted then W.page = page end
        end
    end
    frame:Show()
    W.Rebuild()
    W.UpdateStopBar()
end
