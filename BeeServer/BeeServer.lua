-- This program is the main executable for the bee-graph server.
-- The bee-graph server analyzes the bee breeding data from the apiary adapter
-- and communicates with the breeder robot to give it instructions on which bees to breed.

-- Import BeeBreederBot libraries.
require("Shared.Shared")
local CommLayer = require("Shared.CommLayer")
local GraphParse = require("BeeServer.GraphParse")
local GraphQuery = require("BeeServer.GraphQuery")
local Logger = require("BeeServer.Logger")
local MutationMath = require("BeeServer.MutationMath")
local TraitInfo = require("BeeServer.SpeciesDominance")

---@class BeeServer
---@field event Event
---@field term Term
---@field beeGraph SpeciesGraph
---@field botAddr string
---@field comm CommLayer
---@field conditionsPending boolean
---@field messageHandlerTable table<integer, function>
---@field leafSpeciesList string[]
---@field logFilepath string
---@field terminalHandlerTable table<string, function>
local BeeServer = {}


---------------------
--- Modem handling:

---@param addr string
---@param data BreedInfoRequestPayload
function BeeServer:BreedInfoHandler(addr, data)
    if (data == nil) or (data.parent1 == nil) or (data.parent2 == nil) or (data.target == nil) then
        return
    end

    local targetMutChance, nonTargetMutChance = MutationMath.CalculateBreedInfo(data.parent1, data.parent2, data.target, self.beeGraph)
    local payload = {targetMutChance=targetMutChance, nonTargetMutChance=nonTargetMutChance}
    self.comm:SendMessage(addr, CommLayer.MessageCode.BreedInfoResponse, payload)
end

---@param addr string
---@param data PingRequestPayload
function BeeServer:PingHandler(addr, data)
    -- TODO: If we ever want to support multiple bots, then we will need each bot to have a uid so that
    --       the server can keep track of which is which.
    self.botAddr = addr

    -- Just respond with our own ping, echoing back the transaction id.
    local payload = {transactionId = data.transactionId}
    self.comm:SendMessage(addr, CommLayer.MessageCode.PingResponse, payload)
end

---@param addr string
---@param data PrintErrorPayload
function BeeServer:PrintErrorHandler(addr, data)
    if data.errorMessage == nil then
        Print("Robot error: unknown.")
    else
        Print(string.format("Robot error: %s", data.errorMessage))
    end
end

---@param addr string
---@param data PromptConditionsPayload
function BeeServer:PromptConditionsHandler(addr, data)
    if self.conditionsPending or (data == nil) or (data.parent1 == nil) or (data.parent2 == nil) or (data.target == nil) or (self.beeGraph[data.target] == nil) then
        return
    end

    local conditions = nil
    for _, mut in ipairs(self.beeGraph[data.target].parentMutations) do
        if (
            ((mut.parents[1] == data.parent1) and (mut.parents[2] == data.parent2)) or
            ((mut.parents[1] == data.parent2) and (mut.parents[2] == data.parent1))
        ) then
            conditions = {}
            for _, condition  in ipairs(mut.specialConditions) do
                local isAFoundation = condition:find("foundation") == nil
                if (not isAFoundation) or (data.promptFoundation) then
                    table.insert(conditions, condition)
                end
            end
        end
    end

    if (conditions == nil) or (#conditions > 0) then
        -- If there are no conditions, then immediately tell the robot it can continue.
        Print(string.format("Robot is breeding '%s' from '%s' and '%s'. No conditions are required.", data.target, data.parent1, data.parent2))
        self.comm:SendMessage(addr, CommLayer.MessageCode.PromptConditionsResponse)
    else
        self.conditionsPending = true
        Print(string.format("Robot is breeding '%s' from '%s' and '%s'. The following conditions are required:", data.target, data.parent1, data.parent2))
        for _, condition in ipairs(conditions) do
            Print(condition)
        end
        Print("Once the conditions have been met, enter the command 'continue' to tell the robot to continue.")
    end
end

---@param addr string
---@param data SpeciesFoundRequestPayload
function BeeServer:SpeciesFoundHandler(addr, data)
    if data.species == nil then
        return
    end

    -- Update the species that was found by the robot in our internal state and on disk.
    if not ArrayContains(self.leafSpeciesList, data.species) then
        table.insert(self.leafSpeciesList, data.species)
        Logger.LogSpeciesToDisk(self.logFilepath, data.species)
    end

    -- Respond back to the robot acknowledging that we have recorded the new find.
    self.comm:SendMessage(addr, CommLayer.MessageCode.SpeciesFoundResponse)
end

---@param addr string
---@param data TraitBreedPathRequestPayload
function BeeServer:TraitBreedPathHandler(addr, data)
    if (data.trait == nil) or (data.value == nil) then
        Print("Got unexpected TraitBreedPathRequestPayload format.")
        return
    end

    Print(string.format("Trait '%s: %s' is not found in the bee storage.", data.trait, tostring(data.value)))
    local path = nil
    while path == nil do
        -- TODO: Figure this out from a list of default chromosomes, and don't force the player to figure this out manually.
        --       There may be some portability and memory to that, though.
        Print("Enter a species to breed with the desired trait mutation: ")
        local species = self.term.pull(40000)
        if (species == nil) or self.beeGraph[species] == nil then
            goto continue
        elseif species == "cancel" then
            -- Give the user a way to break out of this, if they need to.
            return
        end

        path = self:GetBreedPath(species, true)
        if path == nil then
            Print(string.format("No path found for species '%s'.", species))
        end
        ::continue::
    end

    self.comm:SendMessage(addr, CommLayer.MessageCode.TraitBreedPathRequest, path)
end

---@param addr string
---@param data TraitInfoRequestPayload
function BeeServer:TraitInfoHandler(addr, data)
    local payload = {dominant = TraitInfo[data.species]}
    self.comm:SendMessage(addr, CommLayer.MessageCode.TraitInfoResponse, payload)
end

---@param timeout number
function BeeServer:PollForMessageAndHandle(timeout)
    local response, addr = self.comm:GetIncoming(timeout, nil)
    if response ~= nil then
        if self.messageHandlerTable[response.code] == nil then
            Print("Received unidentified code " .. tostring(response.code))
        else
            self.messageHandlerTable[response.code](self, UnwrapNull(addr), response.payload)
        end
    end
end


---------------------
--- Terminal handling:

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

    if self.botAddr == nil then
        Print("Error: No comms to bot.")
        return
    end

    for _, leaf in ipairs(self.leafSpeciesList) do
        if leaf == species then
            -- If we already have the species, then send this as a replicate command.
            Print("Replicating " .. species .. " from stored drones.")
            local payload = {species = species}
            self.comm:SendMessage(self.botAddr, CommLayer.MessageCode.ReplicateCommand, payload)
            return
        end
    end

    local path = self:GetBreedPath(species, false)
    if path == nil then
        Print("Error: Could not find breeding path for species '" .. species .. "'.")
        return
    end

    self.comm:SendMessage(self.botAddr, CommLayer.MessageCode.BreedCommand, path)
end

---@param argv string[]
function BeeServer:ContinueCommandHandler(argv)
    self.conditionsPending = false
    self.comm:SendMessage(self.botAddr, CommLayer.MessageCode.PromptConditionsResponse)
end

---@param argv string[]
function BeeServer:ShutdownCommandHandler(argv)
    -- This may or may not cause the robot to actually shut down, but it will prevent it from continuing to start apiaries.
    -- When using this command, expect to have to reset the system manually.
    if self.botAddr ~= nil then
        self.comm:SendMessage(self.botAddr, CommLayer.MessageCode.CancelCommand)
    end
    self:Shutdown(0)
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
    for arg in string.gmatch(UnwrapNull(command), "[^%s]+") do
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


---------------------
--- Other instance functions.

---@param species string
---@param forceRebreed boolean
---@return BreedPathNode[] | nil
function BeeServer:GetBreedPath(species, forceRebreed)
    local path = GraphQuery.QueryBreedingPath(self.beeGraph, self.leafSpeciesList, species, forceRebreed)
    if path == nil then
        Print("Error: Could not find breeding path for species '" .. species .. "'.")
        return nil
    end

    -- We computed a valid path for this species. Send it to the robot and print it out for the user.
    Print("Will breed " .. species .. " bees. Full breeding order:")
    local printstr = ""
    for _, node in ipairs(path) do
        printstr = string.format("%s, %s", printstr, node.target)
    end
    Print(printstr)

    Sleep(0.5)
    Print("Required foundation blocks:")
    printstr = ""
    for _, node in ipairs(path) do
        ---@type string[] | nil
        local conditions = nil
        for _, mut in ipairs(self.beeGraph[node.target].parentMutations) do
            if (
                ((mut.parents[1] == node.parent1) and (mut.parents[2] == node.parent2)) or
                ((mut.parents[1] == node.parent2) and (mut.parents[2] == node.parent1))
            ) then
                conditions = mut.specialConditions
                break
            end
        end
        if (conditions ~= nil) and (#conditions > 0) then
            for _, condition in ipairs(conditions) do
                local foundation = condition:find(" as a foundation")
                if foundation ~= nil then
                    local foundationStr = condition:gsub("Requires ", ""):gsub(" as a foundation.", "")
                    printstr = string.format("%s, %s", printstr, foundationStr)
                    node.foundation = foundationStr
                end
            end
        end
    end
    Print(printstr)

    return path
end

-- Shuts down the server.
---@param code integer
function BeeServer:Shutdown(code)
    if self.comm ~= nil then
        self.comm:Close()
    end

    ExitProgram(code)
end


---------------------
--- Main entry points.

-- Creates a BeeServer and does initial setup (importing the bee graph, etc.).
-- Requires system libraries as an input.
---@param componentLib Component
---@param eventLib Event
---@param serialLib Serialization
---@param termLib Term
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
    obj.event = eventLib
    obj.term = termLib
    obj.logFilepath = logFilepath

    obj.comm = CommLayer:Open(eventLib, componentLib.modem, serialLib, port)
    if obj.comm == nil then
        Print("Failed to open communication layer.")

        -- TODO: Verify whether it is valid to call obj:Shutdown() here.
        --       In theory, it should be fine since we already set the metatable,
        --       but that should be verified.
        obj:Shutdown(1)
    end

    -- Register request handlers.
    obj.messageHandlerTable = {
        [CommLayer.MessageCode.BreedInfoRequest] = BeeServer.BreedInfoHandler,
        [CommLayer.MessageCode.PingRequest] = BeeServer.PingHandler,
        [CommLayer.MessageCode.PrintErrorRequest] = BeeServer.PrintErrorHandler,
        [CommLayer.MessageCode.PromptConditionsRequest] = BeeServer.PromptConditionsHandler,
        [CommLayer.MessageCode.SpeciesFoundRequest] = BeeServer.SpeciesFoundHandler,
        [CommLayer.MessageCode.TraitInfoRequest] = BeeServer.TraitInfoHandler
    }

    -- Register command line handlers
    obj.terminalHandlerTable = {
        ["breed"] = BeeServer.BreedCommandHandler,
        ["continue"] = BeeServer.ContinueCommandHandler,
        ["shutdown"] = BeeServer.ShutdownCommandHandler
    }

    -- Obtain the full bee graph from the attached adapter and apiary.
    -- TODO: This is set up to be attached to an apiary, but this isn't technically required.
    --       We need more generous matching here to determine the correct component.
    Print("Importing bee graph.")
    if componentLib.tile_for_apiculture_0_name == nil then
        Print("Couldn't find attached apiculture tile in the component library.")
        obj:Shutdown(1)
    end
    obj.beeGraph = GraphParse.ImportBeeGraph(componentLib.tile_for_apiculture_0_name)

    -- Read our local logfile to figure out which species we already have.
    obj.leafSpeciesList = Logger.ReadSpeciesLogFromDisk(logFilepath)

    obj.breedPath = nil
    obj.botAddr = nil
    obj.conditionsPending = false

    return obj
end

-- Runs the main BeeServer operation loop.
function BeeServer:RunServer()
    while true do
        self:PollForTerminalInputAndHandle(0.2)
        self:PollForMessageAndHandle(0.2)
    end
end

return BeeServer
