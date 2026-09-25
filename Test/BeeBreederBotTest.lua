require("Shared.Shared")
__ActivateTestMode()

Luaunit = require("Test.luaunit")
require("Test.BeekeeperBotTest.GarbageCollectionTest")
require("Test.BeekeeperBotTest.MatchingMathTest")
require("Test.BeeServerTest.GraphTest")
require("Test.BeeServerTest.MutationMathTest")
require("Test.BeeServerTest.ServerOperationTest")
require("Test.SharedTest.MutationConditionSetTest")
require("Test.SimulationTest.ConvergenceTest")
require("Test.SimulationTest.RawDistributionTest")

os.exit(Luaunit.LuaUnit.run())
