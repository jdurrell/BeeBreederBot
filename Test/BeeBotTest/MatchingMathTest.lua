local MatchingMath = require("BeeBot.MatchingMath")
local MutationMath = require("BeeServer.MutationMath")
local Res = require("Test.Resources.TestData")

-- Returns a breeding information cache element preloaded with all possible combinations for the given target.
---@param target string
---@param graph SpeciesGraph
---@return BreedInfoCacheElement
local function BreedCacheTargetLoad(target, graph)
    local cache = {}

    for spec, _ in pairs(graph) do
        cache[spec] = (cache[spec] == nil and {}) or cache[spec]
        for spec2, _ in pairs(graph) do
            cache[spec2] = (cache[spec2] == nil and {}) or cache[spec2]

            if cache[spec][spec2] == nil then
                Luaunit.assertIsNil(cache[spec2][spec], "Test-internal error.")

                local targetMutChance, nonTargetMutChance = MutationMath.CalculateBreedInfo(spec, spec2, target, graph)
                cache[spec][spec2] = {targetMutChance = targetMutChance, nonTargetMutChance = nonTargetMutChance}
                cache[spec2][spec] = {targetMutChance = targetMutChance, nonTargetMutChance = nonTargetMutChance}
            end
        end
    end

    return cache
end

-- Returns an AnalyzedBeeIndividual with the given breeding parameters and "defaults" otherwise.
-- These aren't *real* defaults, but this is useful when we already know that the undelying function isn't going to access them.
---@param speciesAllele1 string
---@param speciesAllele2 string
---@param fertility integer
---@return AnalyzedBeeIndividual
local function CreateBee(speciesAllele1, speciesAllele2, fertility)
    return {
        active = {
            species = {name = speciesAllele1},
            fertility = fertility
        },
        inactive = {
            species = {name = speciesAllele2},
            fertility = fertility
        }
    }
end

TestArbitraryOffspringIsPureBredTarget = {}
    function TestArbitraryOffspringIsPureBredTarget:TestNoParentAlleleComboYieldsTarget()
        local graph = Res.BeeGraphMundaneIntoCommonIntoCultivated.GetGraph()
        local target = "Cultivated"
        local cacheElement = BreedCacheTargetLoad(target, graph)

        Luaunit.assertEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, CreateBee("Forest", "Forest", 4), CreateBee("Forest", "Forest", 4), cacheElement
        ), 0)
        Luaunit.assertEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, CreateBee("Forest", "Meadows", 4), CreateBee("Forest", "Meadows", 4), cacheElement
        ), 0)
        Luaunit.assertEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, CreateBee("Wintry", "Forest", 4), CreateBee("Forest", "Wintry", 4), cacheElement
        ), 0)
        Luaunit.assertEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, CreateBee("Modest", "Wintry", 4), CreateBee("Tropical", "Meadows", 4), cacheElement
        ), 0)
        Luaunit.assertEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, CreateBee("Marshy", "Forest", 4), CreateBee("Marshy", "Marshy", 4), cacheElement
        ), 0)
    end

    function TestArbitraryOffspringIsPureBredTarget:TestParentAllelesYieldTargetMisaligned()
        local graph = Res.BeeGraphMundaneIntoCommonIntoCultivated.GetGraph()
        local target = "Cultivated"
        local cacheElement = BreedCacheTargetLoad(target, graph)

        Luaunit.assertEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, CreateBee("Forest", "Common", 4), CreateBee("Common", "Forest", 4), cacheElement
        ), 0)
        Luaunit.assertEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, CreateBee("Common", "Forest", 4), CreateBee("Forest", "Common", 4), cacheElement
        ), 0)
        Luaunit.assertEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, CreateBee("Meadows", "Common", 4), CreateBee("Common", "Meadows", 4), cacheElement
        ), 0)
        Luaunit.assertEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, CreateBee("Common", "Meadows", 4), CreateBee("Meadows", "Common", 4), cacheElement
        ), 0)
    end

    function TestArbitraryOffspringIsPureBredTarget:TestParentAllelesCanMutateIntoTarget()
        local graph = Res.BeeGraphMundaneIntoCommonIntoCultivated.GetGraph()
        local target = "Cultivated"
        local cacheElement = BreedCacheTargetLoad(target, graph)

        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, CreateBee("Forest", "Forest", 4), CreateBee("Common", "Common", 4), cacheElement
        ), 0.0144, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, CreateBee("Forest", "Common", 4), CreateBee("Forest", "Common", 4), cacheElement
        ), 0.0144, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, CreateBee("Common", "Forest", 4), CreateBee("Common", "Forest", 4), cacheElement
        ), 0.0144, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, CreateBee("Forest", "Common", 4), CreateBee("Common", "Common", 4), cacheElement
        ), 0.0036, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, CreateBee("Forest", "Forest", 4), CreateBee("Common", "Forest", 4), cacheElement
        ), 0.0036, Res.MathMargin)
    end

    function TestArbitraryOffspringIsPureBredTarget:TestNoMutationSomeAllelesAlreadyTarget()
        local graph = Res.BeeGraphMundaneIntoCommonIntoCultivated.GetGraph()
        local target = "Cultivated"
        local cacheElement = BreedCacheTargetLoad(target, graph)

        Luaunit.assertEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, CreateBee("Forest", "Forest", 4), CreateBee("Forest", "Cultivated", 4), cacheElement
        ), 0, Res.MathMargin)
        Luaunit.assertEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, CreateBee("Forest", "Forest", 4), CreateBee("Cultivated", "Cultivated", 4), cacheElement
        ), 0, Res.MathMargin)
        Luaunit.assertEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, CreateBee("Cultivated", "Forest", 4), CreateBee("Cultivated", "Forest", 4), cacheElement
        ), 0.25, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, CreateBee("Cultivated", "Forest", 4), CreateBee("Cultivated", "Cultivated", 4), cacheElement
        ), 0.5, Res.MathMargin)
    end

    function TestArbitraryOffspringIsPureBredTarget:TestMultiplePossibleMutationsNoExistingPurity()
        local graph = Res.BeeGraphSimpleDuplicateMutations.GetGraph()
        local cache = {}
        for spec, _ in pairs(graph) do
            cache[spec] = BreedCacheTargetLoad(spec, graph)
        end

        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            "Result1", CreateBee("Root1", "Root1", 4), CreateBee("Root2", "Root2", 4), cache["Result1"]
        ), 0.0941467, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            "Result2", CreateBee("Root1", "Root1", 4), CreateBee("Root2", "Root2", 4), cache["Result2"]
        ), 0.0112007, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            "Result3", CreateBee("Root1", "Root1", 4), CreateBee("Root2", "Root2", 4), cache["Result3"]
        ), 0.1540563, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            "Result4", CreateBee("Root1", "Root1", 4), CreateBee("Root2", "Root2", 4), cache["Result4"]
        ), 0.0025840, Res.MathMargin)
    end

    function TestArbitraryOffspringIsPureBredTarget:TestMultiplePossibleMutationsWithExistingPartialPurity()
        local graph = Res.BeeGraphSimpleDuplicateMutations.GetGraph()
        local cache = {}
        for spec, _ in pairs(graph) do
            cache[spec] = BreedCacheTargetLoad(spec, graph)
        end

        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            "Result3", CreateBee("Result3", "Root1", 4), CreateBee("Root2", "Root2", 4), cache["Result3"]
        ), 0.0946416, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            "Result3", CreateBee("Result3", "Root1", 4), CreateBee("Result3", "Root2", 4), cache["Result3"]
        ), 0.25, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            "Result3", CreateBee("Root1", "Result3", 4), CreateBee("Result3", "Root2", 4), cache["Result3"]
        ), 0.2325651, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            "Result3", CreateBee("Result3", "Root1", 4), CreateBee("Result3", "Result3", 4), cache["Result3"]
        ), 0.5, Res.MathMargin)
    end

    function TestArbitraryOffspringIsPureBredTarget:TestParentsAlreadyPure()
        local graph = Res.BeeGraphMundaneIntoCommonIntoCultivated.GetGraph()
        local target = "Cultivated"
        local cacheElement = BreedCacheTargetLoad(target, graph)

        Luaunit.assertEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, CreateBee("Cultivated", "Cultivated", 4), CreateBee("Cultivated", "Cultivated", 4), cacheElement
        ), 1)
    end

TestAtLeastOneOffspringIsPureBredTarget = {}
    function TestAtLeastOneOffspringIsPureBredTarget:TestNoChanceAnyOffspringIsPure()
        local graph = Res.BeeGraphMundaneIntoCommonIntoCultivated.GetGraph()
        local target = "Cultivated"
        local cacheElement = BreedCacheTargetLoad(target, graph)

        Luaunit.assertEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, CreateBee("Forest", "Forest", 1), CreateBee("Forest", "Forest", 2), cacheElement
        ), 0)
        Luaunit.assertEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, CreateBee("Forest", "Forest", 2), CreateBee("Forest", "Forest", 2), cacheElement
        ), 0)
        Luaunit.assertEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, CreateBee("Forest", "Forest", 3), CreateBee("Forest", "Forest", 2), cacheElement
        ), 0)
        Luaunit.assertEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, CreateBee("Forest", "Forest", 4), CreateBee("Forest", "Forest", 2), cacheElement
        ), 0)
    end

    function TestAtLeastOneOffspringIsPureBredTarget:TestOffspringPurityIsUncertain()
        local graph = Res.BeeGraphMundaneIntoCommonIntoCultivated.GetGraph()
        local target = "Cultivated"
        local cacheElement = BreedCacheTargetLoad(target, graph)

        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, CreateBee("Cultivated", "Forest", 1), CreateBee("Cultivated", "Forest", 2), cacheElement
        ), 0.25, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, CreateBee("Cultivated", "Forest", 2), CreateBee("Cultivated", "Forest", 2), cacheElement
        ), 0.4375, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, CreateBee("Cultivated", "Forest", 3), CreateBee("Cultivated", "Forest", 2), cacheElement
        ), 0.578125, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, CreateBee("Cultivated", "Forest", 4), CreateBee("Cultivated", "Forest", 2), cacheElement
        ), 0.6835938, Res.MathMargin)
    end

    function TestAtLeastOneOffspringIsPureBredTarget:TestParentsAlreadyPure()
        local graph = Res.BeeGraphMundaneIntoCommonIntoCultivated.GetGraph()
        local target = "Cultivated"
        local cacheElement = BreedCacheTargetLoad(target, graph)

        Luaunit.assertEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, CreateBee("Cultivated", "Cultivated", 1), CreateBee("Cultivated", "Cultivated", 2), cacheElement
        ), 1)
        Luaunit.assertEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, CreateBee("Cultivated", "Cultivated", 2), CreateBee("Cultivated", "Cultivated", 2), cacheElement
        ), 1)
        Luaunit.assertEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, CreateBee("Cultivated", "Cultivated", 3), CreateBee("Cultivated", "Cultivated", 2), cacheElement
        ), 1)
        Luaunit.assertEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, CreateBee("Cultivated", "Cultivated", 4), CreateBee("Cultivated", "Cultivated", 2), cacheElement
        ), 1)
    end
