-- This program is the main executable for the bee-graph server.
-- The bee-graph server analyzes the bee breeding data from the apiary adapter
-- and communicates with the breeder robot to give it instructions on which bees to breed.

---------------------
-- Global Variables.

-- Load Dependencies.
Component = require("component")
Modem = require("modem")
-- TODO: Should the below be 'require()' statements instead?
dofile("/home/BeeBreederBot/Shared.lua")
dofile("/home/BeeBreederBot/MutationMath.lua")
dofile("/home/BeeBreederBot/GraphParse.lua")
dofile("/home/BeeBreederBot/GraphQuery.lua")

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
---@param data {species: string, location: Point}
function SpeciesFoundHandler(addr, data)
    -- Record the species that was found by the robot to our own disk.
    LogSpeciesFinishedToDisk(LOG_FILE, data.species, data.location)

    -- TODO: Do we need to ACK this?
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
BeeGraph = ImportBeeGraph(Component.tile_for_apiculture_0_name)

-- Read our local logfile to figure out which species we already have (and where they're stored).
-- We will synchronize this with the robot later on.
-- TODO: Actually do this.
-- TODO: Also need to distinguish between the robot having an update vs. the server having an update.
--       This could be done via timestamps, except the only time the server would have an update is when
--       the player updates the list manually, and they likely won't want to deal with timestamps. We
--       could either have them delete the timestamp (and then detect that and generate it later) or
--       dupe the file into a human-editable version (and then overwrite the online version at startup).
FoundSpecies = {}

HandlerTable = {
    [MessageCode.PingRequest] = PingHandler,
    [MessageCode.SpeciesFoundRequest] = SpeciesFoundHandler,
    [MessageCode.BreedInfoRequest] = BreedInfoHandler
}


---------------------
-- Main operation loop.
print("Enter your target species to breed:\n")
local input = nil
while BeeGraph[input] == nil do
    input = io.read()
    print("Error: did not recognize species.\n")
end

BreedPath = QueryBreedingPath(BeeGraph, FoundSpecies, input)
print("Breeding " .. input .. ". Full breeding order:\n")
for _ ,v in ipairs(BreedPath) do
    print(v)
end

while true do
    PollForMessageAndHandle()
    -- TODO: Handle cancelling and selecting a different species without restarting.
end
