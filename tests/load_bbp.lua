-- Loads the installed BetterBlizzPlates options code into the fake API.
-- Usage: local env = dofile("tests/load_bbp.lua")(bbpPath, client)
-- client: forever (default), retail, era, tbc, wrath, cata, mists.
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

-- The game clients BetterBlizzPlates has a TOC for. dir = which copy of its code that TOC loads.
local CLIENTS = {
    forever = { toc = "BetterBlizzPlates_Camelot.toc", dir = "forever", build = "1.60.1", project = 1 },
    retail = { toc = "BetterBlizzPlates.toc", dir = "retail", build = "12.1.5", project = 1 },
    era = { toc = "BetterBlizzPlates_Vanilla.toc", dir = "classics", build = "1.15.9", project = 2 },
    tbc = { toc = "BetterBlizzPlates_TBC.toc", dir = "classics", build = "2.5.6", project = 5 },
    wrath = { toc = "BetterBlizzPlates_Wrath.toc", dir = "classics", build = "3.4.5", project = 11 },
    cata = { toc = "BetterBlizzPlates_Cata.toc", dir = "classics", build = "4.4.2", project = 14 },
    mists = { toc = "BetterBlizzPlates_Mists.toc", dir = "classics", build = "5.5.4", project = 19 },
}
local ORDER = { "forever", "retail", "era", "tbc", "wrath", "cata", "mists" }

local function interfaces(path)
    local list = {}
    for line in io.lines(path) do
        local value = line:match("^##%s*Interface%s*:%s*(.-)%s*$")
        if value then
            for number in value:gmatch("%d+") do list[#list + 1] = tonumber(number) end
        end
    end
    return list
end

local function load(bbpPath, clientName)
    clientName = clientName or "forever"
    local client = assert(CLIENTS[clientName], "unknown client: " .. tostring(clientName))
    local dir = client.dir
    local tocPath = bbpPath .. "/" .. client.toc
    local numbers = interfaces(tocPath)

    mock.install()
    mock.lenientGlobals()
    _G.WOW_PROJECT_ID, _G.WOW_PROJECT_MAINLINE = client.project, 1
    _G.GetBuildInfo = function() return client.build, "1", "date", numbers[1] end
    -- The installed BetterBlizzPlates' real version, as the game would report it.
    mock.readToc("BetterBlizzPlates", tocPath)

    local function run(rel, ...)
        local chunk = assert(loadfile(bbpPath .. "/" .. rel))
        return chunk(...)
    end

    run("init.lua")
    run("locales/locale.lua")
    run("locales/enUS.lua")
    run("shared/functions.lua")
    for _, rel in ipairs({ "shared/fontFallback.lua", "shared/nameplateToggles.lua", "shared/threatTweaks.lua",
        "shared/comboVisibility.lua", dir .. "/modules/profiles.lua", dir .. "/modules/totem.lua" }) do
        local ok, err = pcall(run, rel)
        if not ok and os.getenv("BBBP_VERBOSE") then io.stderr:write("skip ", rel, ": ", tostring(err), "\n") end
    end

    local body = findDefaults(bbpPath .. "/" .. dir .. "/BetterBlizzPlates.lua")
    local defaults = assert(loadstring("local addonVersion = '1.00' local L = BBP.L return {\n" .. body .. "\n}"))()

    BetterBlizzPlatesDB = CopyTable(defaults)
    -- Settings that start as a copy of another one (BetterBlizzPlates fills them at login):
    -- the friendly castbar values and the friendly vertical position.
    local copies, inKeys = { friendlyNameplateVerticalPosition = "nameplateVerticalPosition" }, false
    for line in io.lines(bbpPath .. "/" .. dir .. "/BetterBlizzPlates.lua") do
        if line:match("^BBP%.friendlyCastbarKeys = {") then
            inKeys = true
        elseif inKeys and line:match("^}") then
            break
        elseif inKeys then
            local from, to = line:match("^%s*([%w_]+)%s*=%s*\"([%w_]+)\"")
            if from then copies[to] = from end
        end
    end
    for to, from in pairs(copies) do
        if BetterBlizzPlatesDB[to] == nil then BetterBlizzPlatesDB[to] = BetterBlizzPlatesDB[from] end
    end
    -- The classic clients fill some lists outside the defaults table (per expansion). The options
    -- code needs them to exist; empty is enough here.
    for line in io.lines(bbpPath .. "/" .. dir .. "/gui.lua") do
        if line:find("Create%w*List%w*%(") then
            for key in line:gmatch("BetterBlizzPlatesDB%.([%w_]+)") do
                if BetterBlizzPlatesDB[key] == nil then BetterBlizzPlatesDB[key] = {} end
            end
        end
    end
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

    run(dir .. "/gui.lua")

    return { mock = mock, defaults = defaults, bbpPath = bbpPath, client = clientName, dir = dir,
        interfaces = numbers }
end

-- Called with a path: load. Called with nothing: the client table, for tools that only need the list.
return function(bbpPath, clientName)
    if not bbpPath then return { clients = CLIENTS, order = ORDER, interfaces = interfaces } end
    return load(bbpPath, clientName)
end
