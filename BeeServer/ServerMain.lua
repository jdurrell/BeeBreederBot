-- Load system dependencies.
local component = require("component")
local event = require("event")
local serial = require("serialization")

local BeeServer = require("BeeServer.BeeServer")
local CommLayer = require("Shared.CommLayer")

-- TODO: Read from config file?
local logFilepath = "/home/BeeBreederBot/DroneLocations.log"
local comPort = CommLayer.DefaultComPort

local server = BeeServer:Create(component, event, serial, logFilepath, comPort)
server:RunServer()
