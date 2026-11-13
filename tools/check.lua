-- Pre-release check. Run from the addon folder:
--   luajit tools/check.lua <BetterBlizzPlates folder> [--update]
-- 1. every Lua file parses   2. both test files pass
-- 3. report: versions, pages, and what changed since tools/snapshot.txt
-- --update rewrites the snapshot (do it when releasing).

local bbpPath, update
for _, a in ipairs(arg) do
    if a == "--update" then update = true else bbpPath = bbpPath or a end
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

-- 1. Parse.
local toc, files = tocFields("BetterBetterBlizzPlates.toc")
local sources = { "tests/mock.lua", "tests/load_bbp.lua", "tests/test.lua", "tests/test_missing.lua", "tests/dump.lua" }
for _, file in ipairs(files) do sources[#sources + 1] = file end
for _, file in ipairs(sources) do
    local chunk, err = loadfile(file)
    step("parse " .. file, chunk ~= nil, err)
end

-- 2. Tests, each in its own process.
local function run(script, argument)
    local command = '"' .. exe .. '" ' .. script .. (argument and (' "' .. argument .. '"') or "")
    if windows then command = '"' .. command .. '"' end
    local result = os.execute(command)
    return result == 0 or result == true
end
step("tests/test.lua", run("tests/test.lua", bbpPath))
step("tests/test_missing.lua", run("tests/test_missing.lua"))

-- 3. Report.
local env = dofile("tests/load_bbp.lua")(bbpPath)
local mock = env.mock
local ns = {}
assert(loadfile("Harvest.lua"))("BetterBetterBlizzPlates", ns)
assert(loadfile("Layout.lua"))("BetterBetterBlizzPlates", ns)
ns.Harvest.InstallHooks()
BBP.InitializeOptions()
BBP.LoadGUI()
mock.runTimers(3)
local model = ns.Layout.Build(assert(ns.Harvest.Build("General")), "General")

local theirs = (mock.metadata["BetterBlizzPlates/Version"] or "?"):gsub("^[vV]", "")
local madeFor = toc["X-BetterBlizzPlates-Version"] or "?"
io.write("\nBetterBlizzPlates installed: ", theirs, "\nmade for:                    ", madeFor,
    "\nour version:                 ", toc.Version or "?", "\n")
step("installed version is the one this is made for", theirs == madeFor)
-- Version scheme: <their version>-p<patch level>, with "-dev" on the working copy.
local ours = toc.Version or ""
local rest = ours:sub(1, #madeFor + 1) == madeFor .. "-" and ours:sub(#madeFor + 2) or ""
rest = rest:gsub("%-dev$", "")
step("our version is " .. madeFor .. "-p<number>", rest:match("^p%d+$") ~= nil)

-- Snapshot: checkbox keys with their page and group, plus a count of the rest per page.
local lines, other = {}, 0
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
    io.write(string.format("  %-20s %4d settings\n", page.name, #page.items))
    if page.name == "Other" then other = #page.items end
end
table.sort(lines)
io.write("  total ", #model.items, ", on the Other page: ", other, "\n\n")

local old = {}
local snapshot = io.open("tools/snapshot.txt", "r")
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
    io.write("no snapshot yet (run with --update)\n")
elseif changes == 0 then
    io.write("no change since the snapshot\n")
else
    io.write(changes, " line(s) changed since the snapshot (+ new or moved here, - gone or moved away)\n")
end

if update then
    local out = assert(io.open("tools/snapshot.txt", "wb"))
    out:write(table.concat(lines, "\n"), "\n")
    out:close()
    io.write("snapshot updated\n")
end

io.write(failed and "\nCHECK FAILED\n" or "\ncheck passed\n")
os.exit(failed and 1 or 0)
