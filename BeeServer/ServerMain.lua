-- Load system dependencies.
local component = require("component")
local event = require("event")
local serial = require("serialization")
local term = require("term")

local BeeServer = require("BeeServer.BeeServer")
local ConfigService = require("Shared.Config")

local config = {port = 34000, logFilepath = "./species.log", botAddr = ""}
if not ConfigService.LoadConfig("./server.cfg", config, false) then
    Print("Failed to read configuration.")
    return
end

if config.botAddr == "" then
    Print("Error: required parameter 'botAddr' not specified.")
    return
end

Print("Starting BeeServer with configuration: ")
ConfigService.PrintConfig(config)
Sleep(1)

---@cast component Component
---@cast event Event
---@cast serial Serialization
---@cast term Term
local server = BeeServer:Create(component, event, serial, term, config)
server:RunServer()
