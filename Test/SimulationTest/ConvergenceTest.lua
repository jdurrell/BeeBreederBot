local Luaunit = require("Test.luaunit")

local Apiary = require("Test.SimulatorModules.Apiary")
local Res = require("Test.Resources.TestData")
local Util = require("Test.Utilities.CommonUtilities")
local RollingEnum = require("Test.Utilities.RollingEnum")

require("Shared.Shared")
local MatchingAlgorithms = require("BeeBot.MatchingAlgorithms")

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

    -- TODO: Figure out a better way of combining these than a string.
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

-- Adds the given individual to the chest. If a drone of the exact same data exists, then they will stack.
-- Otherwise, the individual will be placed into the first open slot in the chest.
-- Technically, not every field of AnalyzedBeeStack will be set, but we will set as many as the simulator requires.
---@param individual AnalyzedBeeIndividual
---@param hash string
---@param droneChest (AnalyzedBeeStack | {})[]
local function AddIndividualToChest(individual, hash, droneChest)
    ---@type AnalyzedBeeStack
    local matchingStackWithSpace = nil
    local openSlot = nil  -- TODO: Implement garbage collection and the concept of the chest having limited storage.
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
        openSlot = ((openSlot ~= nil) and openSlot) or (#droneChest + 1)
        droneChest[openSlot] = CreateBeeStack(individual, 1, openSlot, hash)
    end
end

-- Repeatedly performs matches and breeding simulations until `endCondition` becomes true or failing to converge after a maximum number of iterations.
-- Returns the number of iterations taken to converge.
---@param matcher Matcher
---@param endCondition fun(droneStackList: AnalyzedBeeStack[]): boolean
---@param maxIterations integer
---@param apiary Apiary
---@param initialPrincess AnalyzedBeeStack
---@param initialDroneStacks AnalyzedBeeStack[]
---@param target string
---@param cacheElement BreedInfoCacheElement
---@param traitInfo TraitInfo
---@param seed integer | nil
---@return integer
local function RunConvergenceTest(matcher, endCondition, maxIterations, apiary, initialPrincess, initialDroneStacks, target, cacheElement, traitInfo, seed)
    math.randomseed(((seed ~= nil) and seed) or 456)

    ---@type (AnalyzedBeeStack | {})[]
    local droneStacks = Copy(initialDroneStacks)
    local princess = Copy(initialPrincess)

    local i = 0
    while (i < maxIterations) and (not endCondition(droneStacks)) do
        local slot = matcher(princess, droneStacks, target, cacheElement, traitInfo)

        -- Take the drone out of the "chest".
        local chosenDroneStack = droneStacks[slot]
        chosenDroneStack.size = chosenDroneStack.size - 1
        if chosenDroneStack.size == 0 then
           droneStacks[slot] = {}
        end

        -- Give some visibility for debugging.
        if Util.IsVerboseMode() then
            print("Iteration " .. i .. ":")
            print("Princess: " .. princess.individual.active.species.uid .. ", " .. princess.individual.inactive.species.uid)
            print("Chose slot " .. slot)
            print("Drone: " .. chosenDroneStack.individual.active.species.uid .. ", " .. chosenDroneStack.individual.inactive.species.uid .. ", " .. chosenDroneStack.__hash)
            print("")
        end

        local offspringPrincess, offspringDrones = apiary:GenerateDescendants(princess.individual, chosenDroneStack.individual)

        ---@diagnostic disable-next-line: missing-fields
        princess = {individual = offspringPrincess}
        for _, v in ipairs(offspringDrones) do
            AddIndividualToChest(v, HashIndividual(v), droneStacks)
        end

        i = i + 1
    end

    Luaunit.assertIsTrue(i < maxIterations, "Failed to converge within " .. i .. " iterations.")

    return i
end

TestConvergence = {}
    function TestConvergence:TestTwoSimpleSpecies()
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

        ---@param droneStackList AnalyzedBeeStack[]
        ---@return boolean
        local endCondition = function (droneStackList)
            return (MatchingAlgorithms.GetFinishedDroneStack(droneStackList, target) ~= nil)
        end

        local iterations = RunConvergenceTest(
            MatchingAlgorithms.HighestPureBredChance,
            endCondition,
            10000,
            apiary,
            initialPrincess,
            initialDroneStacks,
            "forestry.speciesCommon",
            cacheElement,
            traitInfo
        )

        Luaunit.assertIsTrue(iterations < 200, "number of iterations: " .. iterations)
    end
