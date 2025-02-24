local Luaunit = require("Test.luaunit")

local Apiary = require("Test.SimulatorModules.Apiary")
local MatchingMath = require("BeeBot.MatchingMath")
local MutationMath = require("BeeServer.MutationMath")
local Util = require("Test.Utilities")

local AlphaLevelToTwoSidedZThreshold = {
    [0.01] = 2.58,
    [0.05] = 1.96,
    [0.1]  = 1.64
}

-- Performs `n` Bernoulli trials (defined by `bernoulliTrial`) and verifies that it always succeeds.
---@param bernoulliTrial fun(): boolean  A function that determines whether the outcome of a given Bernoulli trial is a "success".
---@param n integer | nil Number of Bernoulli trials to perform.
local function VerifyAlwaysHappens(bernoulliTrial, n)
    for i = 1, n do
        Luaunit.assertIsTrue(bernoulliTrial())
    end
end

-- Performs `n` Bernoulli trials (defined by `bernoulliTrial`) and verifies that it doesn't succeed once.
---@param bernoulliTrial fun(): boolean  A function that determines whether the outcome of a given Bernoulli trial is a "success".
---@param n integer | nil Number of Bernoulli trials to perform.
local function VerifyNeverHappens(bernoulliTrial, n)
    for i = 1, n do
        Luaunit.assertIsFalse(bernoulliTrial())
    end
end

-- Performs `n` Bernoulli trials (defined by `bernoulliTrial`) and verifies that the observed probability of success
-- does not differ from the expected probability `pZero` to the degree of statistical significance represented by
-- `alphaLevel`. Note that this does not strictly guarantee that the expected probability is "certainly correct",
-- but it is useful for determining that the expected probability is reasonably close to reality.
---@param bernoulliTrial fun(): boolean  A function that determines whether the outcome of a given Bernoulli trial is a "success".
---@param pZero number  The expected probability of "success".
---@param n integer | nil Number of Bernoulli trials to perform.
---@param alphaLevel number | nil
local function VerifyReasonabilityOfAccuracy(bernoulliTrial, pZero, n, alphaLevel)
    n = ((n == nil) and 100000) or n
    alphaLevel = ((alphaLevel == nil) and 0.01) or alphaLevel
    Luaunit.assertNotIsNil(AlphaLevelToTwoSidedZThreshold[alphaLevel], "Test-internal error: alpha level not found in lookup table.")
    Luaunit.assertIsTrue(n >= 10000, "Test-internal error: N must be greater than 10000 to approximate the binomial distribution as a normal distribution.")

    if pZero == 0 then
        VerifyNeverHappens(bernoulliTrial, n)
        return
    elseif pZero == 1 then
        VerifyAlwaysHappens(bernoulliTrial, n)
        return
    end

    -- Perform `n` Benoulli trials and count the number of successes.
    local observedCount = 0
    for i = 1, n do
        local outcome = bernoulliTrial()
        if outcome then
            observedCount = observedCount + 1
        end
    end

    -- Since we have large n, the binomial distribution B(n, p) (`n` trials each with probability `p` of success) representing the outcome of
    -- the sequence of Bernoulli trials can be approximated as the normal distribution N(np, p(1-p)/n) (with mean `np` and variance `p(1-p)/n).
    -- Then, we perform a z-test and reject the expected probability `pZero` if the observed probability differed to a degree of statistical
    -- significance represented by `alphaLevel`.
    local pHat = observedCount / n
    local z = (pHat - pZero) / (math.sqrt((pZero * (1 - pZero)) / n))

    -- Since we must test for the observed probability being greater than or less than the expected probability, our z-test must be two-sided.
    local threshold = AlphaLevelToTwoSidedZThreshold[alphaLevel]
    Luaunit.assertIsTrue(math.abs(z) < threshold,
        "Z-test failed: z=" .. tostring(z) .. " is outside threshold " .. tostring(threshold) .. ". Observed probability " .. tostring(pHat) .. ", expected ~" .. tostring(pZero) .. "."
    )
end

---@param target string
---@param bee AnalyzedBeeIndividual
---@return boolean
local function IsPureBredTarget(target, bee)
    return (bee.active.species.name == target) and (bee.inactive.species.name == target)
end

---@param target string
---@param queen AnalyzedBeeIndividual
---@param drone AnalyzedBeeIndividual
---@param apiary Apiary
---@return fun(): boolean
local function BernoulliTrial_ArbitraryOffspringIsPureBredTarget(target, queen, drone, apiary)
    return function ()
        local _, drones = apiary:GenerateDescendants(queen, drone)

        return IsPureBredTarget(target, drones[1])
    end
end

---@param target string
---@param queenSpecies1 string
---@param queenSpecies2 string
---@param droneSpecies1 string
---@param droneSpecies2 string
---@param resourceProvider any  -- TODO: Adjust this once TestData has been refactored into proper provider classes.
---@param numTrials integer | nil
---@param alphaLevel number | nil
local function RunArbitraryOffspringAccuracyTest(target, queenSpecies1, queenSpecies2, droneSpecies1, droneSpecies2, resourceProvider, numTrials, alphaLevel)
    math.randomseed(456)
    local apiary = Apiary:Create(resourceProvider.GetRawMutationInfo(), resourceProvider.GetSpeciesTraitInfo())
    local graph = resourceProvider.GetGraph()
    local cacheElement = Util.BreedCacheTargetLoad(target, graph)
    local queen = Util.CreateBee(Util.CreateGenome(queenSpecies1, queenSpecies2))
    local drone = Util.CreateBee(Util.CreateGenome(droneSpecies1, droneSpecies2))
    local expectedProbability = MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
        target,
        queen.__genome.species.primary.name, queen.__genome.species.secondary.name,
        drone.__genome.species.primary.name, drone.__genome.species.secondary.name,
        cacheElement
    )

    VerifyReasonabilityOfAccuracy(
        BernoulliTrial_ArbitraryOffspringIsPureBredTarget(target, queen, drone, apiary),
        expectedProbability,
        numTrials,
        alphaLevel
    )
end

TestArbitraryOffspringIsPureBredTargetSimulation = {}
    function TestArbitraryOffspringIsPureBredTargetSimulation:TestParentAllelesCanMutateIntoTarget()
        RunArbitraryOffspringAccuracyTest("Cultivated", "Forest", "Forest", "Common", "Common", Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunArbitraryOffspringAccuracyTest("Cultivated", "Forest", "Common", "Forest", "Common", Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunArbitraryOffspringAccuracyTest("Cultivated", "Common", "Forest", "Common", "Forest", Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunArbitraryOffspringAccuracyTest("Cultivated", "Forest", "Common", "Common", "Common", Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunArbitraryOffspringAccuracyTest("Cultivated", "Forest", "Forest", "Common", "Forest", Res.BeeGraphMundaneIntoCommonIntoCultivated)
    end

    function TestArbitraryOffspringIsPureBredTargetSimulation:TestNoMutationSomeAllelesAlreadyTarget()
        RunArbitraryOffspringAccuracyTest("Cultivated", "Forest", "Forest", "Forest", "Cultivated", Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunArbitraryOffspringAccuracyTest("Cultivated", "Forest", "Forest", "Cultivated", "Cultivated", Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunArbitraryOffspringAccuracyTest("Cultivated", "Cultivated", "Forest", "Cultivated", "Forest", Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunArbitraryOffspringAccuracyTest("Cultivated", "Cultivated", "Forest", "Cultivated", "Cultivated", Res.BeeGraphMundaneIntoCommonIntoCultivated)
    end

    function TestArbitraryOffspringIsPureBredTargetSimulation:TestMultiplePossibleMutationsNoExistingPurity()
        RunArbitraryOffspringAccuracyTest("Result1", "Root1", "Root1", "Root2", "Root2", Res.BeeGraphSimpleDuplicateMutations)
        RunArbitraryOffspringAccuracyTest("Result2", "Root1", "Root1", "Root2", "Root2", Res.BeeGraphSimpleDuplicateMutations)
        RunArbitraryOffspringAccuracyTest("Result3", "Root1", "Root1", "Root2", "Root2", Res.BeeGraphSimpleDuplicateMutations)
        RunArbitraryOffspringAccuracyTest("Result4", "Root1", "Root1", "Root2", "Root2", Res.BeeGraphSimpleDuplicateMutations)
    end

    function TestArbitraryOffspringIsPureBredTargetSimulation:TestMultiplePossibleMutationsWithExistingPartialPurity()
        RunArbitraryOffspringAccuracyTest("Result3", "Result3", "Root1", "Root2", "Root2", Res.BeeGraphSimpleDuplicateMutations)
        RunArbitraryOffspringAccuracyTest("Result3", "Result3", "Root1", "Result3", "Root2", Res.BeeGraphSimpleDuplicateMutations)
        RunArbitraryOffspringAccuracyTest("Result3", "Root1", "Result3", "Result3", "Root2", Res.BeeGraphSimpleDuplicateMutations)
        RunArbitraryOffspringAccuracyTest("Result3", "Result3", "Root1", "Result3", "Result3", Res.BeeGraphSimpleDuplicateMutations)
    end

    function TestArbitraryOffspringIsPureBredTargetSimulation:TestParentsAlreadyPure()
        RunArbitraryOffspringAccuracyTest("Cultivated", "Cultivated", "Cultivated", "Cultivated", "Cultivated", Res.BeeGraphMundaneIntoCommonIntoCultivated)
    end
