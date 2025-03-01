local Luaunit = require("Test.luaunit")

local Res = require("Test.Resources.TestData")
local Util = require("Test.Utilities")

local MatchingMath = require("BeeBot.MatchingMath")

TestArbitraryOffspringIsPureBredTarget = {}
    function TestArbitraryOffspringIsPureBredTarget:TestNoParentAlleleComboYieldsTarget()
        local graph = Res.BeeGraphMundaneIntoCommonIntoCultivated.GetGraph()
        local target = "Cultivated"
        local cacheElement = Util.BreedCacheTargetLoad(target, graph)

        Luaunit.assertEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, "Forest", "Forest", "Forest", "Forest", cacheElement
        ), 0)
        Luaunit.assertEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, "Forest", "Meadows", "Forest", "Meadows", cacheElement
        ), 0)
        Luaunit.assertEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, "Wintry", "Forest", "Forest", "Wintry", cacheElement
        ), 0)
        Luaunit.assertEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, "Modest", "Wintry", "Tropical", "Meadows", cacheElement
        ), 0)
        Luaunit.assertEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, "Marshy", "Forest", "Marshy", "Marshy", cacheElement
        ), 0)
    end

    function TestArbitraryOffspringIsPureBredTarget:TestParentAllelesYieldTargetMisaligned()
        local graph = Res.BeeGraphMundaneIntoCommonIntoCultivated.GetGraph()
        local target = "Cultivated"
        local cacheElement = Util.BreedCacheTargetLoad(target, graph)

        Luaunit.assertEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, "Forest", "Common", "Common", "Forest", cacheElement
        ), 0)
        Luaunit.assertEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, "Common", "Forest", "Forest", "Common", cacheElement
        ), 0)
        Luaunit.assertEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, "Meadows", "Common", "Common", "Meadows", cacheElement
        ), 0)
        Luaunit.assertEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, "Common", "Meadows", "Meadows", "Common", cacheElement
        ), 0)
    end

    function TestArbitraryOffspringIsPureBredTarget:TestParentAllelesCanMutateIntoTarget()
        local graph = Res.BeeGraphMundaneIntoCommonIntoCultivated.GetGraph()
        local target = "Cultivated"
        local cacheElement = Util.BreedCacheTargetLoad(target, graph)

        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, "Forest", "Forest", "Common", "Common", cacheElement
        ), 0.0144, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, "Forest", "Common", "Forest", "Common", cacheElement
        ), 0.0144, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, "Common", "Forest", "Common", "Forest", cacheElement
        ), 0.0144, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, "Forest", "Common", "Common", "Common", cacheElement
        ), 0.0036, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, "Forest", "Forest", "Common", "Forest", cacheElement
        ), 0.0036, Res.MathMargin)
    end

    function TestArbitraryOffspringIsPureBredTarget:TestNoMutationSomeAllelesAlreadyTarget()
        local graph = Res.BeeGraphMundaneIntoCommonIntoCultivated.GetGraph()
        local target = "Cultivated"
        local cacheElement = Util.BreedCacheTargetLoad(target, graph)

        Luaunit.assertEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, "Forest", "Forest", "Forest", "Cultivated", cacheElement
        ), 0, Res.MathMargin)
        Luaunit.assertEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, "Forest", "Forest", "Cultivated", "Cultivated", cacheElement
        ), 0, Res.MathMargin)
        Luaunit.assertEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, "Cultivated", "Forest", "Cultivated", "Forest", cacheElement
        ), 0.25, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, "Cultivated", "Forest", "Cultivated", "Cultivated", cacheElement
        ), 0.5, Res.MathMargin)
    end

    function TestArbitraryOffspringIsPureBredTarget:TestMultiplePossibleMutationsNoExistingPurity()
        local graph = Res.BeeGraphSimpleDuplicateMutations.GetGraph()
        local cache = {}
        for spec, _ in pairs(graph) do
            cache[spec] = Util.BreedCacheTargetLoad(spec, graph)
        end

        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            "Result1", "Root1", "Root1", "Root2", "Root2", cache["Result1"]
        ), 0.0941467, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            "Result2", "Root1", "Root1", "Root2", "Root2", cache["Result2"]
        ), 0.0112007, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            "Result3", "Root1", "Root1", "Root2", "Root2", cache["Result3"]
        ), 0.1540563, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            "Result4", "Root1", "Root1", "Root2", "Root2", cache["Result4"]
        ), 0.0025840, Res.MathMargin)
    end

    function TestArbitraryOffspringIsPureBredTarget:TestMultiplePossibleMutationsWithExistingPartialPurity()
        local graph = Res.BeeGraphSimpleDuplicateMutations.GetGraph()
        local cache = {}
        for spec, _ in pairs(graph) do
            cache[spec] = Util.BreedCacheTargetLoad(spec, graph)
        end

        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            "Result3", "Result3", "Root1", "Root2", "Root2", cache["Result3"]
        ), 0.0946416, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            "Result3", "Result3", "Root1", "Result3", "Root2", cache["Result3"]
        ), 0.25, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            "Result3", "Root1", "Result3", "Result3", "Root2", cache["Result3"]
        ), 0.2325651, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            "Result3", "Result3", "Root1", "Result3", "Result3", cache["Result3"]
        ), 0.5, Res.MathMargin)
    end

    function TestArbitraryOffspringIsPureBredTarget:TestParentsAlreadyPure()
        local graph = Res.BeeGraphMundaneIntoCommonIntoCultivated.GetGraph()
        local target = "Cultivated"
        local cacheElement = Util.BreedCacheTargetLoad(target, graph)

        Luaunit.assertEquals(MatchingMath.CalculateChanceArbitraryOffspringIsPureBredTarget(
            target, "Cultivated", "Cultivated", "Cultivated", "Cultivated", cacheElement
        ), 1)
    end

TestAtLeastOneOffspringIsPureBredTarget = {}
    function TestAtLeastOneOffspringIsPureBredTarget:TestNoChanceAnyOffspringIsPure()
        local graph = Res.BeeGraphMundaneIntoCommonIntoCultivated.GetGraph()
        local traitInfo = Res.BeeGraphMundaneIntoCommonIntoCultivated.GetSpeciesTraitInfo()
        local target = "Cultivated"
        local cacheElement = Util.BreedCacheTargetLoad(target, graph)

        Luaunit.assertEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, Util.CreateBee(Util.CreateGenome("Forest", "Forest", 1)), Util.CreateBee(Util.CreateGenome("Forest", "Forest", 2)), cacheElement, traitInfo
        ), 0)
        Luaunit.assertEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, Util.CreateBee(Util.CreateGenome("Forest", "Forest", 2)), Util.CreateBee(Util.CreateGenome("Forest", "Forest", 2)), cacheElement, traitInfo
        ), 0)
        Luaunit.assertEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, Util.CreateBee(Util.CreateGenome("Forest", "Forest", 3)), Util.CreateBee(Util.CreateGenome("Forest", "Forest", 2)), cacheElement, traitInfo
        ), 0)
        Luaunit.assertEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, Util.CreateBee(Util.CreateGenome("Forest", "Forest", 4)), Util.CreateBee(Util.CreateGenome("Forest", "Forest", 2)), cacheElement, traitInfo
        ), 0)
    end

    function TestAtLeastOneOffspringIsPureBredTarget:TestOffspringPurityIsUncertain()
        local graph = Res.BeeGraphMundaneIntoCommonIntoCultivated.GetGraph()
        local traitInfo = Res.BeeGraphMundaneIntoCommonIntoCultivated.GetSpeciesTraitInfo()
        local target = "Cultivated"
        local cacheElement = Util.BreedCacheTargetLoad(target, graph)

        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, Util.CreateBee(Util.CreateGenome("Cultivated", "Forest", 1)), Util.CreateBee(Util.CreateGenome("Cultivated", "Forest", 2)), cacheElement, traitInfo
        ), 0.25, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, Util.CreateBee(Util.CreateGenome("Cultivated", "Forest", 2)), Util.CreateBee(Util.CreateGenome("Cultivated", "Forest", 2)), cacheElement, traitInfo
        ), 0.4375, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, Util.CreateBee(Util.CreateGenome("Cultivated", "Forest", 3)), Util.CreateBee(Util.CreateGenome("Cultivated", "Forest", 2)), cacheElement, traitInfo
        ), 0.578125, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, Util.CreateBee(Util.CreateGenome("Cultivated", "Forest", 4)), Util.CreateBee(Util.CreateGenome("Cultivated", "Forest", 2)), cacheElement, traitInfo
        ), 0.6835938, Res.MathMargin)
    end

    function TestAtLeastOneOffspringIsPureBredTarget:TestParentsAlreadyPure()
        local graph = Res.BeeGraphMundaneIntoCommonIntoCultivated.GetGraph()
        local traitInfo = Res.BeeGraphMundaneIntoCommonIntoCultivated.GetSpeciesTraitInfo()
        local target = "Cultivated"
        local cacheElement = Util.BreedCacheTargetLoad(target, graph)

        Luaunit.assertEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, Util.CreateBee(Util.CreateGenome("Cultivated", "Cultivated", 1)), Util.CreateBee(Util.CreateGenome("Cultivated", "Cultivated", 2)), cacheElement, traitInfo
        ), 1)
        Luaunit.assertEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, Util.CreateBee(Util.CreateGenome("Cultivated", "Cultivated", 2)), Util.CreateBee(Util.CreateGenome("Cultivated", "Cultivated", 2)), cacheElement, traitInfo
        ), 1)
        Luaunit.assertEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, Util.CreateBee(Util.CreateGenome("Cultivated", "Cultivated", 3)), Util.CreateBee(Util.CreateGenome("Cultivated", "Cultivated", 2)), cacheElement, traitInfo
        ), 1)
        Luaunit.assertEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, Util.CreateBee(Util.CreateGenome("Cultivated", "Cultivated", 4)), Util.CreateBee(Util.CreateGenome("Cultivated", "Cultivated", 2)), cacheElement, traitInfo
        ), 1)
    end

    function TestAtLeastOneOffspringIsPureBredTarget:TestNoExistingPurityWithDominance()
        local graph = Res.BeeGraphSimpleDominance.GetGraph()
        local traitInfo = Res.BeeGraphSimpleDominance.GetSpeciesTraitInfo()
        local target = "RecessiveResult"
        local cacheElement = Util.BreedCacheTargetLoad(target, graph)

        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, Util.CreateBee(Util.CreateGenome("Recessive1", "Recessive1", 2)), Util.CreateBee(Util.CreateGenome("Dominant1", "Dominant1", 2)), cacheElement, traitInfo
        ), 0.0564377, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, Util.CreateBee(Util.CreateGenome("Dominant1", "Recessive1", 2)), Util.CreateBee(Util.CreateGenome("Dominant1", "Recessive1", 2)), cacheElement, traitInfo
        ), 0.0282188, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, Util.CreateBee(Util.CreateGenome("Recessive1", "Recessive1", 2)), Util.CreateBee(Util.CreateGenome("Dominant1", "Recessive1", 2)), cacheElement, traitInfo
        ), 0.0142631, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, Util.CreateBee(Util.CreateGenome("Dominant1", "Dominant1", 2)), Util.CreateBee(Util.CreateGenome("Dominant1", "Recessive1", 2)), cacheElement, traitInfo
        ), 0.0142631, Res.MathMargin)
    end

    function TestAtLeastOneOffspringIsPureBredTarget:TestPartialPurityWithDominance()
        local graph = Res.BeeGraphSimpleDominance.GetGraph()
        local traitInfo = Res.BeeGraphSimpleDominance.GetSpeciesTraitInfo()
        local target = "DominantResult"
        local cacheElement = Util.BreedCacheTargetLoad(target, graph)

        Luaunit.assertEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, Util.CreateBee(Util.CreateGenome("Recessive2", "Recessive2", 2)), Util.CreateBee(Util.CreateGenome("DominantResult", "DominantResult", 2)), cacheElement, traitInfo
        ), 0)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, Util.CreateBee(Util.CreateGenome("DominantResult", "Recessive2", 2)), Util.CreateBee(Util.CreateGenome("Recessive2", "DominantResult", 2)), cacheElement, traitInfo
        ), 0.4375, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, Util.CreateBee(Util.CreateGenome("DominantResult", "DominantResult", 2)), Util.CreateBee(Util.CreateGenome("DominantResult", "Recessive2", 2)), cacheElement, traitInfo
        ), 0.75, Res.MathMargin)

        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, Util.CreateBee(Util.CreateGenome("Recessive2", "Recessive2", 2)), Util.CreateBee(Util.CreateGenome("DominantResult", "Recessive2", 2)), cacheElement, traitInfo
        ), 0, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, Util.CreateBee(Util.CreateGenome("DominantResult", "Recessive3", 2)), Util.CreateBee(Util.CreateGenome("DominantResult", "Recessive2", 2)), cacheElement, traitInfo
        ), 0.4754969, Res.MathMargin)

        target = "RecessiveResult"
        Luaunit.assertEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, Util.CreateBee(Util.CreateGenome("Recessive2", "Recessive2", 2)), Util.CreateBee(Util.CreateGenome("RecessiveResult", "RecessiveResult", 2)), cacheElement, traitInfo
        ), 0)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, Util.CreateBee(Util.CreateGenome("RecessiveResult", "Recessive2", 2)), Util.CreateBee(Util.CreateGenome("Recessive2", "RecessiveResult", 2)), cacheElement, traitInfo
        ), 0.4375, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, Util.CreateBee(Util.CreateGenome("RecessiveResult", "RecessiveResult", 2)), Util.CreateBee(Util.CreateGenome("RecessiveResult", "Recessive2", 2)), cacheElement, traitInfo
        ), 0.75, Res.MathMargin)

        Luaunit.assertEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, Util.CreateBee(Util.CreateGenome("Recessive2", "Recessive3", 2)), Util.CreateBee(Util.CreateGenome("RecessiveResult", "Recessive2", 2)), cacheElement, traitInfo
        ), 0)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            target, Util.CreateBee(Util.CreateGenome("RecessiveResult", "Recessive3", 2)), Util.CreateBee(Util.CreateGenome("RecessiveResult", "Recessive2", 2)), cacheElement, traitInfo
        ), 0.4375, Res.MathMargin)
    end

    function TestAtLeastOneOffspringIsPureBredTarget:TestDominanceMultipleMutations()
        local graph = Res.BeeGraphSimpleDominanceDuplicateMutations.GetGraph()
        local traitInfo = Res.BeeGraphSimpleDominanceDuplicateMutations.GetSpeciesTraitInfo()
        local cache = Util.BreedCachePreloadAll(graph)

        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            "Result1", Util.CreateBee(Util.CreateGenome("Root1", "Root1", 2)), Util.CreateBee(Util.CreateGenome("Root2", "Root1", 2)), cache["Result1"], traitInfo
        ), 0.0465194, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            "Result1", Util.CreateBee(Util.CreateGenome("Root2", "Root1", 2)), Util.CreateBee(Util.CreateGenome("Root2", "Root1", 2)), cache["Result1"], traitInfo
        ), 0.0897149, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            "Result2", Util.CreateBee(Util.CreateGenome("Root1", "Root1", 2)), Util.CreateBee(Util.CreateGenome("Root2", "Root1", 2)), cache["Result2"], traitInfo
        ), 0.0055925, Res.MathMargin)
        Luaunit.assertAlmostEquals(MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
            "Result2", Util.CreateBee(Util.CreateGenome("Root2", "Root1", 2)), Util.CreateBee(Util.CreateGenome("Root2", "Root1", 2)), cache["Result2"], traitInfo
        ), 0.0111380, Res.MathMargin)
    end
