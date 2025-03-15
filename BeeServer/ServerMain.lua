-- Load system dependencies.
local component = require("component")
local event = require("event")
local serial = require("serialization")
local term = require("term")

local BeeServer = require("BeeServer.BeeServer")
local CommLayer = require("Shared.CommLayer")

-- TODO: Read from config file?
local logFilepath = "/home/BeeBreederBot/DroneLocations.log"
local comPort = CommLayer.DefaultComPort

---@cast component Component
---@cast event Event
---@cast serial Serialization
---@cast term Term
local server = BeeServer:Create(component, event, serial, term, logFilepath, comPort)
server:RunServer()
