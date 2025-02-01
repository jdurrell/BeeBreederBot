Luaunit = require("Test.luaunit")
GraphParse = require("BeeServer.GraphParse")
MutationMath = require("BeeServer.MutationMath")
Resources = require("Test.Resources")

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

TestMutationProbabilities = {}
    function TestMutationProbabilities:TestNoOtherMutations()
        local targetChance = 0.234
        Luaunit.assertEquals(MutationMath.CalculateMutationChanceForTarget(targetChance, {}), targetChance)
    end

    function TestMutationProbabilities:TestOneOtherMutation()
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

    function TestMutationProbabilities:TestMultipleOtherMutations()
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

TestCalculateBreedInfo = {}
    function TestCalculateBreedInfo:TestTargetNotExisting()
        local graph = {}
        GraphParse.AddMutationToGraph(graph, "Forest", "Meadows", "Common", 0.15)
        Luaunit.assertEquals(MutationMath.CalculateBreedInfo("shouldntexist", graph), {})
    end

    function TestCalculateBreedInfo:TestRootNodeNoPossibleCombination()
        local graph = {}
        GraphParse.AddMutationToGraph(graph, "Forest", "Meadows", "Common", 0.15)
        GraphParse.AddMutationToGraph(graph, "Meadows", "Marshy", "Common", 0.15)
        Luaunit.assertEquals(MutationMath.CalculateBreedInfo("Forest", graph), {})

        graph = {}
        GraphParse.AddMutationToGraph(graph, "Forest", "Meadows", "Common", 0.15)
        GraphParse.AddMutationToGraph(graph, "Forest", "Modest", "Common", 0.15)
        GraphParse.AddMutationToGraph(graph, "Forest", "Tropical", "Common", 0.15)
        GraphParse.AddMutationToGraph(graph, "Forest", "Marshy", "Common", 0.15)
        GraphParse.AddMutationToGraph(graph, "Forest", "Rocky", "Common", 0.15)
        GraphParse.AddMutationToGraph(graph, "Forest", "Wintry", "Common", 0.15)
        Luaunit.assertEquals(MutationMath.CalculateBreedInfo("Forest", graph), {})
        Luaunit.assertEquals(MutationMath.CalculateBreedInfo("Meadows", graph), {})
        Luaunit.assertEquals(MutationMath.CalculateBreedInfo("Modest", graph), {})
        Luaunit.assertEquals(MutationMath.CalculateBreedInfo("Tropical", graph), {})
        Luaunit.assertEquals(MutationMath.CalculateBreedInfo("Marshy", graph), {})
        Luaunit.assertEquals(MutationMath.CalculateBreedInfo("Wintry", graph), {})
    end

    function TestCalculateBreedInfo:TestOneCombinationUniqueOutcome()
        local graph = {}
        GraphParse.AddMutationToGraph(graph, "Forest", "Meadows", "Common", 0.15)

        local result = {Forest={Meadows=0.15}, Meadows={Forest=0.15}}
        Luaunit.assertAlmostEquals(MutationMath.CalculateBreedInfo("Common", graph), result, Res.MathMargin)
    end

    function TestCalculateBreedInfo:TestManyCombinationsUniqueOutcome()
        local graph = {}
        GraphParse.AddMutationToGraph(graph, "Forest", "Meadows", "Common", 0.15)
        GraphParse.AddMutationToGraph(graph, "Marshy", "Tropical", "Common", 0.35)

        local result = {
            Forest={Meadows=0.15}, Meadows={Forest=0.15},
            Marshy={Tropical=0.35}, Tropical={Marshy=0.35}
        }
        Luaunit.assertAlmostEquals(MutationMath.CalculateBreedInfo("Common", graph), result, Res.MathMargin)

        graph = Res.BeeGraphMundaneIntoCommon:GetGraph()
        Luaunit.assertAlmostEquals(
            MutationMath.CalculateBreedInfo("Common", graph),
            Res.BeeGraphMundaneIntoCommon.ExpectedBreedInfo["Common"],
            Res.MathMargin
        )

        graph = Res.BeeGraphMundaneIntoCommonIntoCultivated:GetGraph()
        Luaunit.assertAlmostEquals(
            MutationMath.CalculateBreedInfo("Common", graph),
            Res.BeeGraphMundaneIntoCommonIntoCultivated.ExpectedBreedInfo["Common"],
            Res.MathMargin
        )
        Luaunit.assertAlmostEquals(
            MutationMath.CalculateBreedInfo("Cultivated", graph),
            Res.BeeGraphMundaneIntoCommonIntoCultivated.ExpectedBreedInfo["Cultivated"],
            Res.MathMargin
        )
    end

    function TestCalculateBreedInfo:TestManyCombinations()
        local graph = Res.BeeGraphSimpleDuplicateMutations:GetGraph()
        for species, _ in pairs(graph) do
            Luaunit.assertAlmostEquals(
                MutationMath.CalculateBreedInfo(species, graph),
                Res.BeeGraphSimpleDuplicateMutations.ExpectedBreedInfo[species],
                Res.MathMargin
            )
        end
    end