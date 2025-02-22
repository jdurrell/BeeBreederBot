-- This module contains logic used by the breeder robot to manipulate bees and the apiaries.
---@class BreedOperator
---@field bk any beekeeper library
---@field ic any inventory controller library
---@field robot any robot library
---@field sides any sides library
---@field logFilepath string
---@field robotComms RobotComms
---@field storageInfo StorageInfo
local BreedOperator = {}

local Logger = require("Shared.Logger")

-- Slots for holding items in the robot.
local PRINCESS_SLOT = 1
local DRONE_SLOT    = 2
local NUM_INTERNAL_SLOTS = 16

-- TODO: There's an existing conflict between this location and the drone storage.
--       Either force the drone storage to not use this value, or physically separate
--       this chest (2nd option probably better because user will likely have to manipulate
--       it manually because princesses will need to enter and leave the system).
---@type Point
local BREEDING_STOCK_PRINCESSES_LOC = {x = 0, y = 0}

local ANALYZED_DRONE_CHEST     -- directly to the right of the breeder station.
local ANALYZED_PRINCESS_CHEST  -- directly to the left of the breeder station.
local HOLDOVER_CHEST           -- to the right of the breeder station, 2 blocks up vertically.
local OUTPUT_CHEST             -- to the left of the breeder station, 2 blocks up vertically.

-- Info for chests for analyzed bees at the start of the apiary row.
local BASIC_CHEST_INVENTORY_SLOTS = 27

function BreedOperator:SyncLogWithServer()
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

function BreedOperator:Create(beekeeperLib, inventoryControllerLib, robotLib, sidesLib, robotComms, logFilepath)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    obj.bk = beekeeperLib
    obj.ic = inventoryControllerLib
    obj.robot = robotLib
    obj.sides = sidesLib
    obj.robotComms = robotComms

    ANALYZED_PRINCESS_CHEST = sidesLib.left
    ANALYZED_DRONE_CHEST = sidesLib.right

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
end

---@param side integer
function BreedOperator:swapBees(side)
    self.robot.select(PRINCESS_SLOT)
    self.bk.swapQueen(side)
    self.robot.select(DRONE_SLOT)
    self.bk.swapDrone(side)
end

-- Returns whether the bee represented by the given stack is a pure bred version of the given species.
---@param beeStack AnalyzedBeeStack
---@param species string
---@return boolean
local function isPureBred(beeStack, species)
    return (beeStack.individual.active.species == species) and (beeStack.individual.active.species == beeStack.individual.inactive.species)
end

-- Robot walks the apiary row and starts an empty apiary with the bees in the inventories in the given slots.
-- Starts at the breeding station and ends at the breeding station.
-- TODO: Deal with the possibility of foundation blocks or special "flowers" being required and tracking which apiaries have them.
---@param princessSlot integer
---@param droneSlot integer
function BreedOperator:InitiateBreeding(princessSlot, droneSlot)
    -- Pick up the specified bees.
    self.robot.select(PRINCESS_SLOT)
    self.ic.suckFromSlot(self.sides.left, princessSlot, 1)
    self.robot.select(DRONE_SLOT)
    self.ic.suckFromSlot(self.sides.right, droneSlot, 1)

    local distFromStart = 0
    local placed = false
    local scanDirection = self.sides.front
    while not placed do
        -- Move by one step. We scan back and forth.
        self.robot.move(scanDirection)
        if scanDirection == self.sides.front then
            distFromStart = distFromStart + 1

            -- Kinda hacky way of checking whether we've hit the end of the row.
            if self.ic.getInventorySize(self.sides.left) == nil and self.ic.getInventorySize(self.sides.right) == nil then
                break
            end
        else
            distFromStart = distFromStart - 1

            -- If we are back at the output chests, move back into the apiary row.
            if distFromStart == 0 then
                scanDirection = self.sides.front
                self.robot.move(scanDirection)
                distFromStart = 1
            end
        end

        -- If an apiary has no princess/queen, then it must be empty (for our purposes). Place the bees inside.
        if self.ic.getStackInSlot(self.sides.left, PRINCESS_SLOT) == nil then
            self:swapBees(self.sides.left)
            placed = true
        elseif self.ic.getStackInSlot(self.sides.right, PRINCESS_SLOT) == nil then
            self:swapBees(self.sides.right)
            placed = true
        end
    end

    -- Return to the breeder station.
    self:moveDistance(self.sides.back, distFromStart)
end

-- Calculates the chance that an abitrary offspring produced by the given princess and drone will be a pure-bred of the target species.
---@param target string   -- TODO: This is only necessary because breedInfoCache is kinda hacked in here.
---@param princess AnalyzedBeeStack
---@param drone AnalyzedBeeStack
---@param breedInfoCache BreedInfoCache
---@return number
function BreedOperator:CalculateChanceArbitraryOffspringIsPureBredtarget(target, princess, drone, breedInfoCache)
    -- Mutations can only happen between a primary species of one bee and the secondary of the other.
    -- Simply checking the item name (primary species) is insufficient because mutation isn't chosen between primaries.
    local A = princess.individual.active.species.name
    local B = princess.individual.inactive.species.name
    local C = drone.individual.active.species.name
    local D = drone.individual.inactive.species.name

    if breedInfoCache[target] == nil then
        breedInfoCache[target] = {}
    end
    local element = breedInfoCache[target]

    -- Cache these numbers from the server response if we don't already have them.
    for _, combo in ipairs({{A, D}, {B, C}}) do
        if (element[combo[1]] == nil) or (element[combo[2]] == nil) or (element[combo[1]][combo[2]] == nil) or (element[combo[1]][combo[2]]) then
            if element[combo[1]] == nil then
                element[combo[1]] = {}
            end
            if element[combo[2]] == nil then
                element[combo[2]] = {}
            end

            local breedInfo = self.robotComms:GetBreedInfoFromServer(target)
            if breedInfo == nil then
                Print("Unexpected error when retrieving target's breed info from server.")
                return 0.0  -- TODO: This should probably return 'nil' and get propagated up.
            end
            breedInfo = UnwrapNull(breedInfo)

            breedInfoCache[target][princess][drone] = breedInfo
            breedInfoCache[target][drone][princess] = breedInfo
        end
    end

    -- Forestry will attempt to do a mutation twice. If the first succeeds, then parent1 will be replaced by the default genome of the resulting
    -- mutation before the Punnet Square. If the second succeeds, then parent2 will be replaced. Each mutation attempt will randomly try for a
    -- mutation between either (1) the first parent's primary gene (A) and the second parent's secondary gene (D), or (2) the first parent's
    -- secondary gene (B) and the second parent's primary gene (C). Put simpler, each mutation attempt has a 50% chance to try using A+D and a
    -- 50% chance to try using B+C. These are disjoint, so the chance of a mutation event ocurring is equal to the sum of the probabilities of
    -- each choice from AD vs. BC (50% for each) times the chance of the given mutation occurring from that choice of parent alleles.
    -- There is an additional layer here that, for each mutation, Forestry iterates through the (shuffled) list of possible mutations from the
    -- two parent species and tries for a mutation in that order. This complicates the math When a given set of parents can result in multiple
    -- mutations. However, the server has already calculated for us (stored in `breedChanceAD` and `breedChanceBC`) the probability that this
    -- set of parents mutates into the target species and the probability that this set of parents mutates into a non-target species. Therefore,
    -- we don't need to worry about that layer here.
    local breedChanceAD = element[A][D]
    local breedChanceBC = element[B][C]

    -- Each mutation attempt can result in three disjoint events: (1) the mutation fails, (2) the mutation results in the target, (3) the
    -- mutation results in a species other than the target.
    local probMutIsTarget = (0.5 * breedChanceAD.targetMutChance) + (0.5 * breedChanceBC.targetMutChance)
    local probMutIsNonTarget = (0.5 * breedChanceAD.nonTargetMutChance) + (0.5 * breedChanceBC.nonTargetMutChance)
    local probNoMut = 1.0 - (probMutIsTarget - probMutIsNonTarget)  -- Probability of no mutation is the complement of the probability of mutation.

    -- Since there are two independent mutation attempts, we have 9 distinct possibilities before we get to the Punnet Squares: one for each
    -- combination of outcomes from the two attempts. Punnet Squares select a combination of chromosomes by randomly picking one from each parent.
    -- Since there are two chromosomes from each parent, each Punnet Square has 4 possible sets of alleles. This would appear to give us 36
    -- total disjoint events.
    -- However, if a mutation occurs, *both* chromosomes from that parent are replaced with the mutated species, which guarantees that particular
    -- allele to be picked from that parent by the Punnet Square. This results in some repeated outcomes after the Punnet Square based on the
    -- prior events:
    --  * In 4 out of 9 mutation outcomes, both parents have mutated. In these scenarios, there is only one possible Punnet Square outcome.
    --  * In another 4 out of 9 mutation outcomes, just one parent has mutated. In these scenarios, there are two possible Punnet Square outcomes.
    --  * If neither parent mutates (which is most likely), then the resulting Punnet Square has four outcomes.
    -- Thus, there are (4*1) + (4*2) + (1*4) = 16 distinct Punnet Square outcomes to consider.
    -- Additionally, in the 5 out of 9 scenarios where either parent has mutated into a non-target species, the Punnet Square must result in an
    -- offspring with at least one non-target chromosome, which eliminates any chance of getting a pure-bred drone. Thus, we ignore the 7
    -- corresponding Punnet Square outcomes.
    -- Therefore, to calculate the chance of getting a pure-bred drone, we only need to consider 9 final Punnet Square outcomes:
    --  * When neither parent has been replaced:
    --    (1) A + C
    --    (2) A + D
    --    (3) B + C
    --    (4) B + D
    --  * When only parent1 has been replaced:
    --    (5) target + C
    --    (6) target + D
    --  * When only parent2 has been replaced:
    --    (7) A + target
    --    (8) B + target
    --  * When both parents have been replaced:
    --    (9) target + target
    -- The outcomes listed above are disjoint. Therefore, we can obtain the possibility of this particular drone being pure-bred of the target
    -- species by adding up the probability of each of the outcomes which result in a pure-bred drone of our target species (based on the
    -- input alleles for A, B, C, and D).
    -- Additionally, the randomness at each stage of this process is independent from previous stages, so the probability of a given outcome
    -- is simply the product of the probability of each of the events that are required for it to occur.
    local probPureBredTarget = 0.0

    if A == target then
        if C == target then
            -- A + C (requires no mutations and has 1 valid Punnet Square outcome).
            probPureBredTarget = probPureBredTarget + (probNoMut * probNoMut * 0.25)
        end

        if D == target then
            -- A + D (requires no mutations and has 1 valid Punnet Square outcome).
            probPureBredTarget = probPureBredTarget + (probNoMut * probNoMut * 0.25)
        end

        -- A + target (requires parent1 to not mutate and parent2 to mutate into the target, and has 2 valid Punnet Square outcomes)
        probPureBredTarget = probPureBredTarget + (probNoMut * probMutIsTarget * 0.5)
    end
    if B == target then
        if C == target then
            -- B + C (requires no mutations and has 1 valid Punnet Square outcome).
            probPureBredTarget = probPureBredTarget + (probNoMut * probNoMut * 0.25)
        end

        if D == target then
            -- B + D (requires no mutations and has 1 valid Punnet Square outcome).
            probPureBredTarget = probPureBredTarget + (probNoMut * probNoMut * 0.25)
        end

        -- B + target (requires parent1 to not mutate and parent2 to mutate into the target, and has 2 valid Punnet Square outcomes)
        probPureBredTarget = probPureBredTarget + (probNoMut * probMutIsTarget * 0.5)
    end

    if C == target then
        -- target + C (requires parent1 to mutate into the target and parent2 to not mutate, and has 2 valid Punnet Square outcomes)
        probPureBredTarget = probPureBredTarget + (probMutIsTarget * probNoMut * 0.5)

        -- Don't check A or B because we already did the A + C and B + C cases above.
    end
    if D == target then
        -- target + D (requires parent1 to mutate into the target and parent2 to not mutate, and has 2 valid Punnet Square outcomes)
        probPureBredTarget = probPureBredTarget + (probMutIsTarget * probNoMut * 0.5)

        -- Don't check A or B because we already did the A + D and B + D cases above.
    end

    -- target + target (all 4 Punnet Square outcomes are valid).
    probPureBredTarget = probPureBredTarget + (probMutIsTarget * probMutIsTarget * 1.0)

    return probPureBredTarget
end

-- Calculates the chance that the given princess and drone have of producing at least one pure-bred drone of the target species.
---@param target string   -- TODO: This is only necessary because breedInfoCache is kinda hacked in here.
---@param princess AnalyzedBeeStack
---@param drone AnalyzedBeeStack
---@param breedInfoCache BreedInfoCache
---@return number
function BreedOperator:CalculateChanceAtLeastOneOffspringIsPureBredTarget(target, princess, drone, breedInfoCache)
    local probPureBredTarget = self:CalculateChanceArbitraryOffspringIsPureBredtarget(target, princess, drone, breedInfoCache)

    -- The probability of succeeding on at least one offspring drone is equal to the probability of *not* failing on every offspring.
    local probAtLeastOneOffspringIsPureBredTarget = 1.0 - ((1.0 - probPureBredTarget) ^ princess.individual.active.fertility)

    return probAtLeastOneOffspringIsPureBredTarget
end

---@param target string
---@param breedInfoCache table  -- map of parent to otherParent to breed chance (basically a lookup matrix for breeding chance)
---@return integer, integer  -- princessSlot, droneSlot.  If princessSlot is -1, then we have enough drones, and droneSlot contains the finished stack.
function BreedOperator:MatchPrincessToDrone(target, breedInfoCache)

    -- Spin until we have a princess to use.
    ---@type AnalyzedBeeStack
    local princess = nil
    local princessSlotInChest = -1
    while princess == nil do
        for i = 0, BASIC_CHEST_INVENTORY_SLOTS - 1 do
            if self.ic.getStackInSlot(ANALYZED_PRINCESS_CHEST, i) ~= nil then
                princess = self.ic.getStackInSlot(ANALYZED_PRINCESS_CHEST, i)

                -- TODO: Deal with the possibility of not having enough temperature/humidity tolerance to work in the climate.
                --       This will probably just involve putting them in a chest to be sent to a Genetics acclimatizer
                --       and then have them just loop back to this chest later on.
                princessSlotInChest = i
                break
            end
        end

        -- Sleep a little. If we don't have a princess, then no point in consuming resources by checking constantly.
        -- If we do, then sleep a little longer to ensure we have all (or at least several of) the drones.
        Sleep(2.0)
    end

    -- Scan the attached inventory to collect all drones and count how many are pure bred of our target.
    ---@type AnalyzedBeeStack[]
    local drones = {}
    for i = 0, BASIC_CHEST_INVENTORY_SLOTS - 1 do
        ---@type AnalyzedBeeStack
        local droneStack = self.ic.getStackInSlot(i)
        if droneStack ~= nil then
            droneStack.slotInChest = i
            table.insert(drones, droneStack)

            -- TODO: It is possible that drones will have a bunch of different traits and not stack up. We will need to decide whether we want to deal with this possibility
            --       or just force them to stack up. For now, it is simplest to force them to stack.
            if isPureBred(droneStack, target) and droneStack.size == 64 then
                -- If we have a full stack of our target, then we are done.
                return -1, i
            end
        end
    end

    -- Determine the drone that has the highest chance of breeding the result when paired with the given princess.
    -- This is important because we will be making use of ignoble princesses, which start dying after they breed too much.
    -- Being efficient with their use lowers the numbers of other princesses we have to manually load into the system.
    local maxChanceDroneSlotInChest = -1
    local maxChance = 0.0
    for _, drone in ipairs(drones) do
        local chance = self:CalculateChanceAtLeastOneOffspringIsPureBredTarget(target, princess, drone, breedInfoCache)
        if chance > maxChance then
            maxChanceDroneSlotInChest = drone.slotInChest
            maxChance = chance
        end
    end

    -- TODO: We will accumulate more drones than we use during the operation of this breeder, so we need to garbage-collect the chest at some point.

    return princessSlotInChest, maxChanceDroneSlotInChest
end

---@param dist integer
---@param direction integer
function BreedOperator:moveDistance(dist, direction)
    for i = 0, dist do
        self.robot.move(direction)
    end
end

---@return boolean succeeded
function BreedOperator:unloadIntoChest()
    for i = 0, NUM_INTERNAL_SLOTS do
        self.robot.select(i)

        -- Early exit when we have hit the end of the items in the inventory.
        if self.robot.count() == 0 then
            break
        end

        local dropped = self.robot.dropDown()
        if not dropped then
            -- TODO: Deal with the possibility of the chest becoming full.
            Print("Failed to drop items.")
            return false
        end
    end

    return true
end

---@param chestLoc Point
function BreedOperator:moveToChest(chestLoc)
    --- Move to the chest row.
    self:moveDistance(3, self.sides.up)
    self:moveDistance(5, self.sides.right)
    self:moveDistance(3, self.sides.down)

    -- Move to the given chest.
    self:moveDistance(self.sides.right, chestLoc.x)
    self:moveDistance(self.sides.front, chestLoc.y)
end

---@param chestLoc Point
function BreedOperator:returnToBreederStationFromChest(chestLoc)
    -- Retrace to the beginning of the row.
    self:moveDistance(self.sides.back, chestLoc.y)
    self:moveDistance(self.sides.left, chestLoc.x)

    -- Return to the start from the chest row.
    self:moveDistance(3, self.sides.up)
    self:moveDistance(5, self.sides.left)
    self:moveDistance(3, self.sides.down)
end

-- Stores the drones on the robot in the chest at the given point.
-- Starts and ends at the default position in the breeder station.
---@param point Point
function BreedOperator:StoreDrones(point)
    self:moveToChest(point)
    -- TODO: Deal with the possibility of the chest having been broken/moved.
    self:unloadIntoChest()
    self:returnToBreederStationFromChest(point)
end

---@param species string
---@return Point
function BreedOperator:ReportNewSpecies(species)
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

---@param preferences string[]
---@return integer
function BreedOperator:RetrieveStockPrincessesFromChest(preferences)
    -- Go to the storage and pull princesses out of the stock chest.
    self:moveToChest(BREEDING_STOCK_PRINCESSES_LOC)
    -- TODO: Analyze the inventory and try to choose princesses according to the given species preferences.
    self.robot.suckDown(1)  -- TODO: Number of retrieved princesses should be equal to the number of apiaries in use, which itself should be a config option.

    -- Return to the breeding station and place the princesses into the princess chest.
    self:returnToBreederStationFromChest(BREEDING_STOCK_PRINCESSES_LOC)
    self.robot.turnLeft()
    self.robot.drop()
    self.robot.select(0)

    return E_NOERROR
end

---@param loc Point
---@param number integer
---@return integer
function BreedOperator:RetrieveDronesFromChest(loc, number)
    -- Go to the storage and pull drones out of the chest.
    self:moveToChest(loc)
    self.robot.select(0)
    self.robot.suckDown(number)

    -- Return to the breeding station and place the drones into the drone chest.
    self:returnToBreederStationFromChest(loc)
    self.robot.turnRight()
    self.robot.drop()
    self.robot.select(0)

    return E_NOERROR
end

-- Replicates drones of the given species.
-- Places outputs into the holdover chest.
---@param species string
---@return boolean
function BreedOperator:ReplicateSpecies(species)
    -- TODO: At some point, we should probably have a way to store + retrieve breeding stock princesses,
    -- but for now, we will just rely on the user to place them into the princess chest manually.
    -- This system currently only supports breeding a stack of drones that somebody could then
    -- use to very simply turn a different princess into a pure-bred production one.

    local breedInfo = self.robotComms:GetBreedInfoFromServer(species)
    if breedInfo == nil then
        Print("Unexpected error when retrieving breed info of species " .. species .. " from server.")
        return false
    end
    breedInfo = UnwrapNull(breedInfo)

    local storagePoint = self.robotComms:GetStorageLocationFromServer(species)
    if storagePoint == nil then
        Print("Error getting storage location of " .. species .. " from server.")
        return false
    end
    storagePoint = UnwrapNull(storagePoint)

    -- Move starter bees to their respective chests.
    self:RetrieveDronesFromChest(storagePoint, 32)  -- TODO: Is 32 a good number? Should this be dependent on number of apiaries?
    self:RetrieveStockPrincessesFromChest({species})

    -- Replicate extras to replace the drones we took from the chest.
    local princessSlot, droneSlot
    while true do
        princessSlot, droneSlot = self:MatchPrincessToDrone(species, breedInfo)
        if princessSlot == -1 then
            -- We have enough drones now, so break out.
            break
        else
            self:InitiateBreeding(princessSlot, droneSlot)
        end
    end

    -- Double check with the server about the location in case the user changed it during operation.
    -- The user shouldn't really do this, and there's no way to eliminate this conflict entirely,
    -- but this is a mostly trivial way to recover from at least some possible bad behavior.
    storagePoint = self.robotComms:GetStorageLocationFromServer(species)
    if storagePoint == nil then
        storagePoint = self.storageInfo.chestArray[species].loc
    else
        storagePoint = UnwrapNull(storagePoint)
    end

    -- Store one half of the drone stack in the holdover chest.
    self.robot.select(DRONE_SLOT)
    self.ic.suckFromSlot(self.sides.right)
    self:moveDistance(2, self.sides.up)
    self.robot.turnLeft()
    self.robot.drop(32)
    self:moveDistance(2, self.sides.down)

    self:StoreDrones(storagePoint)
end

-- Breeds the target species from the two given parents.
-- Requires drones of each species as inputs already in the holdover chest.
-- Places outputs in the holdover chest.
---@param target string
---@param parent1 string
---@param parent2 string
function BreedOperator:BreedSpecies(target, parent1, parent2)
    -- Breed the target using the left-over drones from both parents and the princesses
    -- implied to be created by breeding the replacements for parent 2.
    -- TODO: Technically, it is likely possible that some princesses may not get converted
    --   to one of the two parents. In this case, it could be impossible to get a drone that
    --   has a non-zero chance to breed the target. For now, we will just rely on random
    --   chance to eventually get us out of this scenario instead of detecting it outright.
    --   To solve the above, we will probably just have PickUpBees prioritize breeding
    --   one of the parents if breeding the target has 0 chance with all princesses/drones.
    local breedInfoCache = {}

    -- Move starter bees to their respective chests.
    self:ImportHoldoversToDroneChest()
    self:RetrieveStockPrincessesFromChest({parent1, parent2})

    local princessSlot, droneSlot
    while true do
        princessSlot, droneSlot = self:MatchPrincessToDrone(target, breedInfoCache)
        if princessSlot == -1 then
            break
        else
            self.robot.select(PRINCESS_SLOT)
            self.ic.suckFromSlot(self.sides.left, princessSlot)
            self.robot.select(DRONE_SLOT)
            self.ic.suckFromSlot(self.sides.right, droneSlot)
            self:InitiateBreeding(princessSlot, droneSlot)
        end
    end

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
    self:StoreDrones(point)
end

-- Retrieves the first two stacks from the holdovers chest and places them in the analyzed drone chest.
-- Starts and ends at the breeder station.
function BreedOperator:ImportHoldoversToDroneChest()
    -- Holdover chest is 2 blocks vertical from the robot's default position at the breeder station.
    self:moveDistance(2, self.sides.up)
    self.robot.turnRight()

    for i = 0, 1 do  -- TODO: Are these slots one-indexed?
        self.robot.select(i)
        self.ic.suckFromSlot(self.sides.front, i)
    end

    self:moveDistance(2, self.sides.down)
    for i = 0, 1 do
        self.robot.select(i)
        self.robot.drop()
    end
    self.robot.select(0)
    self.robot.turnLeft()
end

-- Moves every item in the holdover chest to the output chest.
-- This should be used to finish a transaction and provide user output.
function BreedOperator:ExportHoldoversToOutput()
    -- Holdover and output chests are both 2 blocks vertical from the robot's default position at the breeder station.
    self:moveDistance(2, self.sides.up)

    self.robot.turnRight()  -- Face the holdover chest.
    for i = 0, 26 do  -- TODO: Account for inventories with more than 27 slots. This should be a config option. Also TODO: are these slots one-indexed?
        self.ic.suckFromSlot(self.sides.front, i)
        self.robot.turnAround()
        self.robot.drop()

        if not self.robot.count() == 0 then
            -- We couldn't transfer items from the holdover inventory to the output.
            -- Most likely, this would be caused by the output inventory being full.
            -- Turn around and attempt to drop them back into the holdover inventory.
            self.robot.turnAround()
            self.robot.drop()
            -- It's possible that somebody altered the holdover chest during this operation, which would cause another error.
            -- For now, we won't deal with that unlikely possibility.
            Print("Unable to transfer all items from holdover to output inventory.")
            break
        end
    end
    self.robot.turnLeft()  -- Face front.

    self:moveDistance(2, self.sides.down)
end

return BreedOperator
