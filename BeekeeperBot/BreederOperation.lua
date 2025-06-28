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

-- Apiary slots.
local APIARY_PRINCESS_SLOT = 1
local APIARY_DRONE_SLOT    = 2

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

    if (numApiaries < 1) or (numApiaries > 4) then
        Print(string.format("Number of apiaries must be from 1 to 4 (inclusive). Got invalid number: %d", numApiaries))
        return nil
    end
    obj.numApiaries = numApiaries

    return obj
end

-- Returns the list of princesses in the active princess chest.
---@return AnalyzedBeeStack[]
function BreedOperator:GetPrincessesInChest()
    self.robot.turnLeft()

    local princesses = {}
    for i = 1, self.ic.getInventorySize(self.sides.front) do
        local stack = self.ic.getStackInSlot(self.sides.front, i)
        if (stack ~= nil) and (stack.label:find("[P|p]rincess") ~= nil) then
            stack.slotInChest = i
            table.insert(princesses, stack)
        end
    end

    self.robot.turnRight()

    return princesses
end

-- Returns a list of drones in the active drone chest.
-- TODO: Reorganize this into a stream to optimize for low memory.
---@return AnalyzedBeeStack[]
function BreedOperator:GetDronesInChest()
    self.robot.turnRight()

    -- Scan the attached inventory to collect all drones and count how many are pure bred of our target.
    local drones = {}
    for i = 1, self.ic.getInventorySize(self.sides.front) do
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

    -- Move to the 1st apiary.
    self.robot.up()
    self:moveForwards(2)

    -- Find the next open apiary.
    local chosenApiary = 1
    while self:housingIsOccupied() do
        -- Apiaries are set up in a cross.
        self.robot.turnRight()
        self:moveForwards(2)
        self.robot.turnLeft()
        self:moveForwards(2)
        self.robot.turnLeft()
        chosenApiary = chosenApiary + 1
    end

    -- We are at an open apiary, so place the bees inside.
    self.robot.select(PRINCESS_SLOT)
    self.ic.dropIntoSlot(self.sides.front, APIARY_PRINCESS_SLOT)
    self.robot.select(DRONE_SLOT)
    self.ic.dropIntoSlot(self.sides.front, APIARY_DRONE_SLOT)

    -- Return to the breeder station by retracing our steps.
    -- TODO: We could improve this by being aware of the relative location of the final apiary, but a simple retrace is easier for now.
    self.robot.turnLeft()
    for i = 2, chosenApiary do
        self:moveForwards(2)
        self.robot.turnRight()
        self:moveForwards(2)
    end
    self.robot.turnRight()
    self:moveBackwards(2)
    self.robot.down()
end

-- Toggles the state of the lever on the opposite side of the acitve chest, which is wired to the accelerator.
function BreedOperator:ToggleWorldAccelerator()
    self.robot.forward()
    self.robot.turnRight()
    self:moveForwards(2)
    self.robot.turnRight()

    self.robot.use()

    self.robot.turnLeft()
    self:moveBackwards(2)
    self.robot.turnLeft()
    self.robot.back()
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

    -- Collect the drone stacks.
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

    -- Return to the breeder station.
    self:returnToStorageColumnOriginFromChest(chest)
    self:returnToBreederStationFromStorageColumn()

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
-- NOTE: Technically, drones can still appear in the chest after this operation.
--       It does not wait for all possible offspring to appear.
---@param slots integer[] | nil
function BreedOperator:TrashSlotsFromDroneChest(slots)
    self.robot.turnRight()

    if slots == nil then
        slots = {}
        for i = 1, self.ic.getInventorySize(self.sides.front) do
            table.insert(slots, i)
        end
    end

    local slotIdx = 1
    while slotIdx <= #slots do
        local internalSlot = 1
        while (slotIdx <= #slots) and (internalSlot <= 16) do
            self.robot.select(internalSlot)
            if self.ic.getStackInSlot(self.sides.front, slots[slotIdx]) ~= nil then
                self.ic.suckFromSlot(self.sides.front, slots[slotIdx], 64)
                internalSlot = internalSlot + 1
            end
            slotIdx = slotIdx + 1
        end

        -- Trash the stacks.
        self.robot.turnRight()
        self:unloadInventory()

        -- Turn back to the drone chest.
        self.robot.turnLeft()
    end

    -- Clean up by returning to starting position.
    self.robot.turnLeft()
end

-- Moves `n` princesses from the stock chest into the princess chest. If `n` is nil, then moves `numApiaries` princesses.
-- Attempts to choose princesses according to the preferences list.
-- TODO: Actually utilize the preferences list.
-- TODO: Deal with n > 16.
---@param n integer | nil
---@param preferences string[] | nil
---@return boolean success
function BreedOperator:RetrieveStockPrincessesFromChest(n, preferences)
    n = ((n == nil) and self.numApiaries) or n

    -- Move to the stock princesses chest.
    self:moveToStorageColumn()
    self:moveToStockPrincessChestFromStorageColumnOrigin()

    -- Get the princesses out of the chest.
    local numRetrieved = 0
    for i = 1, self.ic.getInventorySize(self.sides.front) do
        if self.ic.getStackInSlot(self.sides.front, i) ~= nil then
            self.robot.select(numRetrieved + 1)
            if not self.ic.suckFromSlot(self.sides.front, i, 1) then
                Print(string.format("Failed to take stock princess out of slot %u.", i))
                return false
            end
            numRetrieved = numRetrieved + 1

            if numRetrieved >= n then
                break
            end
        end
    end

    -- Error out if we didn't find the requested number.
    local succeeded = true
    if numRetrieved < n then
        succeeded = false
        Print(string.format("Failed to retrieve %u stock princesses. Only found %u", n, numRetrieved))
        self:unloadInventory()
    end

    -- Return to the breeder station.
    self:returnToStorageColumnOriginFromStockPrincessChest()
    self:returnToBreederStationFromStorageColumn()

    -- Unload the princesses into the active princess chest.
    self.robot.turnLeft()
    self:unloadInventory()

    -- Clean up by returning to starting position.
    self.robot.turnRight()

    return succeeded
end

-- Returns `amount` princesses from the active chest to the stock chest.
-- If `amount` is nil, then returns all (numApiaries) of the princesses.
---@param amount integer | nil
function BreedOperator:ReturnActivePrincessesToStock(amount)
    amount = ((amount == nil) and self.numApiaries) or amount

    -- Pick up princesses from the active chest.
    -- TODO: Deal with having more than 16 princesses.
    self.robot.turnLeft()
    local numToRetrieve = amount
    local internalSlot = 1
    while numToRetrieve > 0 do
        self.robot.select(internalSlot)
        for i = 1, self.ic.getInventorySize(self.sides.front) do
            local stack = self.ic.getStackInSlot(self.sides.front, i)
            if (stack ~= nil) and (stack.label:find("[P|p]rincess") ~= nil) then
                local retrieved = self.ic.suckFromSlot(self.sides.front, i, 64)
                numToRetrieve = numToRetrieve - retrieved
                internalSlot = internalSlot + 1
            end
        end

        -- We might not actually have all the princesses immediately, so wait around until they finish.
        if numToRetrieve > 0 then
            Sleep(5)
        end
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
---@param traits PartialAnalyzedBeeTraits | AnalyzedBeeTraits
---@param activeChestSlot integer | nil
---@return boolean success
function BreedOperator:RetrieveDrones(traits, activeChestSlot)
    activeChestSlot = ((activeChestSlot == nil) and 1) or activeChestSlot

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

        while not self.ic.dropIntoSlot(self.sides.front, activeChestSlot, 64) do
            -- If we fail to unload this stack into the active chest, then other drones must have
            -- been placed here by the piping system and taken this slot. Simply trash them.
            self.robot.select(2)
            self.ic.suckFromSlot(self.sides.front, 1, 64)
            self.robot.turnRight()
            self.robot.drop(64)
            self.robot.turnLeft()
            self.robot.select(1)
        end

        if self.robot.count(1) ~= 0 then
            -- It is possible that the slot we are dropping into already has drones that match the current stack.
            -- In that case, we have already filled that stack to 64 above, so we can discard the rest of these drones.
            self.robot.turnRight()
            self.robot.drop(64)
            self.robot.turnLeft()
        end

        self.robot.turnLeft()
    else
        Print("Failed to find a full stack of drones with the requested traits.")
        return false
    end

    return true
end

-- Retrieves the first two stacks from the holdover chest and places them in the analyzed drone chest.
-- Starts and ends at the breeder station. Can handle at most 15 stacks at once.
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
        while not self.ic.dropIntoSlot(self.sides.front, slot, amounts[i]) do
            -- If we failed to drop into the slot, then a stray drone must have gotten in our way. Clear it out.
            self.robot.select(16)
            self.ic.suckFromSlot(self.sides.front, slot, 64)
            self.robot.turnRight()
            self.robot.drop(64)
            self.robot.turnLeft()
            self.robot.select(i)
        end
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
---@param amount integer
function BreedOperator:ExportPrincessStackToOutput(slot, amount)
    self.robot.select(1)

    -- Pick up princesses.
    self.robot.turnLeft()
    self.ic.suckFromSlot(self.sides.front, slot, amount)
    self.robot.turnRight()

    -- Go to chest and unload, then return to the breeder station.
    self:moveToOutputChest()
    self.robot.drop(amount)
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
    local apiary = 1
    self:moveForwards(2)
    self.robot.place()
    for i = 2, self.numApiaries do
        -- Apiaries are set up in a cross.
        self.robot.turnRight()
        self:moveForwards(2)
        self.robot.turnLeft()
        self:moveForwards(2)
        self.robot.turnLeft()
        self.robot.place()
        apiary = apiary + 1
    end

    -- Return to the breeder station by retracing our steps.
    -- TODO: We could improve this by being aware of the relative location of the final apiary, but a simple retrace is easier for now.
    self.robot.turnLeft()
    for i = 2, apiary do
        self:moveForwards(2)
        self.robot.turnRight()
        self:moveForwards(2)
    end
    self.robot.turnRight()
    self:moveBackwards(2)
    self.robot.down()

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
    -- Place the foundations.
    local apiary = 1
    self:moveForwards(2)
    self.robot.swing()
    for i = 2, self.numApiaries do
        -- Apiaries are set up in a cross.
        self.robot.turnRight()
        self:moveForwards(2)
        self.robot.turnLeft()
        self:moveForwards(2)
        self.robot.turnLeft()
        self.robot.swing()
        apiary = apiary + 1
    end

    -- Return to the breeder station by retracing our steps.
    -- TODO: We could improve this by being aware of the relative location of the final apiary, but a simple retrace is easier for now.
    self.robot.turnLeft()
    for i = 2, apiary do
        self:moveForwards(2)
        self.robot.turnRight()
        self:moveForwards(2)
    end
    self.robot.turnRight()
    self:moveBackwards(2)
    self.robot.down()

    -- Return the pickaxe and the foundation blocks to the inputs chest.
    self:moveToInputChest()
    self:unloadInventory()

    self:returnToBreederStationFromInputChest()
end

---@return integer
function BreedOperator:GetDroneChestSize()
    self.robot.turnRight()
    local size = self.ic.getInventorySize(self.sides.front)
    self.robot.turnLeft()

    return size
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

-- Returns whether the bee housing in front of the robot is occupied.
---@return boolean
function BreedOperator:housingIsOccupied()
    return (
        (self.ic.getStackInSlot(self.sides.front, APIARY_PRINCESS_SLOT) ~= nil) or
        (self.ic.getStackInSlot(self.sides.front, APIARY_DRONE_SLOT) ~= nil)
    )
end

-- Moves the robot from the breeder station to position 0 of the storage column.
function BreedOperator:moveToStorageColumn()
    --- Move to the chest row.
    self.robot.forward()
    self.robot.turnRight()
    self:moveForwards(3)
end

-- Moves the robot from position 0 of the storage column back to the breeder station.
function BreedOperator:returnToBreederStationFromStorageColumn()
    self:moveBackwards(3)
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
