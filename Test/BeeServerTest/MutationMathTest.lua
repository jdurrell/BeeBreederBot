Luaunit = require("Test.luaunit")
MutationMath = require("BeeServer.MutationMath")

TestFactorial = {}
    function TestFactorial:TestFactorialBasic()
        Luaunit.assertEquals(Factorial(0), 1)
        Luaunit.assertEquals(Factorial(1), 1)
        Luaunit.assertEquals(Factorial(2), 2)
        Luaunit.assertEquals(Factorial(3), 6)
        Luaunit.assertEquals(Factorial(4), 24)
        Luaunit.assertEquals(Factorial(5), 120)
        Luaunit.assertEquals(Factorial(6), 720)
    end

TestPowerset = {}
    function TestPowerset:TestOneInput()
        Luaunit.assertItemsEquals(ComputePowerset({1.0}), {{}, {1.0}})
        Luaunit.assertItemsEquals(ComputePowerset({0.34}), {{}, {0.34}})
    end

    function TestPowerset:TestMultipleInputs()
        local num1 = 0.2
        local num2 = 0.5
        local num3 = 0.787
        Luaunit.assertItemsEquals(
            ComputePowerset({num1, num2}),
            {{}, {num1}, {num2}, {num1, num2}}
        )
        Luaunit.assertItemsEquals(
            ComputePowerset({num1, num2, num3}),
            {{}, {num1}, {num2}, {num3}, {num1, num2}, {num1, num3}, {num2, num3}, {num1, num2, num3}}
        )
    end

    function TestPowerset:TestDuplicateInputs()
        -- In the case of duplicate inputs, each input should be treated independently.
        local num1_a = 0.4
        local num1_b = 0.4
        local num2 = 0.9
        Luaunit.assertItemsEquals(
            ComputePowerset({num1_a, num1_b}),
            {{}, {num1_a}, {num1_b}, {num1_a, num1_b}}
        )
        Luaunit.assertItemsEquals(
            ComputePowerset({num1_a, num1_b, num2}),
            {{}, {num1_a}, {num1_b}, {num2}, {num1_a, num1_b}, {num1_a, num2}, {num1_b, num2}, {num1_a, num1_b, num2}}
        )
    end

    function TestPowerset:TestNoInput()
        Luaunit.assertEquals(ComputePowerset({}), {{}})
    end

TestMutationProbabilities = {}
    local MATH_MARGIN = 0.001

    function TestMutationProbabilities:TestNoOtherMutations()
        local targetChance = 0.234
        Luaunit.assertEquals(CalculateMutationChanceForTarget(targetChance, {}), targetChance)
    end

    function TestMutationProbabilities:TestOneOtherMutation()
        local targetChance = 0.5
        local otherMutation = 0.15
        local correct = 0.4625
        Luaunit.assertAlmostEquals(correct, (1/2 * targetChance) + (1/2 * (1-otherMutation) * targetChance), MATH_MARGIN, "Test constructed improperly.")
        Luaunit.assertAlmostEquals(
            CalculateMutationChanceForTarget(targetChance, {otherMutation}),
            correct,
            MATH_MARGIN
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
            MATH_MARGIN,
            "Test constructed improperly."
        )
        Luaunit.assertAlmostEquals(CalculateMutationChanceForTarget(targetChance, otherMutations2), correct2, MATH_MARGIN)

        local otherMutations3 = {0.6, 0.2, 0.12}
        local correct3 = 0.12168
        Luaunit.assertAlmostEquals(correct3,
            (((6/24) * targetChance) +
                ((2/24) * (1-otherMutations3[1]) * targetChance) + ((2/24) * (1-otherMutations3[2]) * targetChance) + ((2/24) * (1-otherMutations3[3]) * targetChance) + ((2/24) * (1-otherMutations3[1]) * (1-otherMutations3[2]) * targetChance) +
                ((2/24) * (1-otherMutations3[1]) * (1-otherMutations3[3]) * targetChance) + ((2/24) * (1-otherMutations3[2]) * (1-otherMutations3[3]) * targetChance) +
                ((6/24) * (1-otherMutations3[1]) * (1-otherMutations3[2]) * (1-otherMutations3[3]) * targetChance)),
            MATH_MARGIN,
            "Test constructed improperly."
        )
        Luaunit.assertAlmostEquals(CalculateMutationChanceForTarget(targetChance, otherMutations3), correct3, MATH_MARGIN)
    end
