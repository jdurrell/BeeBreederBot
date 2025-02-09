Luaunit = require("Test.luaunit")
require("Test.BeeServerTest.MutationMathTest")
require("Test.BeeServerTest.GraphTest")
require("Test.BeeServerTest.ServerOperationTest")
require("Shared.Shared")

__ActivateTestMode()
os.exit(Luaunit.LuaUnit.run())
