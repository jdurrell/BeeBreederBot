-- This program is the main executable for the breeder robot.
-- The breeder robot works "in the field" and uses information queried
-- from the bee-graph server to determine pairings of princesses and drones
-- and manipulate inventories to move the bees between breeding or storage.

-- Import BeeBreederBot libraries.
require("Shared.Shared")
local BreederOperation = require("BeekeeperBot.BreederOperation")
local GarbageCollectionPolicies = require("BeekeeperBot.GarbageCollectionPolicies")
local MatchingAlgorithms = require("BeekeeperBot.MatchingAlgorithms")
local RobotComms = require("BeekeeperBot.RobotComms")

local matchingAlgorithm = MatchingAlgorithms.HighFertilityAndAlleles
local garbageCollectionAlgorithm = GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSize


---@class BeekeeperBot
---@field component any
---@field event any
---@field breeder BreedOperator
---@field logFilepath string
---@field robotComms RobotComms
local BeekeeperBot = {}

-- Creates a BeekeeperBot and does initial setup.
-- Requires system libraries as an input.
---@param componentLib any
---@param eventLib any
---@param robotLib any
---@param serialLib any
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

    return obj
end

---@param code integer
function BeekeeperBot:Shutdown(code)
    if self.robotComms ~= nil then
        self.robotComms:Shutdown()
    end

    ExitProgram(code)
end

-- Runs the main BeekeeperBot operation loop.
function BeekeeperBot:RunRobot()
    while true do
        -- Poll the server until it has a path to breed for us.
        -- TODO: It might be better for the server to actively command this.
        local breedPath = {}
        while breedPath == {} do
            local path = self.robotComms:GetBreedPathFromServer()
            if path == nil then
                Print("Unexpected error when retrieving breed path from server.")
                self:Shutdown(1)
            end
            breedPath = UnwrapNull(path)
        end

        -- Breed the commanded species based on the given path.
        for _, v in ipairs(breedPath) do
            if v.parent1 ~= nil then
                self:ReplicateSpecies(v.parent1)
            end

            if v.parent2 ~= nil then
                self:ReplicateSpecies(v.parent2)
            end

            self:BreedSpecies(v.target, v.parent1, v.parent2)
        end
    end
end

-- Replicates drones of the given species.
-- Places outputs into the holdover chest.
---@param species string
function BeekeeperBot:ReplicateSpecies(species)
    -- TODO: At some point, we should probably have a way to store + retrieve breeding stock princesses,
    -- but for now, we will just rely on the user to place them into the princess chest manually.
    -- This system currently only supports breeding a stack of drones that somebody could then
    -- use to very simply turn a different princess into a pure-bred production one.

    local storagePoint = self.robotComms:GetStorageLocationFromServer(species)
    if storagePoint == nil then
        Print("Error getting storage location of " .. species .. " from server.")
        return false
    end
    storagePoint = UnwrapNull(storagePoint)

    -- Move starter bees to their respective chests.
    self.breeder:RetrieveDronesFromChest(storagePoint, 32)  -- TODO: Is 32 a good number? Should this be dependent on number of apiaries?
    self.breeder:RetrieveStockPrincessesFromChest(1, {species})

    -- Do the breeding.
    local finishedDroneSlot = self:Breed(species)

    -- Double check with the server about the location in case the user changed it during operation.
    -- The user shouldn't really do this, and there's no way to eliminate this conflict entirely,
    -- but this is a mostly trivial way to recover from at least some possible bad behavior.
    storagePoint = self.robotComms:GetStorageLocationFromServer(species)
    if storagePoint == nil then
        Print("Error getting storage location of " .. species .. " from server.")
        return
    end

    self.breeder:ExportDroneStackToHoldovers(finishedDroneSlot, 32)
    self.breeder:StoreDrones(finishedDroneSlot, storagePoint)
end

-- Breeds the target species from the two given parents.
-- Requires drones of each species as inputs already in the holdover chest.
-- Places finished breed output in the storage columns.
---@param target string
---@param parent1 string
---@param parent2 string
function BeekeeperBot:BreedSpecies(target, parent1, parent2)
    -- Breed the target using the left-over drones from both parents and the princesses
    -- implied to be created by breeding the replacements for parent 2.
    -- TODO: Technically, it is likely possible that some princesses may not get converted
    --   to one of the two parents. In this case, it could be impossible to get a drone that
    --   has a non-zero chance to breed the target. For now, we will just rely on random
    --   chance to eventually get us out of this scenario instead of detecting it outright.
    --   To solve the above, we could have the matcher prioritize breeding one of the parents
    --   if breeding the target has 0 chance with all princesses/drones.

    -- Move starter bees to their respective chests.
    self.breeder:ImportHoldoversToDroneChest()
    self.breeder:RetrieveStockPrincessesFromChest(1, {parent1, parent2})

    -- Do the breeding.
    local finishedDroneSlot = self:Breed(target)

    -- If we have enough of the target species now, then information the server and store the drones at the new location.
    local point = self.robotComms:ReportNewSpeciesToServer(target)
    if point == nil then
        Print("Error getting storage location of " .. target .. " from server.")
        return
    end
    self.breeder:StoreDrones(finishedDroneSlot, point)
end

---@param target string
---@return integer
function BeekeeperBot:Breed(target)
    -- Replicate extras to replace the drones we took from the chest.
    ---@type BreedInfoCache
    local breedInfoCache = {}
    ---@type TraitInfoSpecies
    local traitInfoCache = {species = {}}
    local finishedDroneSlot
    while true do
        -- TODO: Handle the possibility of non-convergence.
        local princessStack = self.breeder:GetPrincessInChest()
        local droneStackList = self.breeder:GetDronesInChest()
        finishedDroneSlot = MatchingAlgorithms.GetFinishedDroneStack(droneStackList, target)
        if finishedDroneSlot ~= nil then
            break
        else
            self:PopulateBreedInfoCache(princessStack, droneStackList, target, breedInfoCache)
            self:PopulateTraitInfoCache(princessStack, droneStackList, traitInfoCache)
            local droneSlot = matchingAlgorithm(princessStack, droneStackList, target, breedInfoCache[target], traitInfoCache)
            self.breeder:InitiateBreeding(princessStack.slotInChest, droneSlot)
            if princessStack.individual.active.fertility > (27 - #droneStackList) then
                local slotsToRemove = garbageCollectionAlgorithm(droneStackList, (27 - #droneStackList) - princessStack.individual.active.fertility, target)
                self.breeder:TrashSlotsFromDroneChest(slotsToRemove)
            end
        end
    end
    finishedDroneSlot = UnwrapNull(finishedDroneSlot)
end

--- Populates `breedInfoCache` with any required information to allow for breeding calculations between the given princess and any drone in
--- the drone chest.
---@param princessStack AnalyzedBeeStack
---@param droneStackList AnalyzedBeeStack[]
---@param target string
---@param breedInfoCache BreedInfoCache  The cache to be populated.
function BeekeeperBot:PopulateBreedInfoCache(princessStack, droneStackList, target, breedInfoCache)
    if breedInfoCache[target] == nil then
        breedInfoCache[target] = {}
    end
    local cacheElement = breedInfoCache[target]

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
                local breedInfo = self.robotComms:GetBreedInfoFromServer(target)
                if breedInfo == nil then
                    Print("Unexpected error when retrieving target's breed info from server.")
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

return BeekeeperBot
