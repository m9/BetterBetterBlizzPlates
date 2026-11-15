-- Pre-release check. Run from the addon folder:
--   luajit tools/check.lua <BetterBlizzPlates folder> [--update]
-- 1. every Lua file parses
-- 2. versions and the client list in our TOC match BetterBlizzPlates'
-- 3. per game client: the tests pass, then pages and what changed since
--    tools/snapshots/<client>.txt
-- --update rewrites the snapshots (do it when releasing).
-- (--client <name> is used by the tool itself: it reports one client.)

local bbpPath, update, only
do
    local i = 1
    while arg[i] do
        if arg[i] == "--update" then
            update = true
        elseif arg[i] == "--client" then
            i = i + 1
            only = arg[i]
        else
            bbpPath = bbpPath or arg[i]
        end
        i = i + 1
    end
end
if not bbpPath then
    io.stderr:write("usage: luajit tools/check.lua <BetterBlizzPlates folder> [--update]\n")
    os.exit(2)
end

local windows = package.config:sub(1, 1) == "\\"
local exe = arg[-1] or "luajit"
local failed = false

local function step(name, ok, detail)
    io.write(ok and "ok    " or "FAIL  ", name, detail and ("  " .. detail) or "", "\n")
    if not ok then failed = true end
end

local function tocFields(path)
    local fields, files = {}, {}
    for line in io.lines(path) do
        local field, value = line:match("^##%s*([%w%-]+)%s*:%s*(.-)%s*$")
        if field then
            fields[field] = value
        elseif line:match("^[%w_\\/]+%.lua%s*$") then
            files[#files + 1] = (line:gsub("%s+$", ""))
        end
    end
    return fields, files
end

local toc, files = tocFields("BetterBetterBlizzPlates.toc")

------------------------------------------------------------
-- One client: pages and snapshot. Runs in its own process (the fake API is global).
------------------------------------------------------------
local function reportClient(client)
    local env = dofile("tests/load_bbp.lua")(bbpPath, client)
    local mock = env.mock
    local ns = {}
    assert(loadfile("Harvest.lua"))("BetterBetterBlizzPlates", ns)
    assert(loadfile("Layout.lua"))("BetterBetterBlizzPlates", ns)
    ns.Harvest.InstallHooks()
    BBP.InitializeOptions()
    BBP.LoadGUI()
    mock.runTimers(3)
    local model = ns.Layout.Build(assert(ns.Harvest.Build("General")), "General")

    -- Snapshot: checkbox keys with their page and group, plus a count of the rest per page.
    local lines, other, counts = {}, 0, {}
    for _, page in ipairs(model.pages) do
        local keyless = 0
        for _, item in ipairs(page.items) do
            if item.key then
                lines[#lines + 1] = item.key .. "\t" .. page.name .. "\t" .. item.sectionName
            else
                keyless = keyless + 1
            end
        end
        lines[#lines + 1] = "#keyless\t" .. page.name .. "\t" .. keyless
        counts[#counts + 1] = page.name .. " " .. #page.items
        if page.name == "Other" then other = #page.items end
    end
    table.sort(lines)
    io.write("  ", table.concat(counts, ", "), "\n")
    io.write("  total ", #model.items, ", on the Other page: ", other, "\n")

    local path = "tools/snapshots/" .. client .. ".txt"
    local old = {}
    local snapshot = io.open(path, "r")
    if snapshot then
        -- Git on Windows may check the file out with CRLF line ends.
        for line in snapshot:lines() do old[(line:gsub("\r$", ""))] = true end
        snapshot:close()
    end
    local now, changes = {}, 0
    for _, line in ipairs(lines) do
        now[line] = true
        if snapshot and not old[line] then
            io.write("  + ", (line:gsub("\t", "  |  ")), "\n")
            changes = changes + 1
        end
    end
    for line in pairs(old) do
        if not now[line] then
            io.write("  - ", (line:gsub("\t", "  |  ")), "\n")
            changes = changes + 1
        end
    end
    if not snapshot then
        io.write("  no snapshot yet (run with --update)\n")
    elseif changes == 0 then
        io.write("  no change since the snapshot\n")
    else
        io.write("  ", changes, " line(s) changed since the snapshot (+ new or moved here, - gone or moved away)\n")
    end

    if update then
        local out = assert(io.open(path, "wb"))
        out:write(table.concat(lines, "\n"), "\n")
        out:close()
        io.write("  snapshot updated\n")
    end
end

if only then
    reportClient(only)
    os.exit(0)
end

------------------------------------------------------------
-- 1. Parse.
------------------------------------------------------------
local sources = { "tests/mock.lua", "tests/load_bbp.lua", "tests/test.lua", "tests/test_missing.lua",
    "tests/dump.lua", "tools/build.lua" }
for _, file in ipairs(files) do sources[#sources + 1] = file end
for _, file in ipairs(sources) do
    local chunk, err = loadfile(file)
    step("parse " .. file, chunk ~= nil, err)
end

------------------------------------------------------------
-- 2. Versions and clients.
------------------------------------------------------------
local known = dofile("tests/load_bbp.lua")()
local theirs
local wanted, wantedList = {}, {}
for _, name in ipairs(known.order) do
    local path = bbpPath .. "/" .. known.clients[name].toc
    local fields = tocFields(path)
    local version = (fields.Version or "?"):gsub("^[vV]", "")
    theirs = theirs or version
    step("BetterBlizzPlates version is the same for " .. name, version == theirs, version)
    for _, number in ipairs(known.interfaces(path)) do
        if not wanted[number] then
            wanted[number] = name
            wantedList[#wantedList + 1] = number
        end
    end
end
local madeFor = toc["X-BetterBlizzPlates-Version"] or "?"
io.write("\nBetterBlizzPlates installed: ", theirs or "?", "\nmade for:                    ", madeFor,
    "\nour version:                 ", toc.Version or "?", "\n")
step("installed version is the one this is made for", theirs == madeFor)
-- Version scheme: <their version>-p<patch level>, with "-dev" on the working copy.
local ours = toc.Version or ""
local rest = ours:sub(1, #madeFor + 1) == madeFor .. "-" and ours:sub(#madeFor + 2) or ""
rest = rest:gsub("%-dev$", "")
step("our version is " .. madeFor .. "-p<number>", rest:match("^p%d+$") ~= nil)

-- Our one TOC lists every client BetterBlizzPlates has a TOC for, and no other.
local have = {}
for number in (toc.Interface or ""):gmatch("%d+") do have[tonumber(number)] = true end
local missing, extra = {}, {}
for _, number in ipairs(wantedList) do
    if not have[number] then missing[#missing + 1] = number .. " (" .. wanted[number] .. ")" end
end
for number in pairs(have) do
    if not wanted[number] then extra[#extra + 1] = tostring(number) end
end
table.sort(extra)
step("our TOC lists BetterBlizzPlates' clients", #missing == 0 and #extra == 0,
    (#missing > 0 and ("missing " .. table.concat(missing, ", ") .. " ") or "")
    .. (#extra > 0 and ("not theirs: " .. table.concat(extra, ", ")) or ""))

------------------------------------------------------------
-- 3. Tests and report, each client in its own process.
------------------------------------------------------------
local function run(script, ...)
    local command = '"' .. exe .. '" ' .. script
    for _, argument in ipairs({ ... }) do
        command = command .. (argument:find("^%-%-") and (" " .. argument) or (' "' .. argument .. '"'))
    end
    if windows then command = '"' .. command .. '"' end
    io.stdout:flush()
    local result = os.execute(command)
    return result == 0 or result == true
end

io.write("\n")
step("tests/test_missing.lua", run("tests/test_missing.lua"))
for _, name in ipairs(known.order) do
    io.write("\n", name, " (", table.concat(known.interfaces(bbpPath .. "/" .. known.clients[name].toc), ", "), ")\n")
    step("tests/test.lua " .. name, run("tests/test.lua", bbpPath, name))
    local reported
    if update then
        reported = run("tools/check.lua", bbpPath, "--client", name, "--update")
    else
        reported = run("tools/check.lua", bbpPath, "--client", name)
    end
    step("report " .. name, reported)
end

io.write(failed and "\nCHECK FAILED\n" or "\ncheck passed\n")
os.exit(failed and 1 or 0)
