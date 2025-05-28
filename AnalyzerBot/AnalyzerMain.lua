local component = require("component")
local robot = require("robot")

local AnalyzerBot = require("AnalyzerBot.AnalyzerBot")

if component == nil then
    print("Couldn't find 'component' module.")
    return
elseif robot == nil then
    print("Coudln't find 'robot' module")
    return
end

---@cast component Component
local bot = AnalyzerBot:Create(component, robot)

if bot == nil then
    print("Failed to start analyzer bot.")
    return
end
bot:Run()
