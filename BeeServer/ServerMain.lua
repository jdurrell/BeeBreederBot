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


function PingHandler(addr, data)
    -- Ping Request: Just respond with our own ping.
    local payload = {transactionId = data.transactionId}
    local sent = Modem.send(addr, COM_PORT, MessageCode.PingResponse, payload)
    if not sent then
        print("Failed to send PingResponse.")
    end
end

---@param data {target: string}
function BreedInfoHandler(addr, data)
    local payload = {}
    payload.breedInfo = CalculateBreedInfo(data.target, BeeGraph)
    local sent = Modem.send(addr, COM_PORT, MessageCode.BreedInfoResponse, payload)
    if not sent then
        print("Failed to send TargetResponse.")
    end
end

function PathHandler(addr, data)
    -- Path Request. Send the breed path to the robot.
    local payload = BreedPath
    local sent = Modem.send(addr, COM_PORT, MessageCode.PathResponse, payload)
    if not sent then
        print("Failed to send PathResponse")
    end
end

function SpeciesFoundHandler(addr, data)

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

-- Obtain the full bee graph from the attached adapter and apiary/bee house.
BeeGraph = ImportBeeGraph(Component.apiary)

-- Read our local logfile to figure out which species we already have (and where they're stored).
-- We will synchronize this with the robot later on.
-- TODO: Actually do this.
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
