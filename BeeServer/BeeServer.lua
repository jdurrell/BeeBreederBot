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
---@field messagingPromptsPending table<string, boolean>
---@field messagingThreadHandle ThreadHandle
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
    local payload = {targetMutChance = targetMutChance, nonTargetMutChance = nonTargetMutChance}
    self.comm:SendMessage(addr, CommLayer.MessageCode.BreedInfoResponse, payload)
end

-- Handles requests for dynamically changing addresses.
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
    if self.messagingPromptsPending["conditions"] or (data == nil) or (data.parent1 == nil) or (data.parent2 == nil) or (data.target == nil) or (self.beeGraph[data.target] == nil) then
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
                -- TODO: Distinguish between foundation blocks that can be placed by the bot and other foundations that can't be.
                local isAFoundation = condition:find("foundation") == nil
                if (not isAFoundation) or (data.promptFoundation) then
                    table.insert(conditions, condition)
                end
            end
        end
    end

    if (conditions == nil) or (#conditions == 0) then
        -- If there are no conditions, then immediately tell the robot it can continue.
        Print(string.format("Robot is breeding '%s' from '%s' and '%s'. No conditions are required.", data.target, data.parent1, data.parent2))
        self.comm:SendMessage(addr, CommLayer.MessageCode.PromptConditionsResponse)
    else
        self.messagingPromptsPending["conditions"] = true
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
    if not TableContains(self.leafSpeciesList, data.species) then
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

    -- TODO: Figure this out from a list of default chromosomes, and don't force the player to figure this out manually.
    --       There may be some portability and memory to that, though.
    self.messagingPromptsPending["traitbreedpath"] = true
    Print(string.format("Trait %s is not found in the bee storage.", TraitsToString({[data.trait] = data.value})))
    Print("Enter a species to breed with the desired trait mutation:")
end

---@param addr string
---@param data TraitInfoRequestPayload
function BeeServer:TraitInfoHandler(addr, data)
    local payload = {dominant = TraitInfo[data.species]}
    self.comm:SendMessage(addr, CommLayer.MessageCode.TraitInfoResponse, payload)
end

---@param timeout number | nil
function BeeServer:PollForMessageAndHandle(timeout)
    local response, addr = self.comm:GetIncoming(timeout, nil, self.botAddr)
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
        return
    end

    self.comm:SendMessage(self.botAddr, CommLayer.MessageCode.BreedCommand, path)
end

---@param argv string[]
function BeeServer:ContinueCommandHandler(argv)
    if not self.messagingPromptsPending["conditions"] then
        Print("Nothing to continue. Unrecognized context for this command.")
        return
    end

    self.comm:SendMessage(self.botAddr, CommLayer.MessageCode.PromptConditionsResponse)
    self.messagingPromptsPending["conditions"] = false
end

function BeeServer:ImportCommandHandler(argv)
    if (argv[2] == nil) then
        Print("Unrecognized command. Usage: import <princesses | drones>")
        return
    end

    if argv[2] == "princesses" then
        self.comm:SendMessage(self.botAddr, CommLayer.MessageCode.ImportPrincessesCommand)
        Print("Importing princesses...")
    elseif argv[2] == "drones" then
        self.comm:SendMessage(self.botAddr, CommLayer.MessageCode.ImportDroneStacksCommand)
        Print("Importing drones...")
    else
        Print("Unrecognized command. Usage: import <princesses | drones>")
    end
end

---@param argv string[]
function BeeServer:TemplateCommandHandler(argv)
    local validTraitsTypes = {
        ["caveDwelling"] = "boolean",
        ["effect"] = "string",
        ["fertility"] = "integer",
        ["flowering"] = "integer",
        ["flowerProvider"] = "integer",
        ["humidityTolerance"] = "string",
        ["lifespan"] = "integer",
        ["nocturnal"] = "boolean",
        ["species"] = "string",
        ["speed"] = "number",
        ["temperatureTolerance"] = "string",
        ["territory"] = "integer",
        ["tolerantFlyer"] = "boolean"
    }
    local payload = {traits = {}}  ---@type MakeTemplatePayload

    -- Remove the orginal command.
    table.remove(argv, 1)

    for i, v in ipairs(argv) do
        local fields = {}
        for match in v:gmatch("[^=]+") do
            table.insert(fields, match)
        end

        if #fields ~= 2 then
            Print(string.format("Unrecognized parameter string '%s'.", v))
            return
        end

        -- TODO: Actually validate all of the values given to us here.
        if validTraitsTypes[fields[2]] == "boolean" then
            fields[2] = fields[2]:lower()
            if fields[2] == "true" then
                payload.traits[fields[1]] = true
            elseif fields[2] == "false" then
                payload.traits[fields[1]] = false
            else
                Print(string.format("Unrecognized boolean value: '%s'.", fields[2]))
                return
            end
        elseif validTraitsTypes[fields[1]] == "integer" then
            local val = tonumber(fields[2], 10)
            if val == nil then
                Print(string.format("Unrecognized integer: '%s'.", fields[2]))
                return
            end
            payload.traits[fields[1]] = val
        elseif validTraitsTypes[fields[1]] == "number" then
            local val = tonumber(fields[2])
            if val == nil then
                Print(string.format("Unrecognized number: '%s'.", fields[2]))
                return
            end
            payload.traits[fields[1]] = val
        elseif validTraitsTypes[fields[1]] == "string" then
            if fields[1] == "species" then
                ---@diagnostic disable-next-line: missing-fields
                payload.traits["species"] = {uid = fields[2]}
            else
                payload.traits[fields[1]] = fields[2]
            end
        else
            Print(string.format("Unrecognized argument: '%s'.", fields[1]))
            return
        end
    end

    Print(string.format("Making internal template: %s.", TraitsToString(payload.traits)))
    self.comm:SendMessage(self.botAddr, CommLayer.MessageCode.MakeTemplateCommand, payload)
end

---@param argv string[]
function BeeServer:TraitBreedPathCommandHandler(argv)
    if self.messagingPromptsPending["traitbreedpath"] then
        local species = argv[1]
        if (species == nil) or self.beeGraph[species] == nil then
            return
        elseif species == "cancel" then
            -- Give the user a way to break out of this, if they need to.
            self.messagingPromptsPending["traitbreedpath"] = false
            return
        end

        local path = self:GetBreedPath(species, true)
        if path == nil then
            Print(string.format("No path found for species '%s'.", species))
            return
        end

        self.comm:SendMessage(self.botAddr, CommLayer.MessageCode.TraitBreedPathResponse, path)
    end
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

function BeeServer:PollForTerminalInputAndHandle()
    local text = self.term.read()
    if (text == nil) or (text == false) then
        Print("Received cancellation token.")
        self:Shutdown(1)
        return
    end

    -- Separate command line options.
    -- TODO provide a way for a single argument to have a space in it.
    local argv = {}
    for arg in string.gmatch(UnwrapNull(text), "[^%s]+") do
        table.insert(argv, arg)
    end

    -- We could theoretically get no commands if the user gave us a blank line.
    if #argv == 0 then
        return
    end

    if self.messagingPromptsPending["traitbreedpath"] then
        self:TraitBreedPathCommandHandler(argv)
    elseif self.terminalHandlerTable[argv[1]] == nil then
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
        if printstr == "" then
            printstr = node.target
        else
            printstr = string.format("%s, %s", printstr, node.target)
        end
    end
    Print(printstr)

    Sleep(0.5)
    Print("")
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
                    if printstr == "" then
                        printstr = foundationStr
                    else
                        printstr = string.format("%s, %s", printstr, foundationStr)
                    end
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
---@param threadLib any
---@param config BeeServerConfig
---@return BeeServer
function BeeServer:Create(componentLib, eventLib, serialLib, termLib, threadLib, config)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    -- Store away system libraries.
    -- Do this in the constructor instead of statically so that we can inject our
    -- own system libraries for testing.
    obj.event = eventLib
    obj.term = termLib
    obj.botAddr = config.botAddr
    obj.logFilepath = config.logFilepath
    obj.breedPath = nil
    obj.conditionsPending = false
    obj.messagingPromptsPending = {}

    obj.comm = CommLayer:Open(componentLib, eventLib, serialLib, config.port)
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
        [CommLayer.MessageCode.TraitBreedPathRequest] = BeeServer.TraitBreedPathHandler,
        [CommLayer.MessageCode.TraitInfoRequest] = BeeServer.TraitInfoHandler
    }

    -- Register command line handlers
    obj.terminalHandlerTable = {
        ["breed"] = BeeServer.BreedCommandHandler,
        ["continue"] = BeeServer.ContinueCommandHandler,
        ["template"] = BeeServer.TemplateCommandHandler,
        ["import"] = BeeServer.ImportCommandHandler,
        ["shutdown"] = BeeServer.ShutdownCommandHandler
    }

    -- Obtain the full bee graph from the attached adapter and apiary.
    -- TODO: This is set up to be attached to an apiary, but this isn't technically required.
    --       We need more generous matching here to determine the correct component.
    Print("Importing bee graph...")
    if not TableContains(componentLib.list(), "tile_for_apiculture_0_name") then
        Print("Couldn't find attached apiculture tile in the component library.")
        obj:Shutdown(1)
    end
    obj.beeGraph = GraphParse.ImportBeeGraph(componentLib.tile_for_apiculture_0_name)
    Print("Imported bee graph.")

    -- Read our local logfile to figure out which species we already have.
    Print("Reading species logfile from " .. config.logFilepath .. "...")
    obj.leafSpeciesList = Logger.ReadSpeciesLogFromDisk(config.logFilepath)
    if #(obj.leafSpeciesList) == 0 then
        Print("No initial species were found.")
    end

    -- Set up the terminal handler thread.
    obj.messagingThreadHandle = threadLib.create(function ()
        while true do
            BeeServer.PollForMessageAndHandle(obj, nil)
        end
    end)
    Print("Comms online.")

    return obj
end

-- Runs the main BeeServer operation loop.
function BeeServer:RunServer()
    Print("Startup Success!")

    while true do
        self:PollForTerminalInputAndHandle()
    end
end

return BeeServer
