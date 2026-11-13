-- Builds the release zip. Run from the addon folder:
--   luajit tools/build.lua [--dev]
-- Result: out/BetterBetterBlizzPlates-<version>.zip holding one folder,
-- BetterBetterBlizzPlates, with the TOC, the files it lists, and README,
-- CHANGELOG and LICENSE when they exist. A "-dev" version needs --dev.

local NAME = "BetterBetterBlizzPlates"
local allowDev = arg[1] == "--dev"
local windows = package.config:sub(1, 1) == "\\"

local version
local files = { NAME .. ".toc" }
for line in io.lines(NAME .. ".toc") do
    version = version or line:match("^##%s*Version%s*:%s*(.-)%s*$")
    local file = line:match("^([%w_\\/]+%.lua)%s*$")
    if file then files[#files + 1] = file end
end
assert(version and version ~= "", "no version in the TOC")
if version:find("-dev$") and not allowDev then
    io.stderr:write("version is ", version, ": set the release version first (or pass --dev)\n")
    os.exit(1)
end
for _, extra in ipairs({ "README.md", "CHANGELOG.md", "LICENSE" }) do
    local f = io.open(extra, "rb")
    if f then
        f:close()
        files[#files + 1] = extra
    end
end

local function sh(command)
    local result = os.execute(command)
    assert(result == 0 or result == true, "failed: " .. command)
end

local stage = "out/" .. NAME
if windows then
    os.execute('if exist out\\' .. NAME .. ' rmdir /s /q out\\' .. NAME)
    sh('mkdir out\\' .. NAME)
else
    sh('rm -rf "' .. stage .. '" && mkdir -p "' .. stage .. '"')
end

for _, file in ipairs(files) do
    local source = assert(io.open(file, "rb"), "missing " .. file)
    local data = source:read("*a")
    source:close()
    local target = assert(io.open(stage .. "/" .. file, "wb"), "cannot write " .. file)
    target:write(data)
    target:close()
end

local zip = NAME .. "-" .. version .. ".zip"
os.remove("out/" .. zip)
if windows then
    -- Windows' own tar writes zip files with forward slashes (Compress-Archive does not).
    sh('"%SystemRoot%\\System32\\tar.exe" -a -c -f out\\' .. zip .. ' -C out ' .. NAME)
else
    sh('cd out && zip -q -r "' .. zip .. '" ' .. NAME)
end

io.write("built out/", zip, " (", #files, " files)\n")
