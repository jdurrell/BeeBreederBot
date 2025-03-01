local Luaunit = require("Test.luaunit")

local Res = require("Test.Resources.TestData")

local GraphParse = require("BeeServer.GraphParse")
local MutationMath = require("BeeServer.MutationMath")

TestFactorial = {}
    function TestFactorial:TestFactorialBasic()
        Luaunit.assertEquals(MutationMath.Factorial(0), 1)
        Luaunit.assertEquals(MutationMath.Factorial(1), 1)
        Luaunit.assertEquals(MutationMath.Factorial(2), 2)
        Luaunit.assertEquals(MutationMath.Factorial(3), 6)
        Luaunit.assertEquals(MutationMath.Factorial(4), 24)
        Luaunit.assertEquals(MutationMath.Factorial(5), 120)
        Luaunit.assertEquals(MutationMath.Factorial(6), 720)
    end

TestPowerset = {}
    function TestPowerset:TestOneInput()
        Luaunit.assertItemsEquals(MutationMath.ComputePowerset({1.0}), {{}, {1.0}})
        Luaunit.assertItemsEquals(MutationMath.ComputePowerset({0.34}), {{}, {0.34}})
    end

    function TestPowerset:TestMultipleInputs()
        local num1 = 0.2
        local num2 = 0.5
        local num3 = 0.787
        Luaunit.assertItemsEquals(
            MutationMath.ComputePowerset({num1, num2}),
            {{}, {num1}, {num2}, {num1, num2}}
        )
        Luaunit.assertItemsEquals(
            MutationMath.ComputePowerset({num1, num2, num3}),
            {{}, {num1}, {num2}, {num3}, {num1, num2}, {num1, num3}, {num2, num3}, {num1, num2, num3}}
        )
    end

    function TestPowerset:TestDuplicateInputs()
        -- In the case of duplicate inputs, each input should be treated independently.
        local num1_a = 0.4
        local num1_b = 0.4
        local num2 = 0.9
        Luaunit.assertItemsEquals(
            MutationMath.ComputePowerset({num1_a, num1_b}),
            {{}, {num1_a}, {num1_b}, {num1_a, num1_b}}
        )
        Luaunit.assertItemsEquals(
            MutationMath.ComputePowerset({num1_a, num1_b, num2}),
            {{}, {num1_a}, {num1_b}, {num2}, {num1_a, num1_b}, {num1_a, num2}, {num1_b, num2}, {num1_a, num1_b, num2}}
        )
    end

    function TestPowerset:TestNoInput()
        Luaunit.assertEquals(MutationMath.ComputePowerset({}), {{}})
    end

TestPermutations = {}
    function TestPermutations:TestNoInputs()
        Luaunit.assertEquals(MutationMath.ComputePermutations({}), {})
    end

    function TestPermutations:TestOneInput()
        Luaunit.assertEquals(MutationMath.ComputePermutations({0.2}), {{0.2}})
        Luaunit.assertEquals(MutationMath.ComputePermutations({0.123}), {{0.123}})
    end

    function TestPermutations:TestMultipleInputs()
        local num1 = 0.3
        local num2 = 0.5
        local num3 = 0.1
        Luaunit.assertItemsEquals(
            MutationMath.ComputePermutations({num1, num2}),
            {{num1, num2}, {num2, num1}}
        )
        Luaunit.assertItemsEquals(
            MutationMath.ComputePermutations({num1, num2, num3}),
            {{num1, num2, num3}, {num1, num3, num2}, {num2, num1, num3}, {num2, num3, num1}, {num3, num1, num2}, {num3, num2, num1}}
        )
    end

    function TestPermutations:TestDuplicateInputs()
        local num1 = 0.3
        local num2 = 0.3
        local num3 = 0.3
        Luaunit.assertItemsEquals(
            MutationMath.ComputePermutations({num1, num2}),
            {{num1, num2}, {num2, num1}}
        )
        Luaunit.assertItemsEquals(
            MutationMath.ComputePermutations({num1, num2, num3}),
            {{num1, num2, num3}, {num1, num3, num2}, {num2, num1, num3}, {num2, num3, num1}, {num3, num1, num2}, {num3, num2, num1}}
        )
    end

-- TODO: Decide whether this set of tests can be removed.
TestMutationChanceForTarget = {}
    function TestMutationChanceForTarget:TestNoOtherMutations()
        local targetChance = 0.234
        Luaunit.assertEquals(MutationMath.CalculateMutationChanceForTarget(targetChance, {}), targetChance)
    end

    function TestMutationChanceForTarget:TestOneOtherMutation()
        local targetChance = 0.5
        local otherMutation = 0.15
        local correct = 0.4625
        Luaunit.assertAlmostEquals(correct, (1/2 * targetChance) + (1/2 * (1-otherMutation) * targetChance), Res.MathMargin, "Test constructed improperly.")
        Luaunit.assertAlmostEquals(
            MutationMath.CalculateMutationChanceForTarget(targetChance, {otherMutation}),
            correct,
            Res.MathMargin
        )
    end

    function TestMutationChanceForTarget:TestMultipleOtherMutations()
        local targetChance = 0.2
        local otherMutations2 = {0.3, 0.5}
        local correct2 = 0.13
        Luaunit.assertAlmostEquals(correct2,
            (((2/6) * targetChance) +
                ((1/6) * (1-otherMutations2[1]) * targetChance) + ((1/6) * (1-otherMutations2[2]) * targetChance) +
                ((2/6) * (1-otherMutations2[1]) * (1-otherMutations2[2]) * targetChance)),
                Res.MathMargin,
            "Test constructed improperly."
        )
        Luaunit.assertAlmostEquals(MutationMath.CalculateMutationChanceForTarget(targetChance, otherMutations2), correct2, Res.MathMargin)

        local otherMutations3 = {0.6, 0.2, 0.12}
        local correct3 = 0.12168
        Luaunit.assertAlmostEquals(correct3,
            (((6/24) * targetChance) +
                ((2/24) * (1-otherMutations3[1]) * targetChance) + ((2/24) * (1-otherMutations3[2]) * targetChance) + ((2/24) * (1-otherMutations3[3]) * targetChance) + ((2/24) * (1-otherMutations3[1]) * (1-otherMutations3[2]) * targetChance) +
                ((2/24) * (1-otherMutations3[1]) * (1-otherMutations3[3]) * targetChance) + ((2/24) * (1-otherMutations3[2]) * (1-otherMutations3[3]) * targetChance) +
                ((6/24) * (1-otherMutations3[1]) * (1-otherMutations3[2]) * (1-otherMutations3[3]) * targetChance)),
                Res.MathMargin,
            "Test constructed improperly."
        )
        Luaunit.assertAlmostEquals(MutationMath.CalculateMutationChanceForTarget(targetChance, otherMutations3), correct3, Res.MathMargin)
    end

TestMutationChances = {}
    function TestMutationChances:TestOnlyTargetMutationPossible()
        local target, nonTarget = MutationMath.CalculateMutationChances("Common", {"Common"}, {["Common"]=0.234})
        Luaunit.assertEquals(target, 0.234)
        Luaunit.assertEquals(nonTarget, 0.0)
    end

    function TestMutationChances:TestOnlyNonTargetMutationPossible()
        local target, nonTarget = MutationMath.CalculateMutationChances("Common", {"Cultivated"}, {["Cultivated"]=0.567})
        Luaunit.assertEquals(target, 0.0)
        Luaunit.assertEquals(nonTarget, 0.567)
    end

    function TestMutationChances:TestNoMutationsPossible()
        local target, nonTarget = MutationMath.CalculateMutationChances("Common", {}, {})
        Luaunit.assertEquals(target, 0.0)
        Luaunit.assertEquals(nonTarget, 0.0)
    end

    function TestMutationChances:TestOneOtherMutation()
        local c = {["Common"]=0.2, ["Cultivated"]=0.3}
        local targetChance, nonTargetChance = MutationMath.CalculateMutationChances("Common", {"Common", "Cultivated"}, c)
        Luaunit.assertAlmostEquals(targetChance, ((1/2) * c["Common"]) + ((1/2) * (1 - c["Cultivated"]) * c["Common"]), Res.MathMargin)
        Luaunit.assertAlmostEquals(nonTargetChance, ((1/2) * c["Cultivated"]) + ((1/2) * (1 - c["Common"]) * c["Cultivated"]), Res.MathMargin)
    end

    function TestMutationChances:TestMultipleOtherMutations()
        local c = {["Common"]=0.2, ["Cultivated"]=0.3, ["Diligent"]=0.4}
        local targetChance, nonTargetChance = MutationMath.CalculateMutationChances("Common", {"Common", "Cultivated", "Diligent"}, c)

        Luaunit.assertAlmostEquals(targetChance, (
            ((2/6) * c["Common"]) +
            ((1/6) * (1 - c["Cultivated"]) * c["Common"]) +
            ((1/6) * (1 - c["Diligent"]) * c["Common"]) +
            ((2/6) * (1 - c["Cultivated"]) * (1 - c["Diligent"]) * c["Common"])
        ), Res.MathMargin)
        Luaunit.assertAlmostEquals(nonTargetChance, (
            (
                ((2/6) * c["Cultivated"]) +
                ((1/6) * (1 - c["Common"]) * c["Cultivated"]) +
                ((1/6) * (1 - c["Diligent"]) * c["Cultivated"]) +
                ((2/6) * (1 - c["Common"]) * (1 - c["Diligent"]) * c["Cultivated"])
            ) + (
                ((2/6) * c["Diligent"]) +
                ((1/6) * (1 - c["Common"]) * c["Diligent"]) +
                ((1/6) * (1 - c["Cultivated"]) * c["Diligent"]) +
                ((2/6) * (1 - c["Common"]) * (1 - c["Cultivated"]) * c["Diligent"])
            )
        ), Res.MathMargin)
    end

TestCalculateBreedInfo = {}
    function TestCalculateBreedInfo:TestTargetNotExisting()
        local graph = {}
        GraphParse.AddMutationToGraph(graph, "Forest", "Meadows", "Common", 0.15)
        local targetChance, nonTargetChance = MutationMath.CalculateBreedInfo("Forest", "Meadows", "shouldntexist", graph)
        Luaunit.assertEquals(targetChance, 0)
        Luaunit.assertEquals(nonTargetChance, 0.15)
    end

    function TestCalculateBreedInfo:TestRootNodeNoPossibleCombination()
        local graph = {}
        GraphParse.AddMutationToGraph(graph, "Forest", "Meadows", "Common", 0.15)
        GraphParse.AddMutationToGraph(graph, "Meadows", "Marshy", "Common", 0.15)
        local targetChance, nonTargetChance = MutationMath.CalculateBreedInfo("Marshy", "Meadows", "Forest", graph)
        Luaunit.assertEquals(targetChance, 0)
        Luaunit.assertEquals(nonTargetChance, 0.15)
    end

    function TestCalculateBreedInfo:TestNoPossibleCombinations()
        local graph = {}
        GraphParse.AddMutationToGraph(graph, "Forest", "Meadows", "Common", 0.15)
        GraphParse.AddMutationToGraph(graph, "Forest", "Modest", "Common", 0.15)
        GraphParse.AddMutationToGraph(graph, "Forest", "Tropical", "Common", 0.15)
        GraphParse.AddMutationToGraph(graph, "Forest", "Marshy", "Common", 0.15)
        GraphParse.AddMutationToGraph(graph, "Forest", "Rocky", "Common", 0.15)
        GraphParse.AddMutationToGraph(graph, "Forest", "Wintry", "Common", 0.15)

        local targetChance, nonTargetChance
        targetChance, nonTargetChance = MutationMath.CalculateBreedInfo("Meadows", "Wintry", "Forest", graph)
        Luaunit.assertEquals(targetChance, 0)
        Luaunit.assertEquals(nonTargetChance, 0)
        targetChance, nonTargetChance = MutationMath.CalculateBreedInfo("Meadows", "Wintry", "Modest", graph)
        Luaunit.assertEquals(targetChance, 0)
        Luaunit.assertEquals(nonTargetChance, 0)
        targetChance, nonTargetChance = MutationMath.CalculateBreedInfo("Meadows", "Wintry", "Tropical", graph)
        Luaunit.assertEquals(targetChance, 0)
        Luaunit.assertEquals(nonTargetChance, 0)
        targetChance, nonTargetChance = MutationMath.CalculateBreedInfo("Meadows", "Wintry", "Marshy", graph)
        Luaunit.assertEquals(targetChance, 0)
        Luaunit.assertEquals(nonTargetChance, 0)
        targetChance, nonTargetChance = MutationMath.CalculateBreedInfo("Meadows", "Wintry", "Rocky", graph)
        Luaunit.assertEquals(targetChance, 0)
        Luaunit.assertEquals(nonTargetChance, 0)
        targetChance, nonTargetChance = MutationMath.CalculateBreedInfo("Meadows", "Rocky", "Wintry", graph)
        Luaunit.assertEquals(targetChance, 0)
        Luaunit.assertEquals(nonTargetChance, 0)
        targetChance, nonTargetChance = MutationMath.CalculateBreedInfo("Modest", "Rocky", "Meadows", graph)
        Luaunit.assertEquals(targetChance, 0)
        Luaunit.assertEquals(nonTargetChance, 0)
    end

    function TestCalculateBreedInfo:TestOneCombinationUniqueOutcome()
        local graph = {}
        GraphParse.AddMutationToGraph(graph, "Forest", "Meadows", "Common", 0.15)

        local targetChance, nonTargetChance = MutationMath.CalculateBreedInfo("Forest", "Meadows", "Common", graph)
        Luaunit.assertAlmostEquals(targetChance, 0.15, Res.MathMargin)
        Luaunit.assertEquals(nonTargetChance, 0)
    end

    function TestCalculateBreedInfo:TestManyCombinationsUniqueOutcome()
        local graph = {}
        GraphParse.AddMutationToGraph(graph, "Forest", "Meadows", "Common", 0.15)
        GraphParse.AddMutationToGraph(graph, "Marshy", "Tropical", "Common", 0.35)

        local targetChance, nonTargetChance = MutationMath.CalculateBreedInfo("Forest", "Meadows", "Common", graph)
        Luaunit.assertAlmostEquals(targetChance, 0.15, Res.MathMargin)
        Luaunit.assertEquals(nonTargetChance, 0)
        targetChance, nonTargetChance = MutationMath.CalculateBreedInfo("Marshy", "Tropical", "Common", graph)
        Luaunit.assertAlmostEquals(targetChance, 0.35, Res.MathMargin)
        Luaunit.assertEquals(nonTargetChance, 0)

        graph = Res.BeeGraphMundaneIntoCommon:GetGraph()
        targetChance, nonTargetChance = MutationMath.CalculateBreedInfo("Meadows", "Modest", "Common", graph)
        Luaunit.assertAlmostEquals(targetChance, 0.15, Res.MathMargin)
        Luaunit.assertEquals(nonTargetChance, 0)

        graph = Res.BeeGraphMundaneIntoCommonIntoCultivated:GetGraph()
        targetChance, nonTargetChance = MutationMath.CalculateBreedInfo("Tropical", "Wintry", "Common", graph)
        Luaunit.assertAlmostEquals(targetChance, 0.15, Res.MathMargin)
        Luaunit.assertEquals(nonTargetChance, 0)

        targetChance, nonTargetChance = MutationMath.CalculateBreedInfo("Tropical", "Common", "Cultivated", graph)
        Luaunit.assertAlmostEquals(targetChance, 0.12, Res.MathMargin)
        Luaunit.assertEquals(nonTargetChance, 0)
    end

    function TestCalculateBreedInfo:TestManyCombinations()
        local graph = Res.BeeGraphSimpleDuplicateMutations:GetGraph()

        local targetChance, nonTargetChance
        targetChance, nonTargetChance = MutationMath.CalculateBreedInfo("Root1", "Root2", "Result1", graph)
        Luaunit.assertAlmostEquals(targetChance, Res.BeeGraphSimpleDuplicateMutations.ExpectedBreedInfo["Result1"]["Root1-Root2"].targetMutChance, Res.MathMargin)
        Luaunit.assertAlmostEquals(nonTargetChance, Res.BeeGraphSimpleDuplicateMutations.ExpectedBreedInfo["Result1"]["Root1-Root2"].nonTargetMutChance, Res.MathMargin)
        targetChance, nonTargetChance = MutationMath.CalculateBreedInfo("Root1", "Root2", "Result2", graph)
        Luaunit.assertAlmostEquals(targetChance, Res.BeeGraphSimpleDuplicateMutations.ExpectedBreedInfo["Result2"]["Root1-Root2"].targetMutChance, Res.MathMargin)
        Luaunit.assertAlmostEquals(nonTargetChance, Res.BeeGraphSimpleDuplicateMutations.ExpectedBreedInfo["Result2"]["Root1-Root2"].nonTargetMutChance, Res.MathMargin)
        targetChance, nonTargetChance = MutationMath.CalculateBreedInfo("Root1", "Root2", "Result3", graph)
        Luaunit.assertAlmostEquals(targetChance, Res.BeeGraphSimpleDuplicateMutations.ExpectedBreedInfo["Result3"]["Root1-Root2"].targetMutChance, Res.MathMargin)
        Luaunit.assertAlmostEquals(nonTargetChance, Res.BeeGraphSimpleDuplicateMutations.ExpectedBreedInfo["Result3"]["Root1-Root2"].nonTargetMutChance, Res.MathMargin)
        targetChance, nonTargetChance = MutationMath.CalculateBreedInfo("Root1", "Root2", "Result4", graph)
        Luaunit.assertAlmostEquals(targetChance, Res.BeeGraphSimpleDuplicateMutations.ExpectedBreedInfo["Result4"]["Root1-Root2"].targetMutChance, Res.MathMargin)
        Luaunit.assertAlmostEquals(nonTargetChance, Res.BeeGraphSimpleDuplicateMutations.ExpectedBreedInfo["Result4"]["Root1-Root2"].nonTargetMutChance, Res.MathMargin)
    end