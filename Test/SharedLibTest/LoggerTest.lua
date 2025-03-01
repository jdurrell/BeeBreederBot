local Luaunit = require("Test.luaunit")

local Util = require("Test.Utilities")

local Logger = require("Shared.Logger")

TestLogger = {}
    function TestLogger:TestNoLog()
        os.remove(Util.DEFAULT_LOG_PATH)

        local result = Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH)
        Luaunit.assertEquals(result, {})

        local success = Logger.LogSpeciesToDisk(Util.DEFAULT_LOG_PATH, "Forest", {x=0, y=0}, 123)
        Luaunit.assertIsTrue(success)

        result = Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH)
        Luaunit.assertEquals(result, {["Forest"]={loc={x=0, y=0}, timestamp=123}})

        Util.VerifyLogIsValidLog(Util.DEFAULT_LOG_PATH)
    end

    function TestLogger:TestReadExistingLog()
        Util.CreateLogfileSeed("BasicLog.log", Util.DEFAULT_LOG_PATH)

        local result = Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH)
        Luaunit.assertEquals(result, {
            ["Forest"]={loc={x=0, y=0}, timestamp=123456},
            ["Meadows"]={loc={x=0, y=1}, timestamp=123456},
            ["Tropical"]={loc={x=0, y=2}, timestamp=123456}
        })

        Util.VerifyLogIsValidLog(Util.DEFAULT_LOG_PATH)
    end

    function TestLogger:TestReadZeroTimestamp()
        Util.CreateLogfileSeed("LogfileWithZeroTimestamps.log", Util.DEFAULT_LOG_PATH)

        local result = UnwrapNull(Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH))
        Luaunit.assertNotIsNil(result)

        local zeroTimestampResult = result["Marshy"]
        Luaunit.assertEquals(zeroTimestampResult.loc, {x=0, y=4})
        Luaunit.assertNotEquals(zeroTimestampResult.timestamp, 0)

        result["Marshy"] = nil
        Luaunit.assertEquals(result, {
            ["Forest"]={loc={x=0, y=0}, timestamp=123456},
            ["Meadows"]={loc={x=0, y=1}, timestamp=123456},
            ["Tropical"]={loc={x=0, y=2}, timestamp=123456}
        })

        local result2 = Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH)
        Luaunit.assertEquals(result2, {
            ["Forest"]={loc={x=0, y=0}, timestamp=123456},
            ["Meadows"]={loc={x=0, y=1}, timestamp=123456},
            ["Tropical"]={loc={x=0, y=2}, timestamp=123456},
            ["Marshy"]=zeroTimestampResult
        })

        Util.VerifyLogIsValidLog(Util.DEFAULT_LOG_PATH)
    end

    function TestLogger:TestOverwriteExisting()
        Util.CreateLogfileSeed("BasicLog.log", Util.DEFAULT_LOG_PATH)

        local result = Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH)
        Luaunit.assertEquals(result, {
            ["Forest"]={loc={x=0, y=0}, timestamp=123456},
            ["Meadows"]={loc={x=0, y=1}, timestamp=123456},
            ["Tropical"]={loc={x=0, y=2}, timestamp=123456}
        })

        local newMeadows = {loc={x=1, y=5}, timestamp=999999}
        local success = Logger.LogSpeciesToDisk(Util.DEFAULT_LOG_PATH, "Meadows", newMeadows.loc, newMeadows.timestamp)
        Luaunit.assertIsTrue(success)
        result = Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH)
        Luaunit.assertEquals(result, {
            ["Forest"]={loc={x=0, y=0}, timestamp=123456},
            ["Meadows"]=newMeadows,
            ["Tropical"]={loc={x=0, y=2}, timestamp=123456}
        })

        Util.VerifyLogIsValidLog(Util.DEFAULT_LOG_PATH)
    end

    function TestLogger:TestNewEntry()
        Util.CreateLogfileSeed("BasicLog.log", Util.DEFAULT_LOG_PATH)
        local newEntryMarshy = {loc={x=1, y=5}, timestamp=987654}

        local success = Logger.LogSpeciesToDisk(Util.DEFAULT_LOG_PATH, "Marshy", newEntryMarshy.loc, newEntryMarshy.timestamp)
        Luaunit.assertIsTrue(success)

        local result = Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH)
        Luaunit.assertEquals(result, {
            ["Forest"]={loc={x=0, y=0}, timestamp=123456},
            ["Meadows"]={loc={x=0, y=1}, timestamp=123456},
            ["Tropical"]={loc={x=0, y=2}, timestamp=123456},
            ["Marshy"]=newEntryMarshy
        })

        Util.VerifyLogIsValidLog(Util.DEFAULT_LOG_PATH)
    end
