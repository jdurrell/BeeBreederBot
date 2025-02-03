-- This file contains logic used by the breeder robot to manipulate bees and the apiaries.

---@param side integer
local function swapBees(side)
    Robot.select(PRINCESS_SLOT)
    BK.swapQueen(side)
    Robot.select(DRONE_SLOT)
    BK.swapDrone(side)
end

---@param beeStack AnalyzedBeeStack
---@param species string
---@return boolean
local function isPureBred(beeStack, species)
    return (beeStack.individual.active.species == beeStack.individual.inactive.species)
end

-- Robot walks the apiary row and starts an empty apiary with the bees in its internal inventory.
-- TODO: Deal with the possibility of foundation blocks or special "flowers" being required and tracking which apiaries have them.
function WalkApiariesAndStartBreeding()
    local distFromStart = 0
    local placed = false
    local scanDirection = Sides.front
    while not placed do
        -- Move by one step. We scan back and forth.
        Robot.move(scanDirection)
        if scanDirection == Sides.front then
            distFromStart = distFromStart + 1

            -- Kinda hacky way of checking whether we've hit the end of the row.
            if IC.getInventorySize(Sides.left) == nil and IC.getInventorySize(Sides.right) == nil then
                break
            end
        else
            distFromStart = distFromStart - 1

            -- If we are back at the output chests, move back into the apiary row.
            if distFromStart == 0 then
                scanDirection = Sides.front
                Robot.move(scanDirection)
                distFromStart = 1
            end
        end

        -- If an apiary has no princess/queen, then it must be empty (for our purposes). Place the bees inside.
        if IC.getStackInSlot(Sides.left, PRINCESS_SLOT) == nil then
            swapBees(Sides.left)
            placed = true
        elseif IC.getStackInSlot(Sides.right, PRINCESS_SLOT) == nil then
            swapBees(Sides.right)
            placed = true
        end
    end

    -- Return to the output chests.
    while distFromStart > 0 do
        Robot.move(Sides.back)
        distFromStart = distFromStart - 1
    end
end

-- TODO: Finish implementing this.
---@param princess AnalyzedBeeStack
---@param drone AnalyzedBeeStack
---@param breedInfo BreedInfo
---@return number
local function calculateTargetMutationChance(princess, drone, breedInfo)

    -- Mutations can only happen between a primary species of one bee and the secondary of the other.
    -- Simply checking the item name (primary species) is insufficient because mutation isn't chosen between primaries.
    local princessPrimarySpecies = ""
    local princessSecondarySpecies = ""
    local dronePrimarySpecies = ""
    local droneSecondarySpecies = ""
    local breedChancePrincessPrimaryDroneSecondary = breedInfo[princessPrimarySpecies][droneSecondarySpecies]
    local breedChancePrincessSecondaryDronePrimary = breedInfo[princessSecondarySpecies][dronePrimarySpecies]

    local breedChance = 0.5 * (breedChancePrincessPrimaryDroneSecondary + breedChancePrincessSecondaryDronePrimary)

    -- Favor higher fertility for higher chances at drones.
    -- TODO: This doesn't directly affect the number of offspring this generation, so it doesn't *really* affect the "target mutation chance" that we're calculating here.
    --       We should determine an exact policy for a clearer understanding of how we want this information to be considered.
    breedChance = breedChance * drone.individual.active.fertility

    return breedChance
end

---@param target string
---@param breedInfo BreedInfo  -- map of parent to otherParent to breed chance (basically a lookup matrix for breeding chance)
---@return integer  -- returns 0 if this succeeded, -1 if it timed out before finding some valid pairing, or 1 if it failed because we have enough drones of the target to move on.
function PickUpBees(target, breedInfo)

    -- Spin until we have a princess to use.
    ---@type AnalyzedBeeStack
    local princess = nil
    local princessSlotInChest = -1
    while princess == nil do
        for i = 0, BASIC_CHEST_INVENTORY_SLOTS do
            if IC.getStackInSlot(ANALYZED_PRINCESS_CHEST, i) ~= nil then
                princess = IC.getStackInSlot(ANALYZED_PRINCESS_CHEST, i)

                -- TODO: Deal with the possibility of not having enough temperature/humidity tolerance to work in the climate.
                --       This will probably just involve putting them in a chest to be sent to a Genetics acclimatizer
                --       and then have them just loop back to this chest later on.
                princessSlotInChest = i
                break
            end
        end

        -- If we don't have a princess right now, then sleep a little to give time to get one.
        -- No point in consuming resources by checking constantly.
        if princess == nil then
            return E_NOPRINCESS
        end
    end

    -- Sleep a little longer to ensure we have all (or at least several of) the drones
    Sleep(2.0)

    -- Scan the attached inventory to collect all drones and count how many are pure bred of our target.
    ---@type AnalyzedBeeStack[]
    local drones = {}
    for i = 0, BASIC_CHEST_INVENTORY_SLOTS do
        ---@type AnalyzedBeeStack
        local droneStack = IC.getStackInSlot(i)
        if droneStack ~= nil then
            droneStack.slotInChest = i
            table.insert(drones, droneStack)

            -- TODO: It is possible that drones will have a bunch of different traits and not stack up. We will need to decide whether we want to deal with this possibility
            --       or just force them to stack up. For now, it is simplest to force them to stack.
            if isPureBred(droneStack, target) and droneStack.size == 64 then
                -- If we have a full stack of our target, then we are done. Pick up the drones into the output slot.
                Robot.select(DRONE_SLOT)
                IC.suckFromSlot(i, 64)
            end
        end
    end

    -- Determine the drone that has the highest chance of breeding the result when paired with the given princess.
    -- This is important because we will be making use of ignoble princesses, which start dying after they breed too much.
    -- Being efficient with their use lowers the numbers of other princesses we have to manually load into the system.
    local maxChanceDroneSlotInChest = -1
    local maxChance = 0.0
    for i, drone in ipairs(drones) do
        local chance = calculateTargetMutationChance(princess, drone, breedInfo)
        if chance > maxChance then
            maxChanceDroneSlotInChest = drone.slotInChest
            maxChance = chance
        end
    end

    -- TODO: We will accumulate more drones than we use during the operation of this breeder, so we need to garbage-collect the chest at some point.

    -- Actually pick up the bees.
    Robot.select(PRINCESS_SLOT)
    IC.suckFromSlot(ANALYZED_PRINCESS_CHEST, princessSlotInChest, 1)
    Robot.select(DRONE_SLOT)
    IC.suckFromSlot(ANALYZED_DRONE_CHEST, maxChanceDroneSlotInChest, 1)

    return 0
end

---@param dist integer
---@param direction integer
local function moveDistance(dist, direction)
    for i = 0, dist do
        Robot.move(direction)
    end
end

---@return boolean succeeded
local function unloadIntoChest()
    for i = 0, NUM_INTERNAL_SLOTS do
        Robot.select(i)

        -- Early exit when we have hit the end of the items in the inventory.
        if Robot.count() == 0 then
            break
        end

        local dropped = Robot.dropDown()
        if not dropped then
            -- TODO: Deal with the possibility of the chest becoming full.
            Print("Failed to drop items.")
            return false
        end
    end

    return true
end

---@param chestLoc Point
local function moveToChest(chestLoc)
    --- Move to the chest row.
    Robot.move(Sides.up)
    moveDistance(5, Sides.right)
    Robot.move(Sides.down)

    -- Move to the given chest.
    moveDistance(Sides.right, chestLoc.x)
    moveDistance(Sides.front, chestLoc.y)
end

---@param chestLoc Point
local function returnToStartFromChest(chestLoc)
    -- Retrace to the beginning of the row.
    moveDistance(Sides.back, chestLoc.y)
    moveDistance(Sides.left, chestLoc.x)

    -- Return to the start from the chest row.
    Robot.move(Sides.up)
    moveDistance(5, Sides.left)
    Robot.move(Sides.down)
end

---@param species string
---@param filepath string
---@param storageInfo StorageInfo
---@return StorageNode
function StoreSpecies(species, filepath, storageInfo)
    local chestNode = storageInfo.chestArray[species]
    if chestNode == nil then
        -- No pre-existing store for this species. Pick the next open one.
        -- Copy by value so that we can update nextChest here as well.
        chestNode = {
            loc = {
                x = storageInfo.nextChest.x,
                y = storageInfo.nextChest.y
            },
            timestamp = GetCurrentTimestamp()
        }

        storageInfo.nextChest.x = storageInfo.nextChest.x + 1
        if storageInfo.nextChest.x > 2 then
            storageInfo.nextChest.x = 0
            storageInfo.nextChest.y = storageInfo.nextChest.y + 1
        end

        storageInfo.chestArray[species] = chestNode

        -- Store this location on our own logfile in case the server is down, and we need to re-sync later.
        LogSpeciesToDisk(filepath, species, chestNode.loc, chestNode.timestamp)
    end

    moveToChest(chestNode.loc)
    -- TODO: Deal with the possibility of the chest having been broken/moved.
    unloadIntoChest()
    returnToStartFromChest(chestNode.loc)

    return chestNode
end

---@param loc Point
---@param number integer
---@param intoSlot integer
---@return integer
function RetrieveDronesFromChest(loc, number, intoSlot)
    moveToChest(loc)

    Robot.select(intoSlot)
    Robot.suckDown(number)

    returnToStartFromChest(loc)

    Robot.turnRight()
    Robot.drop()
    Robot.select(0)

    return E_NOERROR
end
