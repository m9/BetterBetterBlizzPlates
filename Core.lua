-- Start-up, slash command and the entry button.

local ADDON, ns = ...
local H, W = ns.Harvest, ns.Window

local GENERAL = "General"

local function say(text)
    print("|cff00c0ffBetterBetterBlizzPlates|r: " .. text)
end

-- Must be in place before BetterBlizzPlates builds its options.
H.InstallHooks()

-- Each release is made for one exact BetterBlizzPlates version: the TOC line
-- "X-BetterBlizzPlates-Version". With any other version the window stays closed.
local function metadata(addon, field)
    local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    if type(get) ~= "function" then return "" end
    local ok, value = pcall(get, addon, field)
    if not ok or type(value) ~= "string" then return "" end
    -- "v2.2.3f" and "2.2.3f" are the same version.
    return (value:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^[vV]", ""))
end

-- nil when the versions match, else a short message for the player.
function ns.VersionProblem()
    local want = metadata(ADDON, "X-BetterBlizzPlates-Version")
    local have = metadata("BetterBlizzPlates", "Version")
    if want == "" or want == have then return nil end
    return "Made for BetterBlizzPlates " .. want .. ". You have " .. (have ~= "" and have or "?")
        .. ". Get the matching version."
end

local function closeBlizzardPanel()
    if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel and not InCombatLockdown() then
        HideUIPanel(SettingsPanel)
    end
end

local function show()
    local source = H.Build(GENERAL)
    if not source or #source.items == 0 then
        say("Could not read BetterBlizzPlates options.")
        return
    end
    -- Regroup into task-based pages; if that fails, show BetterBlizzPlates' own pages.
    local ok, model = pcall(ns.Layout.Build, source, GENERAL)
    if not ok or type(model) ~= "table" or #model.items == 0 then
        source = H.Build(GENERAL)
        source.previews = {}
        model = source
    end
    W.Show(model)
end

-- `fromPanel`: opened from BetterBlizzPlates' own options page.
function ns.Open(fromPanel)
    if type(BBP) ~= "table" or type(BBP.LoadGUI) ~= "function" then
        say("BetterBlizzPlates not found.")
        return
    end
    if W.IsShown() then
        W.Hide()
        return
    end
    local problem = ns.VersionProblem()
    if problem then
        say(problem)
        return
    end
    if H.IsReady() then
        if fromPanel then closeBlizzardPanel() end
        show()
        return
    end

    if InCombatLockdown() then
        say("In combat. Try again after.")
        return
    end
    local firstRun = type(BetterBlizzPlatesDB) == "table" and BetterBlizzPlatesDB.hasNotOpenedSettings
    local panelWasOpen = SettingsPanel and SettingsPanel:IsShown()
    local ok = pcall(BBP.LoadGUI)
    if firstRun then
        say("Finish the BetterBlizzPlates setup first.")
        return
    end
    if not ok or not H.IsReady() then
        say("Could not load BetterBlizzPlates options.")
        return
    end
    if fromPanel or not panelWasOpen then closeBlizzardPanel() end
    -- BetterBlizzPlates fills some controls a moment after building them.
    C_Timer.After(0.2, show)
end

SLASH_BETTERBETTERBLIZZPLATES1 = "/bbbp"
SlashCmdList["BETTERBETTERBLIZZPLATES"] = function()
    ns.Open(false)
end

-- Button on BetterBlizzPlates' main options page.
-- It sits in the Settings window's title bar, left of the close button: the one
-- strip BetterBlizzPlates leaves empty on every page. (Its header has the title, the
-- "new search" art and the search box; the bottom bar has its Reset and Reload buttons.)
local function isOurPage(frame)
    if type(frame) ~= "table" then return false end
    if frame == BetterBlizzPlates then return true end
    for _, panel in ipairs(H.panels) do
        if panel == frame then return true end
    end
    return false
end

local function updateButton()
    local button = ns.button
    if not button then return end
    local layout = SettingsPanel and SettingsPanel.currentLayout
    button:SetShown(isOurPage(type(layout) == "table" and layout.frame or nil))
end

local function addButton()
    if ns.button or type(SettingsPanel) ~= "table" or type(BetterBlizzPlates) ~= "table" then return end
    local ok, button = pcall(CreateFrame, "Button", nil, SettingsPanel, "UIPanelButtonTemplate")
    if not ok or not button then return end
    button:SetSize(116, 20)
    local close = SettingsPanel.ClosePanelButton
    if type(close) == "table" and type(close.GetFrameLevel) == "function" then
        button:SetPoint("RIGHT", close, "LEFT", -4, 0)
        button:SetFrameLevel(close:GetFrameLevel())
    else
        button:SetPoint("TOPRIGHT", SettingsPanel, "TOPRIGHT", -30, -1)
    end
    button:SetText("Better Settings")
    button:SetScript("OnClick", function() ns.Open(true) end)
    button:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine("Better Settings")
        GameTooltip:AddLine("Open the clean BetterBlizzPlates options.", 1, 1, 1, true)
        local problem = ns.VersionProblem()
        if problem then GameTooltip:AddLine(problem, 1, 0.35, 0.35, true) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    button:Hide()
    ns.button = button

    -- Show it only on BetterBlizzPlates' pages.
    if type(SettingsPanel.DisplayLayout) == "function" then
        hooksecurefunc(SettingsPanel, "DisplayLayout", updateButton)
    end
    SettingsPanel:HookScript("OnShow", updateButton)
    updateButton()
end

-- Reload with the window open (our button, /reload, BetterBlizzPlates' own
-- "reload now?" popup): open it again after. A real log out takes longer and is skipped.
local REOPEN_WINDOW = 45

function ns.MarkReopen()
    BetterBetterBlizzPlatesDB = BetterBetterBlizzPlatesDB or {}
    BetterBetterBlizzPlatesDB.reopen = time()
end

local function reopenAfterReload()
    local saved = BetterBetterBlizzPlatesDB
    local stamp = type(saved) == "table" and saved.reopen
    if not stamp then return end
    saved.reopen = nil
    if type(stamp) ~= "number" or time() - stamp > REOPEN_WINDOW or ns.VersionProblem() then return end
    -- After BetterBlizzPlates' own "reopen options" step (1 second in).
    C_Timer.After(1.5, function()
        if not InCombatLockdown() and not W.IsShown() then ns.Open(true) end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == ADDON then
            BetterBetterBlizzPlatesDB = BetterBetterBlizzPlatesDB or {}
        end
    elseif event == "PLAYER_LOGIN" then
        C_Timer.After(1, addButton)
        reopenAfterReload()
        -- Say it once at login, so a mismatch is not a silent surprise later.
        local problem = ns.VersionProblem()
        if problem then say(problem) end
    elseif event == "PLAYER_LOGOUT" then
        if W.IsShown() then ns.MarkReopen() end
    end
end)
