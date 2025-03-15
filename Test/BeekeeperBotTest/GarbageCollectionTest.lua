local Luaunit = require("Test.luaunit")

local GarbageCollectionPolicies = require("BeekeeperBot.GarbageCollectionPolicies")

---@param size integer
---@return {}[]
local function MakeEmptyChest(size)
    local chest = {}
    for i = 1, size do
        chest[i] = {}
    end

    return chest
end

---@param size integer
---@param activeFertilty integer
---@param passiveFertility integer
---@param activeSpecies string
---@param passiveSpecies string
---@return AnalyzedBeeStack
local function MakeDroneStack(size, activeFertilty, passiveFertility, activeSpecies, passiveSpecies)
    return {
        size = size,
        individual = {
            active = {fertility = activeFertilty, species = {uid = activeSpecies}},
            inactive = {fertility = passiveFertility, species = {uid = passiveSpecies}}
        }
    }
end

local function SetStackSlots(droneStacks)
    for i, stack in ipairs(droneStacks) do
        if stack.individual ~= nil then
            stack.slotInChest = i
        end
    end
end

---@generic T
---@param list T[]
---@param number integer
---@param legalValues T[]
---@return boolean
local function ContainsNumberOf(list, number, legalValues)
    -- TODO: This could use sets instead of lists.
    local numberFound = 0
    for _, v in ipairs(list) do
        local found = false
        for _, v2 in ipairs(legalValues) do
            if v == v2 then
                found = true
                break
            end
        end
        if found then
            numberFound = numberFound + 1
        end
        if numberFound > number then
            return false
        end
    end

    return numberFound == number
end

TestClearDronesByFertilityPurityStackSizeCollector = {}
    function TestClearDronesByFertilityPurityStackSizeCollector:TestClearAllLessThanTwoFertility()
        local droneStacks = MakeEmptyChest(27)
        local target = "A"
        droneStacks[1] = MakeDroneStack(1, 1, 1, target, target)
        droneStacks[2] = MakeDroneStack(1, 2, 1, target, target)
        droneStacks[3] = MakeDroneStack(1, 1, 2, target, target)
        droneStacks[4] = MakeDroneStack(1, 2, 2, target, target)
        droneStacks[6] = MakeDroneStack(1, 1, 1, target, "B")
        droneStacks[7] = MakeDroneStack(1, 2, 1, "B", "B")
        droneStacks[8] = MakeDroneStack(1, 1, 2, "B", "B")
        droneStacks[9] = MakeDroneStack(1, 2, 2, "B", "B")
        SetStackSlots(droneStacks)

        local slotsToRemove = GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSizeCollector(target)(droneStacks, 1)
        Luaunit.assertItemsEquals(slotsToRemove, {1, 2, 3, 6, 7, 8})
    end

    function TestClearDronesByFertilityPurityStackSizeCollector:TestClearLowestStackSizes()
        local droneStacks = MakeEmptyChest(27)
        local target = "A"
        droneStacks[1] = MakeDroneStack(11, 2, 2, target, target)
        droneStacks[2] = MakeDroneStack(21, 2, 2, target, target)
        droneStacks[3] = MakeDroneStack(25, 2, 2, target, target)
        droneStacks[4] = MakeDroneStack(2, 2, 2, target, target)
        droneStacks[5] = MakeDroneStack(34, 2, 2, target, target)
        droneStacks[9] = MakeDroneStack(1, 2, 2, target, target)
        droneStacks[10] = MakeDroneStack(9, 2, 2, target, target)
        droneStacks[13] = MakeDroneStack(3, 2, 2, target, target)
        SetStackSlots(droneStacks)

        local slotsToRemove = GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSizeCollector(target)(droneStacks, 1)
        Luaunit.assertItemsEquals(slotsToRemove, {9})
        slotsToRemove = GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSizeCollector(target)(droneStacks, 2)
        Luaunit.assertItemsEquals(slotsToRemove, {9, 4})
        slotsToRemove = GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSizeCollector(target)(droneStacks, 3)
        Luaunit.assertItemsEquals(slotsToRemove, {9, 4, 13})
        slotsToRemove = GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSizeCollector(target)(droneStacks, 4)
        Luaunit.assertItemsEquals(slotsToRemove, {9, 4, 13, 10})
        slotsToRemove = GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSizeCollector(target)(droneStacks, 5)
        Luaunit.assertItemsEquals(slotsToRemove, {9, 4, 13, 10, 1})
    end

    function TestClearDronesByFertilityPurityStackSizeCollector:TestClearLowestNumberAlleles()
        local droneStacks = MakeEmptyChest(27)
        local target = "A"
        droneStacks[1] = MakeDroneStack(11, 2, 2, "B", "B")
        droneStacks[2] = MakeDroneStack(21, 2, 2, target, target)
        droneStacks[3] = MakeDroneStack(25, 2, 2, "B", target)
        droneStacks[4] = MakeDroneStack(2, 2, 2, "B", "B")
        droneStacks[5] = MakeDroneStack(34, 2, 2, target, target)
        droneStacks[9] = MakeDroneStack(1, 2, 2, target, "B")
        droneStacks[10] = MakeDroneStack(9, 2, 2, "B", target)
        droneStacks[13] = MakeDroneStack(3, 2, 2, target, target)
        SetStackSlots(droneStacks)

        local slotsToRemove = GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSizeCollector(target)(droneStacks, 2)
        Luaunit.assertItemsEquals(slotsToRemove, {1, 4})
        slotsToRemove = GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSizeCollector(target)(droneStacks, 3)
        Luaunit.assertIsTrue(ContainsNumberOf(slotsToRemove, 2, {1, 4}))
        Luaunit.assertIsTrue(ContainsNumberOf(slotsToRemove, 1, {3, 9, 10}))
        Luaunit.assertEquals(#slotsToRemove, 3)
        slotsToRemove = GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSizeCollector(target)(droneStacks, 5)
        Luaunit.assertItemsEquals(slotsToRemove, {1, 4, 3, 9, 10})
        slotsToRemove = GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSizeCollector(target)(droneStacks, 6)
        Luaunit.assertIsTrue(ContainsNumberOf(slotsToRemove, 5, {1, 4, 3, 9, 10}))
        Luaunit.assertIsTrue(ContainsNumberOf(slotsToRemove, 1, {2, 5, 13}))
        Luaunit.assertEquals(#slotsToRemove, 6)
    end

    function TestClearDronesByFertilityPurityStackSizeCollector:TestClearCorrectAmountWhenFertilityBelowTwo()
        local droneStacks = MakeEmptyChest(27)
        local target = "A"
        droneStacks[1] = MakeDroneStack(11, 2, 2, target, target)
        droneStacks[2] = MakeDroneStack(21, 2, 2, target, target)
        droneStacks[3] = MakeDroneStack(25, 2, 2, target, target)
        droneStacks[4] = MakeDroneStack(2, 2, 1, target, target)
        droneStacks[5] = MakeDroneStack(34, 1, 2, target, target)
        droneStacks[9] = MakeDroneStack(1, 2, 2, target, target)
        droneStacks[10] = MakeDroneStack(9, 2, 2, target, target)
        droneStacks[13] = MakeDroneStack(3, 1, 1, target, target)
        droneStacks[15] = MakeDroneStack(3, 1, 2, target, target)
        droneStacks[16] = MakeDroneStack(3, 2, 2, target, target)
        droneStacks[17] = MakeDroneStack(3, 1, 1, target, target)
        droneStacks[18] = MakeDroneStack(3, 2, 2, "B", target)
        SetStackSlots(droneStacks)

        local slotsToRemove
        for i = 1, 5 do
            slotsToRemove = GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSizeCollector(target)(droneStacks, i)
            Luaunit.assertItemsEquals(slotsToRemove, {4, 5, 13, 15, 17})
        end
        slotsToRemove = GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSizeCollector(target)(droneStacks, 6)
        Luaunit.assertItemsEquals(slotsToRemove, {4, 5, 13, 15, 17, 18})
        slotsToRemove = GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSizeCollector(target)(droneStacks, 7)
        Luaunit.assertItemsEquals(slotsToRemove, {4, 5, 13, 15, 17, 18, 9})
        slotsToRemove = GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSizeCollector(target)(droneStacks, 8)
        Luaunit.assertItemsEquals(slotsToRemove, {4, 5, 13, 15, 17, 18, 9, 16})
        slotsToRemove = GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSizeCollector(target)(droneStacks, 9)
        Luaunit.assertItemsEquals(slotsToRemove, {4, 5, 13, 15, 17, 18, 9, 16, 10})
        slotsToRemove = GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSizeCollector(target)(droneStacks, 10)
        Luaunit.assertItemsEquals(slotsToRemove, {4, 5, 13, 15, 17, 18, 9, 16, 10, 1})
        slotsToRemove = GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSizeCollector(target)(droneStacks, 11)
        Luaunit.assertItemsEquals(slotsToRemove, {4, 5, 13, 15, 17, 18, 9, 16, 10, 1, 2})
        slotsToRemove = GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSizeCollector(target)(droneStacks, 12)
        Luaunit.assertItemsEquals(slotsToRemove, {4, 5, 13, 15, 17, 18, 9, 16, 10, 1, 2, 3})
    end
