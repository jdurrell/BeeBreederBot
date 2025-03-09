-- This program is the main executable for the breeder robot.
-- The breeder robot works "in the field" and uses information queried
-- from the bee-graph server to determine pairings of princesses and drones
-- and manipulate inventories to move the bees between breeding or storage.

-- Import BeeBreederBot libraries.
require("Shared.Shared")
local BreederOperation = require("BeekeeperBot.BreederOperation")
local GarbageCollectionPolicies = require("BeekeeperBot.GarbageCollectionPolicies")
local Logger = require("Shared.Logger")
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
---@field storageInfo StorageInfo
local BeekeeperBot = {}

-- Creates a BeekeeperBot and does initial setup.
-- Requires system libraries as an input.
---@param componentLib any
---@param eventLib any
---@param serialLib any
---@param port integer
---@return BeekeeperBot
function BeekeeperBot:Create(componentLib, eventLib, serialLib, sidesLib, logFilepath, port)
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

    local breeder = BreederOperation:Create(componentLib.beekeeper, componentLib.inventory_controller, sidesLib)
    if breeder == nil then
        Print("Failed to initialize breeding operator during BeekeeperBot initialization.")
        obj:Shutdown(1)
    end
    obj.breeder = UnwrapNull(breeder)

    -- Initialize location information of the bees in storage.
    obj.logFilepath = logFilepath
    local chestArray = Logger.ReadSpeciesLogFromDisk(logFilepath)
    if chestArray == nil then
        Print("Error while reading log on startup.")
        obj:Shutdown(1)
    end
    obj.storageInfo = {
        nextChest = {x = 0, y = 0},  -- TODO: Initialize nextChest properly based on the data in chestArray
        chestArray = chestArray
    }

    -- TODO: This is currently a bit messy since it has side effects. Consider either moving the logging into this
    --       or having this function return a value instead of setting it directly.
    obj:SyncLogWithServer()

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
---@return boolean
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
    self.breeder:RetrieveStockPrincessesFromChest({species})

    -- Replicate extras to replace the drones we took from the chest.
    ---@type BreedInfoCache
    local breedInfoCache = {}
    ---@type TraitInfoSpecies
    local traitInfoCache = {species = {}}
    local finishedDroneSlot
    while true do
        local princessStack = self.breeder:GetPrincessInChest()
        local droneStackList = self.breeder:GetDronesInChest()
        finishedDroneSlot = MatchingAlgorithms.GetFinishedDroneStack(droneStackList, species)
        if finishedDroneSlot ~= nil then
            break
        else
            self:PopulateBreedInfoCache(princessStack, droneStackList, species, breedInfoCache)
            self:PopulateTraitInfoCache(princessStack, droneStackList, traitInfoCache)
            local droneSlot = matchingAlgorithm(princessStack, droneStackList, species, breedInfoCache[species], traitInfoCache)
            self.breeder:InitiateBreeding(princessStack.slotInChest, droneSlot)
            if princessStack.individual.active.fertility > (27 - #droneStackList) then
                local slotsToRemove = garbageCollectionAlgorithm(droneStackList, (27 - #droneStackList) - princessStack.individual.active.fertility, species)
                self.breeder:TrashSlotsFromDroneChest(slotsToRemove)
            end
        end
    end
    finishedDroneSlot = UnwrapNull(finishedDroneSlot)

    -- Double check with the server about the location in case the user changed it during operation.
    -- The user shouldn't really do this, and there's no way to eliminate this conflict entirely,
    -- but this is a mostly trivial way to recover from at least some possible bad behavior.
    storagePoint = self.robotComms:GetStorageLocationFromServer(species)
    if storagePoint == nil then
        storagePoint = self.storageInfo.chestArray[species].loc
    else
        storagePoint = UnwrapNull(storagePoint)
    end

    self.breeder:ExportDroneStackToHoldovers(finishedDroneSlot, 32)
    self.breeder:StoreDrones(finishedDroneSlot, storagePoint)
end

-- Breeds the target species from the two given parents.
-- Requires drones of each species as inputs already in the holdover chest.
-- Places outputs in the holdover chest.
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
    self.breeder:RetrieveStockPrincessesFromChest({parent1, parent2})

    -- Replicate extras to replace the drones we took from the chest.
    ---@type BreedInfoCache
    local breedInfoCache = {}
    ---@type TraitInfoSpecies
    local traitInfoCache = {species = {}}
    local finishedDroneSlot
    while true do
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

    -- Double check with the server about the location in case the user changed it during operation.
    -- The user shouldn't really do this, and there's no way to eliminate this conflict entirely,
    -- but this is a mostly trivial way to recover from at least some possible bad behavior.
    local storagePoint = self.robotComms:GetStorageLocationFromServer(target)
    if storagePoint == nil then
        Print("Error getting storage location of " .. target .. " from server.")
    end
    storagePoint = UnwrapNull(storagePoint)

    -- If we have enough of the target species now, then clean up and break out.
    local point = self:ReportNewSpecies(target)
    self.breeder:StoreDrones(finishedDroneSlot, point)
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

---@param species string
---@return Point
function BeekeeperBot:ReportNewSpecies(species)
    -- Pick the next open one store for this species.
    local chestNode = {
        loc = Copy(self.storageInfo.nextChest),
        timestamp = GetCurrentTimestamp()
    }

    self.storageInfo.nextChest.y = self.storageInfo.nextChest.y + 1
    if self.storageInfo.nextChest.y >= 5 then
        self.storageInfo.nextChest.y = 0
        self.storageInfo.nextChest.x = self.storageInfo.nextChest.x + 1
    end

    self.storageInfo.chestArray[species] = chestNode

    -- Store this location on our own logfile in case the server is down, and we need to re-sync later.
    -- TODO: Does this concept even make any sense??? We might get rid of this, especially if we plan to
    -- support multiple bots at some point (since they will all need to sync with the server).
    Logger.LogSpeciesToDisk(self.logFilepath, species, chestNode.loc, chestNode.timestamp)
    self.robotComms:ReportSpeciesFinishedToServer(species, chestNode)

    return chestNode.loc
end

function BeekeeperBot:SyncLogWithServer()
    self.robotComms:SendLogToServer(self.storageInfo.chestArray)

    -- At this point, the server's information is at least as recent as our own because operations are linearizable.
    -- Thus, we can simply overwrite our own information with whatever is handed back to us from the server.
    local newInfo = self.robotComms:RetrieveLogFromServer()
    if newInfo == nil then
        Print("Unexpected error when attempting to synchronize logs with the server.")
        return
    end

    -- TODO: Adjust nextChest here as well. Alternatively, perhaps the server should own the concept of nextChest...
    self.storageInfo.chestArray = UnwrapNull(newInfo)
    for species, entry in pairs(self.storageInfo.chestArray) do
        -- TODO: Overwrite the log in bulk.
        Logger.LogSpeciesToDisk(self.logFilepath, species, entry.loc, entry.timestamp)
    end
end

return BeekeeperBot
