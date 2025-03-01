local Luaunit = require("Test.luaunit")

local Apiary = require("Test.SimulatorModules.Apiary")
local MatchingMath = require("BeeBot.MatchingMath")
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
        Luaunit.assertIsTrue(bernoulliTrial(), "'Always Happens' failed at iteration " .. tostring(i) .. ".")
    end
    Util.VerbosePrint(string.format("\nn = %u, all correct!", n))
end

-- Performs `n` Bernoulli trials (defined by `bernoulliTrial`) and verifies that it doesn't succeed once.
---@param bernoulliTrial fun(): boolean  A function that determines whether the outcome of a given Bernoulli trial is a "success".
---@param n integer | nil Number of Bernoulli trials to perform.
local function VerifyNeverHappens(bernoulliTrial, n)
    for i = 1, n do
        Luaunit.assertIsFalse(bernoulliTrial(), "'Never Happens' failed at iteration " .. tostring(i) .. ".")
    end
    Util.VerbosePrint(string.format("\nn = %u, all correct!", n))
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
    local stdev = math.sqrt((pZero * (1 - pZero)) / n)
    local z = (pHat - pZero) / stdev

    -- Since we must test for the observed probability being greater than or less than the expected probability, our z-test must be two-sided.
    local threshold = AlphaLevelToTwoSidedZThreshold[alphaLevel]
    Util.VerbosePrint(string.format("\nDid Z-test at alpha = %.3f:\np0 = %.7f, rejection distance: %.7f\npHat = %.7f, z = %.3f",
        alphaLevel, pZero, threshold * stdev, pHat, z
    ))

    Luaunit.assertIsTrue(math.abs(z) < threshold,
        "Z-test failed: z=" .. tostring(z) .. " is outside threshold " .. tostring(threshold) .. ". Observed probability " .. tostring(pHat) .. ", expected ~" .. tostring(pZero) .. "."
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
local function RunArbitraryOffspringAccuracyTest(target, queenSpecies1, queenSpecies2, droneSpecies1, droneSpecies2, resourceProvider, numTrials, alphaLevel)
    math.randomseed(456)
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

    VerifyReasonabilityOfAccuracy(
        function ()
            local _, drones = apiary:GenerateDescendants(queen, drone)
            return IsPureBredTarget(target, drones[1])
        end,
        expectedProbability,
        numTrials,
        alphaLevel
    )
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
        return Util.CreateBee(Util.CreateGenome(inactiveSpecies, activeSpecies, fertility))
    else
        return Util.CreateBee(Util.CreateGenome(activeSpecies, inactiveSpecies, fertility))
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
local function RunAtLeastOneOffspringAccuracyTest(target, queenSpecies1, queenSpecies2, droneSpecies1, droneSpecies2, queenFertility, resourceProvider, numTrials, alphaLevel)
    math.randomseed(456)
    local traitInfo = resourceProvider.GetSpeciesTraitInfo()
    local apiary = Apiary:Create(resourceProvider.GetRawMutationInfo(), traitInfo)
    local graph = resourceProvider.GetGraph()
    local cacheElement = Util.BreedCacheTargetLoad(target, graph)

    local expectedProbability = MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
        target,
        CreateBeeFromActiveAndInactive(queenSpecies1, queenSpecies2, queenFertility, traitInfo),
        CreateBeeFromActiveAndInactive(droneSpecies1, droneSpecies2, queenFertility, traitInfo),
        cacheElement,
        traitInfo
    )

    VerifyReasonabilityOfAccuracy(
        function ()
            -- Randomize the order of species chromosomes according to dominance rules.
            local _, drones = apiary:GenerateDescendants(
                CreateBeeFromActiveAndInactive(queenSpecies1, queenSpecies2, queenFertility, traitInfo),
                CreateBeeFromActiveAndInactive(droneSpecies1, droneSpecies2, nil, traitInfo)
            )

            for _, outputDrone in ipairs(drones) do
                if IsPureBredTarget(target, outputDrone) then
                    return true
                end
            end

            return false
        end,
        expectedProbability,
        numTrials,
        alphaLevel
    )
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
