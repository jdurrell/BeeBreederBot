require("Shared.Shared")
__ActivateTestMode()

Luaunit = require("Test.luaunit")
require("Test.BeeBotTest.GarbageCollectionTest")
require("Test.BeeBotTest.MatchingMathTest")
require("Test.BeeServerTest.MutationMathTest")
require("Test.BeeServerTest.GraphTest")
require("Test.BeeServerTest.ServerOperationTest")
require("Test.SharedLibTest.LoggerTest")
require("Test.SimulationTest.ConvergenceTest")
require("Test.SimulationTest.RawDistributionTest")

os.exit(Luaunit.LuaUnit.run())
