-- This program is the main executable for the bee-graph server.
-- The bee-graph server analyzes the bee breeding data from the apiary adapter
-- and communicates with the breeder robot to give it instructions on which bees to breed.

-- Import BeeBreederBot libraries.
require("Shared.Shared")
local CommLayer = require("Shared.CommLayer")
local GraphParse = require("BeeServer.GraphParse")
local GraphQuery = require("BeeServer.GraphQuery")
local Logger = require("Shared.Logger")
local MutationMath = require("BeeServer.MutationMath")

---@class BeeServer
---@field component any
---@field event any
---@field term any
---@field beeGraph SpeciesGraph
---@field breedPath BreedPathNode[]
---@field comm CommLayer
---@field foundSpecies table<string, StorageNode>
---@field messageHandlerTable table<integer, function>
---@field leafSpeciesList string[]
---@field logFilepath string
---@field terminalHandlerTable table<string, function>
local BeeServer = {}

---@param addr string
---@param data PingRequestPayload
function BeeServer:PingHandler(addr, data)
    -- Just respond with our own ping, echoing back the transaction id.
    local payload = {transactionId=data.transactionId}
    self.comm:SendMessage(addr, CommLayer.MessageCode.PingResponse, payload)
end

---@param addr string
---@param data BreedInfoRequestPayload
function BeeServer:BreedInfoHandler(addr, data)
    -- Calculate mutation chances and send them back to the robot.
    local payload = {breedInfo=MutationMath.CalculateBreedInfo(data.target, self.beeGraph)}
    self.comm:SendMessage(addr, CommLayer.MessageCode.BreedInfoResponse, payload)
end

---@param addr string
---@param data PathRequestPayload
function BeeServer:PathHandler(addr, data)
    -- Send the calculated breed path to the robot.
    self.comm:SendMessage(addr, CommLayer.MessageCode.PathResponse, self.breedPath)
end

---@param addr string
---@param data SpeciesFoundRequestPayload
function BeeServer:SpeciesFoundHandler(addr, data)
    -- Record the species that was found by the robot to our own disk.
    if (self.foundSpecies[data.species] == nil) or (self.foundSpecies[data.species].timestamp < data.node.timestamp) then
        self.foundSpecies[data.species] = data.node
        table.insert(self.leafSpeciesList, data.species)
        Logger.LogSpeciesToDisk(self.logFilepath, data.species, data.node.loc, data.node.timestamp)
    end
end

---@param addr string
---@param data LogStreamRequestPayload
function BeeServer:LogStreamHandler(addr, data)
    for species, node in pairs(self.foundSpecies) do
        local payload = {species=species, node=node}
        self.comm:SendMessage(addr, CommLayer.MessageCode.LogStreamResponse, payload)

        -- Give the robot time to actually process these instead of just blowing up its event queue.
        Sleep(0.2)
    end

    -- Send an empty response to indicate that the stream has ended.
    self.comm:SendMessage(addr, CommLayer.MessageCode.LogStreamResponse, {})
end

---@param timeout number
function BeeServer:PollForMessageAndHandle(timeout)
    local response, addr = self.comm:GetIncoming(timeout)
    if response ~= nil then
        if self.messageHandlerTable[response.code] == nil then
            Print("Received unidentified code " .. tostring(response.code))
        else
            self.messageHandlerTable[response.code](self, UnwrapNull(addr), response.payload)
        end
    end
end

---@param argv string[]
function BeeServer:ShutdownCommandHandler(argv)
    self:Shutdown(0)
end

---@param argv string[]
function BeeServer:BreedCommandHandler(argv)
    local species = argv[2]
    if species == nil then
        Print("Error: expected a species name.")
        return
    end

    if self.beeGraph[species] == nil then
        Print("Error: could not find species '" .. species .. "' in breeding graph.")
        return
    end

    local path = GraphQuery.QueryBreedingPath(self.beeGraph, self.leafSpeciesList, species)
    if path == nil then
        Print("Error: Could not find breeding path for species '" .. species .. "'.")
        return
    end

    -- We computed a valid path for this species. Save it to the current breed path and print it out for the user.
    self.breedPath = UnwrapNull(path)
    Print("Breeding " .. species .. " bees. Full breeding order:")
    for _, v in ipairs(self.breedPath) do
        Print(v)
    end
end

---@param timeout number
function BeeServer:PollForTerminalInputAndHandle(timeout)
    local event, command = self.term.pull(timeout)
    if event == nil then
        return
    end

    -- Separate command line options.
    -- TODO provide a way for a single argument to have a space in it.
    local argv = {}
    for arg in string.gmatch(command, "[%w]+") do
        table.insert(argv, arg)
    end

    -- We could theoretically get no commands if the user gave us a blank line.
    if #argv == 0 then
        return
    end

    if self.terminalHandlerTable[argv[1]] == nil then
        Print("Unrecognized command.")
    else
        self.terminalHandlerTable[argv[1]](self, argv)
    end
end

-- Creates a BeeServer and does initial setup (importing the bee graph, etc.).
-- Requires system libraries as an input.
---@param componentLib any
---@param eventLib any
---@param serialLib any
---@param termLib any
---@param logFilepath string
---@param port integer
---@return BeeServer
function BeeServer:Create(componentLib, eventLib, serialLib, termLib, logFilepath, port)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    -- Store away system libraries.
    -- Do this in the constructor instead of statically so that we can inject our
    -- own system libraries for testing.
    obj.component = componentLib
    obj.event = eventLib
    obj.term = termLib
    obj.logFilepath = logFilepath

    obj.comm = CommLayer:Open(componentLib.modem, serialLib, port)
    if obj.comm == nil then
        Print("Failed to open communication layer.")

        -- TODO: Verify whether it is valid to call obj:Shutdown() here.
        --       In theory, it should be fine since we already set the metatable,
        --       but that should be verified.
        obj:Shutdown(1)
    end

    -- Register request handlers.
    obj.messageHandlerTable = {
        [CommLayer.MessageCode.PingRequest] = BeeServer.PingHandler,
        [CommLayer.MessageCode.PathRequest] = BeeServer.PathHandler,
        [CommLayer.MessageCode.SpeciesFoundRequest] = BeeServer.SpeciesFoundHandler,
        [CommLayer.MessageCode.BreedInfoRequest] = BeeServer.BreedInfoHandler,
        [CommLayer.MessageCode.LogStreamRequest] = BeeServer.LogStreamHandler
    }

    -- Register command line handlers
    obj.terminalHandlerTable = {
        ["shutdown"] = BeeServer.ShutdownCommandHandler,
        ["breed"] = BeeServer.BreedCommandHandler
    }

    -- Obtain the full bee graph from the attached adapter and apiary.
    -- TODO: This is set up to be attached to an apiary, but this isn't technically required.
    --       We need more generous matching here to determine the correct component.
    Print("Importing bee graph.")
    if componentLib.tile_for_apiculture_0_name == nil then
        Print("Couldn't find attached apiculture tile in the component library.")
        obj:Shutdown()
    end
    obj.beeGraph = GraphParse.ImportBeeGraph(componentLib.tile_for_apiculture_0_name)

    -- Read our local logfile to figure out which species we already have (and where they're stored).
    -- We will synchronize this with the robot later on via LogStreamHandler when it boots up.
    obj.foundSpecies = Logger.ReadSpeciesLogFromDisk(logFilepath)
    if obj.foundSpecies == nil then
        Print("Got an error while reading logfile.")
        obj:Shutdown()
    end
    obj.leafSpeciesList = {}
    for spec, _ in pairs(obj.foundSpecies) do
        table.insert(obj.leafSpeciesList, spec)
    end

    obj.breedPath = nil

    return obj
end

-- Runs the main BeeServer operation loop.
function BeeServer:RunServer()
    while true do
        self:PollForTerminalInputAndHandle(0.2)
        self:PollForMessageAndHandle(0.2)
    end
end

-- Shuts down the server.
---@param code integer
function BeeServer:Shutdown(code)
    if self.comm ~= nil then
        self.comm:Close()
    end

    ExitProgram(code)
end

return BeeServer