-- This module contains logic used by the breeder robot to manipulate bees and the apiaries.
---@class BreedOperator
---@field bk any beekeeper library  TODO: Is this even necessary?
---@field ic any inventory controller library
---@field robot any robot library
---@field sides any sides library
local BreedOperator = {}

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

-- TODO: Check if the inventory controller can even work with these.
local ANALYZED_DRONE_CHEST     -- directly to the right of the breeder station.
local ANALYZED_PRINCESS_CHEST  -- directly to the left of the breeder station.
local HOLDOVER_CHEST           -- to the right of the breeder station, 2 blocks up vertically.
local OUTPUT_CHEST             -- to the left of the breeder station, 2 blocks up vertically.
local TRASH_CAN

-- Info for chests for analyzed bees at the start of the apiary row.
local BASIC_CHEST_INVENTORY_SLOTS = 27

---@return BreedOperator | nil
function BreedOperator:Create(beekeeperLib, inventoryControllerLib, robotLib, sidesLib)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    if beekeeperLib == nil then
        Print("Couldn't find 'beekeeper' module.")
        return nil
    end
    obj.bk = beekeeperLib

    if inventoryControllerLib == nil then
        Print("Couldn't find 'inventory_controller' module.")
        return nil
    end
    obj.ic = inventoryControllerLib

    if robotLib == nil then
        Print("Couldn't find 'robot' module.")
        return nil
    end
    obj.robot = robotLib

    if sidesLib == nil then
        Print("Couldn't find 'sides' module.")
        return nil
    end
    obj.sides = sidesLib

    ANALYZED_PRINCESS_CHEST = sidesLib.left
    ANALYZED_DRONE_CHEST = sidesLib.right
    TRASH_CAN = sidesLib.back
end

---@param side integer
function BreedOperator:swapBees(side)
    self.robot.select(PRINCESS_SLOT)
    self.bk.swapQueen(side)
    self.robot.select(DRONE_SLOT)
    self.bk.swapDrone(side)
end

-- Robot walks the apiary row and starts an empty apiary with the bees in the inventories in the given slots.
-- Starts at the breeding station and ends at the breeding station.
-- TODO: Deal with the possibility of foundation blocks or special "flowers" being required and tracking which apiaries have them.
---@param princessSlot integer
---@param droneSlot integer
function BreedOperator:InitiateBreeding(princessSlot, droneSlot)
    -- Pick up the specified bees.
    self.robot.select(PRINCESS_SLOT)
    self.ic.suckFromSlot(ANALYZED_PRINCESS_CHEST, princessSlot, 1)
    self.robot.select(DRONE_SLOT)
    self.ic.suckFromSlot(ANALYZED_DRONE_CHEST, droneSlot, 1)

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

-- Returns the next princess in ANALYZED_PRINCESS_CHEST.
---@return AnalyzedBeeStack
function BreedOperator:GetPrincessInChest()
    -- Spin until we have a princess to use.
    ---@type AnalyzedBeeStack
    local princess = nil
    while princess == nil do
        for i = 1, BASIC_CHEST_INVENTORY_SLOTS do
            local stack = self.ic.getStackInSlot(ANALYZED_PRINCESS_CHEST, i)
            if stack ~= nil then
                princess = stack
                princess.slotInChest = i

                -- TODO: Deal with the possibility of not having enough temperature/humidity tolerance to work in the climate.
                --       This will probably just involve putting them in a chest to be sent to a Genetics acclimatizer
                --       and then have them just loop back to this chest later on.
                -- TODO: Consider whether we will even handle this here and just have the piping system run them through an acclimatizer.
                break
            end
        end

        -- Sleep a little. If we don't have a princess, then no point in consuming resources by checking constantly.
        -- If we do, then sleep a little longer to ensure we have all (or at least several of) the drones.
        Sleep(2.0)
    end

    return princess
end

-- Returns a list of drones in ANALYZED_DRONE_CHEST.
-- TODO: Reorganize this into a stream to optimize for low memory.
---@return AnalyzedBeeStack[]
function BreedOperator:GetDronesInChest()
    -- Scan the attached inventory to collect all drones and count how many are pure bred of our target.
    local drones = {}
    for i = 1, BASIC_CHEST_INVENTORY_SLOTS do
        ---@type AnalyzedBeeStack
        local droneStack = self.ic.getStackInSlot(i)
        if droneStack ~= nil then
            droneStack.slotInChest = i
            table.insert(drones, droneStack)
        end
    end

    return drones
end

---@param dist integer
---@param direction integer
function BreedOperator:moveDistance(dist, direction)
    for i = 1, dist do
        self.robot.move(direction)
    end
end

---@return boolean succeeded
function BreedOperator:unloadIntoChest()
    for i = 1, NUM_INTERNAL_SLOTS do
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

-- Stores the drones from the given slot in the drone chest in the storage chest at the given point.
-- Starts and ends at the default position in the breeder station.
---@param slot integer
---@param point Point
function BreedOperator:StoreDrones(slot, point)
    -- Grab the drones from the chest.
    self.robot.select(DRONE_SLOT)
    self.ic.suckFromSlot(ANALYZED_DRONE_CHEST, slot)

    self:moveToChest(point)
    -- TODO: Deal with the possibility of the chest having been broken/moved.
    self:unloadIntoChest()
    self:returnToBreederStationFromChest(point)
end

---@param slots integer[]
function BreedOperator:TrashSlotsFromDroneChest(slots)
    -- TODO: Figure out exactly where the trash slot is going to be.
    self.robot.select(1)
    for _, slot in ipairs(slots) do
        self.ic.suckFromSlot(ANALYZED_DRONE_CHEST, slot, 64)
        self.robot.drop(TRASH_CAN, 64)
    end
end

---@param preferences string[]
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
end

---@param loc Point
---@param number integer
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
end

-- Retrieves the first two stacks from the holdovers chest and places them in the analyzed drone chest.
-- Starts and ends at the breeder station.
function BreedOperator:ImportHoldoversToDroneChest()
    -- Holdover chest is 2 blocks vertical from the robot's default position at the breeder station.
    self:moveDistance(2, self.sides.up)
    self.robot.turnRight()

    for i = 1, 2 do
        self.robot.select(i)
        self.ic.suckFromSlot(self.sides.front, i)
    end

    self:moveDistance(2, self.sides.down)
    for i = 1, 2 do
        self.robot.select(i)
        self.robot.drop()
    end
    self.robot.select(0)
    self.robot.turnLeft()
end

-- Moves the given amount of drones from the given slot from the drone chest to the holdover chest.
---@param slot integer
---@param amount integer
function BreedOperator:ExportDroneStackToHoldovers(slot, amount)
    -- Store one half of the drone stack in the holdover chest.
    self.robot.select(DRONE_SLOT)
    self.ic.suckFromSlot(ANALYZED_DRONE_CHEST, slot, amount)
    self:moveDistance(2, self.sides.up)
    self.robot.turnLeft()
    self.robot.drop(amount)
    self:moveDistance(2, self.sides.down)
end

-- Moves every item in the holdover chest to the output chest.
-- This should be used to finish a transaction and provide user output.
function BreedOperator:ExportHoldoversToOutput()
    -- Holdover and output chests are both 2 blocks vertical from the robot's default position at the breeder station.
    self:moveDistance(2, self.sides.up)

    self.robot.turnRight()  -- Face the holdover chest.
    for i = 1, BASIC_CHEST_INVENTORY_SLOTS do  -- TODO: Account for inventories with more than 27 slots. This should be a config option.
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
