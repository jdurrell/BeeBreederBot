-- Load system dependencies.
local component = require("component")
local event = require("event")
local robot = require("robot")
local serial = require("serialization")
local sides = require("sides")

local ConfigService = require("Shared.Config")
local BeekeeperBot = require("BeekeeperBot.BeekeeperBot")

local config = {port = "34000", apiaries = "1", serverAddr = ""}

if not ConfigService.LoadConfig("./bot.cfg", config, false) then
    Print("Failed to read configuration.")
    return
end

if config.serverAddr == "" then
    Print("Error: Required parameter 'serverAddr' not specified.")
    return
end

---@cast component Component
---@cast event Event
---@cast serial Serialization
local bot = BeekeeperBot:Create(component, event, robot, serial, sides, config)
bot:RunRobot()
