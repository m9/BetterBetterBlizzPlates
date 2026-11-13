-- Minimal fake WoW API for LuaJIT. Enough to run BetterBlizzPlates' options
-- code and this addon outside the game. Not a full emulation.

local M = {}
local state = setmetatable({}, { __mode = "k" })
M.state = state
M.timers = {}
M.unknown = {}
M.metadata = {}

-- Read "## Field: value" lines of a TOC file into M.metadata for `addon`.
function M.readToc(addon, path)
    for line in io.lines(path) do
        local field, value = line:match("^##%s*([%w%-]+)%s*:%s*(.-)%s*$")
        if field then M.metadata[addon .. "/" .. field] = value end
    end
end
M.frames = {}
M.printed = {}

local function noop() end

-- Callable, indexable stand-in for unknown globals (tables or functions).
M.soft = setmetatable({}, { __call = noop, __newindex = noop })
getmetatable(M.soft).__index = function() return M.soft end

local PARENT_KEYS = {
    Text = "FontString", Low = "FontString", High = "FontString", Instructions = "FontString",
    Left = "Texture", Right = "Texture", Middle = "Texture", Background = "Texture",
    Arrow = "Texture", Bg = "Texture", Border = "Texture", Icon = "Texture", Thumb = "Texture",
    NineSlice = "Frame", TitleContainer = "Frame", Content = "Frame", Back = "Button",
    Forward = "Button", Center = "Texture", Slider = "Slider", Inset = "Frame",
    ColorSwatchCurrent = "Texture", TitleText = "FontString",
}

local function partType(key)
    if PARENT_KEYS[key] then return PARENT_KEYS[key] end
    if key:match("Button$") then return "Button" end
    if key:match("Text$") then return "FontString" end
    if key:match("Bar$") or key:match("Frame$") or key:match("Container$") or key:match("Box$") then return "Frame" end
    if key:match("Texture$") or key:match("Icon$") or key:match("Corner$") or key:match("Edge$") then return "Texture" end
end

local VERBS = { "Set", "Create", "Register", "Unregister", "Enable", "Disable", "Clear", "Hook",
    "Show", "Hide", "Start", "Stop", "Add", "Remove", "Update", "Raise", "Lower", "Lock",
    "Unlock", "Toggle", "Init", "Override", "Generate", "Setup", "Open", "Refresh", "On",
    "Apply", "Reset", "Insert", "Wrap", "Highlight", "Close", "Rotate", "Play" }

local Obj = {}
local new

local function index(o, k)
    local m = Obj[k]
    if m ~= nil then return m end
    if type(k) ~= "string" then return nil end
    local s = state[o]
    if M.Dropdown[k] then
        return s.type == "DropdownButton" and M.Dropdown[k] or nil
    end
    if k == "text" and s.type == "CheckButton" then return o.Text end
    if not k:match("^[A-Z]") then return nil end
    -- Names this fake does not really implement, when asked for by the addon under test.
    if M.watch then
        local src = debug.getinfo(2, "S").short_src
        if src:find(M.watch) then M.unknown[k] = true end
    end
    if k:match("^Get") then
        if k:match("Texture$") or k:match("FontString$") or k:match("FontObject$") or k:match("Region$") then
            local part = rawget(o, "__" .. k)
            if not part then
                part = new(k:match("FontString$") and "FontString" or "Texture", o)
                state[part].templatePart = true
                rawset(o, "__" .. k, part)
            end
            return function() return part end
        end
        return function() return 0 end
    end
    if k:match("^Is") or k:match("^Has") or k:match("^Can") or k:match("^Does") then
        return function() return false end
    end
    local pt = partType(k)
    if pt then
        for _, verb in ipairs(VERBS) do
            if k:sub(1, #verb) == verb and not PARENT_KEYS[k] and not k:match("Button$") and k ~= "ScrollBar" then
                return noop
            end
        end
        local part = new(pt, o)
        state[part].templatePart = true
        rawset(o, k, part)
        return part
    end
    return noop
end

local mt = { __index = index, __call = noop }

function new(otype, parent, name, template)
    local o = setmetatable({}, mt)
    state[o] = {
        type = otype, parent = parent, name = name, template = template,
        children = {}, regions = {}, points = {}, scripts = {},
        shown = true, enabled = true, alpha = 1, w = 0, h = 0, scale = 1,
        min = 0, max = 1, step = 1, value = 0, checked = false,
    }
    if parent and state[parent] then
        if otype == "FontString" or otype == "Texture" then
            table.insert(state[parent].regions, o)
        else
            table.insert(state[parent].children, o)
        end
    end
    if name then _G[name] = o end
    M.frames[#M.frames + 1] = o
    return o
end
M.new = new

function Obj:GetObjectType() return state[self].type end
function Obj:IsObjectType(t) return state[self].type == t end
function Obj:GetName() return state[self].name end
function Obj:GetParent() return state[self].parent end
function Obj:SetParent(p)
    local s = state[self]
    local old = s.parent and state[s.parent]
    local isRegion = s.type == "FontString" or s.type == "Texture"
    if old then
        local list = isRegion and old.regions or old.children
        for i, c in ipairs(list) do if c == self then table.remove(list, i) break end end
    end
    s.parent = p
    if p and state[p] then
        table.insert(isRegion and state[p].regions or state[p].children, self)
    end
end
function Obj:GetChildren() return unpack(state[self].children) end
function Obj:GetNumChildren() return #state[self].children end
function Obj:GetRegions() return unpack(state[self].regions) end
function Obj:GetNumRegions() return #state[self].regions end
function Obj:IsForbidden() return false end

function Obj:SetPoint(point, a, b, c, d)
    local rel, relPoint, x, y
    if type(a) == "table" or a == nil and type(b) == "string" then
        rel, relPoint, x, y = a, b, c, d
    elseif type(a) == "string" then
        rel, relPoint, x, y = _G[a], b, c, d
    else
        x, y = a, b
    end
    if rel == nil then rel = state[self].parent end
    if type(relPoint) ~= "string" then
        x, y = relPoint, x
        relPoint = point
    end
    -- Like the game: setting a point that already exists replaces it.
    local points = state[self].points
    local entry = { point, rel, relPoint or point, x or 0, y or 0 }
    for i, existing in ipairs(points) do
        if existing[1] == point then
            points[i] = entry
            return
        end
    end
    table.insert(points, entry)
end
function Obj:SetAllPoints(rel)
    state[self].points = {}
    rel = rel or state[self].parent
    table.insert(state[self].points, { "TOPLEFT", rel, "TOPLEFT", 0, 0 })
    table.insert(state[self].points, { "BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0 })
end
function Obj:ClearAllPoints() state[self].points = {} end
function Obj:GetNumPoints() return #state[self].points end
function Obj:GetPoint(i)
    local p = state[self].points[i or 1]
    if p then return p[1], p[2], p[3], p[4], p[5] end
end

function Obj:SetSize(w, h) state[self].w, state[self].h = w or 0, h or 0 end
function Obj:GetSize() return state[self].w, state[self].h end
function Obj:SetWidth(w) state[self].w = w or 0 end
function Obj:SetHeight(h) state[self].h = h or 0 end
function Obj:GetWidth() return state[self].w end
function Obj:GetHeight() return state[self].h end
function Obj:SetScale(v) state[self].scale = v end
function Obj:GetScale() return state[self].scale end
function Obj:GetEffectiveScale() return 1 end
function Obj:SetAlpha(a) state[self].alpha = a end
function Obj:GetAlpha() return state[self].alpha end
function Obj:GetFrameLevel() return 1 end
function Obj:GetLeft() return 0 end
function Obj:GetTop() return 0 end
function Obj:GetCenter() return 0, 0 end
function Obj:GetCursorPosition() return 0 end

local function fire(o, script, ...)
    local f = state[o].scripts[script]
    if f then return f(o, ...) end
end
M.fire = fire

function Obj:Show()
    local s = state[self]
    if not s.shown then s.shown = true fire(self, "OnShow") end
end
function Obj:Hide()
    local s = state[self]
    if s.shown then s.shown = false fire(self, "OnHide") end
end
function Obj:SetShown(v) if v then self:Show() else self:Hide() end end
function Obj:IsShown() return state[self].shown end
function Obj:IsVisible()
    local o = self
    while o do
        if not state[o].shown then return false end
        o = state[o].parent
    end
    return true
end

function Obj:SetScript(name, fn) state[self].scripts[name] = fn end
function Obj:GetScript(name) return state[self].scripts[name] end
function Obj:HasScript() return true end
function Obj:HookScript(name, fn)
    local old = state[self].scripts[name]
    if old then
        state[self].scripts[name] = function(...) old(...) return fn(...) end
    else
        state[self].scripts[name] = fn
    end
end
function Obj:RegisterEvent(e) state[self].events = state[self].events or {} state[self].events[e] = true end

function Obj:SetText(t)
    local s = state[self]
    if s.type == "Button" or s.type == "CheckButton" then
        state[self.Text].text = t
    else
        s.text = t
    end
    if s.type == "EditBox" then fire(self, "OnTextChanged", false) end
end
function Obj:SetFormattedText(f, ...) self:SetText(string.format(f, ...)) end
function Obj:GetText()
    local s = state[self]
    if s.type == "Button" or s.type == "CheckButton" then return state[self.Text].text end
    if s.type == "EditBox" then return s.text or "" end
    return s.text
end
function Obj:GetStringWidth() return #(state[self].text or "") * 6 end
function Obj:GetStringHeight() return 12 end
function Obj:GetNumLines() return 1 end
function Obj:GetFont() return "font", 12, "" end
function Obj:SetTextColor(r, g, b, a) state[self].color = { r, g, b, a } end
function Obj:GetTextColor()
    local c = state[self].color or { 1, 0.82, 0, 1 }
    return c[1], c[2], c[3], c[4] or 1
end
function Obj:SetVertexColor(r, g, b, a) state[self].vertex = { r, g, b, a } end
function Obj:GetVertexColor()
    local c = state[self].vertex or { 1, 1, 1, 1 }
    return c[1], c[2], c[3], c[4] or 1
end
function Obj:SetColorTexture(r, g, b, a) state[self].colorTexture = { r, g, b, a } end
function Obj:GetFontString() return self.Text end
function Obj:GetNumber() return tonumber(state[self].text) or 0 end
function Obj:SetTitle(t) state[self.TitleContainer.TitleText].text = t end
function Obj:GetTitleText() return self.TitleContainer.TitleText end

function Obj:SetChecked(v) state[self].checked = v and true or false end
function Obj:GetChecked() return state[self].checked end
function Obj:Enable() state[self].enabled = true end
function Obj:Disable() state[self].enabled = false end
function Obj:SetEnabled(v) state[self].enabled = v and true or false end
function Obj:IsEnabled() return state[self].enabled end
function Obj:Click(button)
    local s = state[self]
    if not s.enabled then return end
    if s.type == "CheckButton" then s.checked = not s.checked end
    fire(self, "OnClick", button or "LeftButton", false)
end

function Obj:SetMinMaxValues(a, b) state[self].min, state[self].max = a, b end
function Obj:GetMinMaxValues() return state[self].min, state[self].max end
function Obj:SetValueStep(v) state[self].step = v end
function Obj:GetValueStep() return state[self].step end
function Obj:SetValue(v)
    local s = state[self]
    if type(v) ~= "number" then return end
    if s.type == "Slider" then
        if v < s.min then v = s.min elseif v > s.max then v = s.max end
    end
    if s.value ~= v then
        s.value = v
        fire(self, "OnValueChanged", v, false)
    end
end
function Obj:GetValue() return state[self].value end

function Obj:SetScrollChild(c) state[self].scrollChild = c end
function Obj:GetScrollChild() return state[self].scrollChild end
function Obj:GetVerticalScroll() return state[self].vscroll or 0 end
function Obj:SetVerticalScroll(v) state[self].vscroll = v end
function Obj:GetVerticalScrollRange() return 1000 end

function Obj:CreateFontString(name) return new("FontString", self, name) end
function Obj:CreateTexture(name) return new("Texture", self, name) end
function Obj:CreateAnimationGroup()
    local g = new("AnimationGroup", nil)
    return g
end
function Obj:CreateAnimation() return new("Animation", nil) end

-- dropdown buttons only
local Dropdown = {}
function Dropdown:SetupMenu(gen) rawset(self, "menuGenerator", gen) end
function Dropdown:SetDefaultText(t) state[self.Text].text = t end
function Dropdown:OverrideText(t) state[self.Text].text = t end
function Dropdown:SetSelectionText(fn) state[self].selectionText = fn end
M.Dropdown = Dropdown

function M.install()
    local G = _G
    G.UIParent = new("Frame", nil, "UIParent")
    G.WorldFrame = new("Frame", nil, "WorldFrame")
    G.SettingsPanel = new("Frame", nil, "SettingsPanel")
    G.SettingsPanelSearchIcon = new("Texture", nil, "SettingsPanelSearchIcon")
    G.GameTooltip = new("GameTooltip", nil, "GameTooltip")
    G.ColorPickerFrame = new("Frame", nil, "ColorPickerFrame")
    G.UISpecialFrames = {}
    state[G.SettingsPanel].shown = false
    state[G.SettingsPanel].w, state[G.SettingsPanel].h = 920, 724

    for _, f in ipairs({ "GameFontNormal", "GameFontNormalSmall", "GameFontNormalLarge", "GameFontHighlight",
        "GameFontHighlightSmall", "GameFontHighlightLarge", "GameFontDisable", "GameFontDisableSmall",
        "GameFontNormalHuge", "GameFont_Gigantic", "GameTooltipText", "GameFontWhite" }) do
        G[f] = new("Font", nil, f)
    end

    function G.CreateFrame(otype, name, parent, template)
        local o = new(otype, parent, name, template)
        if otype == "ScrollFrame" and template and template:find("ScrollFrame") then
            local _ = o.ScrollBar
        end
        return o
    end

    function G.hooksecurefunc(a, b, c)
        local tbl, name, hook
        if type(a) == "table" then tbl, name, hook = a, b, c else tbl, name, hook = _G, a, b end
        local orig = tbl[name]
        if type(orig) ~= "function" then orig = noop end
        rawset(tbl, name, function(...)
            local r = { orig(...) }
            hook(...)
            return unpack(r)
        end)
    end

    G.Settings = {}
    M.categories = {}
    local function category(frame, name, parent)
        local cat = { frame = frame, name = name, subs = {}, id = #M.categories + 1 }
        function cat:GetID() return self.id end
        function cat:GetName() return self.name end
        function cat:GetSubcategories() return self.subs end
        M.categories[cat.id] = cat
        if parent then table.insert(parent.subs, cat) end
        return cat
    end
    function G.Settings.RegisterCanvasLayoutCategory(frame, name) return category(frame, name) end
    function G.Settings.RegisterCanvasLayoutSubcategory(parent, frame, name) return category(frame, name, parent) end
    function G.Settings.RegisterAddOnCategory() end
    function G.Settings.OpenToCategory(id) M.openedCategory = id state[G.SettingsPanel].shown = true end
    function G.HideUIPanel(f) f:Hide() end
    function G.ShowUIPanel(f) f:Show() end

    G.C_Timer = {
        After = function(_, fn) M.timers[#M.timers + 1] = fn end,
        NewTicker = function() return { Cancel = noop } end,
        NewTimer = function() return { Cancel = noop } end,
    }
    G.C_CVar = {
        GetCVar = function() return "1" end, SetCVar = noop, GetCVarBool = function() return false end,
        GetCVarDefault = function() return "1" end, SetCVarBitfield = noop, GetCVarBitfield = function() return false end,
    }
    G.GetCVar = G.C_CVar.GetCVar
    G.SetCVar = noop
    G.GetCVarBool = G.C_CVar.GetCVarBool
    G.C_AddOns = {
        IsAddOnLoaded = function() return false end,
        -- M.metadata["Addon/Field"] = value; anything else reads as "test".
        GetAddOnMetadata = function(addon, field)
            local value = M.metadata[tostring(addon) .. "/" .. tostring(field)]
            if value ~= nil then return value end
            return "test"
        end,
        DisableAddOn = noop,
    }
    G.C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = noop }
    G.AnchorUtil = { CreateAnchor = function(...) return { ... } end }
    G.MenuUtil = {
        CreateContextMenu = function(owner, gen)
            M.lastMenu = { owner = owner, generator = gen }
            return { SetClosedCallback = function(_, fn) M.lastMenu.closed = fn end }
        end,
    }
    G.MenuResponse = { CloseAll = 1, Refresh = 2, Close = 3, Open = 4 }
    G.GameTooltip_Hide = noop
    G.GameTooltip_SetTitle = noop
    G.GameTooltip_AddNormalLine = noop
    G.SlashCmdList = {}
    G.StaticPopupDialogs = {}
    G.StaticPopup_Show = noop
    G.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
    G.NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 }
    G.HIGHLIGHT_FONT_COLOR = { r = 1, g = 1, b = 1 }
    G.STANDARD_TEXT_FONT = "font"
    G.SEARCH = "Search"
    G.WOW_PROJECT_ID, G.WOW_PROJECT_MAINLINE = 1, 1

    G.GetLocale = function() return "enUS" end
    G.GetBuildInfo = function() return "1.60.1", "1", "date", 16001 end
    G.InCombatLockdown = function() return M.inCombat or false end
    G.UnitAffectingCombat = function() return false end
    G.IsShiftKeyDown = function() return false end
    G.IsControlKeyDown = function() return false end
    G.IsAltKeyDown = function() return false end
    G.GetTime = function() return 0 end
    G.GetCursorPosition = function() return 0, 0 end
    G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
    G.UnitName = function() return "Tester" end
    G.GetRealmName = function() return "Realm" end
    G.PlaySound = noop
    G.ReloadUI = noop
    G.print = function(...)
        local t = {}
        for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
        M.printed[#M.printed + 1] = table.concat(t, " ")
    end

    G.strsplit = function(sep, s)
        local out = {}
        for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
        return unpack(out)
    end
    G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
    G.strlower, G.strupper, G.strfind, G.strmatch, G.strsub, G.format, G.strlen, G.gsub, G.strrep =
        string.lower, string.upper, string.find, string.match, string.sub, string.format, string.len, string.gsub, string.rep
    G.tinsert, G.tremove, G.sort, G.wipe = table.insert, table.remove, table.sort, function(t)
        for k in pairs(t) do t[k] = nil end
        return t
    end
    G.tContains = function(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
    G.floor, G.ceil, G.min, G.max, G.abs = math.floor, math.ceil, math.min, math.max, math.abs
    G.Clamp = function(v, lo, hi) return math.min(math.max(v, lo), hi) end
    G.CopyTable = function(t)
        local c = {}
        for k, v in pairs(t) do c[k] = type(v) == "table" and G.CopyTable(v) or v end
        return c
    end
    G.CreateFramePool = function() return { Acquire = function() return new("Frame") end, Release = noop, ReleaseAll = noop } end
    G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a, GetRGB = function() return r, g, b end } end
    G.geterrorhandler = function() return function(e) error(e, 0) end end
    G.securecallfunction = function(f, ...) return f(...) end
    G.issecretvalue = function() return false end
    G.date = os.date
    G.time = os.time

    local lib = setmetatable({}, { __index = function() return noop end })
    lib.MediaType = { FONT = "font", STATUSBAR = "statusbar" }
    function lib:HashTable() return { ["Media A"] = "path\\a", ["Media B"] = "path\\b", ["Media C"] = "path\\c" } end
    function lib:Fetch() return "path" end
    function lib:List() return {} end
    G.LibStub = setmetatable({}, { __call = function() return lib end })
end

-- Unknown globals read by BetterBlizzPlates' code: hand back a harmless stub.
function M.lenientGlobals()
    setmetatable(_G, { __index = function(t, k)
        if type(k) == "string" and k:match("^[A-Z]") then
            if k:match("^[A-Z_0-9]+$") or k:match("^BetterB") or k:match("^BBP") then return nil end
            local stub
            if k:match("^C_") then
                stub = setmetatable({}, { __index = function() return noop end })
            elseif k:match("Frame$") or k:match("Tooltip$") or k:match("Panel$") then
                stub = new("Frame", nil)
            else
                return M.soft
            end
            rawset(t, k, stub)
            return stub
        end
    end })
end

function M.runTimers(rounds)
    for _ = 1, rounds or 5 do
        local list = M.timers
        M.timers = {}
        for _, fn in ipairs(list) do fn() end
        if #M.timers == 0 then break end
    end
    M.timers = {}
end

return M
