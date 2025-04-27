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

    local robotComms = RobotComms:Create(componentLib, eventLib, serialLib, config.serverAddr, config.port)
    if robotComms == nil then
        Print("Failed to initialize RobotComms during BeekeeperBot initialization.")
        obj:Shutdown(1)
    end
    obj.robotComms = UnwrapNull(robotComms)

    local breeder = BreederOperation:Create(componentLib, robotLib, sidesLib, config.apiaries)
    if breeder == nil then
        Print("Failed to initialize breeding operator during BeekeeperBot initialization.")
        obj:Shutdown(1)
    end
    obj.breeder = UnwrapNull(breeder)

    obj.messageHandlerTable = {
        [CommLayer.MessageCode.BreedCommand] = BeekeeperBot.BreedCommandHandler,
        [CommLayer.MessageCode.CancelCommand] = BeekeeperBot.CancelCommandHandler,
        [CommLayer.MessageCode.ImportDroneStacksCommand] = BeekeeperBot.ImportDroneStacksHandler,
        [CommLayer.MessageCode.ImportPrincessesCommand] = BeekeeperBot.ImportPrincessesCommandHandler,
        [CommLayer.MessageCode.MakeTemplateCommand] = BeekeeperBot.MakeTemplateHandler,
        [CommLayer.MessageCode.ReplicateCommand] = BeekeeperBot.ReplicateCommandHandler
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
            self:OutputError("Received unrecognized code: " .. request.code .. ".")
        else
            self.messageHandlerTable[request.code](self, request.payload)
        end
    end
end

function BeekeeperBot:CancelCommandHandler(data)
    self:Shutdown(0)
end

---@param data ReplicateCommandPayload
function BeekeeperBot:ReplicateCommandHandler(data)
    if (data == nil) or (data.species == nil) then
        return
    end

    if not self:ReplicateSpecies(data.species, true, true, 64, 1) then
        self:OutputError(string.format("Failed to replicate species '%s'.", data.species))
    end

    self.breeder:TrashSlotsFromDroneChest(nil)
    self.breeder:ImportHoldoverStacksToDroneChest({1}, {64}, {1})
    self.breeder:ExportDroneStackToOutput(1, 64)
end

function BeekeeperBot:ImportPrincessesCommandHandler(data)
    if not self.breeder:ImportPrincessesFromInputsToStock() then
        self.robotComms:ReportErrorToServer("Failed to import princesses")
    end
end

function BeekeeperBot:ImportDroneStacksHandler(data)
    local speciesSet = self.breeder:ImportDroneStacksFromInputsToStore()

    if speciesSet == nil then
        self:OutputError("Failed to import drones.")
    else
        for spec, _ in pairs(speciesSet) do
            self.robotComms:ReportNewSpeciesToServer(spec)
        end
    end
end

---@param data BreedCommandPayload
function BeekeeperBot:BreedCommandHandler(data)
    if data == nil then
        return
    end

    local breedPath = data

    -- Breed the commanded species based on the given path.
    for _, v in ipairs(breedPath) do
        ::restart::
        if v.parent1 ~= nil then
            Print(string.format("Replicating %s.", v.parent1))
            if not self:ReplicateSpecies(v.parent1, true, true, 8, 1) then
                self:OutputError("Fatal error: Replicate species '" .. v.parent1 .. "' failed.")
                self:Shutdown(1)
            end
        end

        if v.parent2 ~= nil then
            Print(string.format("Replicating %s.", v.parent2))
            if not self:ReplicateSpecies(v.parent2, true, false, 8, 2) then
                self:OutputError("Fatal error: Replicate species '" .. v.parent2 .. "' failed.")
                self:Shutdown(1)
            end
        end

        Print(string.format("Breeding %s from %s and %s.", v.target, v.parent1, v.parent2))
        local retval = self:BreedSpecies(v, false, true)
        if retval == nil then
            self:OutputError(string.format("Fatal error: Breeding species '%s' from '%s' and '%s' failed.", v.target, v.parent1, v.parent2))
            self:Shutdown(1)
        elseif not retval then
            -- If the breeding the new mutation didn't converge, then we have to restart from replicating the parents.
            self.breeder:TrashSlotsFromDroneChest(nil)
            self.breeder:ReturnActivePrincessesToStock(nil)
            goto restart
        end

        self.breeder:TrashSlotsFromDroneChest(nil)
    end
end

---@param data MakeTemplatePayload
function BeekeeperBot:MakeTemplateHandler(data)
    if data.traits == nil then
        self:OutputError("Received invalid MakeTemplate payload.")
        return
    end

    if not self:MakeTemplate(data.traits) then
        self:OutputError("Failed to make template.")
        return
    end

    Print(string.format("Finished making template %s.", TraitsToString(data.traits)))
    self.breeder:TrashSlotsFromDroneChest(nil)
end

---@param data PropagateTemplatePayload
function BeekeeperBot:PropagateTemplateHandler(data)
    if (data == nil) or (data.traits == nil) or (data.traits.species == nil) or (data.traits.species.uid == nil) then
        self:OutputError("Received invalid PropagateTemplate payload.")
        return
    end

    if not self:PropagateTemplate(data.traits) then
        self:OutputError("Failed to propagate remplate.")
        return
    end

    Print(string.format("Finished propagating template to species %s.", data.traits.species.uid))
    self.breeder:TrashSlotsFromDroneChest(nil)
end

---@param targetTraits PartialAnalyzedBeeTraits
---@return boolean
function BeekeeperBot:MakeTemplate(targetTraits)
    local beeTraitSets = self.breeder:ScanAllDroneStacks()  -- TODO: Do we have enough memory for this?
    if (beeTraitSets == nil) or (#beeTraitSets == 0) then
        self:OutputError("Failed to find any bees when searching for best initial trait match.")
        return false
    end

    -- If we don't actually have all of the traits, then figure out how to breed them into the storage population.
    local traitPaths = {}  ---@type {trait: string, path: BreedPathNode[]}[]
    for trait, value in pairs(targetTraits) do
        local traitExisting = false
        for _, v  in ipairs(beeTraitSets) do
            if AnalysisUtil.TraitIsEqual(v, trait, value) then
                traitExisting = true
                break
            end
        end

        if not traitExisting then
            -- If we don't have the trait already, then check with the server whether we are able to breed that trait.
            ---@type TraitBreedPathResponsePayload | nil
            local path = self.robotComms:GetBreedPathForTraitFromServer(trait, value)
            if path == nil then
                self:OutputError("Failed to get a valid breeding for the requested mutation.")
                return false
            end

            table.insert(traitPaths, {trait = trait, path = path})
        end
    end

    -- Now, actually breed those traits into the storage population, if necessary.
    local bredNew = false
    for _, v in ipairs(traitPaths) do
        bredNew = true

        Print(string.format("Breeding trait %s into the population via species '%s'.",
            TraitsToString({[v.trait] = targetTraits[v.trait]}),
            v.path[#(v.path)].target
        ))
        for _, pathNode in ipairs(v.path) do
            if not self:ReplicateSpecies(pathNode.parent1, true, true, 8, 1) then
                self:OutputError(string.format("Replicate parent 1 '%s' failed.",  pathNode.parent1))
                return false
            end

            if not self:ReplicateSpecies(pathNode.parent2, true, false, 8, 2) then
                self:OutputError(string.format("Replicate parent 2 '%s' failed.",  pathNode.parent2))
                return false
            end

            -- Set up the breeding station.
            self.breeder:ImportHoldoverStacksToDroneChest({1, 2}, {8, 8}, {1, 2})
            self:EnsureSpecialConditionsMet(pathNode)

            -- We will certainly want to breed high fertility into the drones of the target species.
            local stack1 = self.breeder:GetStackInDroneSlot(1)
            local stack2 = self.breeder:GetStackInDroneSlot(2)
            if (stack1 == nil) or (stack2 == nil) then
                self:OutputError("Drones were removed from chest between holdover import and conditions completion.")
                return false
            end
            local maxFertilityPreExisting = math.max(
                stack1.individual.active.fertility,
                stack2.individual.active.fertility
            )

            -- Do the breeding.
            local breedInfoCacheElement = {}
            local traitInfoCache = {species = {}}
            local finishedDroneSlot = self:Breed(
                MatchingAlgorithms.HighFertilityAndAllelesMatcher(maxFertilityPreExisting, v.trait, targetTraits[v.trait], breedInfoCacheElement, traitInfoCache),
                MatchingAlgorithms.DroneStackOfSpeciesPositiveFertilityFinisher(pathNode.target, maxFertilityPreExisting, 64),
                GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSizeCollector(pathNode.target),
                function (princessStack, droneStackList)
                    self:PopulateBreedInfoCache(princessStack, droneStackList, pathNode.target, breedInfoCacheElement)
                    self:PopulateTraitInfoCache(princessStack, droneStackList, traitInfoCache)
                end
            ).drones

            if finishedDroneSlot == nil then
                self:OutputError(string.format("Error breeding '%s' from '%s' and '%s'. Retrying from parent replication.", pathNode.target, pathNode.parent1, pathNode.parent2))
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

    -- Refresh our view of the bees if necessary.
    if bredNew then
        beeTraitSets = self.breeder:ScanAllDroneStacks()
    end
    if (beeTraitSets == nil) or (#beeTraitSets == 0) then
        self:OutputError("Failed to find any bees when searching for best initial trait match.")
        return false
    end

    -- Look for existing bees that are the closest match to the target template since they will be the best starting point.
    local maxTraitSet = beeTraitSets[1]
    local maxMatchingTraits = -1
    for _, v in ipairs(beeTraitSets) do
        local matchingTraits = 0
        for trait, value in pairs(targetTraits) do
            if AnalysisUtil.TraitIsEqual(v, trait, value) then
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
    if not self:ReplicateTemplate(maxTraitSet, 16, 1, true, false) then
        self:OutputError("Failed to replicate starting template.")
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
        if not self:ReplicateTemplate({[trait] = value}, 16, 2, false, false) then
            self:OutputError("Failed to replicate template of new trait.")
            return false
        end

        -- Now breed the desired traits into the working template.
        Print(string.format("Adding trait %s into the working template.", TraitsToString({[trait] = value})))
        self.breeder:ImportHoldoverStacksToDroneChest({1, 2}, {64, 64}, {1, 2})
        local nextTraits = Copy(finishedTraits)
        nextTraits[trait] = value
        local finishedSlots = self:Breed(
            MatchingAlgorithms.ClosestMatchToTraitsMatcher(nextTraits),
            MatchingAlgorithms.DroneStackAndPrincessOfTraitsFinisher(nextTraits, 16),
            GarbageCollectionPolicies.ClearDronesByFurthestAlleleMatchingCollector(nextTraits),
            nil
        )
        if (finishedSlots.drones == nil) or (finishedSlots.princess == nil) then
            self:OutputError(string.format("Failed to breed trait '%s' into the template.", trait))
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
    local finishedDrones = self:Breed(
        MatchingAlgorithms.ClosestMatchToTraitsMatcher(targetTraits),
        MatchingAlgorithms.DroneStackAndPrincessOfTraitsFinisher(targetTraits, 64),
        GarbageCollectionPolicies.ClearDronesByFurthestAlleleMatchingCollector(targetTraits),
        nil
    ).drones
    if finishedDrones == nil then
        self:OutputError("Failed to breed final template up to 64.")
        return false
    end

    self.breeder:StoreDronesFromActiveChest({finishedDrones})
    self.breeder:ReturnActivePrincessesToStock(nil)

    return true
end

---@param targetTraits PartialAnalyzedBeeTraits
---@return boolean
function BeekeeperBot:PropagateTemplate(targetTraits)
    local nonSpeciesTraits = Copy(targetTraits)
    nonSpeciesTraits.species = nil

    -- Retrieve drones that have the requested species allele. Convert a stock princess to a pure-bred of that species.
    if not self:ReplicateSpecies(targetTraits.species.uid, true, true, 16, 1) then
        self:OutputError(string.format("Failed to replicate species '%s'.", targetTraits.species.uid))
        return false
    end

    if not self:ReplicateTemplate(nonSpeciesTraits, 16, 2, true, false) then
        self:OutputError("Error replicating starting template.")
        return false
    end

    -- Now breed the desired traits onto the desired species.
    self.breeder:ImportHoldoverStacksToDroneChest({1, 2}, {16, 16}, {1, 2})
    local finishedSlots = self:Breed(
        MatchingAlgorithms.ClosestMatchToTraitsMatcher(targetTraits),
        MatchingAlgorithms.DroneStackAndPrincessOfTraitsFinisher(targetTraits, 64),
        GarbageCollectionPolicies.ClearDronesByFurthestAlleleMatchingCollector(targetTraits),
        nil
    )
    if (finishedSlots.drones == nil) or (finishedSlots.princess == nil) then
        self:OutputError(string.format("Convergence failure when propagating template."))
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
function BeekeeperBot:ReplicateTemplate(traits, amount, holdoverDroneSlot, retrievePrincessesFromStock, returnPrincessesToStock)
    -- We can't replicate more than a full stack at a time because we support holdoverSlot semantics.
    if amount > 64 then
        self:OutputError("Invalid argument. Cannot replicate more than a full stack at a time.")
        return nil
    end

    -- Retrieve the princesses.
    if retrievePrincessesFromStock then
        if not self.breeder:RetrieveStockPrincessesFromChest(1, {traits.species.uid}) then
            self:OutputError("Failed to retrieve princesses from stock chest.")
            return nil
        end
    end

    -- Retrieve the starter drones.
    if not self.breeder:RetrieveDrones(traits, 1) then
        self:OutputError(string.format("Failed to retrieve drones for replicating template."))
        if retrievePrincessesFromStock then
            self.breeder:ReturnActivePrincessesToStock(nil)
        end
        return nil
    end

    local remaining = amount
    local finishedSlots = {drones = nil, princess = nil}
    while remaining > 0 do
        -- Technically, we take the drones away for the output first, then replicate the original stack back up to 64.
        local numberToReplicate = math.min(remaining, 32)
        self.breeder:ExportDroneStacksToHoldovers({1}, {numberToReplicate}, {holdoverDroneSlot})

        -- Do the breeding.
        finishedSlots = self:Breed(
            MatchingAlgorithms.ClosestMatchToTraitsMatcher(traits),
            MatchingAlgorithms.DroneStackAndPrincessOfTraitsFinisher(traits, 64),
            GarbageCollectionPolicies.ClearDronesByFurthestAlleleMatchingCollector(traits),
            nil
        )

        if (finishedSlots.drones == nil) or (finishedSlots.princess == nil) then
            -- This should never really happen since we're starting with an absurdly high number of drones.
            self:OutputError("Convergence failure while replicating traits.")
            if retrievePrincessesFromStock then
                self.breeder:ReturnActivePrincessesToStock(nil)
            end
            return nil
        end

        remaining = remaining - numberToReplicate
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
---@param retrievePrincessesFromStock boolean
---@param returnPrincessesToStock boolean
---@param amount integer
---@param holdoverSlot integer
---@return boolean | nil success  `true` indicates a success. `false` indicates a convergence failure. `nil` indicates a fatal error.
function BeekeeperBot:ReplicateSpecies(species, retrievePrincessesFromStock, returnPrincessesToStock, amount, holdoverSlot)

    -- We can't replicate more than a full stack at a time because we support holdoverSlot semantics.
    if amount > 64 then
        self:OutputError("Invalid argument. Cannot replicate more than a full stack at a time.")
        return nil
    end

    if retrievePrincessesFromStock then
        if not self.breeder:RetrieveStockPrincessesFromChest(1, {species}) then
            self:OutputError("Failed to retrieve princesses from stock chest.")
            return nil
        end
    end

    -- Move starter bees to their respective chests.
    local traits = {species = {uid = species}}
    if not self.breeder:RetrieveDrones(traits, 1) then
        self:OutputError(string.format("Failed to retrieve drones with species %s.", species))
        self.breeder:ReturnActivePrincessesToStock(nil)
        return nil
    end

    local finishedDroneSlot
    local remaining = amount
    while remaining > 0 do
        -- Technically, we take the drones away for the output first, then replicate the original stack back up to 64.
        local numberToReplicate = math.min(remaining, 32)
        self.breeder:ExportDroneStacksToHoldovers({1}, {numberToReplicate}, {holdoverSlot})
        local stack = self.breeder:GetStackInDroneSlot(1)
        if stack == nil then
            return nil
        end

        -- Do the breeding.
        local breedInfoCacheElement = {}
        local traitInfoCache = {species = {}}
        finishedDroneSlot = self:Breed(
            MatchingAlgorithms.HighFertilityAndAllelesMatcher(
                stack.individual.active.fertility, "species", traits.species, breedInfoCacheElement, traitInfoCache
            ),
            MatchingAlgorithms.DroneStackOfSpeciesPositiveFertilityFinisher(species, stack.individual.active.fertility, 64),
            GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSizeCollector(species),
            function (princessStack, droneStackList)
                self:PopulateBreedInfoCache(princessStack, droneStackList, species, breedInfoCacheElement)
                self:PopulateTraitInfoCache(princessStack, droneStackList, traitInfoCache)
            end
        ).drones

        if finishedDroneSlot == nil then
            -- This should never really happen since we're starting with an absurdly high number of drones.
            -- The only way this should ever happen is if it picked an unfortunate princess that actually has
            -- a mutation with `species` and the user was also using frenzy frames (which they shouldn't do anyways).
            self:OutputError(string.format("Convergence failure while replicating %s.", species))

            -- If we introduced the princesses, then we should clean then up as well.
            if retrievePrincessesFromStock then
                self.breeder:ReturnActivePrincessesToStock(nil)
            end

            -- Don't trash the drone slots in case the user is able to recover something from this.
            return false
        end

        remaining = remaining - numberToReplicate
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
---@return boolean | nil success  `true` indicates a success. `false` indicates a convergence failure. `nil` indicates a fatal error.
function BeekeeperBot:BreedSpecies(node, retrievePrincessesFromStock, returnPrincessesToStock)
    if retrievePrincessesFromStock then
        self.breeder:RetrieveStockPrincessesFromChest(1, {node.parent1, node.parent2})
    end

    -- Breed the target using the left-over drones from both parents and the princesses
    -- implied to be created by breeding the replacements for parent 2.
    -- TODO: It is technically possible that some princesses may not have been converted
    --   to one of the two parents. In this case, it could be impossible to get a drone that
    --   has a non-zero chance to breed the target. For now, we will just rely on random
    --   chance to eventually get us out of this scenario instead of detecting it outright.
    --   To solve the above, we could have the matcher prioritize breeding one of the parents
    --   if breeding the target has 0 chance with all princesses/drones.

    -- Move starter bees to their respective chests.
    self.breeder:ImportHoldoverStacksToDroneChest({1, 2}, {64, 64}, {1, 2})

    self:EnsureSpecialConditionsMet(node)

    -- We will want to breed high fertility into the drones of the target species.
    local stack1 = self.breeder:GetStackInDroneSlot(1)
    local stack2 = self.breeder:GetStackInDroneSlot(2)
    if (stack1 == nil) or (stack2 == nil) then
        self:OutputError("BreedSpecies: Drones were removed from chest between holdover import and conditions completion.")
        return nil
    end
    local maxFertilityPreExisting = math.max(
        stack1.individual.active.fertility,
        stack2.individual.active.fertility
    )

    -- Do the breeding.
    local breedInfoCacheElement = {}
    local traitInfoCache = {species = {}}
    local finishedDroneSlot = self:Breed(
        MatchingAlgorithms.HighFertilityAndAllelesMatcher(maxFertilityPreExisting, "species", {uid = node.target}, breedInfoCacheElement, traitInfoCache),
        MatchingAlgorithms.DroneStackOfSpeciesPositiveFertilityFinisher(node.target, maxFertilityPreExisting, 64),
        GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSizeCollector(node.target),
        function (princessStack, droneStackList)
            self:PopulateBreedInfoCache(princessStack, droneStackList, node.target, breedInfoCacheElement)
            self:PopulateTraitInfoCache(princessStack, droneStackList, traitInfoCache)
        end
    ).drones

    if finishedDroneSlot == nil then
        self:OutputError(string.format("Error breeding '%s' from '%s' and '%s'. Retrying from parent replication.", node.target, node.parent1, node.parent2))
        self.breeder:BreakAndReturnFoundationsToInputChest()  -- Avoid double-prompting for foundations.
        return false
    end

    -- If we have enough of the target species now, then inform the server and store the drones at the new location.
    if not self.robotComms:ReportNewSpeciesToServer(node.target) then
        self:OutputError(string.format("Error reporting storage location of %s to server.", node.target))
        self.breeder:BreakAndReturnFoundationsToInputChest()
        return nil
    end

    self.breeder:StoreDronesFromActiveChest({finishedDroneSlot})
    if returnPrincessesToStock then
        self.breeder:ReturnActivePrincessesToStock(nil)
    end

    self.breeder:BreakAndReturnFoundationsToInputChest()
    return true
end

-- Breeds the target using the drones and princesses in the active chests.
---@param matchingAlgorithm Matcher
---@param finishedSlotAlgorithm StackFinisher
---@param garbageCollectionAlgorithm GarbageCollector
---@param populateCaches fun(princessStack: AnalyzedBeeStack, droneStackList: AnalyzedBeeStack[]) | nil
---@return {princess: integer | nil, drones: integer | nil}
function BeekeeperBot:Breed(matchingAlgorithm, finishedSlotAlgorithm, garbageCollectionAlgorithm, populateCaches)
    -- Experimentally, convergence should happen well before 300 iterations. If we hit that many, then convergence probably failed.
    local slots = {princess = nil, drones = nil}
    local iteration = 0
    local inventorySize = self.breeder:GetDroneChestSize()

    while iteration < 300 do
        iteration = iteration + 1
        local droneStackList
        local princessStack = nil
        while princessStack == nil do
            princessStack = self.breeder:GetPrincessInChest()
            droneStackList = self.breeder:GetDronesInChest()

            slots = finishedSlotAlgorithm(princessStack, droneStackList)
            if (slots.princess ~= nil) or (slots.drones ~= nil) then
                -- Convergence succeeded. Break out.
                return slots
            end

            local numEmptySlots = (inventorySize - #droneStackList)
            if numEmptySlots < 4 then  -- 4 is the highest naturally occurring fertility. TODO: Consider whether this should truly leave 8 slots.
                -- If there are not many open slots in the drone chest, then eliminate some of them to make room for newer generations.
                local slotsToRemove = garbageCollectionAlgorithm(droneStackList, numEmptySlots - 4)
                self.breeder:TrashSlotsFromDroneChest(slotsToRemove)
            end

            if princessStack == nil then
                -- Poll once every 5 seconds so that we aren't spamming. TODO: Make this configurable.
                Sleep(5)
            end
        end

        -- Not finished, but haven't failed. Continue breeding.
        if populateCaches ~= nil then
            populateCaches(princessStack, droneStackList)
        end

        local droneSlot, score = matchingAlgorithm(princessStack, droneStackList)
        if score ~= nil then
            Print(string.format("iteration %u", iteration))
        end

        self:ShutdownOnCancel()
        self.breeder:InitiateBreeding(princessStack.slotInChest, droneSlot)
    end

    return slots
end

--- Populates `cacheElement` with any required information to allow for breeding calculations between the
--- given princess and any drone in `droneStackList`.
---@param princessStack AnalyzedBeeStack
---@param droneStackList AnalyzedBeeStack[]
---@param target string
---@param cacheElement BreedInfoCacheElement  The cache to be populated.
function BeekeeperBot:PopulateBreedInfoCache(princessStack, droneStackList, target, cacheElement)
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
                    self:OutputError("Unexpected error when retrieving target's breed info from server.")
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
function BeekeeperBot:PopulateTraitInfoCache(princessStack, droneStackList, traitInfoCache)
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
---@return boolean
function BeekeeperBot:EnsureSpecialConditionsMet(node)
    -- Encase this in a loop in case the user doesn't provide the foundations correctly.
    local promptedOnce = false
    while true do
        local shouldPlaceFoundation = self:MustPlaceFoundation(node.foundation)
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

    return true
end

---@param foundation string | nil
---@return boolean
function BeekeeperBot:MustPlaceFoundation(foundation)
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
function BeekeeperBot:OutputError(errMsg)
    self.robotComms:ReportErrorToServer(errMsg)
    Print(errMsg)
end

function BeekeeperBot:ShutdownOnCancel()
    if self.robotComms:PollForCancel() then
        self:Shutdown(1)
    end
end

---@param code integer
function BeekeeperBot:Shutdown(code)
    if self.robotComms ~= nil then
        self.robotComms:Shutdown()
    end

    ExitProgram(code)
end

return BeekeeperBot
