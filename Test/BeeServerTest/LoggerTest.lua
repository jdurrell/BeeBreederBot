local Luaunit = require("Test.luaunit")

local Util = require("Test.Utilities.CommonUtilities")

local Logger = require("BeeServer.Logger")

TestLogger = {}
    function TestLogger:TestNoLog()
        os.remove(Util.DEFAULT_LOG_PATH)

        local result = Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH)
        Luaunit.assertEquals(result, {})

        local success = Logger.LogSpeciesToDisk(Util.DEFAULT_LOG_PATH, "Forest")
        Luaunit.assertIsTrue(success)

        result = Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH)
        Luaunit.assertEquals(result, {"Forest"})
    end

    function TestLogger:TestReadExistingLog()
        Util.CreateLogfileSeed("BasicLog.log", Util.DEFAULT_LOG_PATH)

        local result = Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH)
        Luaunit.assertItemsEquals(result, {"Forest", "Meadows", "Tropical"})
    end

    function TestLogger:TestNewEntry()
        Util.CreateLogfileSeed("BasicLog.log", Util.DEFAULT_LOG_PATH)

        local success = Logger.LogSpeciesToDisk(Util.DEFAULT_LOG_PATH, "Marshy")
        Luaunit.assertIsTrue(success)

        local result = Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH)
        Luaunit.assertItemsEquals(result, {"Forest", "Meadows", "Tropical", "Marshy"})
    end

    function TestLogger:TestAlreadyExisting()
        Util.CreateLogfileSeed("BasicLog.log", Util.DEFAULT_LOG_PATH)

        local success = Logger.LogSpeciesToDisk(Util.DEFAULT_LOG_PATH, "Meadows")
        Luaunit.assertIsTrue(success)

        local result = Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH)
        Luaunit.assertItemsEquals(result, {"Forest", "Meadows", "Tropical"})
    end
