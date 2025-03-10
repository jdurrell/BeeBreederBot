-- Load system dependencies.
local component = require("component")
local event = require("event")
local robot = require("robot")
local serial = require("serialization")
local sides = require("sides")

local CommLayer = require("Shared.CommLayer")
local BeekeeperBot = require("BeekeeperBot.BeekeeperBot")

-- TODO: Read from config file?
local comPort = CommLayer.DefaultComPort
local numApiaries = 1

local bot = BeekeeperBot:Create(component, event, robot, serial, sides, comPort, numApiaries)
bot:RunRobot()
