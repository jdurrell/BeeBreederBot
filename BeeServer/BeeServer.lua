-- This program is the main executable for the bee-graph server.
-- The bee-graph server analyzes the bee breeding data from the apiary adapter
-- and communicates with the breeder robot to give it instructions on which bees to breed.

-- Import BeeBreederBot libraries.
require("Shared.Shared")
local GraphParse = require("BeeServer.GraphParse")
local GraphQuery = require("BeeServer.GraphQuery")
local MutationMath = require("BeeServer.MutationMath")

---@class BeeServer
---@field component any
---@field event any
---@field serial any
---@field beeGraph SpeciesGraph
---@field breedPath BreedPathNode[]
---@field foundSpecies table<string, StorageNode>
---@field handlerTable table<integer, function>
---@field leafSpeciesList string[]
---@field logFilepath string
local BeeServer = {}

---@param addr string
---@param data PingRequestPayload
function BeeServer:PingHandler(addr, data)
    -- Just respond with our own ping, echoing back the transaction id.
    local payload = {transactionId=data.transactionId}
    SendMessage(addr, MessageCode.PingResponse, payload)
end

---@param addr string
---@param data BreedInfoRequestPayload
function BeeServer:BreedInfoHandler(addr, data)
    -- Calculate mutation chances and send them back to the robot.
    local payload = {breedInfo=MutationMath.CalculateBreedInfo(data.target, self.beeGraph)}
    SendMessage(addr, MessageCode.BreedInfoResponse, payload)
end

---@param addr string
---@param data PathRequestPayload
function BeeServer:PathHandler(addr, data)
    -- Send the calculated breed path to the robot.
    SendMessage(addr, MessageCode.PathResponse, self.breedPath)
end

---@param addr string
---@param data SpeciesFoundRequestPayload
function BeeServer:SpeciesFoundHandler(addr, data)
    -- Record the species that was found by the robot to our own disk.
    if (self.foundSpecies[data.species] == nil) or (self.foundSpecies[data.species].timestamp < data.node.timestamp) then
        self.foundSpecies[data.species] = data.node
        table.insert(self.leafSpeciesList, data.species)
        LogSpeciesToDisk(LOG_FILE, data.species, data.node.loc, data.node.timestamp)
    end
end

---@param addr string
---@param data LogStreamRequestPayload
function BeeServer:LogStreamHandler(addr, data)
    -- We check this for nil already.
    for species, node in pairs(UnwrapNull(self.foundSpecies)) do
        local payload = {species=species, node=node}
        SendMessage(addr, MessageCode.LogStreamResponse, payload)

        -- Give the robot time to actually process these instead of just blowing up its event queue.
        Sleep(0.2)
    end

    -- Send an empty response to indicate that the stream has ended.
    SendMessage(addr, MessageCode.LogStreamResponse, nil)
end

function BeeServer:PollForMessageAndHandle()
    local event, _, addr, _, _, response = self.event.pull(2.0, MODEM_EVENT_NAME)
    if event ~= nil then
        response = UnserializeMessage(response)

        if self.handlerTable[response.code] == nil then
            Print("Received unidentified code " .. tostring(response.code))
        else
            self.handlerTable[response.code](self, addr, response.payload)
        end
    end
end

-- Creates a BeeServer and does initial setup (importing the bee graph, etc.).
-- Requires system libraries as an input.
---@param componentLib any
---@param eventLib any
---@param serialLib any
---@param logFilepath string
---@return BeeServer
function BeeServer:Create(componentLib, eventLib, serialLib, logFilepath)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    -- Store away system libraries.
    -- Do this in the constructor instead of statically so that we can inject our
    -- own system libraries for testing.
    obj.component = componentLib
    obj.event = eventLib
    obj.serial = serialLib
    obj.logFilepath = logFilepath

    -- Set up request handlers.
    obj.handlerTable = {
        [MessageCode.PingRequest] = BeeServer.PingHandler,
        [MessageCode.SpeciesFoundRequest] = BeeServer.SpeciesFoundHandler,
        [MessageCode.BreedInfoRequest] = BeeServer.BreedInfoHandler,
        [MessageCode.LogStreamRequest] = BeeServer.LogStreamHandler
    }

    -- Obtain the full bee graph from the attached adapter and apiary.
    -- TODO: This is set up to be attached to an apiary, but this isn't technically required.
    --       We need more generous matching here to determine the correct component.
    Print("Importing bee graph.")
    obj.beeGraph = GraphParse.ImportBeeGraph(componentLib.tile_for_apiculture_0_name)

    -- Read our local logfile to figure out which species we already have (and where they're stored).
    -- We will synchronize this with the robot later on via LogStreamHandler when it boots up.
    obj.foundSpecies = ReadSpeciesLogFromDisk(logFilepath)
    if obj.foundSpecies == nil then
        Print("Failed to get found species from logfile.")
        Shutdown()
    end
    obj.foundSpecies = UnwrapNull(obj.foundSpecies)
    obj.leafSpeciesList = {}
    for spec, _ in pairs(obj.foundSpecies) do
        table.insert(obj.leafSpeciesList, spec)
    end

    obj.breedPath = nil

    return obj
end

-- Runs the main BeeServer operation loop.
function BeeServer:RunServer()
    Print("Enter your target species to breed:")
    local input = nil
    while self.breedPath == nil do
        ::continue::
        input = io.read()

        if (self.beeGraph[input] == nil) then
            Print("Error: did not recognize species.")
            goto continue
        end

        self.breedPath = UnwrapNull(GraphQuery.QueryBreedingPath(self.beeGraph, self.leafSpeciesList, input))
        if self.breedPath == nil then
            Print("Error: Could not find breeding path for species " .. tostring(input))
            goto continue
        end
    end

    Print("Breeding " .. input .. " bees. Full breeding order:")
    for _ , v in ipairs(BreedPath) do
        Print(v)
    end

    Print("Graph server is online to answer queries.")
    while true do
        self:PollForMessageAndHandle()
        -- TODO: Handle cancelling and selecting a different species without restarting.
    end
end

return BeeServer