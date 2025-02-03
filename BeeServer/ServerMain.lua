-- Load system dependencies.
local component = require("component")
local event = require("event")
local serial = require("serialization")

local BeeServer = require("BeeServer.BeeServer")

-- TODO: Read from config file?
local logFilepath = "/home/BeeBreederBot/DroneLocations.log"

local server = BeeServer:Create(component, event, serial, logFilepath)
server:RunServer()
