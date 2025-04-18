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
local NUM_INTERNAL_SLOTS = 16

-- Info for chests for analyzed bees at the start of the apiary row.
local BASIC_CHEST_INVENTORY_SLOTS = 27

---@param componentLib Component
---@param robotLib any
---@param sidesLib any
---@param numApiaries integer
---@return BreedOperator | nil
function BreedOperator:Create(componentLib, robotLib, sidesLib, numApiaries)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    if not TableContains(componentLib.list(), "beekeeper") then
        Print("Couldn't find 'beekeeper' component.")
        return nil
    elseif not TableContains(componentLib.list(), "inventory_controller") then
        Print("Couldn't find 'inventory_controller' component.")
        return nil
    end

    obj.bk = componentLib.beekeeper
    obj.ic = componentLib.inventory_controller
    obj.robot = robotLib
    obj.sides = sidesLib
    obj.numApiaries = numApiaries

    return obj
end

-- Returns the next princess in the active princess chest.
---@return AnalyzedBeeStack
function BreedOperator:GetPrincessInChest()
    self.robot.turnLeft()

    -- Spin until we have a princess to use.
    ---@type AnalyzedBeeStack
    local princess = nil
    while princess == nil do
        for i = 1, self.ic.getInventorySize(self.sides.front) do
            local stack = self.ic.getStackInSlot(self.sides.front, i)
            if stack ~= nil then
                princess = stack
                princess.slotInChest = i
                break
            end
        end

        -- Sleep a little. If we don't have a princess, then no point in consuming resources by checking constantly.
        -- If we do, then sleep a little longer to ensure we have all (or at least several of) the drones.
        Sleep(10)
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
        -- TODO: This isn't necessarily a good condition because there could be problematic environments.
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
---@param slots integer[]  Max size 16.
---@return boolean success
function BreedOperator:StoreDronesFromActiveChest(slots)

    -- Grab the drones from the chest.
    self.robot.turnRight()
    for i, slot in ipairs(slots) do
        self.robot.select(i)
        self.ic.suckFromSlot(self.sides.front, slot, 64)
    end
    self.robot.turnLeft()

    return self:storeDrones()
end

-- Returns a list of bees in the storage system and where to find them.
---@return AnalyzedBeeTraits[]
function BreedOperator:ScanAllDroneStacks()
    self:moveToStorageColumn()

    local droneStacks = {}
    local chest = 0
    while self.ic.getInventorySize(self.sides.front) ~= nil do
        for i = 1, self.ic.getInventorySize(self.sides.front) do
            local stack = self.ic.getStackInSlot(self.sides.front, i)
            if (stack ~= nil) and (stack.label:find("[D|d]rone") ~= nil) and (stack.size == 64) then
                                -- This is a valid drone stack, so add it to the list.
                -- All drones in storage are pure-bred, so we only need to add one set of traits.
                table.insert(droneStacks, stack.individual.active)
            end
        end

        self.robot.turnLeft()
        self.robot.forward()
        self.robot.turnRight()
        chest = chest + 1
    end

    return droneStacks
end

---@param slot integer
---@return AnalyzedBeeStack | nil
function BreedOperator:GetStackInDroneSlot(slot)
    self.robot.turnRight()
    local stack = self.ic.getStackInSlot(self.sides.front, slot)
    self.robot.turnLeft()

    return stack
end

---@return boolean succeeded
function BreedOperator:unloadInventory()
    for i = 1, NUM_INTERNAL_SLOTS do
        self.robot.select(i)
        if self.robot.count() == 0 then
            goto continue
        end

        local dropped = self.robot.drop(64)
        if not dropped then
            -- TODO: Deal with the possibility of the chest becoming full.
            Print("Failed to drop items.")
            return false
        end
        ::continue::
    end

    return true
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
---@param preferences string[] | nil
---@return boolean success
function BreedOperator:RetrieveStockPrincessesFromChest(n, preferences)
    -- Move to the stock princesses chest.
    self:moveToStorageColumn()
    self:moveToStockPrincessChestFromStorageColumnOrigin()

    -- Get the princesses out of the chest.
    local numRetrieved = 0
    for i = 1, self.ic.getInventorySize(self.sides.front) do
        if self.ic.getStackInSlot(self.sides.front, i) ~= nil then
            local numGotten = self.robot.suck(n - numRetrieved)
            numRetrieved = numRetrieved + numGotten

            if numRetrieved >= n then
                break
            end
        end
    end

    -- Error out if we didn't find the requested number.
    if numRetrieved < n then
        Print(string.format("Failed to retrieve %u stock princesses. Only found %u", n, numRetrieved))
        self:unloadInventory()
        return false
    end

    -- Return to the breeder station.
    self:returnToStorageColumnOriginFromStockPrincessChest()
    self:returnToBreederStationFromStorageColumn()

    -- Unload the princesses into the active princess chest.
    self.robot.turnLeft()
    self:unloadInventory()

    -- Clean up by returning to starting position.
    self.robot.turnRight()

    return true
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
    self:moveToStockPrincessChestFromStorageColumnOrigin()
    local success = self:unloadInventory()
    if not success then
        Print("Failed to unload all princesses back into chest.")
    end

    -- Return to the breeder station.
    self:returnToStorageColumnOriginFromStockPrincessChest()
    self:returnToBreederStationFromStorageColumn()
end

-- Retrieves a stack of drones that matches all of the given traits.
---@param traits PartialAnalyzedBeeTraits
---@return boolean success
function BreedOperator:RetrieveDrones(traits)
    self.robot.select(1)
    self:moveToStorageColumn()

    -- Go through the drone chests until we either find the drone or hit the end of the row.
    local found = false
    local chest = 0
    while self.ic.getInventorySize(self.sides.front) ~= nil do
        for i = 1, self.ic.getInventorySize(self.sides.front) do
            ---@type AnalyzedBeeStack
            local stack = self.ic.getStackInSlot(self.sides.front, i)
            if ((stack ~= nil) and
                (string.find(stack.label, "[D|d]rone") ~= nil) and
                (stack.size == 64) and
                AnalysisUtil.AllTraitsEqual(stack.individual, traits)
            ) then
                self.ic.suckFromSlot(self.sides.front, i, 64)
                found = true

                break
            end
        end

        if not found then
            self.robot.turnLeft()
            self.robot.forward()
            self.robot.turnRight()
            chest = chest + 1
        else
            break
        end
    end

    self:returnToStorageColumnOriginFromChest(chest)
    self:returnToBreederStationFromStorageColumn()

    -- Unload the drones if we got them or error out if not.
    if found then
        self.robot.turnRight()
        self.robot.drop(64)
        self.robot.turnLeft()
    else
        Print("Failed to find a full stack of drones with the requested traits.")
        return false
    end

    return true
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

-- Moves the specified number of drones from the given slot in the active chest to the output chest.
---@param slot integer
---@param number integer
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

-- Moves the princesses in the import chest to the breeding stock chest.
---@return boolean
function BreedOperator:ImportPrincessesFromInputsToStock()
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
            if numInternalSlotsTaken >= NUM_INTERNAL_SLOTS then
                break
            end
        end
    end

    self:returnToBreederStationFromInputChest()
    self:moveToStorageColumn()
    self:moveToStockPrincessChestFromStorageColumnOrigin()
    local success = self:unloadInventory()
    if not success then
        Print("Failed to unload all princesses into the stock princess chest.")
    end

    -- Clean up by returning to the starting position.
    self:returnToStorageColumnOriginFromStockPrincessChest()
    self:returnToBreederStationFromStorageColumn()

    return success
end

-- Moves the drone stacks in the import chest to the drone store.
-- Returns a set of the species imported.
---@return table<string, boolean> | nil
function BreedOperator:ImportDroneStacksFromInputsToStore()
    self:moveToInputChest()

    -- TODO: Deal with the case where there are more than 16 princesses.
    -- There are several items in this input chest. Only pick up the princesses.
    local numInternalSlotsTaken = 0
    local species = {}
    for i = 1, self.ic.getInventorySize(self.sides.front) do
        local stack = self.ic.getStackInSlot(self.sides.front, i)
        if (stack ~= nil) and (stack.size == 64) and (string.find(stack.label, "[D|d]rone") ~= nil) then
            if (stack.individual.active.species.uid == stack.individual.inactive.species.uid) then
                species[stack.individual.active.species.uid] = true
            end

            self.robot.select(numInternalSlotsTaken + 1)
            self.ic.suckFromSlot(self.sides.front, i, 64)

            numInternalSlotsTaken = numInternalSlotsTaken + 1
            if numInternalSlotsTaken >= NUM_INTERNAL_SLOTS then
                break
            end
        end
    end

    self:returnToBreederStationFromInputChest()

    if not self:storeDrones() then
        return nil
    end

    return species
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

function BreedOperator:BreakAndReturnFoundationsToInputChest()
    -- Get pickaxe from inputs chest.
    -- TODO: Deal with pickaxe not being there.
    -- TODO: Does a pickaxe deal with all possible foundation blocks we might need as part of this?
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

-- Stores the drones in the robot's inventory in the storage column.
---@return boolean
function BreedOperator:storeDrones()
    -- Store the drones in the storage column.
    self:moveToStorageColumn()

    -- Place the drones into storage.
    local chest = 0
    local failed = false
    for i = 1, NUM_INTERNAL_SLOTS do
        self.robot.select(i)
        if self.robot.count() == 0 then
            goto continue
        end

        -- Find an empty slot in the storages.
        local emptySlot = self:getEmptySlotInChest()
        while emptySlot == -1 do
            self.robot.turnLeft()
            self.robot.forward()
            self.robot.turnRight()
            chest = chest + 1

            emptySlot = self:getEmptySlotInChest()
        end

        if emptySlot == nil then
            failed = true
            break
        end

        self.ic.dropIntoSlot(self.sides.front, emptySlot, 64)
        ::continue::
    end

    -- Return to the breeder station.
    self:returnToStorageColumnOriginFromChest(chest)
    self:returnToBreederStationFromStorageColumn()

    if failed then
        Print("Failed to store drones in the storage column. More chests are required.")
    end

    return not failed
end

-- Returns the index of an empty slot in the chest or `-1` if none exist.
-- Returns nil if there is no chest.
---@return integer | nil
function BreedOperator:getEmptySlotInChest()
    local inventorySize = self.ic.getInventorySize(self.sides.front)
    if inventorySize == nil then
        return nil
    end

    for i = 1, inventorySize do
        if self.ic.getStackInSlot(self.sides.front, i) == nil then
            return i
        end
    end

    return -1
end

-- Moves the robot from the breeder station to position 0 of the storage column.
function BreedOperator:moveToStorageColumn()
    --- Move to the chest row.
    self.robot.forward()
    self.robot.turnRight()
    self:moveForwards(4)
end

-- Moves the robot from position 0 of the storage column back to the breeder station.
function BreedOperator:returnToBreederStationFromStorageColumn()
    self:moveBackwards(4)
    self.robot.turnLeft()
    self.robot.back()
end

function BreedOperator:moveToStockPrincessChestFromStorageColumnOrigin()
    self.robot.turnRight()
    self.robot.forward()
    self.robot.turnLeft()
end

function BreedOperator:returnToStorageColumnOriginFromStockPrincessChest()
    self.robot.turnLeft()
    self.robot.forward()
    self.robot.turnRight()
end

function BreedOperator:returnToStorageColumnOriginFromChest(dist)
    if dist > 0 then
        self.robot.turnRight()
        self:moveForwards(dist)
        self.robot.turnLeft()
    end
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

return BreedOperator
