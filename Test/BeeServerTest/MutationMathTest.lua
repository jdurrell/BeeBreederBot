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

TestCombinations = {}
    function TestCombinations:TestOneInput()
        Luaunit.assertEquals(ComputeCombinations({1.0}), {{1.0}})
        Luaunit.assertEquals(ComputeCombinations({0.34}), {{0.34}})
    end

    function TestCombinations:TestMultipleInputs()
        local num1 = 0.2
        local num2 = 0.5
        local num3 = 0.787
        Luaunit.assertItemsEquals(
            ComputeCombinations({num1, num2}),
            {{num1}, {num2}, {num1, num2}}
        )
        Luaunit.assertItemsEquals(
            ComputeCombinations({num1, num2, num3}),
            {{num1}, {num2}, {num3}, {num1, num2}, {num1, num3}, {num2, num3}, {num1, num2, num3}}
        )
    end

    function TestCombinations:TestDuplicateInputs()
        -- In the case of duplicate inputs, each input should be treated independently.
        local num1_a = 0.4
        local num1_b = 0.4
        local num2 = 0.9
        Luaunit.assertItemsEquals(
            ComputeCombinations({num1_a, num1_b}),
            {{num1_a}, {num1_b}, {num1_a, num1_b}}
        )
        Luaunit.assertItemsEquals(
            ComputeCombinations({num1_a, num1_b, num2}),
            {{num1_a}, {num1_b}, {num2}, {num1_a, num1_b}, {num1_a, num2}, {num1_b, num2}, {num1_a, num1_b, num2}}
        )
    end
