-- This program is the main executable for the bee-graph server.
-- The bee-graph server analyzes the bee breeding data from the apiary adapter
-- and communicates with the breeder robot to give it instructions on which bees to breed.

function PingHandler(addr, data)
    -- Ping Request: Just respond with our own ping.
    local sent = Modem.send(addr, COM_PORT, MessageCode.PingResponse)
    if not sent then
        print("Failed to send PingResponse.")
    end
end

function TargetHandler(addr, data)
    -- Target Request. Send the robot its next target.
    -- TODO: *Technically* this request doesn't necessarily have to come after the SpeciesFoundRequest for the previous species
    --       because messages can arrive out of order over a network (or get lost). However, it seems unlikely that OpenComputers
    --       replicates this reality of distributed systems, so we'll ignore it for now.
    for i, v in ipairs(BreedPath) do
        if FoundSpecies[v] ~= nil then
            -- We have another target in the tree to send: Calculate odds and send them over.
            local payload = {}
            payload.target = v
            payload.breedInfo = CalculateBreedInfo(v, BeeGraph)
            local sent = Modem.send(addr, COM_PORT, MessageCode.TargetResponse, payload)
            if not sent then
                print("Failed to send TargetResponse.")
            end
            return
        end
    end

    -- We have bred everything in BreedPath. Nothing else to do.
    local sent = Modem.send(addr, COM_PORT, MessageCode.TargetResponse)
    if not sent then
        print("Failed to send TargetResponse")
    end
end

function SpeciesFoundHandler(addr, data)

end

function PollForMessageAndHandle()
    local event, _, addr, _, _, code, data = Event.pull(2.0, "modem_message")
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
Component = require("component")
Modem = require("modem")


-- Obtain the full bee graph from the attached adapter and apiary/bee house.
BeeGraph = ImportBeeGraph(Component.apiary)

-- Read our local logfile to figure out which species we already have (and where they're stored).
-- We will synchronize this with the robot later on.
FoundSpecies = {}

HandlerTable = {}
HandlerTable[MessageCode.PingRequest] = PingHandler
HandlerTable[MessageCode.SpeciesFoundRequest] = SpeciesFoundHandler
HandlerTable[MessageCode.TargetRequest] = TargetHandler

---------------------
-- Main operation loop.
while true do
    print("Enter your target species to breed:\n")
    local input = io.read()
    if BeeGraph[input] == nil then
        print("Error: did not recognize species.\n")
        goto continue
    end

    BreedPath = QueryBreedingPath(BeeGraph, FoundSpecies, input)
    print("Breeding given target species. Full breeding order:\n")
    for _ ,v in ipairs(BreedPath) do
        print(v)
    end

    ::continue::
end
