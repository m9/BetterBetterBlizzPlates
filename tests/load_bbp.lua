-- Loads the installed BetterBlizzPlates options code into the fake API.
-- Usage: local env = dofile("tests/load_bbp.lua")(bbpPath)
-- Nothing is copied from BetterBlizzPlates; its files are read from the install.

local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local mock = dofile(here .. "/mock.lua")

local function readLines(path, first, last)
    local out, n = {}, 0
    for line in io.lines(path) do
        n = n + 1
        if n >= first and n <= last then out[#out + 1] = line end
        if n > last then break end
    end
    return table.concat(out, "\n")
end

local function findDefaults(path)
    local first, last
    local n = 0
    for line in io.lines(path) do
        n = n + 1
        if not first and line:match("^local defaultSettings = {") then
            first = n
        elseif first and not last and line:match("^}") then
            last = n
            break
        end
    end
    assert(first and last, "defaultSettings table not found")
    return readLines(path, first + 1, last - 1)
end

return function(bbpPath)
    mock.install()
    mock.lenientGlobals()
    -- The installed BetterBlizzPlates' real version, as the game would report it.
    mock.readToc("BetterBlizzPlates", bbpPath .. "/BetterBlizzPlates_Camelot.toc")

    local function run(rel, ...)
        local chunk = assert(loadfile(bbpPath .. "/" .. rel))
        return chunk(...)
    end

    run("init.lua")
    run("locales/locale.lua")
    run("locales/enUS.lua")
    run("shared/functions.lua")
    for _, rel in ipairs({ "shared/fontFallback.lua", "shared/nameplateToggles.lua", "shared/threatTweaks.lua",
        "shared/comboVisibility.lua", "forever/modules/profiles.lua" }) do
        local ok, err = pcall(run, rel)
        if not ok and os.getenv("BBBP_VERBOSE") then io.stderr:write("skip ", rel, ": ", tostring(err), "\n") end
    end

    local body = findDefaults(bbpPath .. "/forever/BetterBlizzPlates.lua")
    local defaults = assert(loadstring("local addonVersion = '1.00' local L = BBP.L return {\n" .. body .. "\n}"))()

    BetterBlizzPlatesDB = CopyTable(defaults)
    BetterBlizzPlatesDB.hasNotOpenedSettings = nil
    BetterBlizzPlatesDB.wasOnLoadingScreen = false
    BBP.exportDefaults = defaults
    BBP.variablesLoaded = true
    BBP.VersionNumber = "test"
    BBP.ProfileData = {}
    BBP.CVarsAreSaved = function() return true end
    BBP.checkCombatAndWarn = function() return false end
    BBP.isLargeNameplatesEnabled = function() return false end
    setmetatable(BBP, { __index = function(_, k)
        if type(k) == "string" and k:match("^[A-Z]") then
            return function() end
        end
    end })

    run("forever/gui.lua")

    return { mock = mock, defaults = defaults, bbpPath = bbpPath }
end
