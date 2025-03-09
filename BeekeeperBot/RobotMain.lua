-- Load system dependencies.
local component = require("component")
local event = require("event")
local serial = require("serialization")
local sides = require("sides")

local CommLayer = require("Shared.CommLayer")
local BeekeeperBot = require("BeekeeperBot.BeekeeperBot")

-- TODO: Read from config file?
local logFilepath = "/home/BeeBreederBot/DroneLocations.log"
local comPort = CommLayer.DefaultComPort

local robot = BeekeeperBot:Create(component, event, serial, sides, logFilepath, comPort)
robot:RunRobot()
