local Luaunit = require("Test.luaunit")

local Apiary = require("Test.SimulatorModules.Apiary")
local Res = require("Test.Resources.TestData")
local Util = require("Test.Utilities.CommonUtilities")
local RollingEnum = require("Test.Utilities.RollingEnum")

require("Shared.Shared")
local GarbageCollectionPolicies = require("BeekeeperBot.GarbageCollectionPolicies")
local MatchingAlgorithms = require("BeekeeperBot.MatchingAlgorithms")

-- Mapping for optimizing the hash computation.
local effectEnum = RollingEnum:Create()
local floweringEnum = RollingEnum:Create()
local flowerProviderEnum = RollingEnum:Create()
local lifespanEnum = RollingEnum:Create()
local speciesEnum = RollingEnum:Create()
local speedEnum = RollingEnum:Create()
local territoryEnum = RollingEnum:Create()

---@param bool boolean
---@return integer
local function BooleanToInteger(bool)
    return (bool and 1) or 0
end

---@param individual AnalyzedBeeIndividual
---@return string
local function HashIndividual(individual)
    local genome = individual.__genome

    -- Lua integers are 64-bit integers, so we can pack the values from each genome into 40 bits.
    -- As an optimization, we will ignore humidity and temperature because we assume that in a real system, an acclimatizer would ensure equality for all bees.
    -- The territory allele indexes by the first value since the tables of different drones will have unequal references and won't stack up in the enum.
    local hash1 = (
        (BooleanToInteger(genome.caveDwelling.primary)) |                  -- 1 bit
        (effectEnum:Get(genome.effect.primary) << 1) |                     -- 6 bits
        (genome.fertility.primary << 7) |                                  -- 3 bits
        (floweringEnum:Get(genome.flowering.primary) << 10) |              -- 4 bits
        (flowerProviderEnum:Get(genome.flowerProvider.primary) << 14) |    -- 4 bits
        (lifespanEnum:Get(genome.lifespan.primary) << 18) |                -- 4 bits
        (BooleanToInteger(genome.nocturnal.primary) << 22) |               -- 1 bit
        (speciesEnum:Get(genome.species.primary.uid) << 23) |              -- 9 bits
        (speedEnum:Get(genome.speed.primary) << 32) |                      -- 4 bits
        (territoryEnum:Get(genome.territory.primary[1]) << 36) |           -- 3 bits
        (BooleanToInteger(genome.tolerantFlyer.primary) << 39)             -- 1 bit
    )
    local hash2 = (
        (BooleanToInteger(genome.caveDwelling.secondary)) |                -- 1 bit
        (effectEnum:Get(genome.effect.secondary) << 1) |                   -- 6 bits
        (genome.fertility.secondary << 7) |                                -- 3 bits
        (floweringEnum:Get(genome.flowering.secondary) << 10) |            -- 4 bits
        (flowerProviderEnum:Get(genome.flowerProvider.secondary) << 14) |  -- 4 bits
        (lifespanEnum:Get(genome.lifespan.secondary) << 18) |              -- 4 bits
        (BooleanToInteger(genome.nocturnal.secondary) << 22) |             -- 1 bit
        (speciesEnum:Get(genome.species.secondary.uid) << 23) |            -- 9 bits
        (speedEnum:Get(genome.speed.secondary) << 32) |                    -- 4 bits
        (territoryEnum:Get(genome.territory.secondary[1]) << 36) |         -- 3 bits
        (BooleanToInteger(genome.tolerantFlyer.secondary) << 39)           -- 1 bit
    )

    -- TODO: Implement a better way of combining these than a string.
    return tostring(hash1) .. "-" .. tostring(hash2)
end


-- Small wrapper for creating a bee stack from the fields required for this test.
---@param individual AnalyzedBeeIndividual
---@param slotInChest integer
---@param hash string | nil
---@return AnalyzedBeeStack
local function CreateBeeStack(individual, size, slotInChest, hash)
    return {
        individual = individual,
        size = size,
        slotInChest = slotInChest,
        __hash = ((hash ~= nil) and hash) or HashIndividual(individual)
    }
end

local DRONE_CHEST_SIZE = 27

-- Adds the given individual to the chest. If a drone of the exact same data exists, then they will stack.
-- Otherwise, the individual will be placed into the first open slot in the chest.
-- Technically, not every field of AnalyzedBeeStack will be set, but we will set as many as the simulator requires.
---@param individual AnalyzedBeeIndividual
---@param hash string
---@param droneChest (AnalyzedBeeStack | {})[]
local function AddIndividualToChest(individual, hash, droneChest)
    ---@type AnalyzedBeeStack
    local matchingStackWithSpace = nil
    local openSlot = nil
    for i, stack in ipairs(droneChest) do
        if stack.__hash == nil then
            openSlot = ((openSlot == nil) and i) or openSlot
        elseif (stack.size < 64) and (stack.__hash == hash) then
            matchingStackWithSpace = stack
            break
        end
    end

    if matchingStackWithSpace ~= nil then
        matchingStackWithSpace.size = matchingStackWithSpace.size + 1
    else
        -- The size of the chest is fixed, so we can't insert a drone into a chest that has no room for it.
        Luaunit.assertNotIsNil(openSlot, "Garbage collection error: too many drones for the drone chest.")
        openSlot = UnwrapNull(openSlot)
        droneChest[openSlot] = CreateBeeStack(individual, 1, openSlot, hash)
    end
end

-- Repeatedly performs matches and breeding simulations until `endCondition` becomes true or failing to converge after a maximum number of iterations.
-- Returns the number of iterations taken to converge.
---@param matcher Matcher
---@param garbageCollector GarbageCollector
---@param endCondition fun(droneStackList: AnalyzedBeeStack[]): boolean
---@param maxIterations integer
---@param apiary Apiary
---@param initialPrincess AnalyzedBeeStack
---@param initialDroneStacks AnalyzedBeeStack[]
---@param target string
---@param cacheElement BreedInfoCacheElement
---@param traitInfo TraitInfoFull
---@param seed integer | nil
---@return number
local function RunConvergenceTest(matcher, garbageCollector, endCondition, maxIterations, apiary, initialPrincess, initialDroneStacks, target, cacheElement, traitInfo, seed)
    local convergences = 0
    local sumItersToConvergence = 0
    local numTrials = 1000
    math.randomseed(((seed ~= nil) and seed) or 456)
    for i = 1, numTrials do

        ---@type (AnalyzedBeeStack | {})[]
        local droneStacks = Copy(initialDroneStacks)
        for slot = 1, DRONE_CHEST_SIZE do
            if droneStacks[slot] == nil then
                droneStacks[slot] = {}
            end
        end
        local princess = Copy(initialPrincess)

        local iteration = 0
        while (iteration < maxIterations) and (not endCondition(droneStacks)) do
            local slot = matcher(princess, droneStacks, target, cacheElement, traitInfo)

            -- Take the drone out of the "chest".
            local chosenDroneStack = droneStacks[slot]
            chosenDroneStack.size = chosenDroneStack.size - 1
            if chosenDroneStack.size == 0 then
               droneStacks[slot] = {}
            end

            -- Give some visibility for debugging.
            -- if Util.IsVerboseMode() then
            --     print("Iteration " .. iteration .. ":")
            --     print("Princess: " .. princess.individual.active.species.uid .. ", " .. princess.individual.inactive.species.uid)
            --     print("Chose slot " .. slot)
            --     print("Drone: " .. chosenDroneStack.individual.active.species.uid .. ", " .. chosenDroneStack.individual.inactive.species.uid .. ", " .. chosenDroneStack.__hash)
            --     print("")
            -- end

            -- Garbage collect the chest if there are too many drone stacks. 
            -- In the real system, this happens simulataneously with the apiary, so it must generally be done without knowledge of the outputs.
            -- Technically, there may be a race condition here that the simulator doesn't account for: next-generation drones can appear in the
            -- chest while garbage collection happens. If the BeekeeperBot implementation performs a subsequent re-stream of the inventory, then
            -- garbage collection *may* or *may not* consider the next generation. This only happens with frames that considerably reduce
            -- lifetime, though, and in theory, if the `matcher` and `garbageCollector` function are well-constructed, they should make better
            -- choices with the strictly greater information from that race condition firing.
            -- TODO: Make the "minDronesToRemove" concept a configurable function.
            local numEmptySlots = 0
            for _, stack in ipairs(droneStacks) do
                if stack.individual == nil then
                    numEmptySlots = numEmptySlots + 1
                end
            end
            if princess.individual.active.fertility > numEmptySlots then
                local slotsToRemove = garbageCollector(droneStacks, princess.individual.active.fertility - numEmptySlots, target)
                -- Visibility for debugging.
                -- if Util.IsVerboseMode() then
                --     print("Removed " .. #slotsToRemove .. " drone stacks:")
                --     for _, removeSlot in ipairs(slotsToRemove) do
                --         local stack = droneStacks[removeSlot]
                --         print(string.format("\tSlot  = %s\n\tSpecies = %s / %s\n\tfertility  = %u / %u\n\tSize = %u",
                --             stack.slotInChest, stack.individual.active.species.uid, stack.individual.inactive.species.uid,
                --             stack.individual.active.fertility, stack.individual.inactive.fertility, stack.size
                --         ))
                --     end
                -- end
                for _, removeSlot in ipairs(slotsToRemove) do
                    droneStacks[removeSlot] = {}
                end
            end

            local offspringPrincess, offspringDrones = apiary:GenerateDescendants(princess.individual, chosenDroneStack.individual)

            ---@diagnostic disable-next-line: missing-fields
            princess = {individual = offspringPrincess}
            for _, v in ipairs(offspringDrones) do
                AddIndividualToChest(v, HashIndividual(v), droneStacks)
            end

            iteration = iteration + 1
        end
        if iteration < maxIterations then
            convergences = convergences + 1
            sumItersToConvergence = sumItersToConvergence + iteration
        end
    end
    Util.VerbosePrint(string.format("Converged %u / %u times, averaging %.2f iterations to converge.", convergences, numTrials, sumItersToConvergence / convergences))

    return convergences / numTrials
end

---@param target string
---@return fun(droneStackList: AnalyzedBeeStack[]): boolean
local function commonEndCondition(target)
    return function(droneStackList)
        return (MatchingAlgorithms.GetFinishedDroneStack(droneStackList, target) ~= nil)
    end
end

TestConvergenceHighestPureBredChance = {}
    function TestConvergenceHighestPureBredChance:TestTwoSimpleSpecies()
        local rawMutationInfo = Res.BeeGraphActual.GetRawMutationInfo()
        local traitInfo = Res.BeeGraphActual.GetSpeciesTraitInfo()
        local defaultChromosomes = Res.BeeGraphActual.GetDefaultChromosomes()
        local target = "forestry.speciesCommon"
        local cacheElement = Util.BreedCacheTargetLoad(target, Res.BeeGraphActual.GetGraph())
        local apiary = Apiary:Create(rawMutationInfo, traitInfo, defaultChromosomes)
        local initialDroneStacks = {
            CreateBeeStack(Util.CreateBee(defaultChromosomes["forestry.speciesForest"], traitInfo), 32, 1),
            CreateBeeStack(Util.CreateBee(defaultChromosomes["forestry.speciesTropical"], traitInfo), 32, 2)
        }
        local initialPrincess = CreateBeeStack(Util.CreateBee(defaultChromosomes["forestry.speciesTropical"], traitInfo), 1, 1)

        local successRatio = RunConvergenceTest(
            MatchingAlgorithms.HighestPureBredChance,
            GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSize,
            commonEndCondition(target),
            200,
            apiary,
            initialPrincess,
            initialDroneStacks,
            target,
            cacheElement,
            traitInfo,
            1001
        )

        Luaunit.assertIsTrue(successRatio > 0.95, "Converged at ratio " .. successRatio .. ".")
    end

TestConvergenceHighestPureBredChanceGenerationalPositiveFertility = {}
    function TestConvergenceHighestPureBredChanceGenerationalPositiveFertility:TestTwoSimpleSpecies()
        local rawMutationInfo = Res.BeeGraphActual.GetRawMutationInfo()
        local traitInfo = Res.BeeGraphActual.GetSpeciesTraitInfo()
        local defaultChromosomes = Res.BeeGraphActual.GetDefaultChromosomes()
        local target = "forestry.speciesCommon"
        local cacheElement = Util.BreedCacheTargetLoad(target, Res.BeeGraphActual.GetGraph())
        local apiary = Apiary:Create(rawMutationInfo, traitInfo, defaultChromosomes)
        local initialDroneStacks = {
            CreateBeeStack(Util.CreateBee(defaultChromosomes["forestry.speciesForest"], traitInfo), 32, 1),
            CreateBeeStack(Util.CreateBee(defaultChromosomes["forestry.speciesTropical"], traitInfo), 32, 2)
        }
        local initialPrincess = CreateBeeStack(Util.CreateBee(defaultChromosomes["forestry.speciesTropical"], traitInfo), 1, 1)

        local successRatio = RunConvergenceTest(
            MatchingAlgorithms.HighestAverageExpectedAllelesGenerationalPositiveFertility,
            GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSize,
            commonEndCondition(target),
            10000,
            apiary,
            initialPrincess,
            initialDroneStacks,
            target,
            cacheElement,
            traitInfo,
            2001
        )

        Luaunit.assertIsTrue(successRatio > 0.95, "Converged at ratio " .. successRatio .. ".")
    end

    function TestConvergenceHighestPureBredChanceGenerationalPositiveFertility:TestTargetHasOneFertility()
        local rawMutationInfo = Res.BeeGraphActual.GetRawMutationInfo()
        local traitInfo = Res.BeeGraphActual.GetSpeciesTraitInfo()
        local defaultChromosomes = Res.BeeGraphActual.GetDefaultChromosomes()
        local target = "computronics.speciesScummy"
        local cacheElement = Util.BreedCacheTargetLoad(target, Res.BeeGraphActual.GetGraph())
        local apiary = Apiary:Create(rawMutationInfo, traitInfo, defaultChromosomes)
        local initialDroneStacks = {
            CreateBeeStack(Util.CreateBee(defaultChromosomes["forestry.speciesAgrarian"], traitInfo), 32, 1),
            CreateBeeStack(Util.CreateBee(defaultChromosomes["forestry.speciesExotic"], traitInfo), 32, 2)
        }
        local initialPrincess = CreateBeeStack(Util.CreateBee(defaultChromosomes["forestry.speciesExotic"], traitInfo), 1, 1)

        local successRatio = RunConvergenceTest(
            MatchingAlgorithms.HighestAverageExpectedAllelesGenerationalPositiveFertility,
            GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSize,
            commonEndCondition(target),
            10000,
            apiary,
            initialPrincess,
            initialDroneStacks,
            target,
            cacheElement,
            traitInfo,
            2002
        )

        Luaunit.assertIsTrue(successRatio > 0.95, "Converged at ratio " .. successRatio .. ".")
    end

TestConvergenceHighFertilityAndAlleles = {}
    function TestConvergenceHighFertilityAndAlleles:TestTwoSimpleSpecies()
        local rawMutationInfo = Res.BeeGraphActual.GetRawMutationInfo()
        local traitInfo = Res.BeeGraphActual.GetSpeciesTraitInfo()
        local defaultChromosomes = Res.BeeGraphActual.GetDefaultChromosomes()
        local target = "forestry.speciesCommon"
        local cacheElement = Util.BreedCacheTargetLoad(target, Res.BeeGraphActual.GetGraph())
        local apiary = Apiary:Create(rawMutationInfo, traitInfo, defaultChromosomes)
        local initialDroneStacks = {
            CreateBeeStack(Util.CreateBee(defaultChromosomes["forestry.speciesForest"], traitInfo), 32, 1),
            CreateBeeStack(Util.CreateBee(defaultChromosomes["forestry.speciesTropical"], traitInfo), 32, 2)
        }
        local initialPrincess = CreateBeeStack(Util.CreateBee(defaultChromosomes["forestry.speciesTropical"], traitInfo), 1, 1)

        local successRatio = RunConvergenceTest(
            MatchingAlgorithms.HighFertilityAndAlleles,
            GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSize,
            commonEndCondition(target),
            10000,
            apiary,
            initialPrincess,
            initialDroneStacks,
            target,
            cacheElement,
            traitInfo,
            3001
        )

        Luaunit.assertIsTrue(successRatio > 0.95, "Converged at ratio " .. successRatio .. ".")
    end

    function TestConvergenceHighFertilityAndAlleles:TestTargetHasOneFertility()
        local rawMutationInfo = Res.BeeGraphActual.GetRawMutationInfo()
        local traitInfo = Res.BeeGraphActual.GetSpeciesTraitInfo()
        local defaultChromosomes = Res.BeeGraphActual.GetDefaultChromosomes()
        local target = "computronics.speciesScummy"
        local cacheElement = Util.BreedCacheTargetLoad(target, Res.BeeGraphActual.GetGraph())
        local apiary = Apiary:Create(rawMutationInfo, traitInfo, defaultChromosomes)
        local initialDroneStacks = {
            CreateBeeStack(Util.CreateBee(defaultChromosomes["forestry.speciesAgrarian"], traitInfo), 32, 1),
            CreateBeeStack(Util.CreateBee(defaultChromosomes["forestry.speciesExotic"], traitInfo), 32, 2)
        }
        local initialPrincess = CreateBeeStack(Util.CreateBee(defaultChromosomes["forestry.speciesExotic"], traitInfo), 1, 1)

        local successRatio = RunConvergenceTest(
            MatchingAlgorithms.HighFertilityAndAlleles,
            GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSize,
            commonEndCondition(target),
            10000,
            apiary,
            initialPrincess,
            initialDroneStacks,
            target,
            cacheElement,
            traitInfo,
            3002
        )

        Luaunit.assertIsTrue(successRatio > 0.95, "Converged at ratio " .. successRatio .. ".")
    end

    function TestConvergenceHighFertilityAndAlleles:TestReplicateFromOneFertilityNoMutations()
        local rawMutationInfo = Res.BeeGraphActual.GetRawMutationInfo()
        local traitInfo = Res.BeeGraphActual.GetSpeciesTraitInfo()
        local defaultChromosomes = Res.BeeGraphActual.GetDefaultChromosomes()
        local target = "extrabees.species.rock"
        local cacheElement = Util.BreedCacheTargetLoad(target, Res.BeeGraphActual.GetGraph())
        local apiary = Apiary:Create(rawMutationInfo, traitInfo, defaultChromosomes)
        local initialDroneStacks = {
            CreateBeeStack(Util.CreateBee(defaultChromosomes["extrabees.species.rock"], traitInfo), 32, 1),
            CreateBeeStack(Util.CreateBee(defaultChromosomes["forestry.speciesVindictive"], traitInfo), 32, 2)
        }
        local initialPrincess = CreateBeeStack(Util.CreateBee(defaultChromosomes["extrabees.species.rock"], traitInfo), 1, 1)

        local successRatio = RunConvergenceTest(
            MatchingAlgorithms.HighFertilityAndAlleles,
            GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSize,
            commonEndCondition(target),
            10000,
            apiary,
            initialPrincess,
            initialDroneStacks,
            target,
            cacheElement,
            traitInfo,
            3003
        )

        Luaunit.assertIsTrue(successRatio > 0.95, "Converged at ratio " .. successRatio .. ".")
    end

    function TestConvergenceHighFertilityAndAlleles:TestReplicateFromOneFertilityWithMutations()
        local rawMutationInfo = Res.BeeGraphActual.GetRawMutationInfo()
        local traitInfo = Res.BeeGraphActual.GetSpeciesTraitInfo()
        local defaultChromosomes = Res.BeeGraphActual.GetDefaultChromosomes()
        local target = "extrabees.species.rock"
        local cacheElement = Util.BreedCacheTargetLoad(target, Res.BeeGraphActual.GetGraph())
        local apiary = Apiary:Create(rawMutationInfo, traitInfo, defaultChromosomes)
        local initialDroneStacks = {
            CreateBeeStack(Util.CreateBee(defaultChromosomes["extrabees.species.rock"], traitInfo), 32, 1),
            CreateBeeStack(Util.CreateBee(defaultChromosomes["forestry.speciesMeadows"], traitInfo), 32, 2)
        }
        local initialPrincess = CreateBeeStack(Util.CreateBee(defaultChromosomes["extrabees.species.rock"], traitInfo), 1, 1)

        local successRatio = RunConvergenceTest(
            MatchingAlgorithms.HighFertilityAndAlleles,
            GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSize,
            commonEndCondition(target),
            10000,
            apiary,
            initialPrincess,
            initialDroneStacks,
            target,
            cacheElement,
            traitInfo,
            3004
        )

        Luaunit.assertIsTrue(successRatio > 0.95, "Converged at ratio " .. successRatio .. ".")
    end

    function TestConvergenceHighFertilityAndAlleles:TestReplicateFromOneFertilityLowNumberDrones()
        local rawMutationInfo = Res.BeeGraphActual.GetRawMutationInfo()
        local traitInfo = Res.BeeGraphActual.GetSpeciesTraitInfo()
        local defaultChromosomes = Res.BeeGraphActual.GetDefaultChromosomes()
        local target = "extrabees.species.rock"
        local cacheElement = Util.BreedCacheTargetLoad(target, Res.BeeGraphActual.GetGraph())
        local apiary = Apiary:Create(rawMutationInfo, traitInfo, defaultChromosomes)
        local initialDroneStacks = {
            CreateBeeStack(Util.CreateBee(defaultChromosomes["extrabees.species.rock"], traitInfo), 8, 1),
            CreateBeeStack(Util.CreateBee(defaultChromosomes["forestry.speciesMeadows"], traitInfo), 8, 2)
        }
        local initialPrincess = CreateBeeStack(Util.CreateBee(defaultChromosomes["extrabees.species.rock"], traitInfo), 1, 1)

        local successRatio = RunConvergenceTest(
            MatchingAlgorithms.HighFertilityAndAlleles,
            GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSize,
            commonEndCondition(target),
            10000,
            apiary,
            initialPrincess,
            initialDroneStacks,
            target,
            cacheElement,
            traitInfo,
            3005
        )

        Luaunit.assertIsTrue(successRatio > 0.95, "Converged at ratio " .. successRatio .. ".")
    end

    function TestConvergenceHighFertilityAndAlleles:TestReplicateFromOneFertilityAndDifferentPrincess()
        local rawMutationInfo = Res.BeeGraphActual.GetRawMutationInfo()
        local traitInfo = Res.BeeGraphActual.GetSpeciesTraitInfo()
        local defaultChromosomes = Res.BeeGraphActual.GetDefaultChromosomes()
        local target = "extrabees.species.rock"
        local cacheElement = Util.BreedCacheTargetLoad(target, Res.BeeGraphActual.GetGraph())
        local apiary = Apiary:Create(rawMutationInfo, traitInfo, defaultChromosomes)
        local initialDroneStacks = {
            CreateBeeStack(Util.CreateBee(defaultChromosomes["extrabees.species.rock"], traitInfo), 16, 1),
            CreateBeeStack(Util.CreateBee(defaultChromosomes["forestry.speciesMeadows"], traitInfo), 16, 2)
        }
        local initialPrincess = CreateBeeStack(Util.CreateBee(defaultChromosomes["forestry.speciesTropical"], traitInfo), 1, 1)

        local successRatio = RunConvergenceTest(
            MatchingAlgorithms.HighFertilityAndAlleles,
            GarbageCollectionPolicies.ClearDronesByFertilityPurityStackSize,
            commonEndCondition(target),
            10000,
            apiary,
            initialPrincess,
            initialDroneStacks,
            target,
            cacheElement,
            traitInfo,
            3006
        )

        Luaunit.assertIsTrue(successRatio > 0.95, "Converged at ratio " .. successRatio .. ".")
    end
