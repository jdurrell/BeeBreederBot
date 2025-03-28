-- This program is the main executable for the breeder robot.
-- The breeder robot works "in the field" and uses information queried
-- from the bee-graph server to determine pairings of princesses and drones
-- and manipulate inventories to move the bees between breeding or storage.

-- Import BeeBreederBot libraries.
require("Shared.Shared")
local BreederOperation = require("BeekeeperBot.BreederOperation")
local CommLayer = require("Shared.CommLayer")
local GarbageCollectionPolicies = require("BeekeeperBot.GarbageCollectionPolicies")
local MatchingAlgorithms = require("BeekeeperBot.MatchingAlgorithms")
local RobotComms = require("BeekeeperBot.RobotComms")

---@class BeekeeperBot
---@field component Component
---@field event Event
---@field breeder BreedOperator
---@field logFilepath string
---@field messageHandlerTable table<MessageCode, fun(bot: BeekeeperBot, data: any)>
---@field robotComms RobotComms
local BeekeeperBot = {}

-- Creates a BeekeeperBot and does initial setup.
-- Requires system libraries as an input.
---@param componentLib Component
---@param eventLib Event | nil
---@param robotLib any
---@param serialLib Serialization | nil
---@param sidesLib any
---@param port integer
---@param numApiaries integer
---@return BeekeeperBot
function BeekeeperBot:Create(componentLib, eventLib, robotLib, serialLib, sidesLib, port, numApiaries)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    -- This is used for transaction IDs when pinging the server.
    math.randomseed(os.time())

    -- Store away system libraries.
    -- Do this in the constructor instead of statically so that we can inject our
    -- own system libraries for testing.
    if eventLib == nil then
        Print("Couldn't find 'event' module.")
        obj:Shutdown(1)
    end
    obj.event = eventLib

    if componentLib == nil then
        Print("Couldn't find 'component' module")
        obj:Shutdown(1)
    end
    componentLib = UnwrapNull(componentLib)

    local robotComms = RobotComms:Create(eventLib, componentLib.modem, serialLib, port)
    if robotComms == nil then
        Print("Failed to initialize RobotComms during BeekeeperBot initialization.")
        obj:Shutdown(1)
    end
    obj.robotComms = UnwrapNull(robotComms)

    local breeder = BreederOperation:Create(componentLib.beekeeper, componentLib.inventory_controller, robotLib, sidesLib, numApiaries)
    if breeder == nil then
        Print("Failed to initialize breeding operator during BeekeeperBot initialization.")
        obj:Shutdown(1)
    end
    obj.breeder = UnwrapNull(breeder)

    obj.messageHandlerTable = {
        [CommLayer.MessageCode.BreedCommand] = BeekeeperBot.BreedCommandHandler,
        [CommLayer.MessageCode.CancelCommand] = BeekeeperBot.CancelCommandHandler,
        [CommLayer.MessageCode.ReplicateCommand] = BeekeeperBot.ReplicateCommandHandler,
    }

    return obj
end

-- Runs the main BeekeeperBot operation loop.
function BeekeeperBot:RunRobot()
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

    self:ReplicateSpecies(data.species, true, true, 1)
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
            local retval = self:ReplicateSpecies(v.parent1, true, true, 1)
            if retval == nil then
                self:OutputError("Fatal error: Replicate species '" .. v.parent1 .. "' failed.")
                self:Shutdown(1)
            end
            -- Convergence failure is handled inside ReplicateSpecies.
        end

        if v.parent2 ~= nil then
            local retval = self:ReplicateSpecies(v.parent2, true, false, 2)
            if retval == nil then
                self:OutputError("Fatal error: Replicate species '" .. v.parent2 .. "' failed.")
                self:Shutdown(1)
            end
            -- Convergence failure is handled inside ReplicateSpecies.
        end

        local retval = self:BreedSpecies(v, false, true)
        if retval == nil then
            self:OutputError(string.format("Fatal error: Breeding species '%s' from '%s' and '%s' failed.", v.target, v.parent1, v.parent2))
            self:Shutdown(1)
        elseif not retval then
            -- If the breeding the new mutation didn't converge, then we have to restart from replicating the parents.
            self.breeder:TrashSlotsFromDroneChest(nil)
            self.breeder:ReturnActivePrincessesToStock()
            goto restart
        end
    end
end

---@param data PropagateTemplatePayload
function BeekeeperBot:PropagateTemplateHandler(data)
    if (data == nil) or (data.traits == nil) or (data.traits.species == nil) or (data.traits.species.uid == nil) then
        self:OutputError("Received invalid PropagateTemplate payload.")
        return
    end

    -- Retrieve drones that have the requested species allele. Convert a stock princess to a pure-bred of that species.
    local locationPoint = self.robotComms:GetStorageLocationFromServer(data.traits.species.uid)
    if locationPoint == nil then
        self:OutputError("Failed to get location of species " .. data.traits.species.uid .. " from server.")
        return
    end
    self.breeder:RetrieveDronesFromChest(locationPoint.loc, 64)
    self.breeder:RetrieveStockPrincessesFromChest(1, {data.traits.species.uid})
    self.breeder:ExportDroneStacksToHoldovers({1}, {64}, {2})
    self.breeder:ExportPrincessStacksToHoldovers({1}, {1}, {11})

    -- We're propagating the traits onto a new species, so ignore the given species when retrieving the template.
    local retrievableTraits = Copy(data.traits)
    retrievableTraits.species = nil
    self.breeder:RetrieveBeesWithTemplate(data.traits)
    self.breeder:ExportDroneStacksToHoldovers({1}, {64}, {1})
    self.breeder:ExportPrincessStacksToHoldovers({1}, {1}, {10})

    ::restart::
    -- For safety, replicate extras of our starting sets to ensure we don't accidentally breed them out.
    -- We only need 16 more of these, so retrieve 64 - 16 = 48.
    self.breeder:ImportHoldoverStacksToDroneChest({2}, {48}, {1})
    self.breeder:ImportHoldoverStacksToPrincessChest({11}, {1}, {1})
    local existingSpeciesTemplate = self.breeder:GetDronesInChest()[1].individual.active  -- TODO: Make it strictly impossible for the retrieved set of drones to have mixed traits.
    local slots = self:ReplicateTemplate(existingSpeciesTemplate)
    if slots.drones == nil then
        -- This should never error.
        self:OutputError("Error replicating template of starting species.")
        return
    end
    self.breeder:ExportDroneStacksToHoldovers({slots.drones, slots.drones}, {48, 16}, {2, 27})
    self.breeder:ExportPrincessStacksToHoldovers({slots.princess}, {1}, {11})

    -- We only need 16 more of these, so retrieve 64 - 16 = 48.
    self.breeder:ImportHoldoverStacksToDroneChest({1}, {48}, {1})
    self.breeder:ImportHoldoverStacksToPrincessChest({10}, {1}, {1})
    slots = self:ReplicateTemplate(data.traits)
    if slots.drones == nil then
        -- This should never error.
        self:OutputError("Error replicating starting template.")
        return
    end
    self.breeder:ExportDroneStacksToHoldovers({slots.drones, slots.drones}, {48, 16}, {1, 26})
    self.breeder:ExportPrincessStacksToHoldovers({slots.princess}, {1}, {10})

    -- Now breed the desired traits onto the desired species.
    self.breeder:ImportHoldoverStacksToDroneChest({26, 27}, {16, 16}, {1, 2})
    self.breeder:ImportHoldoverStacksToPrincessChest({11}, {1}, {1})
    slots = self:ReplicateTemplate(data.traits)
    if slots.drones == nil then
        self.breeder:ExportPrincessStacksToHoldovers({1}, {1}, {11})
        self.breeder:TrashSlotsFromDroneChest(nil)
        goto restart
    end

    -- Export the output to the outputs.
    self.breeder:ExportDroneStackToOutput(slots.drones, 64)
    self.breeder:ExportPrincessStackToOutput(slots.princess, 1)

    -- Do cleanup.
    self.breeder:TrashSlotsFromDroneChest(nil)
    self.breeder:ImportHoldoverStacksToDroneChest({1, 2}, {64, 64}, {1, 2})
    self.breeder:ImportHoldoverStacksToPrincessChest({10}, {1}, {1})
    self.breeder:StoreDrones(2, locationPoint.loc, false)
end

-- Replicates the given template from pure-bred drones and a pure-bred princess of that template.
-- Requires drones and princess to already be in the active chests.
-- Places outputs in the holdover chest.
---@param traits AnalyzedBeeTraits
---@return {princess: integer | nil, drones: integer | nil}  finishedSlots
function BeekeeperBot:ReplicateTemplate(traits)
    -- Do the breeding.
    local finishedSlots = self:Breed(
        MatchingAlgorithms.ClosestMatchToTraitsMatcher(traits),
        MatchingAlgorithms.FullDroneStackAndPrincessOfTraitsFinisher(traits),
        GarbageCollectionPolicies.ClearDronesByFurthestAlleleMatchingCollector(traits),
        nil
    )

    if (finishedSlots.drones == nil) or (finishedSlots.princess == nil) then
        -- This should never really happen since we're starting with pure-breds of drones and princesses.
        self:OutputError("Error replicating traits.")
        return {nil, nil}
    end

    return finishedSlots
end

-- Replicates drones of the given species.
-- Places outputs into the holdover chest.
---@param species string
---@param retrievePrincessesFromStock boolean
---@param returnPrincessesToStock boolean
---@param holdoverSlot integer
---@return boolean | nil success  `true` indicates a success. `false` indicates a convergence failure. `nil` indicates a fatal error.
function BeekeeperBot:ReplicateSpecies(species, retrievePrincessesFromStock, returnPrincessesToStock, holdoverSlot)
    if retrievePrincessesFromStock then
        self.breeder:RetrieveStockPrincessesFromChest(1, {species})
    end

    ::restart::
    local storageResponse = self.robotComms:GetStorageLocationFromServer(species)
    if storageResponse == nil then
        self:OutputError("Error getting storage location of " .. species .. " from server.")
        return nil
    end

    -- Move starter bees to their respective chests.
    -- TODO: This should fail when we are unable to get drones from the chest.
    self.breeder:RetrieveDronesFromChest(storageResponse.loc, 32)  -- TODO: Is 32 a good number? Should this be dependent on number of apiaries?

    -- Do the breeding.
    local breedInfoCacheElement = {}
    local traitInfoCache = {species = {}}
    local finishedDroneSlot = self:Breed(
        MatchingAlgorithms.HighFertilityAndAllelesMatcher("species", {uid = species}, breedInfoCacheElement, traitInfoCache),
        MatchingAlgorithms.FullDroneStackOfSpeciesPositiveFertilityFinisher(species),
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
        self:OutputError("Error replicating " .. species .. ". Retrying with another drone batch.")
        self.breeder:TrashSlotsFromDroneChest(nil)
        self.breeder:ReturnActivePrincessesToStock()
        goto restart
    end

    -- Double check with the server about the location in case the user changed it during operation.
    -- The user shouldn't really do this, and there's no way to eliminate this conflict entirely,
    -- but this is a mostly trivial way to recover from at least some possible bad behavior.
    storageResponse = self.robotComms:GetStorageLocationFromServer(species)
    if storageResponse == nil then
        self:OutputError("Error getting storage location of " .. species .. " from server.")
        return nil
    end

    self.breeder:ExportDroneStacksToHoldovers({finishedDroneSlot}, {32}, {holdoverSlot})
    self.breeder:StoreDrones(finishedDroneSlot, storageResponse.loc, storageResponse.isNew)
    self.breeder:TrashSlotsFromDroneChest(nil)
    if returnPrincessesToStock then
        self.breeder:ReturnActivePrincessesToStock()
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

    -- Do the breeding.
    local breedInfoCacheElement = {}
    local traitInfoCache = {species = {}}
    local finishedDroneSlot = self:Breed(
        MatchingAlgorithms.HighFertilityAndAllelesMatcher("species", {uid = node.target}, breedInfoCacheElement, traitInfoCache),
        MatchingAlgorithms.FullDroneStackOfSpeciesPositiveFertilityFinisher(node.target),
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
    local storageResponse = self.robotComms:ReportNewSpeciesToServer(node.target)
    if storageResponse == nil then
        self:OutputError("Error getting storage location of " .. node.target .. " from server.")
        self.breeder:BreakAndReturnFoundationsToInputChest()
        return nil
    end

    self.breeder:StoreDrones(finishedDroneSlot, storageResponse.loc, storageResponse.isNew)
    self.breeder:TrashSlotsFromDroneChest(nil)
    if returnPrincessesToStock then
        self.breeder:ReturnActivePrincessesToStock()
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
    local finishedPrincessSlot = nil
    local finishedDroneSlot = nil

    -- Experimentally, convergence should happen well before 300 iterations. If we hit that many, then convergence probably failed.
    local iteration = 0
    while iteration < 300 do
        local princessStack = self.breeder:GetPrincessInChest()
        local droneStackList = self.breeder:GetDronesInChest()
        local slots = finishedSlotAlgorithm(princessStack, droneStackList)
        if (slots.princess ~= nil) or (slots.drones ~= nil) then
            break
        end

        -- Not finished, but haven't failed. Continue breeding.
        if populateCaches ~= nil then
            populateCaches(princessStack, droneStackList)
        end
        local droneSlot = matchingAlgorithm(princessStack, droneStackList)
        self:ShutdownOnCancel()
        self.breeder:InitiateBreeding(princessStack.slotInChest, droneSlot)
        if princessStack.individual.active.fertility > (27 - #droneStackList) then
            local slotsToRemove = garbageCollectionAlgorithm(droneStackList, (27 - #droneStackList) - princessStack.individual.active.fertility)
            self.breeder:TrashSlotsFromDroneChest(slotsToRemove)
        end

        iteration = iteration + 1
    end

    return {princess = finishedPrincessSlot, drones = finishedDroneSlot}
end

--- Populates `cacheElement` with any required information to allow for breeding calculations between the
--- given princess and any drone in `droneStackList`.
---@param princessStack AnalyzedBeeStack
---@param droneStackList AnalyzedBeeStack[]
---@param target string
---@param cacheElement BreedInfoCacheElement  The cache to be populated.
function BeekeeperBot:PopulateBreedInfoCache(princessStack, droneStackList, target, cacheElement)
    for _, droneStack in ipairs(droneStackList) do
        -- Forestry only checks for mutations between the princess's primary and drone's secondary species and the princess's secondary and
        -- drone's primary species.
        local mutCombos = {
            {princessStack.individual.active.species.uid, droneStack.individual.inactive.species.uid},
            {princessStack.individual.inactive.species.uid, droneStack.individual.active.species.uid}
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

-- Populates `traitInfoCache` with any required infromation to allow for breeding calculations between the given princess and any drone in
-- the drone chest.
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

---@param code integer
function BeekeeperBot:Shutdown(code)
    if self.robotComms ~= nil then
        self.robotComms:Shutdown()
    end

    ExitProgram(code)
end

function BeekeeperBot:ShutdownOnCancel()
    if self.robotComms:PollForCancel() then
        self:Shutdown(1)
    end
end

return BeekeeperBot
