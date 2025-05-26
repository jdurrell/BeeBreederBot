-- Load system dependencies.
local component = require("component")
local event = require("event")
local robot = require("robot")
local serial = require("serialization")
local sides = require("sides")

require("Shared.Shared")
local ConfigService = require("Shared.Config")
local BeekeeperBot = require("BeekeeperBot.BeekeeperBot")

if component == nil then
    Print("Couldn't find 'component' module.")
    return
elseif event == nil then
    Print("Couldn't find 'event' module.")
    return
elseif robot == nil then
    Print("Couldn't find 'robot' module.")
    return
elseif serial == nil then
    Print("Couldn't find 'serial' module.")
    return
elseif sides == nil then
    Print("Couldn't find 'sides' module.")
    return
end

local config = {port = 34000, apiaries = 1, serverAddr = "", defaultHumidityTolerance = "BOTH_5", defaultTemperatureTolerance = "BOTH_5"}

if not ConfigService.LoadConfig("./bot.cfg", config, false) then
    Print("Failed to read configuration.")
    return
end

if config.serverAddr == "" then
    Print("Error: Required parameter 'serverAddr' not specified.")
    return
end

Print("Starting BeekeeperBot with configuration: ")
ConfigService.PrintConfig(config)
Sleep(1)

---@cast component Component
---@cast event Event
---@cast serial Serialization
local bot = BeekeeperBot:Create(component, event, robot, serial, sides, config)
bot:RunRobot()
