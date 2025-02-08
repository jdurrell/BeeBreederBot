Luaunit = require("Test.luaunit")
require("Test.BeeServerTest.MutationMathTest")
require("Test.BeeServerTest.GraphTest")
require("Shared.Shared")

__ActivateTestMode()
Luaunit.LuaUnit.run()
