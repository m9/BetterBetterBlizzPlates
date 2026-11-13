-- luajit tests/test.lua <BetterBlizzPlates folder>
-- Runs this addon against the installed BetterBlizzPlates options code in a fake API.

local bbpPath = assert(arg[1], "usage: luajit tests/test.lua <BetterBlizzPlates folder>")
local env = dofile("tests/load_bbp.lua")(bbpPath)
local mock = env.mock
local state = mock.state

local passed = 0
local function check(cond, what)
    if not cond then error("FAIL: " .. what, 2) end
    passed = passed + 1
end

-- Load the addon the way the game does: files in TOC order, shared namespace.
mock.watch = "^[HWCL]%a+%.lua$"
mock.readToc("BetterBetterBlizzPlates", "BetterBetterBlizzPlates.toc")
local ns = {}
for line in io.lines("BetterBetterBlizzPlates.toc") do
    local file = line:match("^([%w_]+%.lua)%s*$")
    if file then assert(loadfile(file))("BetterBetterBlizzPlates", ns) end
end
for _, f in ipairs(mock.frames) do
    local s = state[f]
    if s.events and s.scripts.OnEvent and not s.parent then
        if s.events.ADDON_LOADED then s.scripts.OnEvent(f, "ADDON_LOADED", "BetterBetterBlizzPlates") end
    end
end
BBP.InitializeOptions()

local H, W = ns.Harvest, ns.Window

-- Exact version: this copy is made for the installed BetterBlizzPlates, and only for it.
local madeFor = mock.metadata["BetterBetterBlizzPlates/X-BetterBlizzPlates-Version"]
local installed = mock.metadata["BetterBlizzPlates/Version"]
check(madeFor and installed, "both versions are known")
check(ns.VersionProblem() == nil, "made for " .. tostring(madeFor) .. ", installed " .. tostring(installed)
    .. ": update X-BetterBlizzPlates-Version in the TOC after checking the new version")
local ours = mock.metadata["BetterBetterBlizzPlates/Version"]
check(ours:sub(1, #madeFor + 1) == madeFor .. "-" and ours:sub(#madeFor + 2):gsub("%-dev$", ""):match("^p%d+$"),
    "our version is <theirs>-p<number>: " .. ours)
mock.metadata["BetterBlizzPlates/Version"] = "v9.9.9"
check(ns.VersionProblem():find("Made for BetterBlizzPlates " .. madeFor .. ". You have 9.9.9.", 1, true),
    "other version is reported: " .. tostring(ns.VersionProblem()))
SlashCmdList["BETTERBETTERBLIZZPLATES"]("")
mock.runTimers(3)
check(not H.IsReady() and not W.IsShown(), "window stays closed with another version")
check(mock.printed[#mock.printed]:find("Made for BetterBlizzPlates", 1, true), "and says why")
mock.metadata["BetterBlizzPlates/Version"] = installed

-- Open: builds BetterBlizzPlates' options, then our window.
check(not H.IsReady(), "options not built before first open")
SlashCmdList["BETTERBETTERBLIZZPLATES"]("")
mock.runTimers(6)
check(H.IsReady(), "BetterBlizzPlates options built")
check(W.IsShown(), "window shown")
check(not SettingsPanel:IsShown(), "Blizzard settings panel closed again")

local frame = BetterBetterBlizzPlatesFrame
state[frame.list].h = 520
W.Render()


local model = W.model
check(#model.pages >= 8, "pages found: " .. #model.pages)
check(#model.items >= 500, "settings found: " .. #model.items)

local function find(pred)
    for _, item in ipairs(model.items) do
        if pred(item) then return item end
    end
end

local function pageNamed(name)
    for _, page in ipairs(model.pages) do
        if page.name == name then return page end
    end
    error("no page " .. name)
end

local function sectionNamed(page, name)
    for _, section in ipairs(page.sections) do
        if section.name == name then return section end
    end
    error("no group " .. name)
end

local function rowWhere(page, pred)
    W.SelectPage(page)
    W.FoldAll(false)
    for index, entry in ipairs(W.display) do
        if pred(entry) then
            W.offset = index - 1
            W.Render()
            for _, row in ipairs(W.rows) do
                if row:IsShown() and row.entry == W.display[index] then return row end
            end
        end
    end
    error("no row")
end

local function rowFor(item)
    return rowWhere(item.page, function(entry) return entry.item == item end)
end

local function headerFor(section)
    return rowWhere(section.page, function(entry) return entry.section == section end)
end

-- Pages are task-based now.
local names = {}
for _, page in ipairs(model.pages) do names[#names + 1] = page.name end
check(table.concat(names, ","):find("Nameplates,Size and stacking,Names and text,Colors,Castbar,Auras,Indicators", 1, true),
    "page order: " .. table.concat(names, ","))

-- Every entry on every page renders.
local rendered, listed, seen = 0, 0, {}
for _, page in ipairs(model.pages) do
    for _, section in ipairs(page.sections) do listed = listed + #section.items end
    W.SelectPage(page)
    W.FoldAll(false)
    local offset = 0
    repeat
        W.offset = offset
        W.Render()
        for _, row in ipairs(W.rows) do
            if row:IsShown() and row.entry then
                local shown = row.entry.item
                if shown and not seen[shown] then
                    seen[shown] = true
                    rendered = rendered + 1
                end
                state[row].scripts.OnEnter(row)
                state[row].scripts.OnLeave(row)
            end
        end
        offset = offset + #W.rows
    until offset >= #W.display
end
check(rendered == listed and listed > 500, "all rows rendered: " .. rendered .. "/" .. listed)

-- Checkbox: our control drives the original one.
local item = find(function(i) return i.key == "hideEliteDragon" end)
check(item and item.kind == "check" and item.page.name == "Nameplates", "hideEliteDragon on Nameplates")
local before = BetterBlizzPlatesDB.hideEliteDragon and true or false
local row = rowFor(item)
row.check:Click()
check((BetterBlizzPlatesDB.hideEliteDragon and true or false) == not before, "checkbox click changes the setting")
check(row.check:GetChecked() == item.widget:GetChecked(), "checkbox mirrors the original")
state[row].scripts.OnClick(row, "LeftButton")
check((BetterBlizzPlatesDB.hideEliteDragon and true or false) == before, "row click toggles back")

-- Nested settings keep their parent.
local child = find(function(i) return i.key == "otherNpBuffFilterPurgeableAny" end)
check(child and child.depth == 2 and child.parent and child.parent.key == "otherNpBuffFilterPurgeable",
    "nested setting sits under its parent")
check(child.page.name == "Auras" and child.sectionName == "Enemy Nameplates",
    "aura page groups by heading: " .. tostring(child.sectionName))

-- Feature switch in the group header.
local indicators = pageNamed("Indicators")
local healer = sectionNamed(indicators, "Healer Indicator")
check(healer.master and healer.master.key == "healerIndicator", "Healer Indicator has its switch")
row = headerFor(healer)
check(row.master:IsShown() and row.preview:IsShown(), "header shows switch and preview")
before = BetterBlizzPlatesDB.healerIndicator and true or false
row.master:Click()
check((BetterBlizzPlatesDB.healerIndicator and true or false) == not before, "header switch changes the setting")
check(row.master:GetChecked() == not before, "header switch mirrors the original")
row.master:Click()
for _, it in ipairs(healer.items) do
    check(it.key ~= "healerIndicator" and it.key ~= "healerIndicatorTestMode", "switch and test are not listed twice")
end
check(sectionNamed(pageNamed("Names and text"), "Health Numbers").master.key == "healthNumbers", "Health Numbers switch")
check(sectionNamed(pageNamed("Colors"), "Threat Colors").master.key == "enemyColorThreat", "Threat Colors switch")

-- Moved settings.
check(find(function(i) return i.key == "showGuildNames" end).sectionName == "Names", "guild names moved to Names")
check(find(function(i) return i.key == "changeNameplateBorderColor" end).page.name == "Colors", "border colour on Colors")
check(find(function(i) return i.key == "npBorderTargetColor" end).depth == 1, "moved settings keep their children")
check(find(function(i) return i.key == "overShields" end).sectionName == "Absorb Indicator", "overshields with absorb")

-- Indicators start folded: an overview of features.
BetterBetterBlizzPlatesDB.collapsed = {}
W.SelectPage(indicators)
local groups = 0
for _, section in ipairs(indicators.sections) do
    if not section.base then groups = groups + 1 end
end
check(#W.display == groups, "Indicators page starts folded: " .. #W.display .. "/" .. groups)
frame.foldAll:Click()
check(#W.display > groups + 100, "Unfold all opens every group")
frame.foldAll:Click()
check(#W.display == groups, "Fold all closes every group")

-- Preview: group test mode, stop bar.
row = headerFor(healer)
check(not BetterBlizzPlatesDB.healerIndicatorTestMode, "preview off at start")
row.preview:Click()
check(BetterBlizzPlatesDB.healerIndicatorTestMode == true, "Preview turns the test mode on")
check(row.preview:GetText() == "Stop preview", "Preview button shows it is on")
W.Hide()
check(BetterBetterBlizzPlatesPreviewBar and BetterBetterBlizzPlatesPreviewBar:IsShown(), "stop bar shows after closing")
W.StopPreviews()
check(BetterBlizzPlatesDB.healerIndicatorTestMode == false, "Stop turns the test mode off")
check(not BetterBetterBlizzPlatesPreviewBar:IsShown(), "stop bar hides")
SlashCmdList["BETTERBETTERBLIZZPLATES"]("")
model = W.model
indicators = pageNamed("Indicators")

-- Preview: page level (all indicators, aura test button).
check(indicators.preview and indicators.preview.kind == "check", "Indicators page has a preview")
W.SelectPage(indicators)
check(frame.pagePreview:IsShown(), "page preview button shown")
frame.pagePreview:Click()
check(BetterBlizzPlatesDB.testAllEnabledFeatures == true, "page preview turns test all on")
frame.pagePreview:Click()
check(BetterBlizzPlatesDB.testAllEnabledFeatures == false, "page preview turns it off")
local auras = pageNamed("Auras")
check(auras.preview and auras.preview.kind == "button", "Auras page uses the test button")
auras.preview.widget:Enable()
W.SelectPage(auras)
frame.pagePreview:Click()
check(BetterBlizzPlatesDB.nameplateAuraTestMode == true, "aura preview on")
check(frame.pagePreview:GetText() == "Stop preview", "aura preview shows it is on")
frame.pagePreview:Click()
check(not BetterBlizzPlatesDB.nameplateAuraTestMode, "aura preview off")
check(pageNamed("Size and stacking").preview, "stacking page has a preview")

-- Slider: drag, step buttons, exact value, value outside the range.
item = find(function(i) return i.kind == "slider" and i.sectionName == "Healer Indicator" and i.name == "Friendly Scale" end)
check(item, "Friendly Scale slider found")
row = rowFor(item)
row.slider:SetValue(1.5)
check(BetterBlizzPlatesDB.healerIndicatorScale == 1.5, "slider changes the setting")
row.plus:Click()
check(math.abs(BetterBlizzPlatesDB.healerIndicatorScale - 1.51) < 1e-6, "+ steps up")
row.minus:Click()
row.minus:Click()
check(math.abs(BetterBlizzPlatesDB.healerIndicatorScale - 1.49) < 1e-6, "- steps down")
row.value:SetText("2.25")
state[row.value].scripts.OnEnterPressed(row.value)
check(BetterBlizzPlatesDB.healerIndicatorScale == 2.25, "typed value changes the setting")
row.value:SetText("9")
state[row.value].scripts.OnEnterPressed(row.value)
check(BetterBlizzPlatesDB.healerIndicatorScale == 9, "typed value outside the range is accepted")
W.RefreshRows()
check(row.slider:GetValue() == 9, "our slider follows the wider range")
state[row.slider].scripts.OnMouseDown(row.slider, "LeftButton")
check(frame:GetAlpha() < 0.5, "window fades while a slider is held")
state[row.slider].scripts.OnMouseUp(row.slider, "LeftButton")
check(frame:GetAlpha() == 1, "window comes back")

-- Dropdown: opens BetterBlizzPlates' own menu.
item = find(function(i) return i.kind == "dropdown" and i.sectionName == "Healer Indicator" and i.name == "Enemy Anchor" end)
check(item, "Enemy Anchor dropdown found")
row = rowFor(item)
mock.lastMenu = nil
row.drop:Click()
check(mock.lastMenu and mock.lastMenu.owner == row.drop, "menu opened on our button")
local radios = {}
local root = {}
function root:CreateRadio(text, isSelected, onSelect) radios[#radios + 1] = { text = text, select = onSelect } return root end
function root:CreateButton(text, onSelect) radios[#radios + 1] = { text = text, select = onSelect } return root end
function root:CreateCheckbox(text, isSelected, onSelect) radios[#radios + 1] = { text = text, select = onSelect } return root end
setmetatable(root, { __index = function() return function() end end })
mock.lastMenu.generator(row.drop, root)
check(#radios > 3, "menu has choices")
local target
for _, radio in ipairs(radios) do
    if radio.text ~= BBP.L["Anchor_" .. tostring(BetterBlizzPlatesDB.healerIndicatorEnemyAnchor)] then target = radio end
end
local old = BetterBlizzPlatesDB.healerIndicatorEnemyAnchor
target.select()
check(BetterBlizzPlatesDB.healerIndicatorEnemyAnchor ~= old, "menu choice changes the setting")
W.RefreshRows()
check(row.drop.value:GetText() == BBP.L["Anchor_" .. BetterBlizzPlatesDB.healerIndicatorEnemyAnchor],
    "dropdown shows the new choice")

-- Dropdown clarity: texture sample, count for multi-choice lists.
item = find(function(i) return i.kind == "dropdown" and i.name == "Texture (Enemy)" end)
check(item, "texture dropdown named")
row = rowFor(item)
check(row.drop.sample:IsShown(), "texture dropdown shows a sample")
item = find(function(i) return i.kind == "dropdown" and i.name == "Hide Options" end)
row = rowFor(item)
check(tostring(row.drop.value:GetText()):find("^%d+ of %d+ on$"), "multi-choice shows a count: " .. tostring(row.drop.value:GetText()))
check(not row.drop.sample:IsShown(), "no sample on other dropdowns")

-- Texture menu samples must not leak into the next menu (rows are reused by the game).
do
    local function fakeRoot(rowFrame)
        local rootDesc = {}
        local element = setmetatable({}, { __index = function(_, method)
            if method == "AddInitializer" then
                return function(_, init) init(rowFrame) end
            end
            return function() end
        end })
        return setmetatable(rootDesc, { __index = function() return function() return element end end })
    end
    local function samples(w)
        local shown, total = 0, 0
        for _, region in pairs(w.texturePool) do
            total = total + 1
            if region:IsShown() and region:GetParent() ~= w then shown = shown + 1 end
        end
        return shown, total
    end
    local function tick(dt)
        state[frame].scripts.OnUpdate(frame, dt or 0.02)
    end

    local texItem = find(function(i) return i.kind == "dropdown" and i.name == "Texture (Enemy)" end)
    local other = find(function(i) return i.kind == "dropdown" and i.name == "Enemy Anchor" end)
    local w = texItem.widget
    check(w.texturePool and not w.fontPool, "texture dropdown has only a texture pool")

    -- Open the texture menu: the game builds rows and BetterBlizzPlates puts a sample on each.
    local menuFrame = mock.new("Frame")
    local menuRow = mock.new("Button", menuFrame)
    w:Enable()
    other.widget:Enable()
    local function openTexMenu()
        row = rowFor(texItem)
        mock.lastMenu = nil
        row.drop:Click()
        check(mock.lastMenu and mock.lastMenu.owner == row.drop, "texture menu opened")
        mock.lastMenu.generator(row.drop, fakeRoot(menuRow))
    end
    openTexMenu()
    local shown, total = samples(w)
    check(total >= 3 and shown == total, "samples sit on the menu rows: " .. shown .. "/" .. total)

    -- The reported bug: open another dropdown right after. The samples must be gone.
    row = rowFor(other)
    row.drop:Click()
    check(samples(w) == 0, "samples are cleared when another menu opens")

    -- And when the menu just closes (click outside), without opening another one.
    openTexMenu()
    tick()
    check(samples(w) == total, "samples stay while the menu is open")
    menuFrame:Hide()
    tick()
    check(samples(w) == 0, "samples are cleared when the menu closes")
    menuFrame:Show()

    -- Closing our window clears them too.
    openTexMenu()
    W.Hide()
    check(samples(w) == 0, "samples are cleared when the window closes")
    SlashCmdList["BETTERBETTERBLIZZPLATES"]("")
    model = W.model
end

-- Colour: opens the colour picker through the original swatch.
item = find(function(i) return i.kind == "color" and i.name == "Boss" end)
check(item, "Boss colour found")
local picker
rawset(ColorPickerFrame, "SetupColorPickerAndShow", function(_, info) picker = info end)
row = rowFor(item)
item.widget:SetAlpha(1)
W.RefreshRows()
row.swatch:Click()
check(picker and picker.swatchFunc, "colour picker opened")

-- More: right-click options are reachable.
item = find(function(i) return i.key == "smallPetsInPvP" end)
row = rowFor(item)
check(row.more:IsShown(), "More button shown")
check(BBPSmallPetsOptionsFrame == nil, "small pets window not built yet")
row.more:Click()
check(BBPSmallPetsOptionsFrame ~= nil, "More opens the extra options")

-- Search: finds listed settings, switches and test modes.
frame.search:SetText("healer indicator")
check(W.query == "healer indicator" and #W.display > 5, "search finds settings")
local sawSwitch = false
for _, entry in ipairs(W.display) do
    if entry.item then
        check(entry.item.search:find("healer", 1, true), "result matches")
        if entry.item.key == "healerIndicator" then sawSwitch = true end
    end
end
check(sawSwitch, "search finds the feature switch")
check(frame.search.clear:IsShown(), "clear button shown")
frame.search.clear:Click()
check(W.query == "", "clear button empties the search")
frame.search:SetText("zzqqxx")
check(#W.display == 0 and frame.empty:IsShown(), "no results message")
frame.search:SetText("")

-- Fold one group.
W.SelectPage(model.pages[1])
W.FoldAll(false)
local full = #W.display
W.offset = 0
W.Render()
state[W.rows[1]].scripts.OnClick(W.rows[1], "LeftButton")
check(#W.display < full, "group folds")
state[W.rows[1]].scripts.OnClick(W.rows[1], "LeftButton")
check(#W.display == full, "group unfolds")

-- Toggle closes; reopening rebuilds.
local count = #model.items
SlashCmdList["BETTERBETTERBLIZZPLATES"]("")
check(not W.IsShown(), "slash command toggles the window")
SlashCmdList["BETTERBETTERBLIZZPLATES"]("")
check(W.IsShown() and #W.model.items == count, "reopen works")

-- Original settings.
local srcPage = W.model.source.pages[3]
W.OpenOriginal(srcPage)
check(mock.openedCategory == srcPage.category:GetID(), "original page opens the right category")
check(not W.IsShown(), "window hides for the original page")

-- Reset: BetterBlizzPlates' own "Default" button, shown on the slider row.
SlashCmdList["BETTERBETTERBLIZZPLATES"]("")
model = W.model
item = find(function(i) return i.kind == "slider" and i.reset end)
check(item, "a slider with a reset button exists")
local resets = 0
for _, it in ipairs(model.items) do
    if it.reset then resets = resets + 1 end
end
check(resets >= 10, "reset buttons found: " .. resets)
local resetRan = false
local resetScript = state[item.reset].scripts.OnClick
state[item.reset].scripts.OnClick = function(...)
    resetRan = true
    return resetScript(...)
end
row = rowFor(item)
check(row.reset:IsShown(), "Reset shown on that slider")
row.reset:Click()
check(resetRan, "Reset runs BetterBlizzPlates' own Default button")
item = find(function(i) return i.kind == "slider" and not i.reset end)
check(not rowFor(item).reset:IsShown(), "no Reset where BetterBlizzPlates has none")

-- Keyless settings moved by label.
check(find(function(i) return i.name == "PRD Max Auras" end).sectionName == "Personal Resource Display",
    "PRD sliders sit with the personal resource display")

-- Pages remember their scroll position.
local pageA, pageB = pageNamed("Auras"), pageNamed("Castbar")
W.SelectPage(pageA)
W.FoldAll(false)
W.offset = 7
W.Render()
W.SelectPage(pageB)
W.FoldAll(false)
W.offset = 2
W.Render()
W.SelectPage(pageA)
check(W.offset == 7, "scroll position kept per page")
W.SelectPage(pageB)
check(W.offset == 2, "each page has its own position")

-- Reload UI: the window comes back after.
local reloaded = false
rawset(_G, "ReloadUI", function() reloaded = true end)
frame.reload:Click()
check(reloaded and type(BetterBetterBlizzPlatesDB.reopen) == "number", "Reload UI marks the window to reopen")
local function fireCore(event)
    for _, f in ipairs(mock.frames) do
        local s = state[f]
        if s.events and s.events.PLAYER_LOGOUT and s.scripts.OnEvent then s.scripts.OnEvent(f, event) end
    end
end
W.Hide()
fireCore("PLAYER_LOGIN")
mock.runTimers(4)
check(W.IsShown() and BetterBetterBlizzPlatesDB.reopen == nil, "window reopens after a reload")
BetterBetterBlizzPlatesDB.reopen = nil
fireCore("PLAYER_LOGOUT")
check(type(BetterBetterBlizzPlatesDB.reopen) == "number", "/reload with the window open also reopens it")
W.Hide()
BetterBetterBlizzPlatesDB.reopen = time() - 600
fireCore("PLAYER_LOGIN")
mock.runTimers(4)
check(not W.IsShown(), "no reopen after a real log out")
fireCore("PLAYER_LOGOUT")
check(BetterBetterBlizzPlatesDB.reopen == nil, "closed window is not reopened")

-- Entry button in the original Settings window: title bar, only on BetterBlizzPlates' pages.
local entry = ns.button
check(entry and entry:GetParent() == SettingsPanel, "entry button lives on the Settings window")
local _, anchoredTo = entry:GetPoint(1)
check(anchoredTo == SettingsPanel.ClosePanelButton, "entry button sits next to the close button")
check(not entry:IsShown(), "entry button hidden until a BetterBlizzPlates page shows")
rawset(SettingsPanel, "currentLayout", { frame = BetterBlizzPlates })
SettingsPanel:DisplayLayout()
check(entry:IsShown(), "entry button shown on the main page")
rawset(SettingsPanel, "currentLayout", { frame = ns.Harvest.panels[3] })
SettingsPanel:DisplayLayout()
check(entry:IsShown(), "entry button shown on sub pages")
rawset(SettingsPanel, "currentLayout", { frame = mock.new("Frame") })
SettingsPanel:DisplayLayout()
check(not entry:IsShown(), "entry button hidden on other addons' pages")
rawset(SettingsPanel, "currentLayout", { frame = BetterBlizzPlates })
SettingsPanel:DisplayLayout()
W.Hide()
SettingsPanel:Show()
entry:Click()
mock.runTimers(2)
check(W.IsShown() and not SettingsPanel:IsShown(), "entry button opens the window and closes Settings")

-- If regrouping ever fails, BetterBlizzPlates' own pages are shown instead.
local build = ns.Layout.Build
ns.Layout.Build = function() error("regroup failed") end
W.Hide()
SlashCmdList["BETTERBETTERBLIZZPLATES"]("")
check(W.IsShown() and W.model.pages[1].name == "General" and #W.model.items > 500, "falls back to the original pages")
for _, page in ipairs(W.model.pages) do
    W.SelectPage(page)
    W.FoldAll(false)
end
W.Hide()
ns.Layout.Build = build

io.write("ok - ", passed, " checks, ", count, " settings on ", #model.pages, " pages\n")

-- Widget methods the addon used that the fake API only stubs. Review by hand.
if os.getenv("BBBP_VERBOSE") then
    local stubbed = {}
    for name in pairs(mock.unknown) do stubbed[#stubbed + 1] = name end
    table.sort(stubbed)
    io.write("stubbed widget API used by the addon:\n  ", table.concat(stubbed, " "), "\n")
end
