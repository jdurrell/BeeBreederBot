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
local MutationConditionSet = require("Shared.MutationConditionSet")
local RobotComms = require("BeekeeperBot.RobotComms")

local HOLDOVER_SLOT_WORKING_TEMPLATE = 1
local HOLDOVER_SLOT_GRAFTING_BEES = 2
local ACTIVE_SLOT_WORKING_TEMPLATE = 1
local ACTIVE_SLOT_GRAFTING_BEES = 2

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
        Print(string.format("Invalid `defaultHumidityTolerance` supplied: %s. Must be 'UP_5', 'DOWN_5',' or 'BOTH_5'.", config.defaultHumidityTolerance))
        obj:shutdown(1)
    end
    if not TableContains({"UP_5", "DOWN_5", "BOTH_5"}, config.defaultTemperatureTolerance) then
        Print(string.format("Invalid `defaultTemperatureTolerance` supplied: %s. Must be 'UP_5', 'DOWN_5',' or 'BOTH_5'.", config.defaultTemperatureTolerance))
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
        [CommLayer.MessageCode.CancelCommand] = BeekeeperBot.cancelCommandHandler,
        [CommLayer.MessageCode.ImportDroneStacksCommand] = BeekeeperBot.importDroneStacksHandler,
        [CommLayer.MessageCode.ImportPrincessesCommand] = BeekeeperBot.importPrincessesCommandHandler,
        [CommLayer.MessageCode.MakeTemplateCommand] = BeekeeperBot.makeTemplateHandler,
    }

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

        self.robotComms:ReportCommandDone(request.transactionId)
    end
end

function BeekeeperBot:cancelCommandHandler(data)
    self:shutdown(0)
end

function BeekeeperBot:importPrincessesCommandHandler(data)
    if not self.breeder:ImportPrincessesFromInputsToStock() then
        self.robotComms:ReportErrorToServer("Failed to import princesses.")
    end
end

function BeekeeperBot:importDroneStacksHandler(data)
    if not self.breeder:ImportDroneStacksFromInputsToStore() then
        self:outputError("Failed to import drones.")
    end
end

---@param data MakeTemplateCommandPayload
function BeekeeperBot:makeTemplateHandler(data)
    if data.traits == nil then
        self:outputError("Received invalid MakeTemplate payload.")
        return
    end

    if data.raw then
        Print("Processing raw breed request...")

        -- Set default tolerances. We want this even in raw mode because the acclimatiser setup cannot be avoided.
        data.traits.temperatureTolerance = ((data.traits.temperatureTolerance == nil) and self.config.defaultTemperatureTolerance) or data.traits.temperatureTolerance
        data.traits.humidityTolerance = ((data.traits.humidityTolerance == nil) and self.config.defaultHumidityTolerance) or data.traits.humidityTolerance

        -- If raw is specified, then the user is responsible for organizing everything in the proper chests.
        local slots = self:breed(
            MatchingAlgorithms.ClosestMatchToTraitsMatcher(data.traits, self.breeder.numApiaries, self.config.verbose),
            MatchingAlgorithms.DroneStackAndPrincessOfTraitsFinisher(data.traits, 64),
            GarbageCollectionPolicies.ClearDronesByFurthestAlleleMatchingCollector(data.traits),
            nil
        )

        if (slots.drones == nil) and (slots.princess == nil) then
            self:outputError("Failed to make template.")
            return
        end
    else
        Print("Processing breed request...")
        self.breeder:RefreshStorageCache()  -- TODO: Do we have enough memory for this?
        if self.breeder.storageCache:IsEmpty() then
            self:outputError("Failed to find any bees when searching for best initial trait match.")
            return
        end

        if not self:breedTraitsIntoPopulation(data.traits) then
            self:outputError("Failed to breed target traits from mutations.")
            return
        end
        Print("All required traits now in population.")

        -- No need to do a template breed if the above was enough.
        local newTargetTraits = self:computeBestTraitsFromTraitSet(self.breeder.storageCache:GetAllTraitSets())
        for trait, value in pairs(data.traits) do
            newTargetTraits[trait] = value
        end
        if self.breeder.storageCache:GetDroneEntry(newTargetTraits) == nil then
            if not self:breedTemplateFromEstablishedTraits(newTargetTraits) then
                self:outputError("Failed to breed template from established population traits.")
                return
            end
        end

        self.breeder:TrashSlotsFromDroneChest(nil)
    end

    Print(string.format("Finished making template %s.", TraitsToString(data.traits)))
end

-- Breeds the given traits into the population via mutations, if they don't already exist.
---@param targetTraits PartialAnalyzedBeeTraits
---@return boolean
function BeekeeperBot:breedTraitsIntoPopulation(targetTraits)
    -- If we don't have all of the traits, then figure out how to breed them into the storage population.
    local traitsPresent = {}
    for trait, value in pairs(targetTraits) do
        -- TODO: Eventually, create an iterator for the cache so that we don't have to run through the whole thing several times.
        traitsPresent[trait] = (self.breeder.storageCache:GetDroneEntry({[trait] = value}) ~= nil)
    end

    -- Now, actually breed those traits into the storage population, if necessary.
    for trait, value in pairs(targetTraits) do
        if traitsPresent[trait] then
            -- We already had this trait or happened to discover this trait while breeding something else.
            goto continue
        end

        ---@type TraitBreedPathResponsePayload | nil
        local path = self.robotComms:GetBreedPathForTraitFromServer(trait, value, self.breeder.storageCache:GetAllSpecies())
        if path == nil then
            self:outputError("Failed to get a valid breeding path for the requested mutation.")
            return false
        end

        Print(string.format("Breeding trait %s into the population via species '%s'.", TraitsToString({[trait] = value}), path[#(path)].target))
        for i, pathNode in ipairs(path) do
            -- Obtain the parents.
            -- Best traits to start with from the parents.
            local numSpeciesReplicate = 4 + (2 * self.breeder.numApiaries)
            local templateParent1, templateParent2 = self:computeInitialPreferredParentTraits(pathNode.parent1, pathNode.parent2)
            if not self:replicateIfNecessary(templateParent1, numSpeciesReplicate, 1) then
                self:outputError(string.format("Replicate parent 1 '%s' failed.",  pathNode.parent1))
                return false
            end
            if not self:replicateIfNecessary(templateParent2, numSpeciesReplicate, 2) then
                self:outputError(string.format("Replicate parent 2 '%s' failed.",  pathNode.parent2))
                return false
            end

            -- Set up the breeding station.
            self.breeder:ImportHoldoverStacksToActiveChest({1, 2}, {numSpeciesReplicate, numSpeciesReplicate}, {1, 2})
            local starterDrone1 = self.breeder:GetStackInDroneSlot(1)
            local starterDrone2 = self.breeder:GetStackInDroneSlot(2)
            if (starterDrone1 == nil) or (starterDrone2 == nil) then
                self:outputError("Parents disappeared from drone chest.")
                return false
            end

            -- Only try to breed for the trait if we are the last node (i.e. the one that can actually get that trait).
            -- Otherwise, breed for species so that we can build up the tree to get the last node.
            local mutationTrait = ((i == #pathNode) and value) or "species"
            local mutationValue = ((i == #pathNode) and targetTraits[value]) or {uid=pathNode.target}
            local adjustedMutationTraits, adjustedPreferredTraits = self:computeAdjustedMutationAndPreferredTraits(
                {[mutationTrait]=mutationValue}, 1, 2, pathNode.target
            )
            if (adjustedMutationTraits == nil) or (adjustedPreferredTraits == nil) then
                return false
            end

            self:ensureSpecialConditionsMet(pathNode)
            local droneStack = self:breedNewTrait(pathNode, adjustedMutationTraits, adjustedPreferredTraits)
            if (MutationConditionSet.FoundationIsPlaceableBlock(pathNode.conditions)) then
                self.breeder:BreakAndReturnFoundationsToInputChest()
            end
            if droneStack == nil then
                return false
            end
            self.breeder:ExportDroneStacksToHoldovers({droneStack.slotInChest}, {16}, {HOLDOVER_SLOT_WORKING_TEMPLATE})

            -- TODO: We probably don't necessarily need to return everything if this result will be used next in the breeding path.
            ---@type integer[]
            local stacksToReturn = {}
            for slot, starterDrone in ipairs({starterDrone1, starterDrone2}) do
                local stackAfter = self.breeder:GetStackInDroneSlot(slot)
                if (stackAfter ~= nil) and AnalysisUtil.AllBeeTraitsEqual(stackAfter.individual, starterDrone.individual.active) then
                    table.insert(stacksToReturn, slot)
                end
            end
            self.breeder:StoreDronesFromActiveChest(stacksToReturn)

            -- We have the new mutations, and we have all of the "best" alleles from the *parents*. Check if we have all of the best
            -- alleles from the *population*, too.
            local bestTraits = self:computeBestTraitsFromTraitSet(self.breeder.storageCache:GetAllTraitSets())
            for trait2, value2 in pairs(adjustedMutationTraits) do
                -- Override something we are specifically getting from the mutation.
                bestTraits[trait2] = value2
            end
            self:breedTemplate(droneStack.individual.active, bestTraits)
        end

        ::continue::
    end

    return true
end

---@param parent1 string
---@param parent2 string
---@return PartialAnalyzedBeeTraits, PartialAnalyzedBeeTraits
function BeekeeperBot:computeInitialPreferredParentTraits(parent1, parent2)
    local parentTraits = {}

    for i, v in ipairs({parent1, parent2}) do
        ---@type AnalyzedBeeTraits[]
        local traitSetForSpecies = {}
        for i2, v2 in ipairs(self.breeder.storageCache.cache) do
            if v2.traits.species.uid == v then
                table.insert(traitSetForSpecies, v2.traits)
            end
        end

        -- Find trait set for this species that has the most of the best traits.
        local idealTraits = self:computeBestTraitsFromTraitSet(traitSetForSpecies)
        parentTraits[i] = TableMax(traitSetForSpecies, function (_, item)
            return TableCount(idealTraits, function (trait, value)
                return AnalysisUtil.TraitIsEqual(item, trait, value)
            end)
        end)
    end

    return parentTraits[1], parentTraits[2]
end

---@param targetMutationTraits PartialAnalyzedBeeTraits
---@param parent1Slot integer
---@param parent2Slot integer
---@param targetSpecies string
---@return PartialAnalyzedBeeTraits | nil, PartialAnalyzedBeeTraits | nil
function BeekeeperBot:computeAdjustedMutationAndPreferredTraits(targetMutationTraits, parent1Slot, parent2Slot, targetSpecies)
    local adjustedPreferredTraits = self:computeAdjustedPreferredTraits(targetMutationTraits, parent1Slot, parent2Slot)
    if adjustedPreferredTraits == nil then
        return nil, nil
    end

    local payload = self.robotComms:GetDefaultGenomeFromServer(targetSpecies)
    if payload == nil then
        self:outputError(string.format("Failed to get default genome from server for species '%s'", targetSpecies))
        return nil, nil
    end
    local defaultGenome = payload.traits

    -- Note that the caller might not be looking for species (since it is faster to avoid it when only looking for a particular trait).
    -- Copy the (possibly nil) value here instead of using targetSpecies directly in order to maintain that.
    local adjustedTargetMutationTraits = Copy(targetMutationTraits)

    -- If a given trait is a new target, then it will not appear in the preferred traits. Therefore, we only need to check for new "best"
    -- alleles that are not already given to us as a target, but will happen to newly appear in the target species' default mutation genome.
    -- Additionally, if a new best allele exists in the default genome, then we may need to override a worse allele for the same trait.
    -- However, if a "best" trait *does* already exist in the parents, then don't add it to the mutation traits to avoid higher dependency
    -- on the mutation.
    if (adjustedPreferredTraits.caveDwelling == nil) and defaultGenome.caveDwelling then
        adjustedTargetMutationTraits.caveDwelling = true
    end
    if (adjustedPreferredTraits.effect == nil) and (defaultGenome.effect == "forestry.allele.effect.none") then
        adjustedTargetMutationTraits.effect = "forestry.allele.effect.none"
    end
    if (adjustedPreferredTraits.fertility ~= nil) and (defaultGenome.fertility > adjustedPreferredTraits.fertility) then
        adjustedTargetMutationTraits.fertility = defaultGenome.fertility
        adjustedPreferredTraits.fertility = nil
    end
    if (targetMutationTraits.flowering ~= nil) and (defaultGenome.flowering < adjustedPreferredTraits.flowering) then
        adjustedTargetMutationTraits.flowering = defaultGenome.flowering
        adjustedPreferredTraits.flowering = nil
    end
    if (adjustedPreferredTraits.flowerProvider == nil) and (defaultGenome.flowerProvider == "flowersVanilla") then
        adjustedTargetMutationTraits.flowerProvider = "flowersVanilla"
    end
    if (adjustedPreferredTraits.lifespan ~= nil) and (defaultGenome.lifespan < adjustedPreferredTraits.lifespan) then
        adjustedTargetMutationTraits.lifespan = defaultGenome.lifespan
        adjustedPreferredTraits.lifespan = nil
    end
    if (adjustedPreferredTraits.nocturnal == nil) and defaultGenome.nocturnal then
        adjustedTargetMutationTraits.nocturnal = true
    end
    if (adjustedPreferredTraits.speed ~= nil) and (defaultGenome.speed > adjustedPreferredTraits.speed) then
        adjustedTargetMutationTraits.speed = defaultGenome.speed
        adjustedPreferredTraits.speed = nil
    end
    if (adjustedPreferredTraits.territory ~= nil) and (defaultGenome.territory[1] < adjustedPreferredTraits.territory[1]) then
        adjustedTargetMutationTraits.territory = defaultGenome.territory
        adjustedPreferredTraits.territory = nil
    end
    if (targetMutationTraits.tolerantFlyer == nil) and (defaultGenome.tolerantFlyer) then
        adjustedTargetMutationTraits.tolerantFlyer = true
    end

    return adjustedTargetMutationTraits, adjustedPreferredTraits
end

---@param targetTraits PartialAnalyzedBeeTraits
---@param parent1Slot integer
---@param parent2Slot integer
---@return PartialAnalyzedBeeTraits | nil
function BeekeeperBot:computeAdjustedPreferredTraits(targetTraits, parent1Slot, parent2Slot)
    local parent1Traits = self.breeder:GetStackInDroneSlot(parent1Slot)
    local parent2Traits = self.breeder:GetStackInDroneSlot(parent2Slot)
    if (parent1Traits == nil) or (parent2Traits == nil) then
        self:outputError("Failed to get starting parent genomes from drone chest.")
        return nil
    end

    ---@type PartialAnalyzedBeeTraits
    local adjustedPreferredTraits = self:computeBestTraitsFromTraitSet({parent1Traits.individual.active, parent2Traits.individual.active})

    -- Wipe out anything that is specifically selected for as a target.
    for trait, value in pairs(targetTraits) do
        adjustedPreferredTraits[trait] = nil
    end

    return adjustedPreferredTraits
end

---@param traitSet AnalyzedBeeTraits[]
---@return PartialAnalyzedBeeTraits
function BeekeeperBot:computeBestTraitsFromTraitSet(traitSet)
    local preferredSet = {}

    if TableHasCondition(traitSet, function (_, item)
        return item.caveDwelling
    end) then
        preferredSet.caveDwelling = true
    end

    if TableHasCondition(traitSet, function (_, item)
        return item.effect == "forestry.allele.effect.none"
    end) then
        preferredSet.effect = "forestry.allele.effect.none"
    end

    preferredSet.fertility = TableMax(traitSet, function (_, item)
        return item.fertility
    end).fertility

    preferredSet.flowering = TableMin(traitSet, function (_, item)
        return item.flowering
    end).flowering

    if TableHasCondition(traitSet, function (_, item)
        return item.flowerProvider == "flowersVanilla"
    end) then
        preferredSet.flowerProvider = "flowersVanilla"
    end

    preferredSet.humidityTolerance = self.config.defaultHumidityTolerance

    preferredSet.lifespan = TableMin(traitSet, function (_, item)
        return item.lifespan
    end).lifespan

    if (TableHasCondition(traitSet, function (_, item)
        return item.nocturnal
    end)) then
        preferredSet.nocturnal = true
    end

    preferredSet.speed = TableMax(traitSet, function (_, item)
        return item.speed
    end).speed

    preferredSet.temperatureTolerance = self.config.defaultTemperatureTolerance

    preferredSet.territory = TableMin(traitSet, function (_, item)
        return item.territory[1]
    end).territory

    if (TableHasCondition(traitSet, function (_, item)
        return item.tolerantFlyer
    end)) then
        preferredSet.tolerantFlyer = true
    end

    return preferredSet
end

---@param targetTraits PartialAnalyzedBeeTraits
---@return AnalyzedBeeTraits
function BeekeeperBot:computeMaxMatchingTraitSet(targetTraits)
    return TableMax(self.breeder.storageCache.cache, function (_, item)
        return TableCount(targetTraits, function(trait, value)
            return AnalysisUtil.TraitIsEqual(item.traits, trait, value)
        end)
    end)
end

---@param pathNode BreedPathNode
---@param mutationTraits PartialAnalyzedBeeTraits
---@param preferredTraits PartialAnalyzedBeeTraits
---@return AnalyzedBeeStack | nil
function BeekeeperBot:breedNewTrait(pathNode, mutationTraits, preferredTraits)
    local fullTargetTraits = Copy(mutationTraits)
    for trait, value in pairs(preferredTraits) do
        fullTargetTraits[trait] = value
    end

    -- Do the breeding.
    -- Only try to breed for the trait if we are the last node (i.e. the one that can actually get that trait).
    -- Otherwise, breed for species so that we can build up the tree to get the last node.
    self.breeder:RetrieveStockPrincessesFromChest(nil, {})
    local breedInfoCache = {}
    local traitInfoCache = {species={}}
    local finishedDroneSlot = self:breed(
        MatchingAlgorithms.MutatedAlleleMatcher(
            self.breeder.numApiaries,
            mutationTraits,
            preferredTraits,
            breedInfoCache,
            traitInfoCache,
            self.config.verbose
        ),
        MatchingAlgorithms.DroneStackAndPrincessOfTraitsFinisher(fullTargetTraits, 16),
        GarbageCollectionPolicies.ClearDronesByFurthestAlleleMatchingCollector(fullTargetTraits),
        function (princessStack, droneStackList)
            self:populateBreedInfoCache(princessStack, droneStackList, pathNode.target, breedInfoCache)
            self:populateTraitInfoCache(princessStack, droneStackList, traitInfoCache)
        end
    ).drones

    if finishedDroneSlot == nil then
        self:outputError(string.format("Error breeding '%s' from '%s' and '%s'. Retrying from parent replication.", pathNode.target, pathNode.parent1, pathNode.parent2))
        self.breeder:ReturnActivePrincessesToStock(nil)
        return nil
    end

    -- If we have enough of the target species now, then store the drones at the new location.
    -- Technically, we only require the finished stack to have the desired trait, which doesn't require it to be the "target" species.
    local droneStack = self.breeder:GetStackInDroneSlot(finishedDroneSlot)
    if droneStack == nil then
        self:outputError("Expected finished drone to be in the slot.")
        self.breeder:ReturnActivePrincessesToStock(nil)
        return nil
    end

    self.breeder:ReturnActivePrincessesToStock(nil)
    return droneStack
end

-- Breeds a template bee from traits that already exist in the population.
---@param targetTraits PartialAnalyzedBeeTraits
---@return boolean
function BeekeeperBot:breedTemplateFromEstablishedTraits(targetTraits)
    -- Look for existing bees that are the closest match to the target template since they will be the best starting point.
    local maxStartingTraitSet = self:computeMaxMatchingTraitSet(targetTraits)

    -- Get drones that have the initial best starting traits.
    Print(string.format("Starting with best trait set %s.", TraitsToString(maxStartingTraitSet)))
    local numTraitReplicate = 4 + (2 * self.breeder.numApiaries)
    if not self:replicateIfNecessary(maxStartingTraitSet, numTraitReplicate, HOLDOVER_SLOT_WORKING_TEMPLATE) then
        self:outputError("Failed to replicate starting template.")
        return false
    end

    return self:breedTemplate(maxStartingTraitSet, targetTraits)
end

---@param workingTemplateTraits AnalyzedBeeTraits
---@param requiredTraits PartialAnalyzedBeeTraits
---@return boolean
function BeekeeperBot:breedTemplate(workingTemplateTraits, requiredTraits)
    local finishedTraits = {}
    for trait, value in pairs(requiredTraits) do
        if AnalysisUtil.TraitIsEqual(workingTemplateTraits, trait, value) then
            finishedTraits[trait] = value
        end
    end

    -- Add traits into the starting template one at a time.
    for trait, value in pairs(requiredTraits) do
        if finishedTraits[trait] ~= nil then
            -- We only need to breed in traits that we haven't finished with yet.
            Print(string.format("Trait %s is already present in the working template.", TraitsToString({[trait] = value})))
            goto continue
        end

        -- For subsequent parents, get the best trait set that fills in the gaps of the working template.
        local maxRemainingTraitSet = TableMax(self.breeder.storageCache.cache, function (_, item)
            return TableCount(requiredTraits, function (trait2, value2)
                return (finishedTraits[trait2] == nil) and AnalysisUtil.TraitIsEqual(item.traits, trait2, value2)
            end)
        end)
        local nextTraits = Copy(finishedTraits)
        for trait2, value2 in pairs(requiredTraits) do
            if AnalysisUtil.TraitIsEqual(maxRemainingTraitSet, trait2, value2) then
                nextTraits[trait2] = value2
            end
        end

        -- Get 16 drones that have the requested trait.
        local numTraitReplicate = 4 + (2 * self.breeder.numApiaries)
        Print(string.format("Replicating stack with traits %s.", TraitsToString(maxRemainingTraitSet)))
        if not self:replicateIfNecessary(maxRemainingTraitSet, numTraitReplicate, HOLDOVER_SLOT_GRAFTING_BEES) then
            self:outputError("Failed to replicate template of new trait.")
            return false
        end

        -- Now breed the desired traits into the working template.
        Print(string.format("Adding trait %s into the working template.", TraitsToString({[trait] = value})))
        self.breeder:ImportHoldoverStacksToActiveChest(
            {HOLDOVER_SLOT_WORKING_TEMPLATE, HOLDOVER_SLOT_GRAFTING_BEES},
            {numTraitReplicate, numTraitReplicate},
            {ACTIVE_SLOT_WORKING_TEMPLATE, ACTIVE_SLOT_GRAFTING_BEES}
        )
        local currentWorkingTemplate = self.breeder:GetStackInDroneSlot(ACTIVE_SLOT_WORKING_TEMPLATE)
        local starterStackBefore = self.breeder:GetStackInDroneSlot(ACTIVE_SLOT_GRAFTING_BEES)
        if (currentWorkingTemplate == nil) or (starterStackBefore == nil) then
            self:outputError("Drones were removed from chest between holdover import and breeding start.")
            return false
        end

        if not self.breeder:RetrieveStockPrincessesFromChest(nil, {
            currentWorkingTemplate.individual.active.species.uid,
            starterStackBefore.individual.active.species.uid,
        }) then
            self:outputError("Failed to retrieve princesses from stock chest.")
            return false
        end

        local finishedSlots = self:breed(
            MatchingAlgorithms.ClosestMatchToTraitsMatcher(nextTraits, self.breeder.numApiaries, self.config.verbose),
            MatchingAlgorithms.DroneStackAndPrincessOfTraitsFinisher(nextTraits, 16),
            GarbageCollectionPolicies.ClearDronesByFurthestAlleleMatchingCollector(nextTraits),
            nil
        )
        self.breeder:ReturnActivePrincessesToStock(nil)
        if (finishedSlots.drones == nil) or (finishedSlots.princess == nil) then
            self:outputError(string.format("Failed to breed trait '%s' into the template.", trait))
            return false
        end

        -- We now have a princess and full drone stack of the template with this trait added in.
        -- Update the finished traits. We only tried for `trait`, but we might have added others by luck.
        local newTraits = self.breeder:GetStackInDroneSlot(finishedSlots.drones).individual.active
        for newTrait, _ in pairs(newTraits) do
            if ((finishedTraits[newTrait] == nil) and
                (requiredTraits[newTrait] ~= nil) and
                AnalysisUtil.TraitIsEqual(newTraits, newTrait, requiredTraits[newTrait])
            ) then
                finishedTraits[newTrait] = requiredTraits[newTrait]
            end
        end

        -- Cleanup. Export the new drones to holdovers and return the starter drones (if any still remain) to the storage row.
        self.breeder:ExportDroneStacksToHoldovers({finishedSlots.drones}, {16}, {HOLDOVER_SLOT_WORKING_TEMPLATE})
        local slotsToReturn = {}
        local workingTemplateAfter = self.breeder:GetStackInDroneSlot(ACTIVE_SLOT_WORKING_TEMPLATE)
        if ((workingTemplateAfter ~= nil) and
            AnalysisUtil.AllTraitsPure(workingTemplateAfter.individual) and
            (self.breeder.storageCache:GetDroneEntry(workingTemplateAfter.individual.active) ~= nil)
        ) then
            -- "Working template" might actually just be some drones directly from the storage, especially if this is the first iteration.
            table.insert(slotsToReturn, ACTIVE_SLOT_WORKING_TEMPLATE)
        end
        local starterStackAfter = self.breeder:GetStackInDroneSlot(ACTIVE_SLOT_GRAFTING_BEES)
        if (starterStackAfter ~= nil) and (AnalysisUtil.AllBeeTraitsEqual(starterStackAfter.individual, starterStackBefore.individual.active)) then
            table.insert(slotsToReturn, ACTIVE_SLOT_GRAFTING_BEES)
        end
        self.breeder:StoreDronesFromActiveChest(slotsToReturn)

        ::continue::
    end

    -- Final drone stack is in the holdover chest, but we only have 16. Breed it up to 64 to finish it off, then store it.
    Print("Working template finished. Breeding template up to full stack.")
    self.breeder:ImportHoldoverStacksToActiveChest({HOLDOVER_SLOT_WORKING_TEMPLATE}, {16}, {ACTIVE_SLOT_WORKING_TEMPLATE})
    local droneStack = self.breeder:GetStackInDroneSlot(ACTIVE_SLOT_WORKING_TEMPLATE)
    if droneStack == nil then
        self:outputError("Failed to get drones from chest after importing.")
        return false
    end
    self.breeder:RetrieveStockPrincessesFromChest(nil, {droneStack.individual.active.species.uid})
    local finishedDrones = self:breed(
        MatchingAlgorithms.ClosestMatchToTraitsMatcher(requiredTraits, self.breeder.numApiaries, self.config.verbose),
        MatchingAlgorithms.DroneStackAndPrincessOfTraitsFinisher(requiredTraits, 64),
        GarbageCollectionPolicies.ClearDronesByFurthestAlleleMatchingCollector(requiredTraits),
        nil
    ).drones
    self.breeder:ReturnActivePrincessesToStock(nil)

    if finishedDrones == nil then
        self:outputError("Failed to breed final template up to 64.")
        return false
    end
    self.breeder:StoreDronesFromActiveChest({finishedDrones})

    return true
end

-- Replicates the drone with the given traits and puts it in the specified holdover chest slot.
-- If we already have enough of the drone to maintain its levels safely, then we will just retrieve that amount.
---@param traits AnalyzedBeeTraits | PartialAnalyzedBeeTraits
---@param amount integer
---@param holdoverSlot integer
---@return boolean
function BeekeeperBot:replicateIfNecessary(traits, amount, holdoverSlot)
    local cacheEntry = self.breeder.storageCache:GetDroneEntry(traits)
    if cacheEntry == nil then
        -- We should have already confirmed that the drone is in the cache by this point.
        self:outputError(string.format("Replicator failed to find cache entry for drone with traits %s.", TraitsToString(traits)))
        return false
    end

    if cacheEntry.stackSize - amount >= 16 then
        Print(string.format("Drone stack size sufficient. Skipping replication of trait pattern %s", TraitsToString(traits)))
        self.breeder:RetrieveDroneStacksToHoldovers({{entry=cacheEntry, amount=amount, destinationChestSlot=holdoverSlot}})
        return true
    end

    Print(string.format("Drone stack size insufficient. Replicating trait pettern %s", TraitsToString(traits)))
    return self:replicateTemplate(traits, amount, holdoverSlot, cacheEntry, true, true)
end

-- Replicates the given template from pure-bred drones and a pure-bred princess of that template.
-- Requires drones and princess to already be in the active chests.
-- Places drone outputs in the holdover chest.
---@param traits PartialAnalyzedBeeTraits | AnalyzedBeeTraits
---@param amount integer
---@param holdoverDroneSlot integer
---@param cacheEntry StorageCacheEntry
---@param retrievePrincessesFromStock boolean
---@param returnPrincessesToStock boolean
---@return boolean
function BeekeeperBot:replicateTemplate(traits, amount, holdoverDroneSlot, cacheEntry, retrievePrincessesFromStock, returnPrincessesToStock)
    -- We can't replicate more than a full stack at a time because we support holdoverSlot semantics.
    if amount > 64 then
        self:outputError("Invalid argument. Cannot replicate more than a full stack at a time.")
        return false
    end

    if (traits.fertility ~= nil) and (traits.fertility <= 1) then
        self:outputError("invalid argument. Cannot replicate drones with 1 or lower fertility.")
        return false
    end

    -- Retrieve the princesses.
    if retrievePrincessesFromStock then
        if not self.breeder:RetrieveStockPrincessesFromChest(nil, {traits.species.uid}) then
            self:outputError("Failed to retrieve princesses from stock chest.")
            return false
        end
    end

    -- Retrieve the starter drones.
    self.breeder:RetrieveDronesToActive({{entry=cacheEntry, amount=amount, destinationChestSlot=1}})

    local stack = self.breeder:GetStackInDroneSlot(1)
    if stack == nil then
        self:outputError(string.format("Drones not found in chest after retrieval."))
        if retrievePrincessesFromStock then
            self.breeder:ReturnActivePrincessesToStock(nil)
        end
        return false
    end

    if (stack.individual.active.fertility == 1) and (stack.individual.inactive.fertility == 1) then
        -- If the drone we want to replicate has generationally negative fertility, then don't bother replicating
        -- because we can't. Just output the drones we've got. There is already validation above for trying to specifically
        -- replicate that trait, so this isn't a mistake. Anyone using this doesn't care about the difference, then.
        if stack.size < amount then
            self:outputError("Unable to output drones with non-replicateable fertility.")
            return false
        end

        self.breeder:ExportDroneStacksToHoldovers({1}, {amount}, {holdoverDroneSlot})

        return true
    end

    -- Choose a higher-than-1 fertility to replicate, if we need to.
    local replicateTraits = Copy(traits)
    replicateTraits.fertility = ((replicateTraits.fertility == nil) and math.max(stack.individual.active.fertility, stack.individual.inactive.fertility))
        or replicateTraits.fertility

    local finishedSlots = {drones = nil, princess = nil}
    local exportRemaining = amount
    local numberToExport = math.min(exportRemaining, 32)
    while numberToExport > 0 do
        -- Do the breeding. We start by breeding first in case we grabbed a stack that wasn't full to begin with.
        -- If the stack was already full, then Breed() will return immediately.
        finishedSlots = self:breed(
            MatchingAlgorithms.ClosestMatchToTraitsMatcher(replicateTraits, self.breeder.numApiaries, self.config.verbose),
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
            return false
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
        local princessStackList = {}  ---@type AnalyzedBeeStack[]
        while #princessStackList == 0 do
            princessStackList = self.breeder:GetPrincessesInChest()
            if #princessStackList == 0 then
                -- Poll once every 5 seconds so that we aren't spamming. TODO: Make this configurable.
                Sleep(5)
            end
        end

        local droneStackList = self.breeder:GetDronesInChest()

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

--- Populates `cache` with any required information to allow for breeding calculations between the
--- given princess and any drone in `droneStackList`.
---@param princessStack AnalyzedBeeStack
---@param droneStackList AnalyzedBeeStack[]
---@param target string
---@param cache BreedInfoCache  The cache to be populated.
function BeekeeperBot:populateBreedInfoCache(princessStack, droneStackList, target, cache)
    for _, droneStack in ipairs(droneStackList) do
        local mutCombos = {
            {princessStack.individual.active.species.uid, droneStack.individual.active.species.uid},
            {princessStack.individual.active.species.uid, droneStack.individual.inactive.species.uid},
            {princessStack.individual.inactive.species.uid, droneStack.individual.active.species.uid},
            {princessStack.individual.inactive.species.uid, droneStack.individual.inactive.species.uid}
        }
        for _, combo in ipairs(mutCombos) do
            cache[combo[1]] = ((cache[combo[1]] == nil) and {}) or cache[combo[1]]
            cache[combo[2]] = ((cache[combo[2]] == nil) and {}) or cache[combo[2]]

            if (cache[combo[1]][combo[2]] == nil) or (cache[combo[2]][combo[1]] == nil) then
                local breedInfo = self.robotComms:GetBreedInfoFromServer(combo[1], combo[2], target)
                if breedInfo == nil then
                    self:outputError("Unexpected error when retrieving target's breed info from server.")
                    return  -- Internal error. TODO: Handle this up the stack.
                end
                breedInfo = UnwrapNull(breedInfo)

                cache[combo[1]][combo[2]] = breedInfo
                cache[combo[2]][combo[1]] = breedInfo
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
function BeekeeperBot:ensureSpecialConditionsMet(node)
    if (MutationConditionSet.IsTrivialConditions(node.conditions)) then
        return
    end

    -- Encase this in a loop in case the user doesn't provide the foundations correctly.
    local placingFoundations = MutationConditionSet.FoundationIsPlaceableBlock(node.conditions)
    local promptedOnce = false
    while true do
        local shouldPlaceFoundation = placingFoundations
        if shouldPlaceFoundation then
            local retval = self.breeder:PlaceFoundations(node.conditions.foundation)
            shouldPlaceFoundation = (retval == "no foundation")
        end

        if promptedOnce and (not shouldPlaceFoundation) then
            break
        end

        self.robotComms:WaitForConditionsAcknowledged(node)
        promptedOnce = true
    end
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
