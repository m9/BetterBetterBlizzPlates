-- luajit tests/test_missing.lua
-- The addon must stay quiet (no Lua error) when BetterBlizzPlates is missing or changed.

local function scenario(name, setup, expect)
    local mock = dofile("tests/mock.lua")
    BBP, BetterBlizzPlates, BetterBlizzPlatesDB, BetterBetterBlizzPlatesDB = nil, nil, nil, nil
    mock.install()
    setup(mock)
    local ns = {}
    for line in io.lines("BetterBetterBlizzPlates.toc") do
        local file = line:match("^([%w_]+%.lua)%s*$")
        if file then assert(loadfile(file))("BetterBetterBlizzPlates", ns) end
    end
    SlashCmdList["BETTERBETTERBLIZZPLATES"]("")
    mock.runTimers(3)
    local last = mock.printed[#mock.printed] or ""
    assert(last:find(expect, 1, true), name .. ": expected '" .. expect .. "', got '" .. last .. "'")
    assert(not ns.Window.IsShown(), name .. ": window must stay closed")
    io.write("ok - ", name, "\n")
end

scenario("BetterBlizzPlates missing", function() end, "not found")

scenario("LoadGUI gone", function()
    BBP = {}
end, "not found")

scenario("LoadGUI errors", function()
    BBP = { LoadGUI = function() error("boom") end }
end, "Could not load")

scenario("options built but empty", function(mock)
    BetterBlizzPlates = mock.new("Frame")
    BetterBlizzPlates.guiLoaded = true
    BBP = { LoadGUI = function() end }
end, "Could not read")

scenario("first run", function()
    BetterBlizzPlatesDB = { hasNotOpenedSettings = true }
    BBP = { LoadGUI = function() end }
end, "setup first")

scenario("in combat", function(mock)
    mock.inCombat = true
    BBP = { LoadGUI = function() end }
end, "In combat")
