-- Dev tool: print the settings found in the installed BetterBlizzPlates.
-- luajit tests/dump.lua <BetterBlizzPlates folder> [raw]
--   default: the regrouped pages shown in the window     raw: BetterBlizzPlates' own pages
local env = dofile("tests/load_bbp.lua")(arg[1])
local mock = env.mock

local ns = {}
assert(loadfile("Harvest.lua"))("BetterBetterBlizzPlates", ns)
assert(loadfile("Layout.lua"))("BetterBetterBlizzPlates", ns)
ns.Harvest.InstallHooks()

BBP.InitializeOptions()
BBP.LoadGUI()
mock.runTimers(3)

local model = assert(ns.Harvest.Build("General"), "no model")
if arg[2] ~= "raw" then model = ns.Layout.Build(model, "General") end

local kinds = {}
for _, page in ipairs(model.pages) do
    io.write("\n=== ", page.name, " (", #page.items, ")", page.preview and "  [page preview]" or "", "\n")
    for _, section in ipairs(page.sections) do
        io.write("  [", section.name, "] ", #section.items,
            section.master and ("  master=" .. tostring(section.master.key)) or "",
            section.preview and "  preview" or "", "\n")
        for _, item in ipairs(section.items) do
            kinds[item.kind] = (kinds[item.kind] or 0) + 1
            io.write("    ", string.rep("  ", item.depth), item.kind:sub(1, 2), " ", item.name,
                item.alt and item.alt ~= item.name and ("  {" .. item.alt .. "}") or "",
                item.key and ("  <" .. item.key .. ">") or "", "\n")
        end
    end
end
io.write("\ntotal ", #model.items, ":")
for k, n in pairs(kinds) do io.write(" ", k, "=", n) end
io.write("\n")
