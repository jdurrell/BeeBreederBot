local Luaunit = require("Test.luaunit")

local Apiary = require("Test.SimulatorModules.Apiary")
local Util = require("Test.Utilities.CommonUtilities")
local Res = require("Test.Resources.TestData")

local MatchingMath = require("BeeBot.MatchingMath")

local AlphaLevelToTwoSidedZThreshold = {
    [0.01] = 2.58,
    [0.05] = 1.96,
    [0.1]  = 1.64
}

---@param generateSample fun(): number
---@param value number
---@param n integer
local function VerifyAlwaysGeneratesValue(generateSample, value, n)
    for i = 1, n do
        Luaunit.assertEquals(generateSample(), value, "'Always Equals' failed at iteration " .. tostring(i) .. ".")
    end
    Util.VerbosePrint(string.format("\nn = %u, all correct!", n))
end

---@param generateSample fun(): number  A function that samples the distribution.
---@param muZero number  The expected value of sampling the distribution.
---@param variance number | nil
---@param n integer | nil  Number of samples to retrieve.
---@param alphaLevel number | nil
local function PerformZTest(generateSample, muZero, variance, n, alphaLevel)
    n = ((n == nil) and 100000) or n
    alphaLevel = ((alphaLevel == nil) and 0.01) or alphaLevel
    Luaunit.assertNotIsNil(AlphaLevelToTwoSidedZThreshold[alphaLevel], "Test-internal error: alpha level not found in lookup table.")
    Luaunit.assertIsTrue(n >= 10000, "Test-internal error: N must be greater than 10000 to approximate the binomial distribution as a normal distribution.")

    -- Perform `n` samples and count the total number of outcomes.
    -- TODO: Depending on the distribution, it might be possible to overflow the sums here.
    local observedSum = 0
    local results = {}
    for i = 1, n do
        local result = generateSample()
        observedSum = observedSum + result
        table.insert(results, result)
    end

    -- Since we have large n, the distribution of the normalized difference between muZero and xBar approaches a normal distribution
    -- by the Central Limit Theorem. We can approximate the variance using the standard deviation.
    local xBar = observedSum / n
    local stdev
    if variance ~= nil then
        stdev = math.sqrt(variance / n)
    else
        local sumSquaredDeviations = 0
        for _, val in ipairs(results) do
            sumSquaredDeviations = sumSquaredDeviations + ((val - xBar) ^ 2)
        end
        stdev = math.sqrt(sumSquaredDeviations / n)
    end
    if stdev == 0 then
        -- Force stdev to a very small number to avoid NaNs.
        -- In theory, a stdev of 0 means we should reject if xBar does not strictly equal muZero, but we need some tolerance for floating point errors.
        stdev = 0.0000001
    end
    local z = (xBar - muZero) / stdev

    -- Then, we perform a z-test and reject the expected mu `muZero` if the observed value differed to a degree of statistical
    -- significance represented by `alphaLevel`. Since we must test for the observed value being greater than or less than the expected
    -- probability, our z-test must be two-sided.
    local threshold = AlphaLevelToTwoSidedZThreshold[alphaLevel]
    Util.VerbosePrint(string.format("\nDid Z-test at alpha = %.3f:\nz = %.3f, mu0 = %.7f,\nrejection distance: %.7f, xBar = %.7f",
        alphaLevel, z, muZero, threshold * stdev, xBar
    ))

    Luaunit.assertIsTrue(math.abs(z) < threshold,
        string.format("Z-test failed: z=%.3f is outside threshold %.7f. Observed xBar %.7f, expected ~%.7f.", z, threshold, xBar, muZero)
    )
    Util.VerbosePrint("H0 not rejected!")
end

---@param target string
---@param bee AnalyzedBeeIndividual
---@return boolean
local function IsPureBredTarget(target, bee)
    return (bee.active.species.uid == target) and (bee.inactive.species.uid == target)
end

---@param target string
---@param queenSpecies1 string
---@param queenSpecies2 string
---@param droneSpecies1 string
---@param droneSpecies2 string
---@param resourceProvider any  -- TODO: Adjust this once TestData has been refactored into proper provider classes.
---@param numTrials integer | nil
---@param alphaLevel number | nil
---@param seed integer | nil
local function RunArbitraryOffspringAccuracyTest(target, queenSpecies1, queenSpecies2, droneSpecies1, droneSpecies2, resourceProvider, numTrials, alphaLevel, seed)
    numTrials = ((numTrials ~= nil) and numTrials) or 100000
    math.randomseed(((seed ~= nil) and seed) or 456)
    local apiary = Apiary:Create(resourceProvider.GetRawMutationInfo(), resourceProvider.GetSpeciesTraitInfo())
    local graph = resourceProvider.GetGraph()
    local cacheElement = Util.BreedCacheTargetLoad(target, graph)
    local queen = Util.CreateBee(Util.CreateGenome(queenSpecies1, queenSpecies2))
    local drone = Util.CreateBee(Util.CreateGenome(droneSpecies1, droneSpecies2))
    local expectedProbability = MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
        target,
        queen.__genome.species.primary.uid, queen.__genome.species.secondary.uid,
        drone.__genome.species.primary.uid, drone.__genome.species.secondary.uid,
        cacheElement
    )
    local sampleFunction = function ()
        local _, drones = apiary:GenerateDescendants(queen, drone)
        return (IsPureBredTarget(target, drones[1]) and 1) or 0
    end

    if (expectedProbability == 0) or (expectedProbability == 1) then
        VerifyAlwaysGeneratesValue(sampleFunction, expectedProbability, numTrials)
    else
        -- Since we have large n, we can approximate the binomial distribution B(n, p) (`n` trials each with probability `p` of success)
        -- representing the outcome of the sequence of Bernoulli trials as a normal distribution N(np, p(1-p)/n) (with mean `np` and
        -- variance `p(1-p)/n).
        -- The Z-test verifies this for us.
        PerformZTest(
            sampleFunction,
            expectedProbability,
            expectedProbability * (1 - expectedProbability),
            numTrials,
            alphaLevel
        )
    end
end

-- Randomly decides the genome ordering of traits based on observed active and inactive traits and according to dominance rules.
---@param activeSpecies string
---@param inactiveSpecies string
---@param fertility integer | nil
---@param traitInfo TraitInfo
---@return AnalyzedBeeIndividual
local function CreateBeeFromActiveAndInactive(activeSpecies, inactiveSpecies, fertility, traitInfo)
    -- If one trait is dominant and the other is recessive, then randomize the order.
    if (traitInfo.species[activeSpecies] ~= traitInfo.species[inactiveSpecies]) and math.random() < 0.5 then
        return Util.CreateBee(Util.CreateGenome(inactiveSpecies, activeSpecies, fertility), traitInfo)
    else
        return Util.CreateBee(Util.CreateGenome(activeSpecies, inactiveSpecies, fertility), traitInfo)
    end
end

---@param target string
---@param queenSpeciesActive string
---@param queenSpeciesInactive string
---@param droneSpeciesActive string
---@param droneSpeciesInactive string
---@param resourceProvider any  -- TODO: Adjust this once TestData has been refactored into proper provider classes.
---@param numTrials integer | nil
---@param alphaLevel number | nil
local function RunAtLeastOneOffspringAccuracyTest(target, queenSpeciesActive, queenSpeciesInactive, droneSpeciesActive, droneSpeciesInactive, queenFertility, resourceProvider, numTrials, alphaLevel)
    math.randomseed(456)
    numTrials = ((numTrials ~= nil) and numTrials) or 100000
    local traitInfo = resourceProvider.GetSpeciesTraitInfo()
    local apiary = Apiary:Create(resourceProvider.GetRawMutationInfo(), traitInfo)
    local graph = resourceProvider.GetGraph()
    local cacheElement = Util.BreedCacheTargetLoad(target, graph)
    local expectedProbability = MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
        target,
        Util.CreateBee(Util.CreateGenome(queenSpeciesActive, queenSpeciesInactive, queenFertility)),
        Util.CreateBee(Util.CreateGenome(droneSpeciesActive, droneSpeciesInactive)),
        cacheElement,
        traitInfo
    )
    local sampleFunction = function ()
        -- Randomize the order of species chromosomes according to dominance rules.
        local _, drones = apiary:GenerateDescendants(
            CreateBeeFromActiveAndInactive(queenSpeciesActive, queenSpeciesInactive, queenFertility, traitInfo),
            CreateBeeFromActiveAndInactive(droneSpeciesActive, droneSpeciesInactive, nil, traitInfo)
        )

        for _, outputDrone in ipairs(drones) do
            if IsPureBredTarget(target, outputDrone) then
                return 1
            end
        end

        return 0
    end

    if (expectedProbability == 0) or (expectedProbability == 1) then
        VerifyAlwaysGeneratesValue(sampleFunction, expectedProbability, numTrials)
    else
        PerformZTest(
            sampleFunction,
            expectedProbability,
            expectedProbability * (1 - expectedProbability),
            numTrials,
            alphaLevel
        )
    end
end

TestArbitraryOffspringIsPureBredTargetSimulation = {}
    function TestArbitraryOffspringIsPureBredTargetSimulation:TestParentAllelesCanMutateIntoTarget()
        local target = "Cultivated"
        RunArbitraryOffspringAccuracyTest(target, "Forest", "Forest", "Common", "Common", Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunArbitraryOffspringAccuracyTest(target, "Forest", "Common", "Forest", "Common", Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunArbitraryOffspringAccuracyTest(target, "Common", "Forest", "Common", "Forest", Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunArbitraryOffspringAccuracyTest(target, "Forest", "Common", "Common", "Common", Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunArbitraryOffspringAccuracyTest(target, "Forest", "Forest", "Common", "Forest", Res.BeeGraphMundaneIntoCommonIntoCultivated)
    end

    function TestArbitraryOffspringIsPureBredTargetSimulation:TestNoMutationSomeAllelesAlreadyTarget()
        local target = "Cultivated"
        RunArbitraryOffspringAccuracyTest(target, "Forest", "Forest", "Forest", "Cultivated", Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunArbitraryOffspringAccuracyTest(target, "Forest", "Forest", "Cultivated", "Cultivated", Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunArbitraryOffspringAccuracyTest(target, "Cultivated", "Forest", "Cultivated", "Forest", Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunArbitraryOffspringAccuracyTest(target, "Cultivated", "Forest", "Cultivated", "Cultivated", Res.BeeGraphMundaneIntoCommonIntoCultivated)
    end

    function TestArbitraryOffspringIsPureBredTargetSimulation:TestMultiplePossibleMutationsNoExistingPurity()
        RunArbitraryOffspringAccuracyTest("Result1", "Root1", "Root1", "Root2", "Root2", Res.BeeGraphSimpleDuplicateMutations)
        RunArbitraryOffspringAccuracyTest("Result2", "Root1", "Root1", "Root2", "Root2", Res.BeeGraphSimpleDuplicateMutations)
        RunArbitraryOffspringAccuracyTest("Result3", "Root1", "Root1", "Root2", "Root2", Res.BeeGraphSimpleDuplicateMutations)
        RunArbitraryOffspringAccuracyTest("Result4", "Root1", "Root1", "Root2", "Root2", Res.BeeGraphSimpleDuplicateMutations)
    end

    function TestArbitraryOffspringIsPureBredTargetSimulation:TestMultiplePossibleMutationsWithExistingPartialPurity()
        local target = "Result3"
        RunArbitraryOffspringAccuracyTest(target, "Result3", "Root1", "Root2", "Root2", Res.BeeGraphSimpleDuplicateMutations)
        RunArbitraryOffspringAccuracyTest(target, "Result3", "Root1", "Result3", "Root2", Res.BeeGraphSimpleDuplicateMutations)
        RunArbitraryOffspringAccuracyTest(target, "Root1", "Result3", "Result3", "Root2", Res.BeeGraphSimpleDuplicateMutations)
        RunArbitraryOffspringAccuracyTest(target, "Result3", "Root1", "Result3", "Result3", Res.BeeGraphSimpleDuplicateMutations)
    end

    function TestArbitraryOffspringIsPureBredTargetSimulation:TestParentsAlreadyPure()
        RunArbitraryOffspringAccuracyTest("Cultivated", "Cultivated", "Cultivated", "Cultivated", "Cultivated", Res.BeeGraphMundaneIntoCommonIntoCultivated)
    end

TestAtLeastOneOffspringIsPureBredTargetSimulation = {}
    function TestAtLeastOneOffspringIsPureBredTargetSimulation:TestNoChanceAnyOffspringIsPure()
        local target = "Cultivated"
        RunAtLeastOneOffspringAccuracyTest(target, "Forest", "Forest", "Forest", "Forest", 1, Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunAtLeastOneOffspringAccuracyTest(target, "Forest", "Forest", "Forest", "Forest", 2, Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunAtLeastOneOffspringAccuracyTest(target, "Forest", "Forest", "Forest", "Forest", 3, Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunAtLeastOneOffspringAccuracyTest(target, "Forest", "Forest", "Forest", "Forest", 4, Res.BeeGraphMundaneIntoCommonIntoCultivated)
    end

    function TestAtLeastOneOffspringIsPureBredTargetSimulation:TestPartialPurity()
        local target = "Cultivated"
        RunAtLeastOneOffspringAccuracyTest(target, "Cultivated", "Forest", "Cultivated", "Forest", 1, Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunAtLeastOneOffspringAccuracyTest(target, "Cultivated", "Forest", "Cultivated", "Forest", 2, Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunAtLeastOneOffspringAccuracyTest(target, "Cultivated", "Forest", "Cultivated", "Forest", 3, Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunAtLeastOneOffspringAccuracyTest(target, "Cultivated", "Forest", "Cultivated", "Forest", 4, Res.BeeGraphMundaneIntoCommonIntoCultivated)
    end

    function TestAtLeastOneOffspringIsPureBredTargetSimulation:TestParentsAlreadyPure()
        local target = "Cultivated"
        RunAtLeastOneOffspringAccuracyTest(target, target, target, target, target, 1, Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunAtLeastOneOffspringAccuracyTest(target, target, target, target, target, 2, Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunAtLeastOneOffspringAccuracyTest(target, target, target, target, target, 3, Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunAtLeastOneOffspringAccuracyTest(target, target, target, target, target, 4, Res.BeeGraphMundaneIntoCommonIntoCultivated)
    end

    function TestAtLeastOneOffspringIsPureBredTargetSimulation:TestNoExistingPurityWithDominance()
        local target = "RecessiveResult"
        RunAtLeastOneOffspringAccuracyTest(target, "Recessive1", "Recessive1", "Dominant1", "Dominant1", 2, Res.BeeGraphSimpleDominance)
        RunAtLeastOneOffspringAccuracyTest(target, "Dominant1", "Recessive1", "Dominant1", "Recessive1", 2, Res.BeeGraphSimpleDominance)
        RunAtLeastOneOffspringAccuracyTest(target, "Recessive1", "Recessive1", "Dominant1", "Recessive1", 2, Res.BeeGraphSimpleDominance)
        RunAtLeastOneOffspringAccuracyTest(target, "Dominant1", "Dominant1", "Dominant1", "Recessive1", 2, Res.BeeGraphSimpleDominance)
    end

    function TestAtLeastOneOffspringIsPureBredTargetSimulation:TestPartialPurityWithDominance()
        local target = "DominantResult"
        RunAtLeastOneOffspringAccuracyTest(target, "Recessive2", "Recessive2", "DominantResult", "DominantResult", 2, Res.BeeGraphSimpleDominance)
        RunAtLeastOneOffspringAccuracyTest(target, "DominantResult", "Recessive2", "Recessive2", "DominantResult", 2, Res.BeeGraphSimpleDominance)
        RunAtLeastOneOffspringAccuracyTest(target, "DominantResult", "DominantResult", "DominantResult", "Recessive2", 2, Res.BeeGraphSimpleDominance)

        RunAtLeastOneOffspringAccuracyTest(target, "Recessive2", "Recessive3", "DominantResult", "Recessive2", 2, Res.BeeGraphSimpleDominance)
        RunAtLeastOneOffspringAccuracyTest(target, "DominantResult", "Recessive3", "DominantResult", "Recessive2", 2, Res.BeeGraphSimpleDominance)

        target = "RecessiveResult"
        RunAtLeastOneOffspringAccuracyTest(target, "Recessive2", "Recessive2", "RecessiveResult", "RecessiveResult", 2, Res.BeeGraphSimpleDominance)
        RunAtLeastOneOffspringAccuracyTest(target, "RecessiveResult", "Recessive2", "Recessive2", "RecessiveResult", 2, Res.BeeGraphSimpleDominance)
        RunAtLeastOneOffspringAccuracyTest(target, "RecessiveResult", "RecessiveResult", "RecessiveResult", "Recessive2", 2, Res.BeeGraphSimpleDominance)

        RunAtLeastOneOffspringAccuracyTest(target, "Recessive2", "Recessive3", "RecessiveResult", "Recessive2", 2, Res.BeeGraphSimpleDominance)
        RunAtLeastOneOffspringAccuracyTest(target, "RecessiveResult", "Recessive3", "RecessiveResult", "Recessive2", 2, Res.BeeGraphSimpleDominance)
    end

    function TestAtLeastOneOffspringIsPureBredTargetSimulation:TestDominanceMultipleMutations()
        RunAtLeastOneOffspringAccuracyTest("Result1", "Root1", "Root1", "Root2", "Root1", 2, Res.BeeGraphSimpleDominanceDuplicateMutations)
        RunAtLeastOneOffspringAccuracyTest("Result1", "Root2", "Root1", "Root2", "Root1", 2, Res.BeeGraphSimpleDominanceDuplicateMutations)
        RunAtLeastOneOffspringAccuracyTest("Result2", "Root1", "Root1", "Root2", "Root1", 2, Res.BeeGraphSimpleDominanceDuplicateMutations)
        RunAtLeastOneOffspringAccuracyTest("Result2", "Root2", "Root1", "Root2", "Root1", 2, Res.BeeGraphSimpleDominanceDuplicateMutations)
    end

---@param target string
---@param queenSpeciesActive string
---@param queenSpeciesInactive string
---@param droneSpeciesActive string
---@param droneSpeciesInactive string
---@param resourceProvider any  -- TODO: Adjust this once TestData has been refactored into proper provider classes.
---@param numTrials integer | nil
---@param alphaLevel number | nil
local function RunExpectedTargetAllelesTest(target, queenSpeciesActive, queenSpeciesInactive, droneSpeciesActive, droneSpeciesInactive, resourceProvider, numTrials, alphaLevel)
    math.randomseed(789)
    numTrials = ((numTrials ~= nil) and numTrials) or 100000
    local traitInfo = resourceProvider.GetSpeciesTraitInfo()
    local apiary = Apiary:Create(resourceProvider.GetRawMutationInfo(), traitInfo)
    local graph = resourceProvider.GetGraph()
    local cacheElement = Util.BreedCacheTargetLoad(target, graph)
    local expectedAlleles = MatchingMath.CalculateExpectedNumberOfTargetAllelesPerOffspring(
        target,
        Util.CreateBee(Util.CreateGenome(queenSpeciesActive, queenSpeciesInactive)),
        Util.CreateBee(Util.CreateGenome(droneSpeciesActive, droneSpeciesInactive)),
        cacheElement,
        traitInfo
    )

    local sum = 0
    for i = 1, numTrials do
        -- Randomize the order of species chromosomes according to dominance rules.
        local _, drones = apiary:GenerateDescendants(
            CreateBeeFromActiveAndInactive(queenSpeciesActive, queenSpeciesInactive, nil, traitInfo),
            CreateBeeFromActiveAndInactive(droneSpeciesActive, droneSpeciesInactive, nil, traitInfo)
        )

        sum = sum + (((drones[1].active.species.uid == target) and 1) or 0) + (((drones[1].inactive.species.uid == target) and 1) or 0)
    end
    local average = sum / numTrials

    if (expectedAlleles == 0) or (expectedAlleles == 2) then
        Luaunit.assertEquals(average, expectedAlleles)
    else
        -- The variance is too large for us to use a Z-test, even at large sample sizes. Mostly the distribution is not normal.
        Luaunit.assertIsTrue(math.abs(average - expectedAlleles) < 0.005,
            string.format("Got %.7f, expected ~%.7f. Difference %.7f", average, expectedAlleles, average - expectedAlleles)
        )
    end
end

TestExpectedTargetAllelesPerOffspringSimulation = {}
    function TestExpectedTargetAllelesPerOffspringSimulation:TestNoAlleles()
        RunExpectedTargetAllelesTest("Forest", "Meadows", "Meadows", "Meadows", "Meadows", Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunExpectedTargetAllelesTest("Cultivated", "Forest", "Tropical", "Meadows", "Marshy", Res.BeeGraphMundaneIntoCommonIntoCultivated)
    end

    function TestExpectedTargetAllelesPerOffspringSimulation:TestBothAlleles()
        RunExpectedTargetAllelesTest("Cultivated", "Cultivated", "Cultivated", "Cultivated", "Cultivated", Res.BeeGraphMundaneIntoCommonIntoCultivated)
    end

    function TestExpectedTargetAllelesPerOffspringSimulation:TestNoExistingPurity()
        local target = "Cultivated"
        RunExpectedTargetAllelesTest(target, "Forest", "Forest", "Common", "Common", Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunExpectedTargetAllelesTest(target, "Forest", "Common", "Forest", "Common", Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunExpectedTargetAllelesTest(target, "Forest", "Forest", "Common", "Forest", Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunExpectedTargetAllelesTest(target, "Common", "Forest", "Common", "Common", Res.BeeGraphMundaneIntoCommonIntoCultivated)
    end

    function TestExpectedTargetAllelesPerOffspringSimulation:TestExistingPartialPurity()
        local target = "Cultivated"
        RunExpectedTargetAllelesTest(target, "Cultivated", "Forest", "Cultivated", "Forest", Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunExpectedTargetAllelesTest(target, "Cultivated", "Forest", "Cultivated", "Forest", Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunExpectedTargetAllelesTest(target, "Cultivated", "Forest", "Cultivated", "Forest", Res.BeeGraphMundaneIntoCommonIntoCultivated)
        RunExpectedTargetAllelesTest(target, "Cultivated", "Forest", "Cultivated", "Forest", Res.BeeGraphMundaneIntoCommonIntoCultivated)
    end

    function TestExpectedTargetAllelesPerOffspringSimulation:TestNoExistingPurityWithDominance()
        local target = "RecessiveResult"
        RunExpectedTargetAllelesTest(target, "Recessive1", "Recessive1", "Dominant1", "Dominant1", Res.BeeGraphSimpleDominance)
        RunExpectedTargetAllelesTest(target, "Dominant1", "Recessive1", "Dominant1", "Recessive1", Res.BeeGraphSimpleDominance)
        RunExpectedTargetAllelesTest(target, "Recessive1", "Recessive1", "Dominant1", "Recessive1", Res.BeeGraphSimpleDominance)
        RunExpectedTargetAllelesTest(target, "Dominant1", "Dominant1", "Dominant1", "Recessive1", Res.BeeGraphSimpleDominance)
    end

    function TestExpectedTargetAllelesPerOffspringSimulation:TestPartialPurityWithDominance()
        local target = "DominantResult"
        RunExpectedTargetAllelesTest(target, "Recessive2", "Recessive2", "DominantResult", "DominantResult", Res.BeeGraphSimpleDominance)
        RunExpectedTargetAllelesTest(target, "DominantResult", "Recessive2", "Recessive2", "DominantResult", Res.BeeGraphSimpleDominance)
        RunExpectedTargetAllelesTest(target, "DominantResult", "DominantResult", "DominantResult", "Recessive2", Res.BeeGraphSimpleDominance)

        RunExpectedTargetAllelesTest(target, "Recessive2", "Recessive3", "DominantResult", "Recessive2", Res.BeeGraphSimpleDominance)
        RunExpectedTargetAllelesTest(target, "DominantResult", "Recessive3", "DominantResult", "Recessive2", Res.BeeGraphSimpleDominance)

        target = "RecessiveResult"
        RunExpectedTargetAllelesTest(target, "Recessive2", "Recessive2", "RecessiveResult", "RecessiveResult", Res.BeeGraphSimpleDominance)
        RunExpectedTargetAllelesTest(target, "RecessiveResult", "Recessive2", "Recessive2", "RecessiveResult", Res.BeeGraphSimpleDominance)
        RunExpectedTargetAllelesTest(target, "RecessiveResult", "RecessiveResult", "RecessiveResult", "Recessive2", Res.BeeGraphSimpleDominance)

        RunExpectedTargetAllelesTest(target, "Recessive2", "Recessive3", "RecessiveResult", "Recessive2", Res.BeeGraphSimpleDominance)
        RunExpectedTargetAllelesTest(target, "RecessiveResult", "Recessive3", "RecessiveResult", "Recessive2", Res.BeeGraphSimpleDominance)
    end

    function TestExpectedTargetAllelesPerOffspringSimulation:TestDominanceMultipleMutations()
        RunExpectedTargetAllelesTest("Result1", "Root1", "Root1", "Root2", "Root1", Res.BeeGraphSimpleDominanceDuplicateMutations)
        RunExpectedTargetAllelesTest("Result1", "Root2", "Root1", "Root2", "Root1", Res.BeeGraphSimpleDominanceDuplicateMutations)
        RunExpectedTargetAllelesTest("Result2", "Root1", "Root1", "Root2", "Root1", Res.BeeGraphSimpleDominanceDuplicateMutations)
        RunExpectedTargetAllelesTest("Result2", "Root2", "Root1", "Root2", "Root1", Res.BeeGraphSimpleDominanceDuplicateMutations)
    end
