-- This module contains logic used by the breeder robot to manipulate bees and the apiaries.
-- TODO: A lot of "return" logic could really just keep track of the moves and then retrace, which would likely be simpler to use.
-- TODO: This entire class assumes that nobody is messing with the system while it is running, so it doesn't check for error on
--       most operations. Although we likely can't recover from any errors, it might be useful to check for them and fail.
---@class BreedOperator
---@field bk any beekeeper library  TODO: Is this even necessary?
---@field ic any inventory controller library
---@field robot any robot library
---@field sides any sides library
---@field numApiaries integer
local BreedOperator = {}

require("Shared.Shared")
local AnalysisUtil = require("BeekeeperBot.BeeAnalysisUtil")

-- Slots for holding items in the robot.
local PRINCESS_SLOT      = 1
local DRONE_SLOT         = 2
local CHEST_SLOT         = 3
local NUM_INTERNAL_SLOTS = 16

-- Info for chests for analyzed bees at the start of the apiary row.
local BASIC_CHEST_INVENTORY_SLOTS = 27

---@param beekeeperLib any
---@param inventoryControllerLib any
---@param robotLib any
---@param sidesLib any
---@param numApiaries integer
---@return BreedOperator | nil
function BreedOperator:Create(beekeeperLib, inventoryControllerLib, robotLib, sidesLib, numApiaries)
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
    obj.numApiaries = numApiaries
end

-- Returns the next princess in ANALYZED_PRINCESS_CHEST.
---@return AnalyzedBeeStack
function BreedOperator:GetPrincessInChest()
    self.robot.turnLeft()

    -- Spin until we have a princess to use.
    ---@type AnalyzedBeeStack
    local princess = nil
    while princess == nil do
        for i = 1, self.ic.getInventorySize() do
            local stack = self.ic.getStackInSlot(self.sides.front, i)
            if stack ~= nil then
                princess = stack
                princess.slotInChest = i
                break
            end
        end

        -- Sleep a little. If we don't have a princess, then no point in consuming resources by checking constantly.
        -- If we do, then sleep a little longer to ensure we have all (or at least several of) the drones.
        Sleep(2.0)
    end

    self.robot.turnRight()

    return princess
end

-- Returns a list of drones in ANALYZED_DRONE_CHEST.
-- TODO: Reorganize this into a stream to optimize for low memory.
---@return AnalyzedBeeStack[]
function BreedOperator:GetDronesInChest()
    self.robot.turnRight()

    -- Scan the attached inventory to collect all drones and count how many are pure bred of our target.
    local drones = {}
    for i = 1, BASIC_CHEST_INVENTORY_SLOTS do
        ---@type AnalyzedBeeStack
        local droneStack = self.ic.getStackInSlot(self.sides.front, i)
        if droneStack ~= nil then
            droneStack.slotInChest = i
            table.insert(drones, droneStack)
        end
    end

    self.robot.turnLeft()

    return drones
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
    -- Pick up the princess, then face forward.
    self.robot.select(PRINCESS_SLOT)
    self.robot.turnLeft()
    self.ic.suckFromSlot(self.sides.front, princessSlot, 1)
    self.robot.turnRight()

    -- Pick up the drone, then face forward.
    self.robot.select(DRONE_SLOT)
    self.robot.turnRight()
    self.ic.suckFromSlot(self.sides.front, droneSlot, 1)
    self.robot.turnLeft()

    -- Move to the start of the apiary row.
    self.robot.up()
    self:moveForwards(2)

    -- Scan in both directions until we find an empty apiary for this princess-drone pair.
    -- Then, place them inside the apiary.
    local distFromStart = 0
    local scanForwards = true
    while true do
        if self.bk.getBeeProgress(self.sides.left) == 0 then
            -- This apiary is empty. Place the princess and drone here.
           self:swapBees(self.sides.left)
           break
        end

        if scanForwards then
            self.robot.forward()
            distFromStart = distFromStart + 1

            if distFromStart == self.numApiaries then
                scanForwards = false
            end
        else
            self.robot.back()
            distFromStart = distFromStart - 1

            if distFromStart == 0 then
                scanForwards = true
            end
        end
    end

    -- Return to the breeder station.
    self:moveBackwards(distFromStart + 2)
    self.robot.down()
end

-- Stores the drones from the given slot in the drone chest in the storage chest at the given point.
-- Starts and ends at the default position in the breeder station.
---@param slot integer
---@param point Point
---@param isNew boolean
function BreedOperator:StoreDrones(slot, point, isNew)
    if isNew then
        -- Grab a new chest from the inputs.
        self:moveToInputChest()

        -- Block until there is a chest ready.
        local i = 1
        while true do
            local stack = self.ic.getStackInSlot(self.sides.front, i)
            if string.find(stack.label, "Chest") ~= nil then
                self.robot.select(CHEST_SLOT)
                self.ic.suckFromSlot(self.sides.front, i, 1)
                break
            end

            i = i + 1
            if i > self.ic.getInventorySize(self.sides.front) then
                i = 1
            end
        end

        self:returnToBreederStationFromInputChest()
    end

    -- Grab the drones from the chest.
    self.robot.select(DRONE_SLOT)
    self.robot.turnRight()
    self.ic.suckFromSlot(self.sides.front, slot, 64)

    -- Store the drones in the storage column.
    self:moveToStorageColumn()
    self:moveToChestFromStorageColumn(point)

    if isNew then
        -- Place the chest, then back up to be facing it.
        self.robot.forward()
        self.robot.up()
        self.robot.select(CHEST_SLOT)
        self.robot.placeDown(self.sides.down, true)
        self.robot.back()
        self.robot.down()
    end

    self:unloadInventory()
    self:returnToStorageColumnOriginFromChest(point)
    self:returnToBreederStationFromStorageColumn()
end

---@param dist integer
function BreedOperator:moveForwards(dist)
    for i = 1, dist do
        self.robot.forward()
    end
end

---@param dist integer
function BreedOperator:moveBackwards(dist)
    for i = 1, dist do
        self.robot.back()
    end
end

---@param dist integer
function BreedOperator:moveUpwards(dist)
    for i = 1, dist do
        self.robot.up()
    end
end

---@param dist integer
function BreedOperator:moveDownwards(dist)
    for i = 1, dist do
        self.robot.down()
    end
end

---@return boolean succeeded
function BreedOperator:unloadInventory()
    for i = 1, NUM_INTERNAL_SLOTS do
        self.robot.select(i)

        local dropped = self.robot.drop(64)
        if not dropped then
            -- TODO: Deal with the possibility of the chest becoming full.
            Print("Failed to drop items.")
            return false
        end
    end

    return true
end

-- Moves the robot from the breeder station to position {-1, -1, -1} of the storage column.
function BreedOperator:moveToStorageColumn()
    --- Move to the chest row.
    self.robot.forward()
    self.robot.turnRight()
    self:moveForwards(4)
end

-- Moves the robot from position {-1, -1, -1} of the storage column back to the breeder station.
function BreedOperator:returnToBreederStationFromStorageColumn()
    self:moveBackwards(4)
    self.robot.turnLeft()
    self.robot.back()
end

-- Moves the robot from position {-1, -1, -1} of the storage column to be facing the chest at the given point.
---@param point Point
function BreedOperator:moveToChestFromStorageColumn(point)
    self:moveForwards(point.z)
    self.robot.turnLeft()
    self:moveForwards(point.x + 1)
    self.robot.turnRight()
    self:moveUpwards(point.y)
end

-- Moves the robot from the chest at the given point to position {-1, -1, -1} of the storage column.
function BreedOperator:returnToStorageColumnOriginFromChest(point)
    self:moveDownwards(point.y)
    self.robot.turnRight()
    self:moveForwards(point.x + 1)
    self.robot.turnLeft()
    self:moveBackwards(point.z)
end

-- Moves all stacks from the given slot in the drone chest to the trash can.
-- If slots is nil, then trashes all slots.
---@param slots integer[] | nil
function BreedOperator:TrashSlotsFromDroneChest(slots)
    if slots == nil then
        slots = {}
        for i = 1, 27 do
            table.insert(slots, i)
        end
    end

    self.robot.select(1)
    self.robot.turnRight()

    for _, slot in ipairs(slots) do
        -- Pick up the stack.
        self.ic.suckFromSlot(self.sides.front, slot, 64)

        -- Trash the stack.
        self.robot.turnRight()
        self.robot.drop(64)

        -- Turn back to the drone chest.
        self.robot.turnLeft()
    end

    -- Clean up by returning to starting position.
    self.robot.turnLeft()
end

-- Moves `n` princesses from the stock chest into the princess chest.
-- Attempts to choose princesses according to the preferences list.
-- TODO: Actually utilize the preferences list.
-- TODO: Deal with n > 16.
---@param n integer
---@param preferences string[]
function BreedOperator:RetrieveStockPrincessesFromChest(n, preferences)
    -- Move to the stock princesses chest.
    self:moveToStorageColumn()
    self.robot.turnRight()
    self.robot.forward()
    self.robot.turnLeft()

    -- Get the princesses out of the chest.
    local numRetrieved = 0
    self.robot.select(1)
    while numRetrieved < n do
        local numGotten = self.robot.suck(n - numRetrieved)
        numRetrieved = numRetrieved + numGotten
    end

    -- Return to the breeder station.
    self.robot.turnLeft()
    self.robot.forward()
    self.robot.turnRight()
    self:returnToBreederStationFromStorageColumn()

    -- Unload the princesses into the active princess chest.
    self.robot.turnLeft()
    self:unloadInventory()

    -- Clean up by returning to starting position.
    self.robot.turnRight()
end

function BreedOperator:ReturnActivePrincessesToStock()
    -- Pick up princesses from the active chest.
    -- TODO: Deal with having more than 16 princesses.
    self.robot.turnLeft()
    for i = 1, NUM_INTERNAL_SLOTS do
        self.robot.select(i)
        self.robot.suck(64)
    end
    self.robot.turnRight()

    -- Move to the stock chest and unload the princesses.
    self:moveToStorageColumn()
    self.robot.turnRight()
    self.robot.forward()
    self.robot.turnLeft()
    self:unloadInventory()

    -- Return to the breeder station.
    self.robot.turnLeft()
    self.robot.forward()
    self.robot.turnRight()
    self:returnToBreederStationFromStorageColumn()
end

-- Retrieves `number` drones from the chest located at `loc` in the storage column.
---@param loc Point
---@param number integer
function BreedOperator:RetrieveDronesFromChest(loc, number)
    -- Retrieve the drones from the chest.
    -- TODO: Deal with the possibility of drones not being in the chest.
    self:moveToStorageColumn()
    self:moveToChestFromStorageColumn(loc)
    self.robot.select(1)
    self.robot.suck(number)
    self:returnToStorageColumnOriginFromChest(loc)
    self:returnToBreederStationFromStorageColumn()

    -- Unload the drones into the active drone chest.
    self.robot.turnRight()
    self:unloadInventory()

    -- Clean up by returning to starting position.
    self.robot.turnLeft()
end

-- Retrieves a stack of drones and a princess with the given template and places them in the active chests.
---@param templateTraits AnalyzedBeeTraits
function BreedOperator:RetrieveBeesWithTemplate(templateTraits)
    -- Move to the templates chest.
    self:moveToStorageColumn()
    self.robot.turnRight()
    self.robot.forward()
    self.robot.turnLeft()
    self.robot.up()

    -- TODO: Deal with the case where the template doesn't actually exist.
    local hasDrones = false
    local hasPrincess = false
    for i = 1, self.ic.getInventorySize(self.sides.front) do
        local stack = self.ic.getStackInSlot(self.sides.front, i)
        if (stack == nil) or AnalysisUtil.AllTraitsEqual(stack.individual, templateTraits) then
            goto continue
        end

        if (not hasDrones) and (string.find(stack.label, "Drone") ~= nil) then
            self.robot.select(DRONE_SLOT)
            self.ic.suckFromSlot(self.sides.front, i, 64)
            hasDrones = true
        elseif (not hasPrincess) and (string.find(stack.label, "[P|p]rincess") ~= nil) then
            self.robot.select(PRINCESS_SLOT)
            self.ic.suckFromSlot(self.sides.front, i, 1)
            hasPrincess = true
        end

        if hasDrones and hasPrincess then
            break
        end

        ::continue::
    end

    -- Return to the breeder station.
    self.robot.down()
    self.robot.turnLeft()
    self.robot.forward()
    self.robot.turnRight()
    self:returnToBreederStationFromStorageColumn()

    -- Unload the bees, then return to starting orientation.
    self.robot.turnRight()
    self.robot.select(DRONE_SLOT)
    self.robot.drop(64)
    self.robot.turnLeft()
    self.robot.turnLeft()
    self.robot.select(PRINCESS_SLOT)
    self.robot.drop(1)
    self.robot.turnRight()
end

---@param droneChestSlot integer
---@param princessChestSlot integer
function BreedOperator:StoreBeesInTemplate(droneChestSlot, princessChestSlot)
    -- Grab drones.
    self.robot.turnRight()
    self.robot.select(DRONE_SLOT)
    self.ic.suckFromSlot(self.sides.front, droneChestSlot, 64)

    -- Grab princess.
    self.robot.turnLeft()
    self.robot.turnLeft()
    self.robot.select(PRINCESS_SLOT)
    self.ic.suckFromSlot(self.sides.front, princessChestSlot, 1)

    -- Move to templates chest.
    self:moveToStorageColumn()
    self.robot.turnRight()
    self.robot.forward()
    self.robot.turnLeft()
    self.robot.up()

    -- Unload the bees.
    self.robot.select(DRONE_SLOT)
    self.robot.drop(64)
    self.robot.select(PRINCESS_SLOT)
    self.robot.drop(1)

    -- Return to the breeder station.
    self.robot.down()
    self.robot.turnLeft()
    self.robot.forward()
    self.robot.turnRight()
    self:returnToBreederStationFromStorageColumn()
end

-- Retrieves the first two stacks from the holdover chest and places them in the analyzed drone chest.
-- Starts and ends at the breeder station.
---@param holdoverChestSlots integer[]
---@param amounts integer[]
---@param droneChestSlots integer[]
function BreedOperator:ImportHoldoverStacksToDroneChest(holdoverChestSlots, amounts, droneChestSlots)
    -- Move to the Holdover chest, located 1 block vertical from the robot's default position at the breeder station.
    self.robot.up()
    self.robot.turnRight()

    -- Get the drone stacks out of the Holdover chest.
    for i, slot in ipairs(holdoverChestSlots) do
        self.robot.select(i)
        self.ic.suckFromSlot(self.sides.front, slot, amounts[i])
    end

    -- Place the drone stacks into the Drone chest.
    self.robot.down()
    for i, slot in ipairs(droneChestSlots) do
        self.robot.select(i)
        self.ic.dropIntoSlot(self.sides.front, slot, amounts[i])
    end

    -- Clean up by returning to starting position.
    self.robot.turnLeft()
end

---@param holdoverChestSlots integer[]
---@param amounts integer[]
---@param princessChestSlots integer[]
function BreedOperator:ImportHoldoverStacksToPrincessChest(holdoverChestSlots, amounts, princessChestSlots)
    -- Move to the Holdover chest, located 1 block vertical from the robot's default position at the breeder station.
    self.robot.up()
    self.robot.turnRight()

    -- Get the princess stacks out of the Holdover chest.
    for i, slot in ipairs(holdoverChestSlots) do
        self.robot.select(i)
        self.ic.suckFromSlot(self.sides.front, slot, amounts[i])
    end

    -- Place the princess stacks into the Drone chest.
    self.robot.down()
    self.robot.turnLeft()
    self.robot.turnLeft()
    for i, slot in ipairs(princessChestSlots) do
        self.robot.select(i)
        self.ic.dropIntoSlot(self.sides.front, slot, amounts[i])
    end

    -- Clean up by returning to starting position.
    self.robot.turnRight()
end

-- Moves the given drones from the drone chest to the holdover chest.
---@param droneChestSlots integer[]
---@param amounts integer[]
---@param holdoverChestSlots integer[]
function BreedOperator:ExportDroneStacksToHoldovers(droneChestSlots, amounts, holdoverChestSlots)
    -- Take stacks out of the drone chest.
    self.robot.turnRight()
    for i, slot in ipairs(droneChestSlots) do
        self.robot.select(i)
        self.ic.suckFromSlot(self.sides.front, slot, amounts[i])
    end

    -- Place stack in the holdover chest.
    self.robot.up()
    for i, slot in ipairs(holdoverChestSlots) do
        self.robot.select(i)
        self.ic.dropIntoSlot(self.sides.front, slot, amounts[i])
    end

    -- Clean up by returning to starting position.
    self.robot.down()
    self.robot.turnLeft()
end

-- Moves the given princesses from the princess chest to the holdover chest.
---@param princessChestSlots integer[]
---@param amounts integer[]
---@param holdoverChestSlots integer[]
function BreedOperator:ExportPrincessStacksToHoldovers(princessChestSlots, amounts, holdoverChestSlots)
    -- Take stacks out of the princess chest.
    self.robot.turnLeft()
    for i, slot in ipairs(princessChestSlots) do
        self.robot.select(i)
        self.ic.suckFromSlot(self.sides.front, slot, amounts[i])
    end

    -- Place stack in the holdover chest.
    self.robot.turnRight()
    self.robot.turnRight()
    self.robot.up()
    for i, slot in ipairs(holdoverChestSlots) do
        self.robot.select(i)
        self.ic.dropIntoSlot(self.sides.front, slot, amounts[i])
    end

    -- Clean up by returning to starting position.
    self.robot.down()
    self.robot.turnLeft()
end

-- Moves the princesses in the import chest to the breeding stock chest.
function BreedOperator:ImportPrincessesToStock()
    self:moveToInputChest()

    -- TODO: Deal with the case where there are more than 16 princesses.
    -- There are several items in this input chest. Only pick up the princesses.
    local numInternalSlotsTaken = 0
    for i = 1, self.ic.getInventorySize(self.sides.front) do
        local stack = self.ic.getStackInSlot(self.sides.front, i)
        if (stack ~= nil) and (string.find(stack.label, "[P|p]rincess") ~= nil) then
            self.robot.select(numInternalSlotsTaken + 1)
            self.ic.suckFromSlot(self.sides.front, i, 64)

            numInternalSlotsTaken = numInternalSlotsTaken + 1
            if numInternalSlotsTaken >= 16 then
                break
            end
        end
    end

    -- Move to the stock princess chest.
    self:returnToBreederStationFromInputChest()
    self:moveToStorageColumn()
    self.robot.turnRight()
    self.robot.forward()
    self.robot.turnLeft()

    self:unloadInventory()

    -- Clean up by returning to the starting position.
    self.robot.turnRight()
    self.robot.forward()
    self.robot.turnRight()
    self:returnToBreederStationFromStorageColumn()
end

-- Moves the specified number of drones from the given slot in the active chest to the output chest.
---@param slot integer
function BreedOperator:ExportDroneStackToOutput(slot, number)
    self.robot.select(1)

    -- Pick up drones.
    self.robot.turnRight()
    self.ic.suckFromSlot(self.sides.front, slot, number)
    self.robot.turnLeft()

    -- Go to chest and unload, then return to the breeder station.
    self:moveToOutputChest()
    self.robot.drop(number)
    self:returnToBreederStationFromOutputChest()
end

-- Moves the specified number of princesses from the given slot in the active chest to the output chest.
---@param slot integer
function BreedOperator:ExportPrincessStackToOutput(slot, number)
    self.robot.select(1)

    -- Pick up princesses.
    self.robot.turnLeft()
    self.ic.suckFromSlot(self.sides.front, slot, number)
    self.robot.turnRight()

    -- Go to chest and unload, then return to the breeder station.
    self:moveToOutputChest()
    self.robot.drop(number)
    self:returnToBreederStationFromOutputChest()
end

-- Moves the robot from the breeder station to facing the input chest.
function BreedOperator:moveToInputChest()
    self.robot.up()
    self:moveBackwards(2)
    self.robot.turnLeft()
    self.robot.forward()
    self.robot.turnLeft()
end

function BreedOperator:returnToBreederStationFromInputChest()
    self.robot.turnLeft()
    self.robot.forward()
    self.robot.turnLeft()
    self:moveForwards(2)
    self.robot.down()
end

-- Moves the robot from the breeder station to facing the output chest.
function BreedOperator:moveToOutputChest()
    self.robot.up()
    self:moveBackwards(2)
    self.robot.turnRight()
    self.robot.forward()
    self.robot.turnRight()
end

function BreedOperator:returnToBreederStationFromOutputChest()
    self.robot.turnRight()
    self.robot.forward()
    self.robot.turnRight()
    self:moveForwards(2)
    self.robot.down()
end

function BreedOperator:BreakAndReturnFoundationsToInputChest()
    -- Get pickaxe from inputs chest.
    -- TODO: Deal with pickaxes not being there.
    self:moveToInputChest()
    self.robot.select(1)
    for i = 1, self.ic.getInventorySize(self.sides.front) do
        local stack = self.ic.getStackInSlot(self.sides.front, i)
        if (stack ~= nil) and (string.find(stack.label, "[P|p]ickaxe") ~= nil) then
            self.ic.suckFromSlot(self.sides.front, i, 1)
            break
        end
    end
    self:returnToBreederStationFromInputChest()

    -- Break the existing foundation blocks, then return to the breeder station.
    self.robot.forward()
    for i = 1, self.numApiaries do
        self.robot.forward()
        self.robot.turnLeft()
        self.robot.swing()
        self.robot.turnRight()
    end
    self:moveBackwards(self.numApiaries + 1)

    -- Return the pickaxe and the foundation blocks to the inputs chest.
    self:moveToInputChest()
    self:unloadInventory()

    self:returnToBreederStationFromInputChest()
end

---@param block string
---@return "success" | "no foundation"
function BreedOperator:PlaceFoundations(block)
    -- Get foundations from chest.
    self:moveToInputChest()
    self.robot.select(1)
    local hasStack = false
    for i = 1, self.ic.getInventorySize(self.sides.front) do
        local stack = self.ic.getStackInSlot(self.sides.front, i)
        if (stack ~= nil) and (string.find(stack.label, block) ~= nil) and (stack.size >= self.numApiaries) then  -- TODO: Allow foundation blocks to be spread out over multiple stacks.
            self.ic.suckFromSlot(self.sides.front, i, self.numApiaries)
            hasStack = true
            break
        end
    end
    self:returnToBreederStationFromInputChest()

    if not hasStack then
        return "no foundation"
    end

    -- Place the foundations.
    self.robot.forward()
    for i = 1, self.numApiaries do
        self.robot.forward()
        self.robot.turnLeft()
        self.robot.place()
        self.robot.turnRight()
    end
    self:moveBackwards(self.numApiaries + 1)

    return "success"
end

return BreedOperator
