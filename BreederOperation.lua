-- This file contains logic used by the breeder robot to manipulate bees and the apiaries.

---@param side integer
local function swapBees(side)
    Robot.select(PRINCESS_SLOT)
    BK.swapQueen(side)
    Robot.select(DRONE_SLOT)
    BK.swapDrone(side)
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

---@param target string
---@param princess AnalyzedBeeStack
---@param drone AnalyzedBeeStack
---@param breedInfo table<string, table<string, number>>
---@return number
local function calculateTargetMutationChance(target, princess, drone, breedInfo)

    -- Mutations can only happen between a primary species of one bee and the secondary of the other.
    -- Simply checking the item name (primary species) is insufficient because mutation isn't chosen between primaries.
    local princessPrimarySpecies = ""
    local princessSecondarySpecies = ""
    local dronePrimarySpecies = ""
    local droneSecondarySpecies = ""
    local breedChancePrincessPrimaryDroneSecondary = breedInfo[princessPrimarySpecies][droneSecondarySpecies]
    local breedChancePrincessSecondaryDronePrimary = breedInfo[princessSecondarySpecies][dronePrimarySpecies]

    -- TODO: Account for multiple possible mutations and order shuffling logic.
    -- TODO: Account for escritoire reseach.
    -- TODO: Perhaps the above TODOs should be calculated by the server and baked into the breedInfo received by the robot...

    local breedChance = 0.5 * (breedChancePrincessPrimaryDroneSecondary + breedChancePrincessSecondaryDronePrimary)

    -- Favor higher fertility for higher chances at drones.
    -- TODO: This doesn't directly affect the number of offspring this generation, so it doesn't *really* affect the "target mutation chance" that we're calculating here.
    --       We should determine an exact policy for a clearer understanding of how we want this information to be considered.
    breedChance = breedChance * drone.individual.active.fertility

    return breedChance
end

---@param target string
---@param breedInfo table<string, table<string, number>>  -- map of parent to otherParent to breed chance (basically a lookup matrix for breeding chance)
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

    -- Collect a list of all drones in the attached inventory.
    ---@type AnalyzedBeeStack[]
    local drones = {}
    for i = 0, BASIC_CHEST_INVENTORY_SLOTS do
        if IC.getStackInSlot(i) ~= nil then
            table.insert(drones, IC.getStackInSlot(i))
        end
    end

    -- Determine the drone that has the highest chance of breeding the result when paired with the given princess.
    -- This is important because we will be making use of ignoble princesses, which start dying after they breed too much
    -- being efficient with their use lowers the numbers of other princesses we have to manually load into the system.
    local maxChanceDroneSlotInChest = -1
    local maxChance = 0.0
    for i, drone in ipairs(drones) do
        local chance = calculateTargetMutationChance(target, princess, drone, breedInfo)
        if chance > maxChance then
            maxChanceDroneSlotInChest = i
            maxChance = chance
        end
    end

    -- Actually pick up the bees.
    Robot.select(PRINCESS_SLOT)
    IC.suckFromSlot(ANALYZED_PRINCESS_CHEST, princessSlotInChest, 1)
    Robot.select(DRONE_SLOT)
    IC.suckFromSlot(ANALYZED_DRONE_CHEST, maxChanceDroneSlotInChest, 1)

    return 0
end