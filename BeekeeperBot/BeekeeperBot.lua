-- This program is the main executable for the breeder robot.
-- The breeder robot works "in the field" and uses information queried
-- from the bee-graph server to determine pairings of princesses and drones
-- and manipulate inventories to move the bees between breeding or storage.
-- TODO: Clean up and unify all the different breeding mechanisms.

-- Import BeeBreederBot libraries.
require("Shared.Shared")
local AnalysisUtil = require("BeekeeperBot.BeeAnalysisUtil")
local BreederOperation = require("BeekeeperBot.BreederOperation")
local CommLayer = require("Shared.CommLayer")
local GarbageCollectionPolicies = require("BeekeeperBot.GarbageCollectionPolicies")
local MatchingAlgorithms = require("BeekeeperBot.MatchingAlgorithms")
local RobotComms = require("BeekeeperBot.RobotComms")

---@class BeekeeperBot
---@field config BeekeeperBotConfig
---@field component Component
---@field event Event
---@field breeder BreedOperator
---@field messageHandlerTable table<MessageCode, fun(bot: BeekeeperBot, data: any)>
---@field robotComms RobotComms
local BeekeeperBot = {}

-- Creates a BeekeeperBot and does initial setup.
-- Requires system libraries as an input.
---@param componentLib Component
---@param eventLib Event
---@param robotLib any
---@param serialLib Serialization
---@param sidesLib any
---@param config BeekeeperBotConfig
---@return BeekeeperBot
function BeekeeperBot:Create(componentLib, eventLib, robotLib, serialLib, sidesLib, config)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    -- This is used for transaction IDs when pinging the server.
    math.randomseed(os.time())

    -- Store away system libraries.
    -- Do this in the constructor instead of statically so that we can inject our
    -- own system libraries for testing.
    obj.event = eventLib

    if not TableContains({"UP_5", "DOWN_5", "BOTH_5"}, config.defaultHumidityTolerance) then
        Print(string.format("Invalid `defaultHumidityTolerance` supplied: %s. Must be 'UP_5', 'DOWN_5',' or 'BOTH_5'."))
        obj:shutdown(1)
    end
    if not TableContains({"UP_5", "DOWN_5", "BOTH_5"}, config.defaultTemperatureTolerance) then
        Print(string.format("Invalid `defaultTemperatureTolerance` supplied: %s. Must be 'UP_5', 'DOWN_5',' or 'BOTH_5'."))
        obj:shutdown(1)
    end
    obj.config = config

    local robotComms = RobotComms:Create(componentLib, eventLib, serialLib, config.serverAddr, config.port)
    if robotComms == nil then
        Print("Failed to initialize RobotComms during BeekeeperBot initialization.")
        obj:shutdown(1)
    end
    obj.robotComms = UnwrapNull(robotComms)

    local breeder = BreederOperation:Create(componentLib, robotLib, sidesLib, config.apiaries)
    if breeder == nil then
        Print("Failed to initialize breeding operator during BeekeeperBot initialization.")
        obj:shutdown(1)
    end
    obj.breeder = UnwrapNull(breeder)

    obj.messageHandlerTable = {
        [CommLayer.MessageCode.BreedCommand] = BeekeeperBot.breedCommandHandler,
        [CommLayer.MessageCode.CancelCommand] = BeekeeperBot.cancelCommandHandler,
        [CommLayer.MessageCode.ImportDroneStacksCommand] = BeekeeperBot.importDroneStacksHandler,
        [CommLayer.MessageCode.ImportPrincessesCommand] = BeekeeperBot.importPrincessesCommandHandler,
        [CommLayer.MessageCode.MakeTemplateCommand] = BeekeeperBot.makeTemplateHandler,
        [CommLayer.MessageCode.ReplicateCommand] = BeekeeperBot.replicateCommandHandler
    }

    Print("Pinging server for startup...")
    obj.robotComms:EstablishComms()
    Print("Got response from server " .. obj.robotComms.serverAddr .. ".")

    return obj
end

-- Runs the main BeekeeperBot operation loop.
function BeekeeperBot:RunRobot()
    Print("Startup success!")
    while true do
        local request = self.robotComms:GetCommandFromServer()

        if (request.code == nil) or (self.messageHandlerTable[request.code] == nil) then
            self:outputError("Received unrecognized code: " .. request.code .. ".")
        else
            self.messageHandlerTable[request.code](self, request.payload)
        end
    end
end

function BeekeeperBot:cancelCommandHandler(data)
    self:shutdown(0)
end

function BeekeeperBot:importPrincessesCommandHandler(data)
    if not self.breeder:ImportPrincessesFromInputsToStock() then
        self.robotComms:ReportErrorToServer("Failed to import princesses")
    end
end

function BeekeeperBot:importDroneStacksHandler(data)
    local speciesSet = self.breeder:ImportDroneStacksFromInputsToStore()

    if speciesSet == nil then
        self:outputError("Failed to import drones.")
    else
        for spec, _ in pairs(speciesSet) do
            self.robotComms:ReportNewSpeciesToServer(spec)
        end
    end
end

---@param data ReplicateCommandPayload
function BeekeeperBot:replicateCommandHandler(data)
    if (data == nil) or (data.species == nil) then
        return
    end

    if not self:replicateSpecies(data.species, 64, 1, true, true) then
        self:outputError(string.format("Failed to replicate species '%s'.", data.species))
        return
    end

    self.breeder:TrashSlotsFromDroneChest(nil)
    self.breeder:ImportHoldoverStacksToDroneChest({1}, {64}, {1})
    self.breeder:ExportDroneStackToOutput(1, 64)
end

---@param data BreedCommandPayload
function BeekeeperBot:breedCommandHandler(data)
    if (data == nil) or (data.path == nil) or (data.path[1] == nil) then
        self:outputError("Got invalid BreedCommand payload.")
        return
    end

    if data.raw then
        local node = data.path[1]
        local breedInfoCacheElement = {}
        local traitInfoCache = {species = {}}

        self:breed(
            MatchingAlgorithms.MutatedAlleleMatcher(
                self.breeder.numApiaries,
                "species",
                {uid = node.target},
                {humidityTolerance = self.config.defaultHumidityTolerance, temperatureTolerance = self.config.defaultTemperatureTolerance},
                breedInfoCacheElement,
                traitInfoCache
            ),
            MatchingAlgorithms.DroneStackOfSpeciesPositiveFertilityFinisher(node.target, 2, 64),
            GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSizeCollector(node.target),
            function (princessStack, droneStackList)
                self:populateBreedInfoCache(princessStack, droneStackList, node.target, breedInfoCacheElement)
                self:populateTraitInfoCache(princessStack, droneStackList, traitInfoCache)
            end
        )
    else
        if not self:breedSpeciesCommand(data) then
            self:outputError("Failed to breed new species.")
            return
        end

        self.breeder:TrashSlotsFromDroneChest(nil)
    end

    Print(string.format("Finished breeding path ending in %s.", data.path[#(data.path)].target))
end

---@param data MakeTemplatePayload
function BeekeeperBot:makeTemplateHandler(data)
    if data.traits == nil then
        self:outputError("Received invalid MakeTemplate payload.")
        return
    end

    -- Set default tolerances.
    data.traits.temperatureTolerance = ((data.traits.temperatureTolerance == nil) and self.config.defaultTemperatureTolerance) or data.traits.temperatureTolerance
    data.traits.humidityTolerance = ((data.traits.humidityTolerance == nil) and self.config.defaultHumidityTolerance) or data.traits.humidityTolerance

    if data.raw then
        -- If raw is specified, then the user is responsible for organizing everything in the proper chests.
        self:breed(
            MatchingAlgorithms.ClosestMatchToTraitsMatcher(data.traits, self.breeder.numApiaries),
            MatchingAlgorithms.DroneStackAndPrincessOfTraitsFinisher(data.traits, 64),
            GarbageCollectionPolicies.ClearDronesByFurthestAlleleMatchingCollector(data.traits),
            nil
        )
    else
        if not self:makeTemplate(data.traits) then
            self:outputError("Failed to make template.")
            return
        end

        self.breeder:TrashSlotsFromDroneChest(nil)
    end

    Print(string.format("Finished making template %s.", TraitsToString(data.traits)))
end

---@param data PropagateTemplatePayload
function BeekeeperBot:propagateTemplateHandler(data)
    if (data == nil) or (data.traits == nil) or (data.traits.species == nil) or (data.traits.species.uid == nil) then
        self:outputError("Received invalid PropagateTemplate payload.")
        return
    end

    -- Set default tolerances.
    data.traits.temperatureTolerance = ((data.traits.temperatureTolerance == nil) and self.config.defaultTemperatureTolerance) or data.traits.temperatureTolerance
    data.traits.humidityTolerance = ((data.traits.humidityTolerance == nil) and self.config.defaultHumidityTolerance) or data.traits.humidityTolerance

    if not self:propagateTemplate(data.traits) then
        self:outputError("Failed to propagate remplate.")
        return
    end

    self.breeder:TrashSlotsFromDroneChest(nil)
    Print(string.format("Finished propagating template to species %s.", data.traits.species.uid))
end

-- Breeds the commanded species based on the given path.
---@param breedPath BreedPathNode[]
---@return boolean
function BeekeeperBot:breedSpeciesCommand(breedPath)
    local numDronesReplicate = 4 + (2 * self.breeder.numApiaries)
    self.breeder:RefreshStorageCache()

    for _, v in ipairs(breedPath) do
        if ((v.parent1 == nil) and (v.parent2 ~= nil)) or ((v.parent1 ~= nil) and (v.parent2 == nil)) then
            self:outputError("Cannot breed a species that has only one parent node.")
            return false
        end

        local breedParents = (v.parent1 ~= nil)
        if breedParents then
            ---@diagnostic disable-next-line: missing-fields
            local cacheEntry1 = self.breeder.storageCache:GetDroneEntry({species = {uid = v.parent1}})
            ---@diagnostic disable-next-line: missing-fields
            local cacheEntry2 = self.breeder.storageCache:GetDroneEntry({species = {uid = v.parent2}})

            if (cacheEntry1 == nil) or (cacheEntry2 == nil) then
                self:outputError(string.format("Did not find both parents in the breed cache.\nGot %s: %s.\nGot %s: %s",
                    v.parent1, tostring(cacheEntry1 ~= nil), v.parent2, tostring(cacheEntry2 ~= nil)
                ))
                return false
            end

            local retrievableStacks = {}
            local parent1Cached = (cacheEntry1.stackSize >= numDronesReplicate + 16)  -- Leave at least 16 in case we need them.
            local parent2Cached = (cacheEntry2.stackSize >= numDronesReplicate + 16)  -- Leave at least 16 in case we need them.
            if not parent1Cached then
                Print(string.format("Replicating %s.", v.parent1))
                if not self:replicateSpecies(v.parent1, numDronesReplicate, 1, true, not parent2Cached) then
                    self:outputError(string.format("Error: Replicate species '%s' failed.", v.parent1))
                    return false
                end
            else
                retrievableStacks.insert({entry = cacheEntry1, amount = 16, holdoverSlot = 1})
                Print(string.format("Skipping replicating %s because there is already enough of it.", v.parent1))
            end
            if not parent2Cached then
                Print(string.format("Replicating %s.", v.parent2))
                if not self:replicateSpecies(v.parent2, numDronesReplicate, 2, true, false) then
                    self:outputError(string.format("Error: Replicate species '%s' failed.", v.parent2))
                    return false
                end
            else
                retrievableStacks.insert({entry = cacheEntry2, amount = 16, holdoverSlot = 2})
                Print(string.format("Skipping replicating %s because there is already enough of it.", v.parent2))
            end

            if #retrievableStacks == 2 then
                -- If both parents are already cached, then we still need to retrieve princesses.
                self.breeder:RetrieveStockPrincessesFromChest(nil, {v.parent1, v.parent2})
            end
            if #retrievableStacks > 0 then
                self.breeder:RetrieveDroneStacksToHoldovers(retrievableStacks)
            end
        end

        Print(string.format("Breeding %s from %s and %s.", v.target, v.parent1, v.parent2))
        local retval = self:breedSpecies(v, false, true)
        if not retval then
            self:outputError(string.format("Error: Breeding species '%s' from '%s' and '%s' failed.", v.target, v.parent1, v.parent2))
            self.breeder:ReturnActivePrincessesToStock(nil)
            return false
        end

        -- Leave the first two slots because they might still have useful drones.
        -- Get rid of the other slots because they'll just cause us to keep doing garbage collection.
        local slotsToTrash = {}
        for i = 3, self.breeder:GetDroneChestSize() do
            table.insert(slotsToTrash, i)
        end
        self.breeder:TrashSlotsFromDroneChest(slotsToTrash)
    end

    return true
end

---@param targetTraits PartialAnalyzedBeeTraits
---@return boolean
function BeekeeperBot:makeTemplate(targetTraits)
    self.breeder:RefreshStorageCache()  -- TODO: Do we have enough memory for this?
    if self.breeder.storageCache:IsEmpty() then
        self:outputError("Failed to find any bees when searching for best initial trait match.")
        return false
    end

    -- If we don't actually have all of the traits, then figure out how to breed them into the storage population.
    local traitPaths = {}  ---@type {trait: string, path: BreedPathNode[]}[]
    for trait, value in pairs(targetTraits) do
        local traitExisting = false
        for _, v  in ipairs(self.breeder.storageCache.cache) do
            if AnalysisUtil.TraitIsEqual(v.traits, trait, value) then
                traitExisting = true
                break
            end
        end

        if not traitExisting then
            -- If we don't have the trait already, then check with the server whether we are able to breed that trait.
            ---@type TraitBreedPathResponsePayload | nil
            local path = self.robotComms:GetBreedPathForTraitFromServer(trait, value)
            if path == nil then
                self:outputError("Failed to get a valid breeding path for the requested mutation.")
                return false
            end

            table.insert(traitPaths, {trait = trait, path = path})
        end
    end

    -- Now, actually breed those traits into the storage population, if necessary.
    local bredNew = false
    for _, v in ipairs(traitPaths) do
        local numSpeciesReplicate = 4 + (2 * self.breeder.numApiaries)
        bredNew = true

        Print(string.format("Breeding trait %s into the population via species '%s'.",
            TraitsToString({[v.trait] = targetTraits[v.trait]}),
            v.path[#(v.path)].target
        ))
        for _, pathNode in ipairs(v.path) do
            if not self:replicateSpecies(pathNode.parent1, numSpeciesReplicate, 1, true, true) then
                self:outputError(string.format("Replicate parent 1 '%s' failed.",  pathNode.parent1))
                return false
            end

            if not self:replicateSpecies(pathNode.parent2, numSpeciesReplicate, 2, true, false) then
                self:outputError(string.format("Replicate parent 2 '%s' failed.",  pathNode.parent2))
                return false
            end

            -- Set up the breeding station.
            self.breeder:ImportHoldoverStacksToDroneChest({1, 2}, {numSpeciesReplicate, numSpeciesReplicate}, {1, 2})
            self:ensureSpecialConditionsMet(pathNode)

            -- We will certainly want to breed high fertility into the drones of the target species.
            local stack1 = self.breeder:GetStackInDroneSlot(1)
            local stack2 = self.breeder:GetStackInDroneSlot(2)
            if (stack1 == nil) or (stack2 == nil) then
                self:outputError("Drones were removed from chest between holdover import and conditions completion.")
                return false
            end
            local maxFertilityPreExisting = math.max(
                stack1.individual.active.fertility,
                stack2.individual.active.fertility
            )

            -- Do the breeding.
            local breedInfoCacheElement = {}
            local traitInfoCache = {species = {}}
            local finishedDroneSlot = self:breed(
                MatchingAlgorithms.MutatedAlleleMatcher(
                    self.breeder.numApiaries,
                    v.trait,
                    targetTraits[v.trait],
                    {humidityTolerance = self.config.defaultHumidityTolerance, temperatureTolerance = self.config.defaultTemperatureTolerance},
                    breedInfoCacheElement,
                    traitInfoCache
                ),
                MatchingAlgorithms.DroneStackOfSpeciesPositiveFertilityFinisher(pathNode.target, maxFertilityPreExisting, 64),
                GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSizeCollector(pathNode.target),
                function (princessStack, droneStackList)
                    self:populateBreedInfoCache(princessStack, droneStackList, pathNode.target, breedInfoCacheElement)
                    self:populateTraitInfoCache(princessStack, droneStackList, traitInfoCache)
                end
            ).drones

            if finishedDroneSlot == nil then
                self:outputError(string.format("Error breeding '%s' from '%s' and '%s'. Retrying from parent replication.", pathNode.target, pathNode.parent1, pathNode.parent2))
                self.breeder:BreakAndReturnFoundationsToInputChest()  -- Avoid double-prompting for foundations.
                return false
            end

            -- If we have enough of the target species now, then inform the server and store the drones at the new location.
            -- Technically, we only require the finished stack to have the desired trait, which doesn't require it to be the "target" species.
            local species = UnwrapNull(self.breeder:GetStackInDroneSlot(finishedDroneSlot)).individual.active.species.uid
            self.robotComms:ReportNewSpeciesToServer(species)

            self.breeder:StoreDronesFromActiveChest({finishedDroneSlot})
            self.breeder:TrashSlotsFromDroneChest(nil)
            self.breeder:ReturnActivePrincessesToStock(nil)
            self.breeder:BreakAndReturnFoundationsToInputChest()
        end
    end
    Print("All required traits now in population.")

    -- Refresh our view of the bees if necessary.
    if bredNew then
        self.breeder:RefreshStorageCache()
    end
    if self.breeder.storageCache:IsEmpty() then
        self:outputError("Failed to find any bees when searching for best initial trait match.")
        return false
    end

    -- Look for existing bees that are the closest match to the target template since they will be the best starting point.
    local maxTraitSet = self.breeder.storageCache.cache[1].traits
    local maxMatchingTraits = -1
    for _, v in ipairs(self.breeder.storageCache.cache) do
        local matchingTraits = 0
        for trait, value in pairs(targetTraits) do
            if AnalysisUtil.TraitIsEqual(v.traits, trait, value) then
                matchingTraits = matchingTraits + 1
            end
        end

        if matchingTraits > maxMatchingTraits then
            maxTraitSet = v
            maxMatchingTraits = matchingTraits
        end
    end

    local finishedTraits = {}
    for trait, value in pairs(targetTraits) do
        if AnalysisUtil.TraitIsEqual(maxTraitSet, trait, value) then
            finishedTraits[trait] = value
        end
    end

    -- Get 16 drones that have the initial best starting traits.
    Print(string.format("Starting with best trait set %s.", TraitsToString(maxTraitSet)))
    local numTraitReplicate = 8 + (4 * self.breeder.numApiaries)
    if not self:replicateTemplate(maxTraitSet, numTraitReplicate, 1, true, false) then
        self:outputError("Failed to replicate starting template.")
        return false
    end

    -- Add traits into the starting template one at a time.
    for trait, value in pairs(targetTraits) do
        if finishedTraits[trait] ~= nil then
            -- We only need to breed in traits that we haven't finished with yet.
            Print(string.format("Trait %s is already present in the working template.", TraitsToString({[trait] = value})))
            goto continue
        end

        -- Get 16 drones that have the requested trait.
        Print(string.format("Replicating stack with trait %s.", TraitsToString({[trait] = value})))
        if not self:replicateTemplate({[trait] = value}, numTraitReplicate, 2, false, false) then
            self:outputError("Failed to replicate template of new trait.")
            return false
        end

        -- Now breed the desired traits into the working template.
        Print(string.format("Adding trait %s into the working template.", TraitsToString({[trait] = value})))
        self.breeder:ImportHoldoverStacksToDroneChest({1, 2}, {64, 64}, {1, 2})
        local nextTraits = Copy(finishedTraits)
        nextTraits[trait] = value
        local finishedSlots = self:breed(
            MatchingAlgorithms.ClosestMatchToTraitsMatcher(nextTraits, self.breeder.numApiaries),
            MatchingAlgorithms.DroneStackAndPrincessOfTraitsFinisher(nextTraits, 16),
            GarbageCollectionPolicies.ClearDronesByFurthestAlleleMatchingCollector(nextTraits),
            nil
        )
        if (finishedSlots.drones == nil) or (finishedSlots.princess == nil) then
            self:outputError(string.format("Failed to breed trait '%s' into the template.", trait))
            return false
        end

        -- We now have a princess and full drone stack of the template with this trait added in.
        -- Update the finished traits. We only tried for `trait`, but we might have added others by luck.
        local newTraits = self.breeder:GetStackInDroneSlot(finishedSlots.drones).individual.active
        for newTrait, _ in pairs(newTraits) do
            if ((finishedTraits[newTrait] == nil) and
                (targetTraits[newTrait] ~= nil) and
                AnalysisUtil.TraitIsEqual(newTraits, newTrait, targetTraits[newTrait])
            ) then
                finishedTraits[newTrait] = targetTraits[newTrait]
            end
        end

        self.breeder:ExportDroneStacksToHoldovers({finishedSlots.drones}, {16}, {1})

        ::continue::
    end

    -- Final drone stack is in the holdover chest, but we only have 16. Breed it up to 64 to finish it off, then store it.
    Print("Working template finished. Breeding template up to full stack.")
    self.breeder:ImportHoldoverStacksToDroneChest({1}, {16}, {1})
    local finishedDrones = self:breed(
        MatchingAlgorithms.ClosestMatchToTraitsMatcher(targetTraits, self.breeder.numApiaries),
        MatchingAlgorithms.DroneStackAndPrincessOfTraitsFinisher(targetTraits, 64),
        GarbageCollectionPolicies.ClearDronesByFurthestAlleleMatchingCollector(targetTraits),
        nil
    ).drones
    if finishedDrones == nil then
        self:outputError("Failed to breed final template up to 64.")
        return false
    end

    self.breeder:StoreDronesFromActiveChest({finishedDrones})
    self.breeder:ReturnActivePrincessesToStock(nil)

    return true
end

---@param targetTraits PartialAnalyzedBeeTraits
---@return boolean
function BeekeeperBot:propagateTemplate(targetTraits)
    local nonSpeciesTraits = Copy(targetTraits)
    nonSpeciesTraits.species = nil

    -- Retrieve drones that have the requested species allele. Convert a stock princess to a pure-bred of that species.
    local numTraitReplicate = 8 + (4 * self.breeder.numApiaries)
    if not self:replicateSpecies(targetTraits.species.uid, numTraitReplicate, 1, true, true) then
        self:outputError(string.format("Failed to replicate species '%s'.", targetTraits.species.uid))
        return false
    end

    if not self:replicateTemplate(nonSpeciesTraits, numTraitReplicate, 2, true, false) then
        self:outputError("Error replicating starting template.")
        return false
    end

    -- Now breed the desired traits onto the desired species.
    self.breeder:ImportHoldoverStacksToDroneChest({1, 2}, {numTraitReplicate, numTraitReplicate}, {1, 2})
    local finishedSlots = self:breed(
        MatchingAlgorithms.ClosestMatchToTraitsMatcher(targetTraits, self.breeder.numApiaries),
        MatchingAlgorithms.DroneStackAndPrincessOfTraitsFinisher(targetTraits, 64),
        GarbageCollectionPolicies.ClearDronesByFurthestAlleleMatchingCollector(targetTraits),
        nil
    )
    if (finishedSlots.drones == nil) or (finishedSlots.princess == nil) then
        self:outputError(string.format("Convergence failure when propagating template."))
        return false
    end

    -- Export the output to the outputs.
    self.breeder:ExportDroneStackToOutput(finishedSlots.drones, 64)
    self.breeder:ExportPrincessStackToOutput(finishedSlots.princess, 1)

    self.breeder:ReturnActivePrincessesToStock(self.breeder.numApiaries - 1)
    self.breeder:TrashSlotsFromDroneChest(nil)
    return true
end

-- Replicates the given template from pure-bred drones and a pure-bred princess of that template.
-- Requires drones and princess to already be in the active chests.
-- Places drone outputs in the holdover chest.
---@param traits PartialAnalyzedBeeTraits | AnalyzedBeeTraits
---@param amount integer
---@param holdoverDroneSlot integer
---@param retrievePrincessesFromStock boolean
---@param returnPrincessesToStock boolean
---@return boolean | nil
function BeekeeperBot:replicateTemplate(traits, amount, holdoverDroneSlot, retrievePrincessesFromStock, returnPrincessesToStock)
    -- We can't replicate more than a full stack at a time because we support holdoverSlot semantics.
    if amount > 64 then
        self:outputError("Invalid argument. Cannot replicate more than a full stack at a time.")
        return nil
    end

    if (traits.fertility ~= nil) and (traits.fertility <= 1) then
        self:outputError("invalid argument. Cannot replicate drones with 1 or lower fertility.")
        return nil
    end

    -- Retrieve the princesses.
    if retrievePrincessesFromStock then
        if not self.breeder:RetrieveStockPrincessesFromChest(nil, {traits.species.uid}) then
            self:outputError("Failed to retrieve princesses from stock chest.")
            return nil
        end
    end

    -- Retrieve the starter drones.
    if not self.breeder:RetrieveDrones(traits, 1) then
        self:outputError(string.format("Failed to retrieve drones for replicating template."))
        if retrievePrincessesFromStock then
            self.breeder:ReturnActivePrincessesToStock(nil)
        end

        return nil
    end

    local stack = self.breeder:GetStackInDroneSlot(1)
    if stack == nil then
        self:outputError(string.format("Drones not found in chest after retrieval."))
        if retrievePrincessesFromStock then
            self.breeder:ReturnActivePrincessesToStock(nil)
        end
        return nil
    end

    if (stack.individual.active.fertility == 1) and (stack.individual.inactive.fertility == 1) then
        -- If the drone we want to replicate has generationally negative fertility, then don't bother replicating
        -- because we can't. Just output the drones we've got. There is already validation above for trying to specifically
        -- replicate that trait, so this isn't a mistake. Anyone using this doesn't care about the difference, then.
        if stack.size < amount then
            self:outputError("Unable to output drones with non-replicatable fertility.")
            return nil
        end

        self.breeder:ExportDroneStacksToHoldovers({1}, {amount}, {holdoverDroneSlot})

        return true
    end

    -- Choose a higher than 1 fertility to replicate, if we need to.
    local replicateTraits = Copy(traits)
    replicateTraits.fertility = ((replicateTraits.fertility == nil) and math.max(stack.individual.active.fertility, stack.individual.inactive.fertility)) or replicateTraits.fertility

    local finishedSlots = {drones = nil, princess = nil}
    local exportRemaining = amount
    local numberToExport = math.min(exportRemaining, 32)
    while numberToExport > 0 do
        -- Do the breeding. We start by breeding first in case we grabbed a stack that wasn't full to begin with.
        -- If the stack was already full, then Breed() will return immediately.
        finishedSlots = self:breed(
            MatchingAlgorithms.ClosestMatchToTraitsMatcher(replicateTraits, self.breeder.numApiaries),
            MatchingAlgorithms.DroneStackAndPrincessOfTraitsFinisher(replicateTraits, 64),
            GarbageCollectionPolicies.ClearDronesByFurthestAlleleMatchingCollector(replicateTraits),
            nil
        )

        if (finishedSlots.drones == nil) or (finishedSlots.princess == nil) then
            -- This should never really happen since we're starting with an absurdly high number of drones.
            self:outputError("Convergence failure while replicating traits.")
            if retrievePrincessesFromStock then
                self.breeder:ReturnActivePrincessesToStock(nil)
            end
            return nil
        end

        -- Take drones away for the output and replicate the original stack back up to 64.
        numberToExport = math.min(exportRemaining, 32)
        exportRemaining = exportRemaining - numberToExport
        self.breeder:ExportDroneStacksToHoldovers({finishedSlots.drones}, {numberToExport}, {holdoverDroneSlot})
    end

    -- Do cleanup operations.
    self.breeder:StoreDronesFromActiveChest({finishedSlots.drones})
    if returnPrincessesToStock then
        self.breeder:ReturnActivePrincessesToStock(nil)
    end

    return true
end

-- Replicates drones of the given species.
-- Places outputs into the holdover chest.
---@param species string
---@param amount integer
---@param holdoverSlot integer
---@param retrievePrincessesFromStock boolean
---@param returnPrincessesToStock boolean
---@return boolean success
function BeekeeperBot:replicateSpecies(species, amount, holdoverSlot, retrievePrincessesFromStock, returnPrincessesToStock)

    -- We can't replicate more than a full stack at a time because we support holdoverSlot semantics.
    if amount > 64 then
        self:outputError("Invalid argument. Cannot replicate more than a full stack at a time.")
        return false
    end

    -- Check to see if we already have enough of this species in the chest already.
    -- If so, then just re-use that and return early.
    for _, stack in ipairs(self.breeder:GetDronesInChest()) do
        if ((stack.size >= amount) and
            AnalysisUtil.IsPureBred(stack.individual, species) and
            (AnalysisUtil.NumberOfMatchingAlleles(stack.individual, "humidityTolerance", self.config.defaultHumidityTolerance) == 2) and
            (AnalysisUtil.NumberOfMatchingAlleles(stack.individual, "temperatureTolerance", self.config.defaultTemperatureTolerance) == 2) and
            ((stack.individual.active.fertility > 1) and (stack.individual.inactive.fertility > 1))
        ) then
            self.breeder:ExportDroneStacksToHoldovers({stack.slotInChest}, {amount}, {holdoverSlot})
            return true
        end
    end

    if retrievePrincessesFromStock then
        if not self.breeder:RetrieveStockPrincessesFromChest(nil, {species}) then
            self:outputError("Failed to retrieve princesses from stock chest.")
            return false
        end
    end

    -- Move starter bees to their respective chests.
    ---@diagnostic disable-next-line: missing-fields
    if not self.breeder:RetrieveDrones({species = {uid = species}}, 1) then
        self:outputError(string.format("Failed to retrieve drones with species %s.", species))
        if retrievePrincessesFromStock then
            self.breeder:ReturnActivePrincessesToStock(nil)
        end
        return false
    end

    local droneStack = self.breeder:GetStackInDroneSlot(1)
    if droneStack == nil then
        self:outputError("replicateSpecies: Drones were removed from chest between storage import and stack get.")
        if retrievePrincessesFromStock then
            self.breeder:ReturnActivePrincessesToStock(nil)
        end
        return false
    end

   if (droneStack.individual.active.fertility <= 1) and (droneStack.individual.inactive.fertility <= 1) then
        -- If the drone we want to replicate has generationally negative fertility, then don't bother replicating
        -- because we can't. Just output the drones we've got. There is already validation above for trying to specifically
        -- replicate that trait, so this isn't a mistake. Anyone using this doesn't care about the difference, then.
        if droneStack.size < amount then
            self:outputError("Unable to output drones with non-replicatable fertility.")
            return false
        end

        self.breeder:ExportDroneStacksToHoldovers({1}, {amount}, {holdoverSlot})

        return true
    end

    local finishedDroneSlot = nil
    local exportRemaining = amount
    local numberToExport = math.min(exportRemaining, 32)
    while numberToExport > 0 do
        -- Do the breeding. We start by breeding first in case we grabbed a stack that wasn't full to begin with.
        -- If the stack was already full, then Breed() will return immediately.
        local breedInfoCacheElement = {}
        local traitInfoCache = {species = {}}
        finishedDroneSlot = self:breed(
            MatchingAlgorithms.ClosestMatchToTraitsMatcher(droneStack.individual.active, self.breeder.numApiaries),
            MatchingAlgorithms.DroneStackOfSpeciesPositiveFertilityFinisher(species, droneStack.individual.active.fertility, 64),
            GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSizeCollector(species),
            function (princessStack, droneStackList)
                self:populateBreedInfoCache(princessStack, droneStackList, species, breedInfoCacheElement)
                self:populateTraitInfoCache(princessStack, droneStackList, traitInfoCache)
            end
        ).drones

        if finishedDroneSlot == nil then
            -- This should never really happen since we're starting with an absurdly high number of drones.
            -- The only way this should ever happen is if it picked an unfortunate princess that actually has
            -- a mutation with `species` and the user was also using frenzy frames (which they shouldn't do anyways).
            self:outputError(string.format("Convergence failure while replicating %s.", species))

            -- If we introduced the princesses, then we should clean then up as well.
            if retrievePrincessesFromStock then
                self.breeder:ReturnActivePrincessesToStock(nil)
            end

            -- Don't trash the drone slots in case the user is able to recover something from this.
            return false
        end

        -- Take drones away for the output and replicate the original stack back up to 64.
        numberToExport = math.min(exportRemaining, 32)
        exportRemaining = exportRemaining - numberToExport
        self.breeder:ExportDroneStacksToHoldovers({1}, {numberToExport}, {holdoverSlot})
    end

    -- Do cleanup operations.
    self.breeder:StoreDronesFromActiveChest({finishedDroneSlot})
    if returnPrincessesToStock then
        self.breeder:ReturnActivePrincessesToStock(nil)
    end

    return true
end

-- Breeds the target species from the two given parents.
-- Requires drones of each species as inputs already in the holdover chest.
-- Places finished breed output in the storage columns.
---@param node BreedPathNode
---@param retrievePrincessesFromStock boolean
---@param returnPrincessesToStock boolean
---@return boolean success
function BeekeeperBot:breedSpecies(node, retrievePrincessesFromStock, returnPrincessesToStock)
    if retrievePrincessesFromStock then
        self.breeder:RetrieveStockPrincessesFromChest(nil, {node.parent1, node.parent2})
    end

    -- Breed the target using the left-over drones from both parents.
    -- As long as the drones were properly replicated beforehand, this shouldn't
    -- require any specific princesses.

    -- Move starter bees to their respective chests.
    self.breeder:ImportHoldoverStacksToDroneChest({1, 2}, {64, 64}, {1, 2})

    local conditions = self:ensureSpecialConditionsMet(node)

    -- We will want to breed high fertility into the drones of the target species.
    local stack1 = self.breeder:GetStackInDroneSlot(1)
    local stack2 = self.breeder:GetStackInDroneSlot(2)
    if (stack1 == nil) or (stack2 == nil) then
        self:outputError("breedSpecies: Drones were removed from chest between holdover import and conditions completion.")
        return false
    end
    local maxFertilityPreExisting = math.max(
        stack1.individual.active.fertility,
        stack2.individual.active.fertility
    )

    -- Do the breeding.
    local breedInfoCacheElement = {}
    local traitInfoCache = {species = {}}
    local finishedDroneSlot = self:breed(
        MatchingAlgorithms.MutatedAlleleMatcher(
            self.breeder.numApiaries,
            "species",
            {uid = node.target},
            {humidityTolerance = self.config.defaultHumidityTolerance, temperatureTolerance = self.config.defaultTemperatureTolerance},
            breedInfoCacheElement,
            traitInfoCache
        ),
        MatchingAlgorithms.DroneStackOfSpeciesPositiveFertilityFinisher(node.target, maxFertilityPreExisting, 64),
        GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSizeCollector(node.target),
        function (princessStack, droneStackList)
            self:populateBreedInfoCache(princessStack, droneStackList, node.target, breedInfoCacheElement)
            self:populateTraitInfoCache(princessStack, droneStackList, traitInfoCache)
        end
    ).drones

    if finishedDroneSlot == nil then
        self:outputError(string.format("Error breeding '%s' from '%s' and '%s'. Retrying from parent replication.", node.target, node.parent1, node.parent2))
        self.breeder:BreakAndReturnFoundationsToInputChest()  -- Avoid double-prompting for foundations.
        return false
    end

    -- If we have enough of the target species now, then inform the server and store the drones at the new location.
    if not self.robotComms:ReportNewSpeciesToServer(node.target) then
        self:outputError(string.format("Error reporting storage location of %s to server.", node.target))
        self.breeder:BreakAndReturnFoundationsToInputChest()
        return false
    end

    self.breeder:StoreDronesFromActiveChest({finishedDroneSlot})
    if returnPrincessesToStock then
        self.breeder:ReturnActivePrincessesToStock(nil)
    end

    if conditions == "foundations placed" then
        self.breeder:BreakAndReturnFoundationsToInputChest()
    end

    return true
end

-- Breeds the target using the drones and princesses in the active chests.
---@param matchingAlgorithm Matcher
---@param finishedSlotAlgorithm StackFinisher
---@param garbageCollectionAlgorithm GarbageCollector
---@param populateCaches fun(princessStack: AnalyzedBeeStack, droneStackList: AnalyzedBeeStack[]) | nil
---@return {princess: integer | nil, drones: integer | nil}
function BeekeeperBot:breed(matchingAlgorithm, finishedSlotAlgorithm, garbageCollectionAlgorithm, populateCaches)
    -- Experimentally, convergence should happen well before 300 iterations. If we hit that many, then convergence probably failed.
    local slots = {princess = nil, drones = nil}
    local inventorySize = self.breeder:GetDroneChestSize()

    self.breeder:ToggleWorldAccelerator()
    for iteration = 1, (300 * self.breeder.numApiaries) do
        local droneStackList
        local princessStackList = {}
        while #princessStackList == 0 do
            princessStackList = self.breeder:GetPrincessesInChest()
            droneStackList = self.breeder:GetDronesInChest()

            slots = finishedSlotAlgorithm(princessStackList[1], droneStackList)
            if (slots.princess ~= nil) or (slots.drones ~= nil) then
                -- Convergence succeeded. Break out.
                -- Even after we've finished breeding, the world accelerator still speeds up remaining queens.
                -- Wait until they've finished before turning it off.
                while #(self.breeder:GetPrincessesInChest()) < self.breeder.numApiaries do
                    Sleep(5)
                end
                self.breeder:ToggleWorldAccelerator()

                Print(string.format("Finished stacks: princess = %s, drones = %s.", tostring(slots.princess), tostring(slots.drones)))
                return slots
            end

            local numEmptySlots = (inventorySize - #droneStackList)
            if numEmptySlots < 4 then  -- 4 is the highest naturally occurring fertility. TODO: Consider whether this should truly leave 8 slots.
                -- If there are not many open slots in the drone chest, then eliminate some of them to make room for newer generations.
                local slotsToRemove = garbageCollectionAlgorithm(droneStackList, 4 - numEmptySlots)
                self.breeder:TrashSlotsFromDroneChest(slotsToRemove)
            end

            if #princessStackList == 0 then
                -- Poll once every 5 seconds so that we aren't spamming. TODO: Make this configurable.
                Sleep(5)
            end
        end

        -- Not finished, but haven't failed. Continue breeding.
        if populateCaches ~= nil then
            populateCaches(princessStackList[1], droneStackList)
        end

        local droneSlot, score = matchingAlgorithm(princessStackList[1], droneStackList)
        if score ~= nil then
            Print(string.format("iteration %u", iteration))
        end

        self:shutdownOnCancel()
        self.breeder:InitiateBreeding(princessStackList[1].slotInChest, droneSlot)
    end

    while #(self.breeder:GetPrincessesInChest()) < self.breeder.numApiaries do
        Sleep(5)
    end
    self.breeder:ToggleWorldAccelerator()
    return slots
end

--- Populates `cacheElement` with any required information to allow for breeding calculations between the
--- given princess and any drone in `droneStackList`.
---@param princessStack AnalyzedBeeStack
---@param droneStackList AnalyzedBeeStack[]
---@param target string
---@param cacheElement BreedInfoCacheElement  The cache to be populated.
function BeekeeperBot:populateBreedInfoCache(princessStack, droneStackList, target, cacheElement)
    for _, droneStack in ipairs(droneStackList) do
        local mutCombos = {
            {princessStack.individual.active.species.uid, droneStack.individual.active.species.uid},
            {princessStack.individual.active.species.uid, droneStack.individual.inactive.species.uid},
            {princessStack.individual.inactive.species.uid, droneStack.individual.active.species.uid},
            {princessStack.individual.inactive.species.uid, droneStack.individual.inactive.species.uid}
        }
        for _, combo in ipairs(mutCombos) do
            cacheElement[combo[1]] = ((cacheElement[combo[1]] == nil) and {}) or cacheElement[combo[1]]
            cacheElement[combo[2]] = ((cacheElement[combo[2]] == nil) and {}) or cacheElement[combo[2]]

            if (cacheElement[combo[1]][combo[2]] == nil) or (cacheElement[combo[1]][combo[2]] == nil) then
                local breedInfo = self.robotComms:GetBreedInfoFromServer(combo[1], combo[2], target)
                if breedInfo == nil then
                    self:outputError("Unexpected error when retrieving target's breed info from server.")
                    return  -- Internal error. TODO: Handle this up the stack.
                end
                breedInfo = UnwrapNull(breedInfo)

                cacheElement[combo[1]][combo[2]] = breedInfo
                cacheElement[combo[2]][combo[1]] = breedInfo
            end
        end
    end
end

-- Populates `traitInfoCache` with any required information to allow for breeding calculations between
-- the given princess and any drone in the drone chest.
---@param princessStack AnalyzedBeeStack
---@param droneStackList AnalyzedBeeStack[]
---@param traitInfoCache TraitInfoSpecies  The cache to be populated.
function BeekeeperBot:populateTraitInfoCache(princessStack, droneStackList, traitInfoCache)
    local princessSpecies1 = princessStack.individual.active.species.uid
    local princessSpecies2 = princessStack.individual.inactive.species.uid
    if traitInfoCache[princessSpecies1] == nil then
        local dominance = self.robotComms:GetTraitInfoFromServer(princessSpecies1)
        if dominance == nil then
            return nil -- TODO: Deal with this at some point.
        end

        traitInfoCache[princessSpecies1] = dominance
    end

    if traitInfoCache[princessSpecies2] == nil then
        local dominance = self.robotComms:GetTraitInfoFromServer(princessSpecies2)
        if dominance == nil then
            return nil -- TODO: Deal with this at some point.
        end

        traitInfoCache[princessSpecies2] = dominance
    end

    for _, stack in ipairs(droneStackList) do
        local droneSpecies1 = stack.individual.active.species.uid
        local droneSpecies2 = stack.individual.inactive.species.uid
        if traitInfoCache[droneSpecies1] == nil then
            local dominance = self.robotComms:GetTraitInfoFromServer(droneSpecies1)
            if dominance == nil then
                return nil -- TODO: Deal with this at some point.
            end

            traitInfoCache[droneSpecies1] = dominance
        end
        if traitInfoCache[droneSpecies2] == nil then
            local dominance = self.robotComms:GetTraitInfoFromServer(droneSpecies2)
            if dominance == nil then
                return nil -- TODO: Deal with this at some point.
            end

            traitInfoCache[droneSpecies2] = dominance
        end
    end
end

---@param node BreedPathNode
---@return "foundations placed" | "no foundations" | nil
function BeekeeperBot:ensureSpecialConditionsMet(node)
    local placingFoundations = self:mustPlaceFoundation(node.foundation)

    -- Encase this in a loop in case the user doesn't provide the foundations correctly.
    local promptedOnce = false
    while true do
        local shouldPlaceFoundation = placingFoundations
        if shouldPlaceFoundation then
            local retval = self.breeder:PlaceFoundations(node.foundation)
            shouldPlaceFoundation = (retval == "no foundation")
        end

        if promptedOnce and (not shouldPlaceFoundation) then
            break
        end

        self.robotComms:WaitForConditionsAcknowledged(node.target, node.parent1, node.parent2, shouldPlaceFoundation)
        promptedOnce = true
    end

    if placingFoundations then
        return "foundations placed"
    else
        return "no foundations"
    end
end

---@param foundation string | nil
---@return boolean
function BeekeeperBot:mustPlaceFoundation(foundation)
    if foundation == nil then
        return false
    end

    return (
        (foundation ~= "α Centauri Bb Surface Block")  -- TODO: Verify whether this name will match correctly. It might not need to be manual.
        (foundation ~= "Aura node") and
        (foundation ~= "Ender Goo") and
        (foundation ~= "IC2 Coolant") and
        (foundation ~= "IC2 Hot Coolant") and
        (foundation ~= "Lava") and
        (foundation ~= "Short Mead") and
        (foundation ~= "Water")
    )
end

---@param errMsg string
function BeekeeperBot:outputError(errMsg)
    self.robotComms:ReportErrorToServer(errMsg)
    Print(errMsg)
end

function BeekeeperBot:shutdownOnCancel()
    if self.robotComms:PollForCancel() then
        self:shutdown(1)
    end
end

---@param code integer
function BeekeeperBot:shutdown(code)
    if self.robotComms ~= nil then
        self.robotComms:Shutdown()
    end

    ExitProgram(code)
end

return BeekeeperBot
