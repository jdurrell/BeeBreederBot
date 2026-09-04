-- This program is the main executable for the bee-graph server.
-- The bee-graph server analyzes the bee breeding data from the apiary adapter
-- and communicates with the breeder robot to give it instructions on which bees to breed.

-- Import BeeBreederBot libraries.
require("Shared.Shared")
local CommLayer = require("Shared.CommLayer")
local GraphParse = require("BeeServer.GraphParse")
local GraphQuery = require("BeeServer.GraphQuery")
local MutationConditionsSet = require("Shared.MutationConditionSet")
local MutationMath = require("BeeServer.MutationMath")
local MutationTraits = require("BeeServer.SpeciesMutationTraits")
local TraitInfo = require("BeeServer.SpeciesDominance")
local StringToTraitValue = require("BeeServer.StringToTraitValue")
local ValidTraitValues = require("BeeServer.ValidTraitValues")

---@class BeeServer
---@field event Event
---@field term Term
---@field beeGraph SpeciesGraph
---@field beeNameToUids table<string, string[]>
---@field botAddr string
---@field comm CommLayer
local BeeServer = {}

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

    obj.comm = CommLayer:Open(componentLib, eventLib, serialLib, config.port)
    if obj.comm == nil then
        Print("Failed to open communication layer.")
        obj:shutdown(1)
    end

    -- Obtain the full bee graph from the attached adapter and apiary.
    -- TODO: This is set up to be attached to an apiary, but this isn't technically required.
    --       We need more generous matching here to determine the correct component.
    Print("Importing bee graph...")
    local apicultureComponent
    if TableContains(componentLib.list(), "tile_for_apiculture_0_name") then
        apicultureComponent = componentLib.tile_for_apiculture_0_name
    elseif TableContains(componentLib.list(), "tile_for_apiculture_2_name") then
        apicultureComponent = componentLib.tile_for_apiculture_2_name
    else
        Print("Couldn't find attached apiculture tile in the component library.")
        Print("tile_for_apiculture_0_name, tile_for_apiculture_2_name not found.")
        obj:shutdown(1)
    end
    obj.beeGraph = GraphParse.ImportBeeGraph(apicultureComponent)
    obj.beeNameToUids = GraphParse.ImportBeeNames(apicultureComponent)
    Print("Imported bee graph.")

    Print("Startup Success!")
    return obj
end

-- Executes the given BeeServer command.
---@param command string | nil
---@param flags Set<string>
---@param values table<string, string>
function BeeServer:RunServer(command, flags, values)
    if command == nil then
        Print("Expected a command, got nothing.")
        self:shutdown(1)
    end

    if command == "template" then
        self:TemplateCommand(flags, values)
    elseif command == "import" then
        self:ImportCommandHandler(flags, values)
    else
        Print(string.format("Unrecognized command '%s'.", command))
        self:shutdown(1)
    end

    self:shutdown(0)
end

---------------------
--- Terminal handling:

---@param flags Set<string>
---@param values table<string, string>
function BeeServer:TemplateCommand(flags, values)
    ---@type MakeTemplateCommandPayload
    local payload = {traits={}, raw=SetContains(flags, "raw")}

    for k, v in pairs(values) do
        local stringLower = v:lower()
        if ValidTraitValues[k] == nil then
            Print(string.format("Unrecognized option '%s'", k))
            self:shutdown(1)
        end

        local realValue
        if StringToTraitValue[k][stringLower] ~= nil then
            realValue = StringToTraitValue[k][stringLower]
            if type(realValue) == "table" then
                -- Some string items are ambiguous due to overlap between mods.
                -- Ask the user directly to disambiguate.
                Print(string.format("Value '%s' for trait '%s' is ambiguous: Please select one of the following: ", v, k))
                ---@cast realValue table
                for i, v2 in ipairs(realValue) do
                    Print(string.format("[%d]: %s", i, v2))
                end

                local value = self.term.read()
                if value == nil or value == false then
                    Print("Invalid input.")
                    self:shutdown(1)
                end

                ---@cast value string
                value = UnwrapNull(value):gsub("[\r\n]", "")
                local index = tonumber(value, 10)
                realValue = StringToTraitValue[k][stringLower][index]
            end
        else
            local expectedType = type(ValidTraitValues[k][1])
            if expectedType == "boolean" then
                if (v:lower() ~= "true") and (v:lower() ~= "false") then
                    Print(string.format("Unrecognized value '%s' for boolean field '%s'. Expected 'true' or 'false'", v, k))
                    self:shutdown(1)
                end
                realValue = (v:lower() == "true")
            elseif expectedType == "number" then
                local integerValue = tonumber(v, 10)
                if not type(integerValue) == "number" then
                    Print(string.format("Unrecognized value '%s' for integer field '%s'.", k, v))
                    self:shutdown(1)
                end
                realValue = integerValue
            elseif expectedType == "string" then
                realValue = v
            else
                Print(string.format("Unrecognized type %s.", expectedType))
                self:shutdown(1)
            end
        end

        if not TableContains(ValidTraitValues[k], realValue) then
            Print(string.format("Unrecognized value for field %s: '%s'", k, v))
            self:shutdown(1)
        end

        if k == "species" then
            ---@diagnostic disable-next-line: missing-fields
            ---@cast realValue string
            payload.traits.species = {uid = realValue}
        elseif k == "territory" then
            ---@cast realValue integer[]
            payload.traits.territory = realValue
        else
            payload.traits[k] = realValue
        end
    end

    Print(string.format("Making internal template: %s.", TraitsToString(payload.traits)))
    self:RunCommand(CommLayer.MessageCode.MakeTemplateCommand, payload)
end

---@param args string[]
---@param values any
function BeeServer:ImportCommandHandler(args, values)
    if (#args ~= 1) or (not TableIsEmpty(values)) then
        Print("Unrecognized command. Usage: import <princesses | drones>")
        self:shutdown(1)
    end

    if args[1] == "princesses" then
        self.comm:SendMessage(self.botAddr, CommLayer.MessageCode.ImportPrincessesCommand)
        Print("Importing princesses...")
    elseif args[1] == "drones" then
        self.comm:SendMessage(self.botAddr, CommLayer.MessageCode.ImportDroneStacksCommand)
        Print("Importing drones...")
    else
        Print("Unrecognized command. Usage: import <princesses | drones>")
        self:shutdown(1)
    end
end

---@param messageCode integer
---@param payload table
function BeeServer:RunCommand(messageCode, payload)
    local transactionId = self.comm:SendMessage(self.botAddr, messageCode, nil, payload)

    local messageHandlerTable = {
        [CommLayer.MessageCode.BreedInfoRequest] = BeeServer.BreedInfoHandler,
        [CommLayer.MessageCode.PingRequest] = BeeServer.PingHandler,
        [CommLayer.MessageCode.PrintErrorRequest] = BeeServer.PrintErrorHandler,
        [CommLayer.MessageCode.PromptConditionsRequest] = BeeServer.PromptConditionsHandler,
        [CommLayer.MessageCode.TraitBreedPathRequest] = BeeServer.TraitBreedPathHandler,
        [CommLayer.MessageCode.TraitInfoRequest] = BeeServer.TraitInfoHandler
    }

    while true do
        local message, addr = self.comm:GetIncoming(nil, nil, self.botAddr)
        if message == nil then
            goto continue
        end
        addr = UnwrapNull(addr)

        if message.code == CommLayer.MessageCode.CommandFinishRequest then
            if message.transactionId == transactionId then
                -- The bot finished executing this command. We are done.
                self.comm:SendMessage(addr, CommLayer.MessageCode.CommandFinishResponse, message.transactionId)
                break
            else
                Print("Got unexpected transactionId for finished command.")
            end
        elseif messageHandlerTable[message.code] ~= nil then
            messageHandlerTable[message.code](self, UnwrapNull(addr), message.transactionId, message.payload)
        else
            Print(string.format("Received unidentified message code: %d", message.code))
        end
        ::continue::
    end
end

-- Handles requests for dynamically changing addresses.
---@param addr string
---@param transactionId integer
function BeeServer:PingHandler(addr, transactionId, data)
    self.botAddr = addr

    -- Just respond with our own ping, echoing back the transaction id.
    self.comm:SendMessage(addr, CommLayer.MessageCode.PingResponse, transactionId, nil)
end

---@param addr string
---@param transactionId integer
---@param data BreedInfoRequestPayload
function BeeServer:BreedInfoHandler(addr, transactionId, data)
    if (data == nil) or (data.parent1 == nil) or (data.parent2 == nil) or (data.target == nil) then
        return
    end

    local targetMutChance, nonTargetMutChance = MutationMath.CalculateBreedInfo(data.parent1, data.parent2, data.target, self.beeGraph)
    local payload = {targetMutChance = targetMutChance, nonTargetMutChance = nonTargetMutChance}
    self.comm:SendMessage(addr, CommLayer.MessageCode.BreedInfoResponse, transactionId, payload)
end

---@param addr string
---@param transactionId integer
---@param data TraitBreedPathRequestPayload
function BeeServer:TraitBreedPathHandler(addr, transactionId, data)
    if (data.trait == nil) or (data.value == nil) then
        Print("Got unexpected TraitBreedPathRequestPayload format.")
        return
    end

    local validTargets = {}  ---@type string[]
    if data.trait == "species" then
        validTargets = {[data.value.uid] = true}
    else
        local indexableValue = data.value
        if data.trait == "territory" then
            indexableValue = data.value[1]
        elseif data.trait == "speed" then
            -- Round to 1 decimal point.
            indexableValue = math.floor(data.value * 10 + 0.5) / 10
        end
        validTargets = MutationTraits[data.trait][indexableValue]
    end

    if validTargets == nil then
        Print(string.format("Error: Failed to find valid breeding target for trait '%s' with value '%s'",
            data.trait, TraitToString(data.trait, data.value)
        ))
        self.comm:SendMessage(addr, CommLayer.MessageCode.TraitBreedPathResponse, transactionId, {})
        return
    end

    local path = GraphQuery.QueryBestBreedingPath(self.beeGraph, data.existingSpecies, validTargets)
    if path == nil then
        Print(string.format("Error: Failed to find breeding path for trait '%s' with value '%s'",
            data.trait, TraitToString(data.trait, data.value)
        ))
        self.comm:SendMessage(addr, CommLayer.MessageCode.TraitBreedPathResponse, transactionId, {})
        return
    end

    -- Sleep after printing things because OpenComputers' screen is really small.
    -- This gives the player some time to actually look at it.
    -- TODO: Switch this to something that requires scrolling to the end and back up.
    Print(string.format("Trait '%s: %s' not found in breeding path. Breeding it through:",
        data.trait, TraitToString(data.trait, data.value)
    ))
    for _, v in ipairs(path) do
        Print(string.format("  %s + %s = %s", v.parent1, v.parent2, v.target))
        Sleep(0.5)
    end
    Sleep(2)

    local printedFoundations = false
    for _, v in ipairs(path) do
        if (v.conditions ~= nil) and MutationConditionsSet.FoundationIsPlaceableBlock(v.conditions) then
            if not printedFoundations then
                printedFoundations = true
                Print(string.format("\nPlease gather the following foundations:"))
                Sleep(0.5)
            end
            Print(string.format("  %s", v.conditions.foundation))
            Sleep(0.5)
        end
    end

    self.comm:SendMessage(addr, CommLayer.MessageCode.TraitBreedPathResponse, transactionId, path)
end

---@param addr string
---@param transactionId integer
---@param data TraitInfoRequestPayload
function BeeServer:TraitInfoHandler(addr, transactionId, data)
    local payload = {dominant = TraitInfo[data.species]}
    self.comm:SendMessage(addr, CommLayer.MessageCode.TraitInfoResponse, transactionId, payload)
end

---@param addr string
---@param transactionId integer
---@param data PromptConditionsPayload
function BeeServer:PromptConditionsHandler(addr, transactionId, data)
    local pathNode = data.pathNode
    if MutationConditionsSet.IsTrivialConditions(pathNode.conditions) then
        -- If there are no conditions, then immediately tell the robot it can continue.
        Print(string.format("Robot is breeding '%s' from '%s' and '%s'. No conditions are required.",
            pathNode.target, pathNode.parent1, pathNode.parent2
        ))
        self.comm:SendMessage(addr, CommLayer.MessageCode.PromptConditionsResponse, transactionId)
    else
        Print(string.format("Robot is breeding '%s' from '%s' and '%s'. The following conditions are required:",
            pathNode.target, pathNode.parent1, pathNode.parent2
        ))
        MutationConditionsSet.PrintConditions(pathNode.conditions)
        Print("Once the conditions have been met, enter the command 'continue' to tell the robot to continue.")
    end
end

---@param addr string
---@param transactionId integer
---@param data PrintErrorPayload
function BeeServer:PrintErrorHandler(addr, transactionId, data)
    if data.errorMessage == nil then
        Print("Robot error: unknown.")
    else
        Print(string.format("Robot error: %s", data.errorMessage))
    end
end

-- Shuts down the server.
---@param code integer
function BeeServer:shutdown(code)
    if self.comm ~= nil then
        self.comm:Close()
    end

    ExitProgram(code)
end

return BeeServer
