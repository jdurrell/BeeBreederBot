-- This program is the main executable for the bee-graph server.
-- The bee-graph server analyzes the bee breeding data from the apiary adapter
-- and communicates with the breeder robot to give it instructions on which bees to breed.

---------------------
-- Global Variables.

-- Load Dependencies.
Component = require("component")
Event = require("event")
Serial = require("serialization")
Modem = Component.modem

require("Shared.Shared")
MutationMath = require("BeeServer.MutationMath")
GraphParse = require("BeeServer.GraphParse")
GraphQuery = require("BeeServer.GraphQuery")
Sleep(0.5)

LOG_FILE_ONLINE = "/home/BeeBreederBot/DroneLocations.log"


---@param addr string
---@param data PingRequestPayload
function PingHandler(addr, data)
    -- Just respond with our own ping, echoing back the transaction id.
    local payload = {transactionId=data.transactionId}
    SendMessage(addr, MessageCode.PingResponse, payload)
end

---@param addr string
---@param data BreedInfoRequestPayload
function BreedInfoHandler(addr, data)
    -- Calculate mutation chances and send them back to the robot.
    local payload = {breedInfo=MutationMath.CalculateBreedInfo(data.target, BeeGraph)}
    SendMessage(addr, MessageCode.BreedInfoResponse, payload)
end

---@param addr string
---@param data PathRequestPayload
function PathHandler(addr, data)
    -- Send the calculated breed path to the robot.
    SendMessage(addr, MessageCode.PathResponse, BreedPath)
end

---@param addr string
---@param data SpeciesFoundRequestPayload
function SpeciesFoundHandler(addr, data)
    -- Record the species that was found by the robot to our own disk.
    if (FoundSpecies[data.species] == nil) or (FoundSpecies[data.species].timestamp < data.node.timestamp) then
        FoundSpecies[data.species] = data.node
        table.insert(LeafSpeciesList, data.species)
        LogSpeciesToDisk(LOG_FILE, data.species, data.node.loc, data.node.timestamp)
    end
end

---@param addr string
---@param data LogStreamRequestPayload
function LogStreamHandler(addr, data)
    -- We check this for nil already.
    for species, node in pairs(UnwrapNull(FoundSpecies)) do
        local payload = {species=species, node=node}
        SendMessage(addr, MessageCode.LogStreamResponse, payload)

        -- Give the robot time to actually process these instead of just blowing up its event queue.
        Sleep(0.2)
    end

    -- Send an empty response to indicate that the stream has ended.
    SendMessage(addr, MessageCode.LogStreamResponse, nil)
end

function PollForMessageAndHandle()
    local event, _, addr, _, _, response = Event.pull(2.0, MODEM_EVENT_NAME)
    if event ~= nil then
        response = UnserializeMessage(response)

        if HandlerTable[response.code] == nil then
            Print("Received unidentified code " .. tostring(response.code))
        else
            HandlerTable[response.code](addr, response.payload)
        end
    end
end


---------------------
-- Initial Setup.

-- Obtain the full bee graph from the attached adapter and apiary.
-- TODO: This is set up to be attached to an apiary, but this isn't technically required.
--       We need more generous matching here to determine the correct component.
Print("Importing bee graph.")
BeeGraph = GraphParse.ImportBeeGraph(Component.tile_for_apiculture_0_name)

-- Read our local logfile to figure out which species we already have (and where they're stored).
-- We will synchronize this with the robot later on via LogStreamHandler when it boots up.
FoundSpecies = ReadSpeciesLogFromDisk(LOG_FILE_ONLINE)
if FoundSpecies == nil then
    Print("Failed to get found species from logfile.")
    Shutdown()
end
FoundSpecies = UnwrapNull(FoundSpecies)
LeafSpeciesList = {}
for spec, _ in pairs(FoundSpecies) do
    table.insert(LeafSpeciesList, spec)
end

HandlerTable = {
    [MessageCode.PingRequest] = PingHandler,
    [MessageCode.SpeciesFoundRequest] = SpeciesFoundHandler,
    [MessageCode.BreedInfoRequest] = BreedInfoHandler,
    [MessageCode.LogStreamRequest] = LogStreamHandler
}


---------------------
-- Main operation loop.
Print("Enter your target species to breed:")
local input = nil
while BreedPath == nil do
    ::continue::
    input = io.read()

    if (BeeGraph[input] == nil) then
        Print("Error: did not recognize species.")
        goto continue
    end

    BreedPath = GraphQuery.QueryBreedingPath(BeeGraph, LeafSpeciesList, input)
    if BreedPath == nil then
        Print("Error: Could not find breeding path for species " .. tostring(input))
        goto continue
    end
end

Print("Breeding " .. input .. " bees. Full breeding order:")
for _ ,v in ipairs(BreedPath) do
    Print(v)
end

Print("Graph server is online to answer queries.")
while true do
    PollForMessageAndHandle()
    -- TODO: Handle cancelling and selecting a different species without restarting.
end
