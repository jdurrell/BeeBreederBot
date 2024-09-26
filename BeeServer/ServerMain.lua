-- This program is the main executable for the bee-graph server.
-- The bee-graph server analyzes the bee breeding data from the apiary adapter
-- and communicates with the breeder robot to give it instructions on which bees to breed.

---------------------
-- Global Variables.

-- Load Dependencies.
Component = require("component")
Event = require("event")
Modem = Component.modem
-- TODO: Should the below be 'require()' statements instead?
dofile("/home/BeeBreederBot/Shared.lua")
dofile("/home/BeeBreederBot/MutationMath.lua")
dofile("/home/BeeBreederBot/GraphParse.lua")
dofile("/home/BeeBreederBot/GraphQuery.lua")
Sleep(0.5)

LOG_FILE_ONLINE = "/home/BeeBreederBot/DroneLocations.log"

---@param addr string
---@param data {transactionId: integer}
function PingHandler(addr, data)
    -- Just respond with our own ping.
    local payload = {transactionId = data.transactionId}
    local sent = Modem.send(addr, COM_PORT, MessageCode.PingResponse, payload)
    if not sent then
        print("Failed to send PingResponse.")
    end
end

---@param addr string
---@param data {target: string}
function BreedInfoHandler(addr, data)
    -- Calculate mutation chances and send them back to the robot.
    local payload = {}
    payload.breedInfo = CalculateBreedInfo(data.target, BeeGraph)
    local sent = Modem.send(addr, COM_PORT, MessageCode.BreedInfoResponse, payload)
    if not sent then
        print("Failed to send TargetResponse.")
    end
end

---@param addr string
---@param data nil
function PathHandler(addr, data)
    -- Send the calculated breed path to the robot.
    local payload = BreedPath
    local sent = Modem.send(addr, COM_PORT, MessageCode.PathResponse, payload)
    if not sent then
        print("Failed to send PathResponse")
    end
end

---@param addr string
---@param data {species: string, node: StorageNode}
function SpeciesFoundHandler(addr, data)
    -- Record the species that was found by the robot to our own disk.
    if (FoundSpecies[data.species] == nil) or (FoundSpecies[data.species].timestamp < data.node.timestamp) then
        FoundSpecies[data.species] = data.node
        LogSpeciesToDisk(LOG_FILE, data.species, data.node.loc, data.node.timestamp)
    end
end

---@param addr string
---@param data nil
function LogStreamHandler(addr, data)
    --- Disabled warning because we check this for nil already.
    ---@diagnostic disable-next-line: param-type-mismatch
    for species, node in pairs(FoundSpecies) do
        local payload = {
            species=species,
            node=node
        }

        local sent = Modem.send(addr, COM_PORT, MessageCode.LogStreamResponse, payload)
        if not sent then
            print("Failed to send LogStreamResponse.")
        end

        -- Give the robot time to actually process these instead of just blowing up its event queue.
        Sleep(0.2)
    end

    -- Send an empty response to indicate that the stream has ended.
    local sent = Modem.send(addr, COM_PORT, MessageCode.LogStreamResponse, nil)
    if not sent then
        print("Failed to send LogStreamResponse.")
    end
end

function PollForMessageAndHandle()
    local event, _, addr, _, _, code, data = Event.pull(2.0, MODEM_EVENT_NAME)
    if event ~= nil then
        if HandlerTable[code] == nil then
            print("Received unidentified code " .. tostring(code))
        else
            HandlerTable[code](addr, data)
        end
    end
end


---------------------
-- Initial Setup.

-- Obtain the full bee graph from the attached adapter and apiary.
-- TODO: This is set up to be attached to an apiary, but this isn't technically required.
--       We need more generous matching here to determine the correct component.
print("Importing bee graph.")
BeeGraph = ImportBeeGraph(Component.tile_for_apiculture_0_name)

-- Read our local logfile to figure out which species we already have (and where they're stored).
-- We will synchronize this with the robot later on via LogStreamHandler when it boots up.
FoundSpecies = ReadSpeciesLogFromDisk(LOG_FILE_ONLINE)
if FoundSpecies == nil then
    print("Failed to get found species from logfile.")
    os.exit(1, true)
end

HandlerTable = {
    [MessageCode.PingRequest] = PingHandler,
    [MessageCode.SpeciesFoundRequest] = SpeciesFoundHandler,
    [MessageCode.BreedInfoRequest] = BreedInfoHandler,
    [MessageCode.LogStreamRequest] = LogStreamHandler
}


---------------------
-- Main operation loop.
print("Enter your target species to breed:")
local input = nil
while BreedPath == nil do
    ::continue::
    input = io.read()

    if (BeeGraph[input] == nil) then
        print("Error: did not recognize species.")
        goto continue
    end

    BreedPath = QueryBreedingPath(BeeGraph, FoundSpecies, input)
    if BreedPath == nil then
        print("Error: Could not find breeding path for species " .. tostring(input))
        goto continue
    end
end

print("Breeding " .. input .. " bees. Full breeding order:")
for _ ,v in ipairs(BreedPath) do
    print(v)
end

print("Graph server is online to answer queries.")
while true do
    PollForMessageAndHandle()
    -- TODO: Handle cancelling and selecting a different species without restarting.
end
